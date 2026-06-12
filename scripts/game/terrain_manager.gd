# Port of TerrainManager.cs: tilling/watering tile swaps on the ground
# layers plus per-cell crop state. Crops render as Sprite2D children (texture
# swap per growth stage) instead of a crop tilemap - same behavior, and tall
# crops aren't constrained to the 64px grid.
class_name TerrainManager
extends Node2D

const WATER_DURATION := 60.0


class GroundData:
	var water_timer: float = 0.0


class CropData:
	var growing_crop: Crop = null
	var current_growth_stage: int = 0
	var growth_ratio: float = 0.0
	var growth_timer: float = 0.0
	var harvest_count: int = 0
	var dying_timer: float = 0.0

	var harvest_done: bool:
		get:
			return harvest_count == growing_crop.number_of_harvest

	func harvest() -> Crop:
		var crop := growing_crop
		harvest_count += 1
		current_growth_stage = growing_crop.stage_after_harvest
		growth_ratio = current_growth_stage / float(growing_crop.growth_stage_textures.size())
		growth_timer = growing_crop.growth_time * growth_ratio
		return crop

	func save_data() -> Dictionary:
		return {
			"crop_id": growing_crop.unique_id,
			"stage": current_growth_stage,
			"growth_ratio": growth_ratio,
			"growth_timer": growth_timer,
			"harvest_count": harvest_count,
			"dying_timer": dying_timer,
		}

	func load_data(d: Dictionary, crop_database) -> void:
		growing_crop = crop_database.get_from_id(d["crop_id"])
		current_growth_stage = int(d["stage"])
		growth_ratio = d["growth_ratio"]
		growth_timer = d["growth_timer"]
		harvest_count = int(d["harvest_count"])
		dying_timer = d["dying_timer"]


# The pre-painted tillable dirt layer (Unity's GroundTilemap reference).
@export var ground_layer: TileMapLayer
# Watered overlay (Unity's WaterTilemap reference).
@export var water_overlay: TileMapLayer

var _ground_data := {}  # Vector2i -> GroundData
var _crop_data := {}    # Vector2i -> CropData
var _crop_sprites := {} # Vector2i -> Sprite2D
var _crops_root: Node2D

# (source_id, atlas_coords) per soil kind, found by scanning the tileset
var _soil_tiles := {}

# in-memory per-scene snapshots, like Unity's SaveSystem.s_ScenesDataLookup
static var _scene_states := {}


func _ready() -> void:
	GameManager.terrain = self
	_crops_root = Node2D.new()
	_crops_root.name = "Crops"
	_crops_root.y_sort_enabled = true
	add_child(_crops_root)
	_find_soil_tiles()


func _exit_tree() -> void:
	if GameManager.terrain == self:
		GameManager.terrain = null


func _find_soil_tiles() -> void:
	var tileset := ground_layer.tile_set
	for i in tileset.get_source_count():
		var sid := tileset.get_source_id(i)
		var src := tileset.get_source(sid) as TileSetAtlasSource
		if src == null:
			continue
		for t in src.get_tiles_count():
			var coords := src.get_tile_id(t)
			var kind: String = src.get_tile_data(coords, 0).get_custom_data("soil")
			if kind != "":
				_soil_tiles[kind] = [sid, coords]


# ------------------------------------------------------------------ queries

func is_tillable(target: Vector2i) -> bool:
	var data := ground_layer.get_cell_tile_data(target)
	return data != null and data.get_custom_data("tillable") and not is_tilled(target)


func is_tilled(target: Vector2i) -> bool:
	return _ground_data.has(target)


func is_plantable(target: Vector2i) -> bool:
	return is_tilled(target) and not _crop_data.has(target)


func get_crop_data_at(target: Vector2i) -> CropData:
	return _crop_data.get(target)


# ------------------------------------------------------------------ actions

func till_at(target: Vector2i) -> void:
	if is_tilled(target):
		return
	_set_soil(ground_layer, target, "tilled")
	_ground_data[target] = GroundData.new()
	_spawn_till_puff(ground_layer.to_global(ground_layer.map_to_local(target)))


func water_at(target: Vector2i) -> void:
	var ground: GroundData = _ground_data.get(target)
	if ground == null:
		return
	ground.water_timer = WATER_DURATION
	_set_soil(water_overlay, target, "watered")


func plant_at(target: Vector2i, crop_to_plant: Crop) -> void:
	var data := CropData.new()
	data.growing_crop = crop_to_plant
	_crop_data[target] = data
	_update_crop_visual(target)


func harvest_at(target: Vector2i) -> Crop:
	var data: CropData = _crop_data.get(target)
	if data == null or not is_equal_approx(data.growth_ratio, 1.0):
		return null
	var produce := data.harvest()
	if data.harvest_done:
		_crop_data.erase(target)
	_update_crop_visual(target)
	_spawn_harvest_burst(ground_layer.to_global(ground_layer.map_to_local(target)))
	return produce


func override_growth_stage(target: Vector2i, new_stage: int) -> void:
	var data: CropData = _crop_data.get(target)
	if data == null:
		return
	data.growth_ratio = clampf(
		(new_stage + 1) / float(data.growing_crop.growth_stage_textures.size()), 0.0, 1.0)
	data.growth_timer = data.growth_ratio * data.growing_crop.growth_time
	data.current_growth_stage = new_stage
	_update_crop_visual(target)


func _process(delta: float) -> void:
	for cell: Vector2i in _ground_data.keys():
		var ground: GroundData = _ground_data[cell]
		if ground.water_timer > 0.0:
			ground.water_timer -= delta
			if ground.water_timer <= 0.0:
				water_overlay.erase_cell(cell)
		var crop: CropData = _crop_data.get(cell)
		if crop == null:
			continue
		if ground.water_timer <= 0.0:
			# dry crops wither and eventually die
			crop.dying_timer += delta
			if crop.dying_timer > crop.growing_crop.dry_death_timer:
				_crop_data.erase(cell)
				_update_crop_visual(cell)
		else:
			crop.dying_timer = 0.0
			# growth is wall-clock while watered (the day cycle only drives
			# lighting/events), matching TerrainManager.Update
			crop.growth_timer = clampf(crop.growth_timer + delta, 0.0,
				crop.growing_crop.growth_time)
			crop.growth_ratio = crop.growth_timer / crop.growing_crop.growth_time
			var stage := crop.growing_crop.get_growth_stage(crop.growth_ratio)
			if stage != crop.current_growth_stage:
				crop.current_growth_stage = stage
				_update_crop_visual(cell)


# ------------------------------------------------------------------ visuals

func _set_soil(layer: TileMapLayer, cell: Vector2i, kind: String) -> void:
	var tile: Array = _soil_tiles.get(kind, [])
	if tile.is_empty():
		push_warning("no '%s' soil tile in tileset" % kind)
		return
	layer.set_cell(cell, tile[0], tile[1])


func _update_crop_visual(target: Vector2i) -> void:
	var data: CropData = _crop_data.get(target)
	if data == null:
		var old: Sprite2D = _crop_sprites.get(target)
		if old:
			old.queue_free()
		_crop_sprites.erase(target)
		return
	var spr: Sprite2D = _crop_sprites.get(target)
	if spr == null:
		spr = Sprite2D.new()
		var pos := ground_layer.to_global(ground_layer.map_to_local(target))
		spr.position = _crops_root.to_local(pos) + Vector2(0, 24)  # near cell bottom for y-sort
		_crops_root.add_child(spr)
		_crop_sprites[target] = spr
	var tex: Texture2D = data.growing_crop.growth_stage_textures[
		mini(data.current_growth_stage, data.growing_crop.growth_stage_textures.size() - 1)]
	spr.texture = tex
	var s: float = data.growing_crop.stage_texture_scale
	spr.scale = Vector2(s, s)
	# anchor the sprite's bottom to the cell bottom so tall stages grow upward
	# (offset is pre-scale local space)
	spr.offset = Vector2(0, -tex.get_height() / 2.0 - 8.0 / s)


# Leaf-bit burst on harvest (approximation of Crop.HarvestEffect VFX).
func _spawn_harvest_burst(world_pos: Vector2) -> void:
	var burst := CPUParticles2D.new()
	burst.position = to_local(world_pos) + Vector2(0, -16)
	burst.one_shot = true
	burst.emitting = true
	burst.amount = 16
	burst.lifetime = 0.6
	burst.spread = 180.0
	burst.direction = Vector2(0, -1)
	burst.initial_velocity_min = 60.0
	burst.initial_velocity_max = 140.0
	burst.gravity = Vector2(0, 320)
	burst.scale_amount_min = 2.0
	burst.scale_amount_max = 4.0
	burst.color = Color(0.45, 0.72, 0.3)
	add_child(burst)
	get_tree().create_timer(1.0).timeout.connect(burst.queue_free)


func _spawn_till_puff(world_pos: Vector2) -> void:
	var puff := CPUParticles2D.new()
	puff.position = to_local(world_pos)
	puff.one_shot = true
	puff.emitting = true
	puff.amount = 12
	puff.lifetime = 0.5
	puff.spread = 180.0
	puff.initial_velocity_min = 30.0
	puff.initial_velocity_max = 70.0
	puff.gravity = Vector2(0, 60)
	puff.scale_amount_min = 2.0
	puff.scale_amount_max = 5.0
	puff.color = Color(0.45, 0.32, 0.2)
	add_child(puff)
	get_tree().create_timer(1.0).timeout.connect(puff.queue_free)


# ------------------------------------------------------- state (save/swap)

func save_data() -> Dictionary:
	var ground := []
	for cell: Vector2i in _ground_data:
		ground.append({"cell": [cell.x, cell.y],
			"water_timer": _ground_data[cell].water_timer})
	var crops := []
	for cell: Vector2i in _crop_data:
		var d: Dictionary = _crop_data[cell].save_data()
		d["cell"] = [cell.x, cell.y]
		crops.append(d)
	return {"ground": ground, "crops": crops}


func load_data(data: Dictionary) -> void:
	for cell in _crop_sprites:
		_crop_sprites[cell].queue_free()
	_crop_sprites.clear()
	_ground_data.clear()
	_crop_data.clear()
	for g: Dictionary in data.get("ground", []):
		var cell := Vector2i(int(g["cell"][0]), int(g["cell"][1]))
		var ground := GroundData.new()
		ground.water_timer = g["water_timer"]
		_ground_data[cell] = ground
		_set_soil(ground_layer, cell, "tilled")
		if ground.water_timer > 0.0:
			_set_soil(water_overlay, cell, "watered")
		else:
			water_overlay.erase_cell(cell)
	for c: Dictionary in data.get("crops", []):
		var cell := Vector2i(int(c["cell"][0]), int(c["cell"][1]))
		var crop := CropData.new()
		crop.load_data(c, GameManager.crop_database)
		_crop_data[cell] = crop
		_update_crop_visual(cell)


# Per-scene in-memory snapshots around scene swaps (game_scene.gd hooks).
func store_state(scene_name: String) -> void:
	_scene_states[scene_name] = save_data()


func restore_state(scene_name: String) -> void:
	if _scene_states.has(scene_name):
		load_data(_scene_states[scene_name])
