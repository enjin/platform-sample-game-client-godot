# Plants a crop on tilled soil. Port of SeedBag.cs.
class_name SeedBag
extends Item

@export var planted_crop: Crop


func can_use(target: Vector2i) -> bool:
	return GameManager.terrain != null and GameManager.terrain.is_plantable(target)


func use(target: Vector2i) -> bool:
	GameManager.terrain.plant_at(target, planted_crop)
	return true
