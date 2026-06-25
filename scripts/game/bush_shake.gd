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

var _shaking := {}


func _ready() -> void:
	if props_root == null:
		return
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
