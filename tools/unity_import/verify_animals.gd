# Animal verification: 5 animals placed, they wander inside their pens, and
# the animation toggles between idle and walk.
#   godot --headless -s tools/unity_import/verify_animals.gd
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
	await gm.move_to("res://scenes/farm_outdoor.tscn", 0)
	await process_frame
	await process_frame

	var animals := []
	for child in current_scene.get_node("Maps/Props").get_children():
		if child.get_script() != null \
				and child.get_script().resource_path.ends_with("animal.gd"):
			animals.append(child)
	_check(animals.size() == 5, "5 animals placed (%d)" % animals.size())
	var chickens := 0
	var pigs := 0
	for a in animals:
		if "Chicken" in String(a.name):
			chickens += 1
		else:
			pigs += 1
	_check(chickens == 3 and pigs == 2, "3 chickens + 2 pigs")

	for a in animals:
		_check(a.area.size != Vector2.ZERO, "%s has pen area" % a.name)
		_check(a.sprite.sprite_frames.has_animation("idle")
			and a.sprite.sprite_frames.has_animation("walk"),
			"%s has idle+walk animations" % a.name)
		_check(a.sprite.is_playing(), "%s animating" % a.name)

	# fast-forward wandering: shrink idle times so they move within the window
	# (including the already-rolled first idle target)
	for a in animals:
		a.min_idle_time = 0.1
		a.max_idle_time = 0.3
		a._idle_target = 0.1
	var start_positions := {}
	for a in animals:
		start_positions[a] = a.global_position
	var saw_walk := false
	var facing_ok := true
	for i in 60:  # ~3s
		await create_timer(0.05).timeout
		for a in animals:
			if a.sprite.animation == &"walk":
				saw_walk = true
				# art faces right; flip_h must be on exactly when heading left
				var dx: float = a._target.x - a.global_position.x
				if absf(dx) > 1.0 and a.sprite.flip_h != (dx < 0):
					facing_ok = false
	var moved := 0
	var inside := true
	for a in animals:
		if a.global_position.distance_to(start_positions[a]) > 8.0:
			moved += 1
		var grown: Rect2 = a.area.grow(4.0)  # tolerance for clamp edge
		if not grown.has_point(a.global_position):
			inside = false
	_check(moved >= 4, "animals wander (%d/5 moved)" % moved)
	_check(saw_walk, "walk animation plays while moving")
	_check(facing_ok, "animals face their movement direction")
	_check(inside, "all animals stayed inside their pens")

	print("---- %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	quit(0 if _failures == 0 else 1)
