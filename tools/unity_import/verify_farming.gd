# M4 verification: the full farming loop on the real farm scene.
#   godot --headless -s tools/unity_import/verify_farming.gd
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
	var terrain = gm.terrain
	_check(terrain != null, "terrain registered")

	# crop initializer pre-planted the demo beds
	var beds := 0
	for cell in terrain._crop_data:
		beds += 1
	_check(beds == 88, "88 demo beds planted (%d)" % beds)

	# find a free tillable cell (field area, no crop)
	var target := Vector2i.ZERO
	var found := false
	for x in range(-40, 70):
		for y in range(-40, 50):
			var c := Vector2i(x, y)
			if terrain.is_tillable(c) and terrain.get_crop_data_at(c) == null:
				target = c
				found = true
				break
		if found:
			break
	_check(found, "found free tillable cell %s" % target)

	# manual loop: till -> water -> plant -> grow -> harvest
	_check(not terrain.is_tilled(target), "not tilled initially")
	terrain.till_at(target)
	_check(terrain.is_tilled(target), "tilled")
	_check(not terrain.is_tillable(target), "tilled cell no longer tillable")
	_check(terrain.is_plantable(target), "plantable")
	terrain.water_at(target)
	var corn: Resource = gm.crop_database.get_from_id("corn_crop")
	terrain.plant_at(target, corn)
	_check(terrain.get_crop_data_at(target) != null, "crop planted")
	_check(not terrain.is_plantable(target), "occupied cell not plantable")
	# fast-forward growth
	terrain.override_growth_stage(target, corn.growth_stage_textures.size() - 1)
	var data = terrain.get_crop_data_at(target)
	_check(is_equal_approx(data.growth_ratio, 1.0), "growth ratio 1.0 after override")

	# harvest through the basket item + player inventory
	var inv = gm.ensure_inventory()
	var basket: Resource = gm.item_database.get_from_id("basket")
	var corn_before := _count_item(inv, "corn_cob")
	_check(basket.can_use(target), "basket can_use on grown crop")
	_check(basket.use(target), "basket harvest")
	var corn_after := _count_item(inv, "corn_cob")
	_check(corn_after == corn_before + corn.product_per_harvest,
		"harvest yielded %d corn" % corn.product_per_harvest)

	# water expiry: tick water timer down and confirm overlay clears
	var ground = terrain._ground_data[target]
	ground.water_timer = 0.05
	await create_timer(0.3).timeout
	_check(terrain.water_overlay.get_cell_source_id(target) == -1, "water overlay expired")

	# hoe use triggers terrain till + (sometimes) token reveal - run on a new
	# cell via the item path to cover the Enjin hook signature
	var hoe: Resource = gm.item_database.get_from_id("hoe")
	var target2 := target + Vector2i(1, 0) if terrain.is_tillable(target + Vector2i(1, 0)) else target
	var ok := true
	if terrain.is_tillable(target2):
		ok = hoe.use(target2)
	_check(ok, "hoe.use works (incl. randomly_reveal_token call)")

	# scene-swap state retention
	await gm.move_to("res://scenes/house_interior.tscn", 1)
	await gm.move_to("res://scenes/farm_outdoor.tscn", 0)
	await process_frame
	await process_frame
	terrain = gm.terrain
	_check(terrain.is_tilled(target), "tilled state survived scene round-trip")

	print("---- %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	quit(0 if _failures == 0 else 1)


func _count_item(inv, id: String) -> int:
	var total := 0
	for e in inv.entries:
		if e.item != null and e.item.unique_id == id:
			total += e.stack_size
	return total
