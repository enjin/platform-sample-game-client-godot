# Captures the running farm scene with the player for visual checks.
#   godot --path . -s tools/unity_import/capture_gameplay.gd
extends SceneTree


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var gm: Node = root.get_node("/root/GameManager")
	await gm.move_to("res://scenes/farm_outdoor.tscn", 0)
	await create_timer(0.5).timeout
	var out := ProjectSettings.globalize_path("res://tools/unity_import/out")
	root.get_viewport().get_texture().get_image().save_png(out + "/gameplay_farm.png")
	# field shot: teleport next to the demo crop beds
	gm.player.global_position = Vector2(3 * 64, 14 * 64)
	gm.player.get_node("Camera2D").reset_smoothing()
	await create_timer(0.4).timeout
	root.get_viewport().get_texture().get_image().save_png(out + "/gameplay_field.png")
	Input.action_press("move_left")
	await create_timer(1.2).timeout
	Input.action_release("move_left")
	root.get_viewport().get_texture().get_image().save_png(out + "/gameplay_farm_walk.png")
	await gm.move_to("res://scenes/house_interior.tscn", 1)
	await create_timer(0.5).timeout
	root.get_viewport().get_texture().get_image().save_png(out + "/gameplay_house.png")
	print("captured gameplay shots")
	quit(0)
