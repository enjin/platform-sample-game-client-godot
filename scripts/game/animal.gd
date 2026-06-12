# Roaming pen animal (chicken, pig). Port of BasicAnimalMovement.cs:
# idle for 3-5s, pick a random point clamped to the pen area, walk to it.
# Animation state mirrors the Unity controller's Speed float: "idle" loops
# the squash-stretch clip, "walk" plays while moving. Random animal sounds
# play positionally every few seconds.
extends Node2D

@export var area: Rect2 = Rect2()  # pen bounds, world px
@export var min_idle_time: float = 3.0
@export var max_idle_time: float = 5.0
@export var speed: float = 192.0  # 3 units/s at 64 px/unit
@export var animal_sounds: Array[AudioStream] = []
@export var min_sound_time: float = 4.0
@export var max_sound_time: float = 8.0

var _is_idle := true
var _idle_timer := 0.0
var _idle_target := 0.0
var _sound_timer := 0.0
var _target := Vector2.ZERO

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	if max_idle_time <= min_idle_time:
		max_idle_time = min_idle_time + 0.1
	_sound_timer = randf_range(min_sound_time, max_sound_time)
	# desync herd animation phases
	sprite.frame = randi() % maxi(1, sprite.sprite_frames.get_frame_count("idle"))
	_pick_new_idle_time()


func _process(delta: float) -> void:
	if not animal_sounds.is_empty():
		_sound_timer -= delta
		if _sound_timer <= 0.0:
			if has_node("/root/SoundManager"):
				get_node("/root/SoundManager").play_sfx_at(
					global_position, animal_sounds.pick_random())
			_sound_timer = randf_range(min_sound_time, max_sound_time)

	if _is_idle:
		_idle_timer += delta
		if _idle_timer >= _idle_target:
			_pick_new_target()
	else:
		global_position = global_position.move_toward(_target, speed * delta)
		if global_position == _target:
			_pick_new_idle_time()


func _pick_new_idle_time() -> void:
	_is_idle = true
	_idle_target = randf_range(min_idle_time, max_idle_time)
	_idle_timer = 0.0
	sprite.play("idle")


func _pick_new_target() -> void:
	_is_idle = false
	var dir := Vector2.UP.rotated(randf() * TAU) * randf_range(1.0, 10.0) * 64.0
	var pts := global_position + dir
	if not area.has_point(pts):
		pts = pts.clamp(area.position, area.end)
	_target = pts
	# baked art faces right; Unity flips localScale.x negative when moving left
	sprite.flip_h = (_target.x - global_position.x) < 0
	sprite.play("walk")
