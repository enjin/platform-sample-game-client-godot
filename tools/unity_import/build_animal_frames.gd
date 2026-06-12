# Assembles art/animals/baked/<animal>/<clip>/frame_*.png (Unity bake) into
# per-animal SpriteFrames resources.
#   godot --headless --import .
#   godot --headless -s tools/unity_import/build_animal_frames.gd
extends SceneTree

const BAKED_DIR := "res://art/animals/baked"
const FPS := 12.0


func _init() -> void:
	var dir := DirAccess.open(BAKED_DIR)
	if dir == null:
		push_error("no baked animal frames - run BakeAnimalFrames in Unity first")
		quit(1)
		return
	for animal in dir.get_directories():
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		for clip in DirAccess.open(BAKED_DIR + "/" + animal).get_directories():
			var clip_dir := "%s/%s/%s" % [BAKED_DIR, animal, clip]
			var files: Array[String] = []
			for f in DirAccess.open(clip_dir).get_files():
				if f.ends_with(".png"):
					files.append(f)
			files.sort()
			frames.add_animation(clip)
			frames.set_animation_speed(clip, FPS)
			frames.set_animation_loop(clip, true)
			for f in files:
				var tex: Texture2D = load(clip_dir + "/" + f)
				if tex:
					frames.add_frame(clip, tex)
		var out := "res://resources/%s_frames.tres" % animal
		var err := ResourceSaver.save(frames, out)
		print("saved %s (%s)" % [out, error_string(err)])
	quit(0)
