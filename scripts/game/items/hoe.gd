# Tills soil. Port of Hoe.cs - including the Enjin hook: tilling is where
# tokens are randomly revealed in the Unity sample (Hoe.cs:18), despite the
# roadmap's "harvest-time" phrasing.
class_name Hoe
extends Item


func can_use(target: Vector2i) -> bool:
	return GameManager.terrain != null and GameManager.terrain.is_tillable(target)


func use(target: Vector2i) -> bool:
	var terrain: Node = GameManager.terrain
	terrain.till_at(target)
	EnjinManager.randomly_reveal_token(
		terrain.ground_layer.to_global(terrain.ground_layer.map_to_local(target)))
	return true
