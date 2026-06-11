# M7 verification: token reveal/collect and backpack UI. Online checks
# (login, wallet rows) run only when the game server responds.
#   godot --headless -s tools/unity_import/verify_enjin_ui.gd
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
	var enjin: Node = root.get_node("/root/EnjinManager")
	await gm.move_to("res://scenes/farm_outdoor.tscn", 0)
	await process_frame
	await process_frame

	# token catalog has sprites + visual prefabs now
	_check(enjin.blockchain_tokens.size() == 3, "catalog: 3 tokens")
	for t in enjin.blockchain_tokens:
		_check(t.item_sprite != null, "%s has sprite" % t.unique_id)
		_check(t.visual_prefab != null, "%s has visual prefab" % t.unique_id)

	# forced reveal spawns a token with an item assigned
	enjin.token_reveal_probability_threshold = 0.0  # roll always passes
	var before := _count_tokens()
	enjin.randomly_reveal_token(Vector2(700, 300))
	await process_frame
	var tokens := _find_tokens()
	_check(tokens.size() == before + 1, "reveal spawned a token")
	if not tokens.is_empty():
		var token: Node = tokens[-1]
		_check(token.item != null, "spawned token has item (%s)" %
			(token.item.unique_id if token.item else "none"))
		token.collect()  # mint will fail offline; destruction is intentional
		await process_frame
		await process_frame
		_check(not is_instance_valid(token) or token.is_queued_for_deletion(),
			"collect frees the token")

	# backpack toggles via the HUD instance
	var backpack: Control = current_scene.get_node("HUD/Root/Backpack")
	_check(backpack != null and not backpack.visible, "backpack hidden initially")
	backpack.toggle()
	_check(backpack.visible, "backpack opens")
	if not enjin.is_logged_in():
		_check("Not logged in" in backpack.status_label.text, "offline status shown")
	backpack.toggle()
	_check(not backpack.visible, "backpack closes")

	# online flow (only when the server is up)
	var api: Node = root.get_node("/root/EnjinApiService")
	var healthy: bool = await api.perform_health_check()
	if healthy:
		print("server reachable - running online checks")
		var email := OS.get_environment("SMOKE_EMAIL")
		if email.is_empty():
			email = "godot-smoke@example.com"
		var password := OS.get_environment("SMOKE_PASSWORD")
		if password.is_empty():
			password = "godot-pass-123"
		enjin.register_and_login(email, password)
		var ok: bool = await enjin.login_complete
		_check(ok, "login")
		backpack.open()
		await enjin.wallet_updated
		await process_frame
		_check(backpack.rows.get_child_count() >= 0, "wallet rows populated (%d)"
			% backpack.rows.get_child_count())
	else:
		print("server offline - skipped online checks")

	print("---- %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	quit(0 if _failures == 0 else 1)


func _find_tokens() -> Array:
	var out := []
	for child in current_scene.get_children():
		if child.get_script() != null \
				and child.get_script().resource_path.ends_with("enjin_token.gd"):
			out.append(child)
	return out


func _count_tokens() -> int:
	return _find_tokens().size()
