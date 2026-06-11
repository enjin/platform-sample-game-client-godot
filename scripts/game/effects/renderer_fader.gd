# Fades a CanvasItem (tree canopy, roof) while the player stands inside the
# area. Port of RendererFader.cs.
extends Area2D

@export var target: CanvasItem
@export var faded_alpha: float = 0.45
@export var fade_time: float = 0.5

var _tween: Tween


func _ready() -> void:
	collision_mask = 2  # player layer
	body_entered.connect(func(_b: Node2D) -> void: _fade_to(faded_alpha))
	body_exited.connect(func(_b: Node2D) -> void: _fade_to(1.0))


func _fade_to(alpha: float) -> void:
	if target == null:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(target, "modulate:a", alpha, fade_time)
