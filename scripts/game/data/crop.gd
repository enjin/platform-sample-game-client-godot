# Crop definition: growth stages, produce, timers. Port of Crop.cs.
# Stage visuals are plain textures (Godot crops render as Sprite2Ds managed
# by the TerrainManager) instead of Unity's TileBase array.
class_name Crop
extends Resource

@export var unique_id: String = ""
@export var growth_stage_textures: Array[Texture2D] = []
@export var produce: Product
@export var growth_time: float = 1.0
@export var number_of_harvest: int = 1
@export var stage_after_harvest: int = 1
@export var product_per_harvest: int = 1
@export var dry_death_timer: float = 30.0


func get_growth_stage(grow_ratio: float) -> int:
	return int(grow_ratio * (growth_stage_textures.size() - 1))
