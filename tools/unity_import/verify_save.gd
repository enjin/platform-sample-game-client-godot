# M5 verification: save -> mutate -> load restores state.
#   godot --headless -s tools/unity_import/verify_save.gd
extends SceneTree

var _failures := 0


func _init() -> void:
	_run.call_deferred()


func _check(cond: bool, label: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + label)
	if not cond:
		_failures += 1


func _run() -> void:
	await process_frame
	var gm: Node = root.get_node("/root/GameManager")
	var save: Node = root.get_node("/root/SaveSystem")
	# clean slate
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.sav"))

	await gm.move_to("res://scenes/farm_outdoor.tscn", 0)
	await process_frame
	await process_frame

	# set up identifiable state
	var terrain = gm.terrain
	var cell := Vector2i(-16, 4)
	terrain.till_at(cell)
	terrain.water_at(cell)
	terrain.plant_at(cell, gm.crop_database.get_from_id("wheat_crop"))
	gm.coins = 77
	gm.player.global_position = Vector2(123, 456)
	save.save_game()
	_check(FileAccess.file_exists("user://save.sav"), "save file written")
	var parsed = JSON.parse_string(
		FileAccess.open("user://save.sav", FileAccess.READ).get_as_text())
	_check(parsed != null, "save file is valid JSON")
	_check(int(parsed["player"]["coins"]) == 77, "coins in save")
	_check(parsed["scenes"].has("Farm"), "farm terrain in save")

	# mutate everything
	gm.coins = 1
	gm.player.global_position = Vector2(999, 999)
	terrain.harvest_at(cell)  # no-op (not grown) but fine
	gm.inventory.remove(0, 1)  # drop the hoe

	await save.load_game()
	await process_frame
	await process_frame
	_check(gm.coins == 77, "coins restored")
	_check(gm.player.global_position.distance_to(Vector2(123, 456)) < 2.0,
		"player position restored")
	_check(gm.inventory.entries[0].item != null
		and gm.inventory.entries[0].item.unique_id == "hoe", "inventory restored")
	var t = gm.terrain
	_check(t.is_tilled(cell), "tilled cell restored")
	_check(t.get_crop_data_at(cell) != null
		and t.get_crop_data_at(cell).growing_crop.unique_id == "wheat_crop",
		"crop restored")

	print("---- %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	quit(0 if _failures == 0 else 1)
