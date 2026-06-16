# Drop shadow blob. Port of ShadowInstance.cs + the shadow side of
# DayCycleHandler: outdoors a SunShadowDriver rotates and stretches every
# shadow with the sun; indoors (no driver) it stays at its resting pose.
# The sprite extends upward from the node origin (the prop's base), so
# rotation sweeps it around the base like a sundial.
extends Sprite2D

@export var base_length: float = 1.0

var _base_scale := Vector2.ONE


func _ready() -> void:
	add_to_group("sun_shadows")
	if texture == null:
		texture = load("res://art/vfx/shadow_circle.png")
	centered = false
	# anchor: bottom-center of the blob at the node origin
	offset = Vector2(-texture.get_width() / 2.0, -texture.get_height() * 0.92)
	_base_scale = scale
	modulate = Color(0, 0, 0, 0.22)
	# resting pose (interior / before the first driver tick): short, slightly
	# offset shadow like Unity's editor preview
	apply_sun(18.0, 0.55, 0.22)


func apply_sun(angle_degrees: float, length: float, alpha: float) -> void:
	rotation_degrees = angle_degrees
	scale = Vector2(_base_scale.x,
		_base_scale.y * maxf(0.05, length * base_length))
	modulate.a = alpha
