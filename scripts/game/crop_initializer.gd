# Pre-plants the demo crop beds on scene start. Port of CropInitializer.cs;
# the bed list was extracted from the Unity Farm_Outdoor scene into
# resources/databases/farm_crop_init.json.
extends Node

@export_file("*.json") var init_list_path: String = "res://resources/databases/farm_crop_init.json"


func _ready() -> void:
	# wait one frame so the TerrainManager registers first
	await get_tree().process_frame
	# untyped on purpose: a TerrainManager annotation makes this script's
	# compile depend on the global class cache, which the headless -s test
	# harness doesn't have yet at scene load
	var terrain = GameManager.terrain
	if terrain == null:
		return
	var f := FileAccess.open(init_list_path, FileAccess.READ)
	if f == null:
		push_warning("crop init list missing: " + init_list_path)
		return
	for bed: Dictionary in JSON.parse_string(f.get_as_text()):
		var cell := Vector2i(int(bed["cell"][0]), int(bed["cell"][1]))
		var crop: Crop = GameManager.crop_database.get_from_id(bed["crop_id"])
		if crop == null:
			continue
		if (terrain.is_tillable(cell) or terrain.is_tilled(cell)) \
				and terrain.get_crop_data_at(cell) == null:
			terrain.till_at(cell)
			terrain.water_at(cell)
			terrain.plant_at(cell, crop)
			terrain.override_growth_stage(cell, int(bed["starting_stage"]))
