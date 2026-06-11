# Save/load to user://save.sav as JSON. Port of SaveSystem.cs - the structure
# mirrors Unity's PlayerSaveData + per-scene TerrainDataSave field-for-field.
# Per-scene snapshots around scene swaps live on TerrainManager._scene_states;
# this file persists everything across runs.
extends Node

const SAVE_PATH := "user://save.sav"
# loaded lazily: naming the TerrainManager class here would tie this
# autoload's compile to the global class cache / autoload init order
const _TERRAIN_SCRIPT := "res://scripts/game/terrain_manager.gd"


func _scene_states() -> Dictionary:
	return load(_TERRAIN_SCRIPT)._scene_states


func save_game() -> void:
	var player: Node2D = GameManager.player
	var data := {
		"player": {
			"position": [GameManager.player.global_position.x,
				GameManager.player.global_position.y] if player else [0, 0],
			"coins": GameManager.coins,
			"inventory": GameManager.inventory.save_data() if GameManager.inventory else [],
		},
		"time": {
			"time_seconds": GameManager._current_time_seconds,
			"day": GameManager.day,
		},
		"current_scene": get_tree().current_scene.scene_file_path,
		"scenes": {},
	}
	# flush the active scene's terrain into the in-memory cache, then persist
	# every cached scene
	if GameManager.current_scene_data:
		GameManager.current_scene_data.save_scene_state()
	var states := _scene_states()
	for scene_name in states:
		data["scenes"][scene_name] = states[scene_name]

	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	print("[SaveSystem] saved to ", SAVE_PATH)


func load_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("[SaveSystem] no save file")
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	if data == null:
		push_error("[SaveSystem] corrupt save file")
		return

	GameManager.coins = int(data["player"]["coins"])
	GameManager.ensure_inventory().load_data(
		data["player"]["inventory"], GameManager.item_database)
	GameManager._current_time_seconds = data["time"]["time_seconds"]
	GameManager.day = int(data["time"]["day"])

	var states := _scene_states()
	states.clear()
	for scene_name in data.get("scenes", {}):
		states[scene_name] = data["scenes"][scene_name]

	# reload the saved scene; terrain restores via game_scene/load hooks
	await GameManager.move_to(data.get("current_scene",
		"res://scenes/farm_outdoor.tscn"), 0)
	if GameManager.terrain and GameManager.current_scene_data:
		GameManager.current_scene_data.load_scene_state()
	if GameManager.player:
		var pos: Array = data["player"]["position"]
		GameManager.player.global_position = Vector2(pos[0], pos[1])
		var cam := GameManager.player.get_viewport().get_camera_2d()
		if cam:
			cam.reset_smoothing()
	print("[SaveSystem] loaded from ", SAVE_PATH)
