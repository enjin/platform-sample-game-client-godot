# Captures main menu and backpack shots for the final visual check.
#   godot --path . -s tools/unity_import/capture_ui.gd
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var out := ProjectSettings.globalize_path("res://tools/unity_import/out")
	change_scene_to_file("res://scenes/main_menu.tscn")
	await create_timer(0.6).timeout
	root.get_viewport().get_texture().get_image().save_png(out + "/ui_menu.png")

	var gm: Node = root.get_node("/root/GameManager")
	await gm.move_to("res://scenes/farm_outdoor.tscn", 0)
	await create_timer(0.4).timeout
	current_scene.get_node("HUD/Root/Backpack").open()
	await create_timer(0.3).timeout
	root.get_viewport().get_texture().get_image().save_png(out + "/ui_backpack.png")
	print("captured ui shots")
	quit(0)
