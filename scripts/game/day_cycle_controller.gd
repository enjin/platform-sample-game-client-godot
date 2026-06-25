# Day/night tint. Functional approximation of DayCycleHandler.cs: Unity
# blended five additive URP Light2D gradients; here one CanvasModulate samples
# a single authored gradient by day ratio. Known divergence (documented in
# the README): no rim lights or rotating building shadows.
extends CanvasModulate

@export var tint_gradient: Gradient
# Optional sun: a DirectionalLight2D that shades the sprites' normal maps for
# depth (Godot otherwise renders them flat). Its energy follows the day so it
# only shades in daylight (off at night, or it would wash out the dark). The
# CanvasModulate (tint) is the dim ambient base; the sun adds the lit side.
@export var sun_light: DirectionalLight2D
@export var sun_max_energy: float = 0.55


func _ready() -> void:
	GameManager.day_ratio_changed.connect(_on_ratio)
	_on_ratio(GameManager.current_day_ratio)
	GameManager.day_cycle = self


func _exit_tree() -> void:
	if GameManager.day_cycle == self:
		GameManager.day_cycle = null


func _on_ratio(ratio: float) -> void:
	if tint_gradient:
		color = tint_gradient.sample(ratio)
	if sun_light:
		# ramp up after dawn, hold through midday, fade out before dusk; 0 at night
		var day := smoothstep(0.26, 0.40, ratio) * (1.0 - smoothstep(0.70, 0.80, ratio))
		sun_light.energy = day * sun_max_energy
