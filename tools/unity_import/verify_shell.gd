# M1 verification: boots scenes and runs a farm<->house transition headlessly.
#   godot --headless -s tools/unity_import/verify_shell.gd
extends SceneTree

var _failures := 0


func _init() -> void:
	_run()


func _check(cond: bool, label: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + label)
	if not cond:
		_failures += 1


func _run() -> void:
	await process_frame
	# scenes load and instantiate
	for path in ["res://scenes/loader.tscn", "res://scenes/main_menu.tscn",
			"res://scenes/farm_outdoor.tscn", "res://scenes/house_interior.tscn"]:
		var ps: PackedScene = load(path)
		_check(ps != null, "load " + path)

	# move_to farm: spawn registration + scene data hookup
	var gm: Node = root.get_node("/root/GameManager")
	await gm.move_to("res://scenes/farm_outdoor.tscn", 0)
	_check(current_scene != null and current_scene.name == "FarmOutdoor", "move_to farm")
	_check(gm.current_scene_data == current_scene, "scene data registered")
	_check(gm.get_spawn(0) != null, "farm spawn 0 registered")
	_check(gm.current_scene_data.unique_scene_name == "Farm", "farm unique name")

	# transition to house spawn 1
	await gm.move_to("res://scenes/house_interior.tscn", 1)
	_check(current_scene != null and current_scene.name == "HouseInterior", "move_to house")
	_check(gm.get_spawn(0) != null and gm.get_spawn(1) != null, "house spawns registered")

	# clock ticks
	var r0: float = gm.current_day_ratio
	await create_timer(0.3).timeout
	_check(gm.current_day_ratio != r0, "day clock ticking")
	_check(gm.get_time_as_string(0.5) == "12:00", "time formatting")

	print("---- %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	quit(0 if _failures == 0 else 1)
