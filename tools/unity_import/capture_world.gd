# Captures night/rain shots for M6 visual verification.
#   godot --path . -s tools/unity_import/capture_world.gd
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var gm: Node = root.get_node("/root/GameManager")
	await gm.move_to("res://scenes/farm_outdoor.tscn", 0)
	await create_timer(0.5).timeout
	var out := ProjectSettings.globalize_path("res://tools/unity_import/out")

	gm._current_time_seconds = 0.92 * gm.day_duration_seconds  # night
	await create_timer(0.3).timeout
	root.get_viewport().get_texture().get_image().save_png(out + "/world_night.png")

	gm._current_time_seconds = 0.5 * gm.day_duration_seconds  # noon
	current_scene.get_node("Weather").change_weather(2 | 4)
	await create_timer(2.5).timeout
	root.get_viewport().get_texture().get_image().save_png(out + "/world_rain.png")
	print("captured world shots")
	quit(0)
