# Harvests fully grown crops. Port of Basket.cs.
class_name Basket
extends Item


func can_use(target: Vector2i) -> bool:
	if GameManager.terrain == null:
		return false
	var data = GameManager.terrain.get_crop_data_at(target)
	return data != null and data.growing_crop != null \
		and is_equal_approx(data.growth_ratio, 1.0)


func use(target: Vector2i) -> bool:
	var terrain: Node = GameManager.terrain
	var data = terrain.get_crop_data_at(target)
	var player: Node = GameManager.player
	if player == null or data == null:
		return false
	if not player.can_fit_in_inventory(data.growing_crop.produce,
			data.growing_crop.product_per_harvest):
		return false
	var crop = terrain.harvest_at(target)
	if crop == null:
		return false
	for i in crop.product_per_harvest:
		player.add_item(crop.produce)
	return true
