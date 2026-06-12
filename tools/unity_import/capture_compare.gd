# Renders Godot shots framed identically to CaptureSceneShots.cs in the Unity
# project (out/unity_ref/) for side-by-side comparison.
#   godot --path . --resolution 1280x720 -s tools/unity_import/capture_compare.gd
extends SceneTree

# [scene, godot world pos (px), zoom, name]
# zoom = canvas_height / (unity_ortho_size * 2 * 64); the project canvas is
# 1080 high regardless of window size (canvas_items stretch), hence 1080.
var shots := [
	["res://scenes/farm_outdoor.tscn", Vector2(704, 0), 1.5, "farm_outdoor_house"],
	["res://scenes/farm_outdoor.tscn", Vector2(672, 250), 2.25, "farm_outdoor_spawn"],
	["res://scenes/farm_outdoor.tscn", Vector2(2560, 768), 1.2054, "farm_outdoor_pond"],
	["res://scenes/farm_outdoor.tscn", Vector2(192, 896), 2.25, "farm_outdoor_field"],
	["res://scenes/farm_outdoor.tscn", Vector2(1024, 256), 0.42188, "farm_outdoor_overview"],
	["res://scenes/house_interior.tscn", Vector2(0, -16), 1.5, "house_interior_interior"],
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var gm: Node = root.get_node("/root/GameManager")
	var out := ProjectSettings.globalize_path("res://tools/unity_import/out/godot_ref")
	DirAccess.make_dir_recursive_absolute(out)
	var current := ""
	for shot: Array in shots:
		if shot[0] != current:
			await gm.move_to(shot[0], 0)
			current = shot[0]
			gm.is_ticking = false
			gm._current_time_seconds = 0.43 * gm.day_duration_seconds  # flat white tint
			gm.day_ratio_changed.emit(gm.current_day_ratio)
			# hide gameplay-only elements for a fair scene comparison
			for n in ["HUD", "Player"]:
				if current_scene.has_node(n):
					current_scene.get_node(n).visible = false
			if current_scene.has_node("Player"):
				current_scene.get_node("Player").process_mode = Node.PROCESS_MODE_DISABLED
		var cam := Camera2D.new()
		cam.position = shot[1]
		cam.zoom = Vector2(shot[2], shot[2])
		root.add_child(cam)
		cam.make_current()
		await process_frame
		await process_frame
		await process_frame
		root.get_viewport().get_texture().get_image().save_png(
			"%s/%s.png" % [out, shot[3]])
		print("captured ", shot[3])
		cam.queue_free()
	quit(0)
