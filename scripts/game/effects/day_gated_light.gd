# A PointLight2D that follows the day cycle: on at night by default (lamps,
# lit windows), or inverted for daytime effects (sun shafts through windows).
# Finds the scene's DayEventHandler via the GameManager registry, so it works
# inside generated scenes without manual wiring.
extends PointLight2D

@export var active_during_day: bool = false
# day range fallback when the scene has no DayEventHandler node
@export var day_range: Vector2 = Vector2(0.25, 0.77)


func _ready() -> void:
	GameManager.day_ratio_changed.connect(_on_ratio)
	_on_ratio(GameManager.current_day_ratio)


func _on_ratio(ratio: float) -> void:
	var is_day := ratio >= day_range.x and ratio <= day_range.y
	visible = is_day if active_during_day else not is_day
