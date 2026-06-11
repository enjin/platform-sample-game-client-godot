# Renders generated tilemap scenes to PNGs for visual verification.
# Run windowed (rendering needed):
#   godot --path . -s tools/unity_import/capture_preview.gd
extends SceneTree

const SHOTS := [
	# scene, camera center (px), zoom, output
	["res://scenes/maps/farm_outdoor_tilemaps.tscn", Vector2(16 * 64, 4 * 64), 0.28, "farm_preview.png"],
	["res://scenes/maps/farm_outdoor_tilemaps.tscn", Vector2(11 * 64, 0), 1.0, "farm_house_closeup.png"],
	["res://scenes/maps/farm_outdoor_tilemaps.tscn", Vector2(40 * 64, 12 * 64), 0.8, "farm_pond_closeup.png"],
	["res://scenes/maps/house_interior_tilemaps.tscn", Vector2(5 * 64, -4 * 64), 0.7, "house_preview.png"],
]


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var out_dir := ProjectSettings.globalize_path("res://tools/unity_import/out")
	for shot: Array in SHOTS:
		var scene: PackedScene = load(shot[0])
		var inst: Node2D = scene.instantiate()
		root.add_child(inst)
		var cam := Camera2D.new()
		cam.position = shot[1]
		cam.zoom = Vector2(shot[2], shot[2])
		root.add_child(cam)
		cam.make_current()
		await process_frame
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out_dir + "/" + shot[3])
		print("captured ", shot[3])
		cam.queue_free()
		inst.queue_free()
		await process_frame
	quit(0)
