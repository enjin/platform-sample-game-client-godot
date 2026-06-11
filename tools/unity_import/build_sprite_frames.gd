# Assembles art/characters/baked/<clip>/frame_*.png (from the Unity bake)
# into a SpriteFrames resource for the player's AnimatedSprite2D.
#   godot --headless --import .          (after the bake copied new PNGs)
#   godot --headless -s tools/unity_import/build_sprite_frames.gd
extends SceneTree

const BAKED_DIR := "res://art/characters/baked"
const OUT_PATH := "res://resources/player_frames.tres"
const FPS := 10.0
const LOOPING := ["walk_down", "walk_up", "walk_side", "walk_side_l",
	"idle_front", "idle_side", "idle_up", "eating"]


func _init() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var dir := DirAccess.open(BAKED_DIR)
	if dir == null:
		push_error("no baked frames at " + BAKED_DIR + " - run the Unity bake first")
		quit(1)
		return
	var clip_count := 0
	for clip in dir.get_directories():
		var clip_dir := BAKED_DIR + "/" + clip
		var files: Array[String] = []
		for f in DirAccess.open(clip_dir).get_files():
			if f.ends_with(".png"):
				files.append(f)
		files.sort()
		if files.is_empty():
			continue
		var anim := clip.to_lower()
		frames.add_animation(anim)
		frames.set_animation_speed(anim, FPS)
		frames.set_animation_loop(anim, anim in LOOPING)
		for f in files:
			var tex: Texture2D = load(clip_dir + "/" + f)
			if tex:
				frames.add_frame(anim, tex)
		clip_count += 1
	var err := ResourceSaver.save(frames, OUT_PATH)
	print("saved %s: %d animations (%s)" % [OUT_PATH, clip_count, error_string(err)])
	quit(0 if err == OK else 1)
