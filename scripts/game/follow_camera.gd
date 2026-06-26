# Pixel-snapped smooth-follow camera.
#
# Godot's built-in Camera2D position_smoothing eases the camera at sub-pixel
# positions. `snap_2d_transforms_to_pixel` snaps SPRITES relative to the camera
# but NOT the camera's own smoothed position, so while the camera is moving the
# character inherits that sub-pixel drift and blurs with Linear filtering - it
# only looks crisp when the camera is still (e.g. pinned against a limit).
#
# So we ease the camera ourselves and snap its position to the whole-SCREEN-
# pixel grid every frame. The eased motion stays smooth (the internal target is
# fractional) while the rendered camera is always pixel-aligned, so the
# character (and the world) stay sharp while walking.
extends Camera2D

@export var follow_speed: float = 8.0

var _target: Node2D
var _smooth_pos: Vector2


func _ready() -> void:
	make_current()
	position_smoothing_enabled = false  # we do the easing ourselves
	set_as_top_level(true)              # move independently of the player
	_target = get_parent() as Node2D
	if _target:
		_smooth_pos = _target.global_position
		global_position = _smooth_pos


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	# framerate-independent exponential ease toward the player
	var t := 1.0 - exp(-follow_speed * delta)
	_smooth_pos = _smooth_pos.lerp(_target.global_position, t)
	# snap to the whole-screen-pixel grid (zoom-aware): zoom screen px per world
	# unit, so multiples of 1/zoom world units land exactly on screen pixels.
	global_position = (_smooth_pos * zoom).round() / zoom
