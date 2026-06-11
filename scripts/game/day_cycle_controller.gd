# Day/night tint. Functional approximation of DayCycleHandler.cs: Unity
# blended five additive URP Light2D gradients; here one CanvasModulate samples
# a single authored gradient by day ratio. Known divergence (documented in
# the README): no rim lights or rotating building shadows.
extends CanvasModulate

@export var tint_gradient: Gradient


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
