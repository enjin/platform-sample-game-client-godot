# Sellable produce (corn, wheat, carrot). Port of Product.cs.
class_name Product
extends Item

@export var sell_price: int = 1


func can_use(_target: Vector2i) -> bool:
	return true


func use(_target: Vector2i) -> bool:
	return true


func need_target() -> bool:
	return false
