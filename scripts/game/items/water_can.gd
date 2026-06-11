# Waters tilled soil. Port of WaterCan.cs.
class_name WaterCan
extends Item


func can_use(target: Vector2i) -> bool:
	return GameManager.terrain != null and GameManager.terrain.is_tilled(target)


func use(target: Vector2i) -> bool:
	GameManager.terrain.water_at(target)
	return true
