# Bushes ruffle (squash + bounce) when the player walks into them, reproducing
# Unity's Prefab_Bush: a trigger CircleCollider2D (TriggerEvent) that plays the
# Anim_Bush_ruffle scale wobble. Bushes are walk-through (no solid collider),
# like Unity. Mirrors foliage_wind.gd / lamp_*.gd: a runtime pass over the
# generated Maps/Props node that gives each bush sprite a detector Area2D and
# runs a quick scale-squash tween when the player enters. Composes fine with the
# foliage wind shader (that's a vertex effect; this scales the node).
extends Node

@export var props_root: Node2D

const BUSH_KEY := "bush"
# the ruffle dips to this fraction of the rest scale, then bounces back -- from
# Anim_Bush_ruffle (x 0.919->0.850 ~= 0.93, y 0.9305->0.721 ~= 0.78), a quick
# vertical squash like the bush is brushed aside.
const SQUASH := Vector2(0.93, 0.78)

# rustle the bush plays on contact (Unity "Move between bush" AudioSource);
# two variants, picked at random so repeated brushes don't sound identical
const RUSTLE_SOUNDS := [
	preload("res://audio/bush/move_between_bush-001.wav"),
	preload("res://audio/bush/move_between_bush-002.wav"),
]

# leaf bits that puff out on contact (Unity bush LeafParticle: green leaves,
# ~0.3-unit, spinning); copied from Unity's VFX/Leaves/Leaf.png
const LEAF_TEX := preload("res://art/vfx/leaves/leaf.png")

var _shaking := {}
var _leaves := {}  # bush Sprite2D -> its one-shot CPUParticles2D burst
var _leaf_ramp: Gradient


func _ready() -> void:
	if props_root == null:
		return
	# leaves go from leafy green to a slightly darker green, fading out
	_leaf_ramp = Gradient.new()
	_leaf_ramp.set_color(0, Color(0.561, 0.62, 0.22, 1.0))
	_leaf_ramp.set_color(1, Color(0.38, 0.52, 0.18, 0.0))
	for child in props_root.get_children():
		var spr := child as Sprite2D
		if spr == null or spr.texture == null:
			continue
		if not (BUSH_KEY in _texture_file(spr)):
			continue
		var rect := spr.get_rect()
		var sc: Vector2 = spr.scale
		var area := Area2D.new()
		area.collision_layer = 0
		area.collision_mask = 2  # the player CharacterBody2D sits on layer 2
		# centre on the bush body, in props_root space (NOT a child of the bush:
		# the shake squashes the bush non-uniformly, which would warp a child
		# CircleShape2D)
		area.position = spr.position + rect.get_center() * sc
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = rect.size.y * 0.4 * sc.y
		shape.shape = circle
		area.add_child(shape)
		props_root.add_child(area)
		area.body_entered.connect(_on_body_entered.bind(spr))

		var leaves := _make_leaf_burst(area.position)
		props_root.add_child(leaves)
		_leaves[spr] = leaves


func _make_leaf_burst(pos: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = LEAF_TEX
	p.position = pos
	p.z_index = 1  # leaves puff out in front of the bush
	p.amount = 10
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.9  # a burst, not a stream
	p.lifetime = 0.5
	p.direction = Vector2(0, -1)
	p.spread = 100.0  # burst out in nearly all directions
	# Unity's leaves fly fast (~256 px/s) with no gravity, so they scatter wide;
	# keep a little gravity so they eventually settle, but let them spread first
	p.gravity = Vector2(0, 45.0)
	p.initial_velocity_min = 100.0
	p.initial_velocity_max = 200.0
	p.scale_amount_min = 0.28  # ~0.3-unit leaves (Unity startSize)
	p.scale_amount_max = 0.42
	p.angular_velocity_min = -200.0  # tumble
	p.angular_velocity_max = 200.0
	p.color_ramp = _leaf_ramp
	return p


func _on_body_entered(body: Node, bush: Sprite2D) -> void:
	if body == GameManager.player:
		_shake(bush)


func _shake(bush: Sprite2D) -> void:
	if _shaking.has(bush):
		return
	_shaking[bush] = true
	var sound := get_node_or_null(^"/root/SoundManager")
	if sound != null:
		sound.play_sfx_at(bush.global_position, RUSTLE_SOUNDS.pick_random())
	var leaves: CPUParticles2D = _leaves.get(bush)
	if leaves != null:
		leaves.restart()  # one-shot burst
	var rest: Vector2 = bush.scale
	var squash: Vector2 = rest * SQUASH
	var tw := bush.create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(bush, "scale", squash, 0.07)
	tw.tween_property(bush, "scale", rest, 0.05)
	tw.tween_property(bush, "scale", squash, 0.06)
	tw.tween_property(bush, "scale", rest, 0.07)
	tw.tween_callback(func() -> void: _shaking.erase(bush))


func _texture_file(spr: Sprite2D) -> String:
	var t: Texture2D = spr.texture
	if t is CanvasTexture:
		t = (t as CanvasTexture).diffuse_texture
	return "" if t == null else t.resource_path.get_file().to_lower()
