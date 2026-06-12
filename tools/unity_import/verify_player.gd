# M2 verification: player exists, moves, animates, collides.
#   godot --headless -s tools/unity_import/verify_player.gd
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
	var gm: Node = root.get_node("/root/GameManager")
	await gm.move_to("res://scenes/farm_outdoor.tscn", 0)
	await process_frame
	var player: CharacterBody2D = gm.player
	_check(player != null, "player registered")
	if player == null:
		quit(1)
		return
	_check(player.global_position.distance_to(Vector2(671, 247)) < 2.0,
		"player at spawn 0")
	var cam := player.get_viewport().get_camera_2d()
	_check(cam == player.get_node("Camera2D"), "player camera current")
	_check(cam.limit_right == 4480, "camera limits applied from game_scene")

	# walk right for half a second from open ground south of the porch
	# (the spawn itself is boxed in by the house wall colliders, as in Unity)
	player.global_position = Vector2(671, 420)
	var x0 := player.global_position.x
	Input.action_press("move_right")
	await create_timer(0.5).timeout
	Input.action_release("move_right")
	var moved := player.global_position.x - x0
	_check(moved > 80.0, "moved right (%0.f px)" % moved)

	# the house wall collider blocks walking right from the porch spawn
	player.global_position = Vector2(671, 247)
	Input.action_press("move_right")
	await create_timer(0.5).timeout
	# assert while the key is still held: on release the look direction falls
	# back to facing the mouse, which sits at (0,0) in headless runs
	_check(player.global_position.x < 760.0,
		"house wall blocks porch exit right (x=%.0f)" % player.global_position.x)
	_check(player.get_node("AnimatedSprite2D").animation in [&"walk_side", &"idle_side"],
		"side animation playing (%s)" % player.get_node("AnimatedSprite2D").animation)
	_check(player.look_direction == Vector2.RIGHT, "look direction right")
	Input.action_release("move_right")
	await process_frame

	# walk down into the pond area south of spawn; collision should stop us
	Input.action_press("move_down")
	await create_timer(4.0).timeout
	Input.action_release("move_down")
	var y := player.global_position.y
	# unobstructed walking would cover 4s * 256px = 1024px; the shoreline
	# south of the spawn is ~400px away, so stopping early means collision
	_check(y - 247.0 < 900.0, "pond collision stopped player (dy=%.0f)" % (y - 247.0))

	# toggle_control freezes movement
	player.toggle_control(false)
	var p0: Vector2 = player.global_position
	Input.action_press("move_left")
	await create_timer(0.3).timeout
	Input.action_release("move_left")
	_check(player.global_position.distance_to(p0) < 1.0, "toggle_control(false) freezes")
	player.toggle_control(true)

	print("---- %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	quit(0 if _failures == 0 else 1)
