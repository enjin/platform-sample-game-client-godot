# Base resource for everything that can sit in the inventory.
# Port of Item.cs (abstract ScriptableObject).
class_name Item
extends Resource

@export var unique_id: String = "default_id"
@export var display_name: String = ""
@export var item_sprite: Texture2D
@export var max_stack_size: int = 10
@export var consumable: bool = true
@export var buy_price: int = -1

# Scene instanced in the player's hand when equipped (tool visuals).
@export var visual_prefab: PackedScene
@export var player_animator_trigger_use: String = "GenericToolSwing"
@export var use_sound: Array[AudioStream] = []


func can_use(_target: Vector2i) -> bool:
	return false


func use(_target: Vector2i) -> bool:
	return false


# Items that don't need a cell target (products: eaten anytime) override this.
func need_target() -> bool:
	return true
