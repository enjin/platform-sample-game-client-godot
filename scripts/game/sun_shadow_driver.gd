# Sweeps every "sun_shadows" sprite with the sun. Port of
# DayCycleHandler.UpdateShadow: angle and length sampled per day ratio.
# Morning sun (east) throws shadows west; noon is short; dusk throws east.
extends Node

const DAWN := 0.25
const DUSK := 0.77


func _ready() -> void:
	GameManager.day_ratio_changed.connect(_on_ratio)
	_on_ratio(GameManager.current_day_ratio)


func _on_ratio(ratio: float) -> void:
	var angle: float
	var length: float
	var alpha: float
	if ratio < DAWN or ratio > DUSK:
		# night: faint, fixed moon-ish shadow
		angle = 15.0
		length = 0.7
		alpha = 0.08
	else:
		var t := inverse_lerp(DAWN, DUSK, ratio)
		angle = lerpf(-70.0, 70.0, t)
		# long at dawn/dusk, shortest at noon
		length = lerpf(1.35, 0.55, sin(t * PI))
		alpha = lerpf(0.13, 0.25, sin(t * PI))
	for shadow in get_tree().get_nodes_in_group("sun_shadows"):
		shadow.apply_sun(angle, length, alpha)
