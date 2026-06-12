# Port of PlayerController.cs. Movement, look direction, cell targeting,
# interactions and use-item animation flow. Inventory arrives in Phase 4 -
# every inventory touch point is guarded so the shell runs without it.
extends CharacterBody2D

# 4.0 units/s in Unity at 64 px/unit.
const SPEED := 256.0
# collision layer 3 = interactive objects (market, warehouse, tokens)
const INTERACTIVE_MASK := 1 << 2

@export var can_control: bool = true

var look_direction := Vector2.RIGHT
var current_target := Vector2i.ZERO  # targeted cell (terrain scenes only)
var has_target := false

var _interactive_target: Node = null
var _is_over_ui := false
var _oneshot_playing := false
var _item_visuals := {}  # Item -> Node2D under ItemAttachBone

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var target_marker: Sprite2D = $TargetMarker
@onready var item_attach_bone: Node2D = $ItemAttachBone
@onready var camera: Camera2D = $Camera2D
@onready var step_dust: CPUParticles2D = $StepDust


func _ready() -> void:
	GameManager.player = self
	camera.make_current()
	target_marker.visible = false
	sprite.animation_finished.connect(_on_animation_finished)
	# cross-scene state lives on the GameManager (Unity kept the player in
	# DontDestroyOnLoad instead)
	GameManager.ensure_inventory()
	_rebuild_item_visuals()


func _exit_tree() -> void:
	if GameManager.player == self:
		GameManager.player = null


func toggle_control(value: bool) -> void:
	can_control = value
	if not value:
		velocity = Vector2.ZERO
		_update_animation(Vector2.ZERO)


func _physics_process(_delta: float) -> void:
	if not can_control:
		return
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if move != Vector2.ZERO:
		_set_look_direction_from(move)
	else:
		_set_look_direction_from(get_global_mouse_position() - global_position)
	velocity = move * SPEED
	move_and_slide()
	step_dust.emitting = move != Vector2.ZERO
	_update_animation(move)


func _process(_delta: float) -> void:
	_interactive_target = null
	has_target = false
	_is_over_ui = get_viewport().gui_get_hovered_control() != null
	if not can_control or _is_over_ui:
		target_marker.visible = false
		return

	var mouse_pos := get_global_mouse_position()

	# interactive object under the mouse takes priority over cell targeting
	var params := PhysicsPointQueryParameters2D.new()
	params.position = mouse_pos
	params.collision_mask = INTERACTIVE_MASK
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var hits := get_world_2d().direct_space_state.intersect_point(params, 1)
	if not hits.is_empty():
		var collider: Object = hits[0].collider
		if collider is Node and (collider as Node).has_method("interacted_with"):
			_interactive_target = collider
		target_marker.visible = false
		return

	# cell targeting needs a terrain (outdoor scenes only)
	var terrain: Node = GameManager.terrain
	if terrain == null:
		target_marker.visible = false
		return
	var ground: TileMapLayer = terrain.ground_layer
	var current_cell: Vector2i = ground.local_to_map(ground.to_local(global_position))
	var pointed_cell: Vector2i = ground.local_to_map(ground.to_local(mouse_pos))
	var to_target := pointed_cell - current_cell
	to_target.x = clampi(to_target.x, -1, 1)
	to_target.y = clampi(to_target.y, -1, 1)
	current_target = current_cell + to_target
	target_marker.global_position = ground.to_global(ground.map_to_local(current_target))

	var inventory = GameManager.inventory
	if inventory != null and inventory.equipped_item != null \
			and inventory.equipped_item.can_use(current_target):
		has_target = true
		target_marker.visible = true
	else:
		target_marker.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not can_control:
		return
	if event.is_action_pressed("interact"):
		_use_object()
	elif event.is_action_pressed("equip_next"):
		_change_equip_offset(1)
	elif event.is_action_pressed("equip_prev"):
		_change_equip_offset(-1)
	elif event.is_action_pressed("save_game"):
		if has_node("/root/SaveSystem"):
			get_node("/root/SaveSystem").save_game()
	elif event.is_action_pressed("load_game"):
		if has_node("/root/SaveSystem"):
			get_node("/root/SaveSystem").load_game()


# ------------------------------------------------------------------ actions

func _use_object() -> void:
	if _is_over_ui:
		return
	if _interactive_target != null:
		_interactive_target.interacted_with()
		return
	var inventory = GameManager.inventory
	if inventory == null or inventory.equipped_item == null:
		return
	if inventory.equipped_item.need_target() and not has_target:
		return
	use_item()


func use_item() -> void:
	var inventory = GameManager.inventory
	if inventory == null or inventory.equipped_item == null:
		return
	var previous_equipped = inventory.equipped_item
	inventory.use_equipped(current_target, self)
	_play_use_animation(previous_equipped.player_animator_trigger_use)
	var visual: Node2D = _item_visuals.get(previous_equipped)
	if visual and visual.has_method("play_use"):
		visual.play_use(look_direction)
	if inventory.equipped_item == null and visual:
		# entry now empty (consumable ran out): hide after the swing finishes
		get_tree().create_timer(1.0).timeout.connect(
			func() -> void: visual.visible = false)


func change_equip_item(index: int) -> void:
	var inventory = GameManager.inventory
	if inventory == null:
		return
	_toggle_tool_visual(false)
	inventory.equip_item(index)
	_toggle_tool_visual(true)


func _change_equip_offset(offset: int) -> void:
	var inventory = GameManager.inventory
	if inventory == null:
		return
	_toggle_tool_visual(false)
	if offset > 0:
		inventory.equip_next()
	else:
		inventory.equip_prev()
	_toggle_tool_visual(true)


# --------------------------------------------------------------- visuals

func _set_look_direction_from(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return
	if absf(direction.x) > absf(direction.y):
		look_direction = Vector2.RIGHT if direction.x > 0 else Vector2.LEFT
	else:
		# godot y-down: up on screen is -y
		look_direction = Vector2.DOWN if direction.y > 0 else Vector2.UP


func _update_animation(move: Vector2) -> void:
	if _oneshot_playing:
		return
	var moving := move != Vector2.ZERO
	if look_direction == Vector2.UP:
		sprite.flip_h = false
		sprite.play("walk_up" if moving else "idle_up")
	elif look_direction == Vector2.DOWN:
		sprite.flip_h = false
		sprite.play("walk_down" if moving else "idle_front")
	elif look_direction == Vector2.LEFT:
		if moving:
			sprite.flip_h = false
			sprite.play("walk_side_l")  # dedicated left clip from the bake
		else:
			sprite.flip_h = true
			sprite.play("idle_side")
	else:
		sprite.flip_h = false
		sprite.play("walk_side" if moving else "idle_side")


# Unity trigger names -> baked clip prefixes.
const TRIGGER_TO_CLIP := {
	"GenericToolSwing": "tool_swing",
	"Water": "water",
	"Plant": "planting",
	"Pickup": "picking",
	"Eat": "eating",
}


func _play_use_animation(trigger: String) -> void:
	var prefix: String = TRIGGER_TO_CLIP.get(trigger, "tool_swing")
	var suffix := "front"
	var flip := false
	if look_direction == Vector2.UP:
		suffix = "up"
	elif look_direction == Vector2.LEFT:
		suffix = "side"
		flip = true
	elif look_direction == Vector2.RIGHT:
		suffix = "side"
	var anim := "%s_%s" % [prefix, suffix]
	if not sprite.sprite_frames.has_animation(anim):
		anim = prefix + "_front"
		if not sprite.sprite_frames.has_animation(anim):
			return
	sprite.flip_h = flip
	_oneshot_playing = true
	sprite.play(anim)


func _on_animation_finished() -> void:
	_oneshot_playing = false
	_update_animation(Vector2.ZERO)


func _toggle_tool_visual(enable: bool) -> void:
	var inventory = GameManager.inventory
	if inventory == null or inventory.equipped_item == null:
		return
	var visual: Node2D = _item_visuals.get(inventory.equipped_item)
	if visual:
		visual.visible = enable


func _rebuild_item_visuals() -> void:
	for child in item_attach_bone.get_children():
		child.queue_free()
	_item_visuals.clear()
	for entry in GameManager.inventory.entries:
		if entry != null and entry.item != null:
			create_item_visual(entry.item)
	_toggle_tool_visual(true)


func create_item_visual(item) -> void:
	if item.visual_prefab == null or _item_visuals.has(item):
		return
	var visual: Node2D = item.visual_prefab.instantiate()
	visual.visible = false
	item_attach_bone.add_child(visual)
	_item_visuals[item] = visual


func add_item(item) -> bool:
	var inventory = GameManager.inventory
	if inventory == null:
		return false
	create_item_visual(item)
	return inventory.add_item(item)


func can_fit_in_inventory(item, count: int) -> bool:
	var inventory = GameManager.inventory
	return inventory != null and inventory.can_fit_item(item, count)


func sell_item(inventory_index: int, count: int) -> void:
	var inventory = GameManager.inventory
	if inventory == null:
		return
	var entry = inventory.entries[inventory_index]
	if entry == null or entry.item == null or not ("sell_price" in entry.item):
		return
	var actual: int = inventory.remove(inventory_index, count)
	GameManager.coins += actual * entry.item.sell_price


func buy_item(item) -> bool:
	if item.buy_price > GameManager.coins:
		return false
	GameManager.coins -= item.buy_price
	add_item(item)
	return true
