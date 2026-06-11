# M3 verification: databases, starting inventory, equip cycling, and the
# EnjinItem -> Item refactor regression (existing .tres must still load).
#   godot --headless -s tools/unity_import/verify_items.gd
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

	# 9 game items/products + the 3 EnjinItem tokens sharing resources/items
	_check(gm.item_database.size() == 12, "item db has 12 entries (%d)" % gm.item_database.size())
	_check(gm.crop_database.size() == 3, "crop db has 3 crops")
	var hoe: Resource = gm.item_database.get_from_id("hoe")
	_check(hoe != null and hoe.display_name == "Hoe", "hoe loads with display name")
	_check(hoe != null and not hoe.consumable and hoe.max_stack_size == 1, "hoe non-consumable")
	var corn_seed: Resource = gm.item_database.get_from_id("corn_seed")
	_check(corn_seed != null and corn_seed.planted_crop != null
		and corn_seed.planted_crop.unique_id == "corn_crop", "seed bag -> crop reference")
	var corn_crop: Resource = gm.crop_database.get_from_id("corn_crop")
	_check(corn_crop != null and corn_crop.produce != null
		and corn_crop.produce.unique_id == "corn_cob", "crop -> produce reference")
	_check(corn_crop != null and corn_crop.growth_stage_textures.size() >= 4,
		"crop has stage textures (%d)" % (corn_crop.growth_stage_textures.size() if corn_crop else 0))
	_check(corn_crop != null and corn_crop.produce.item_sprite != null, "produce has icon sprite")

	# inventory with starting loadout
	var inv = gm.ensure_inventory()
	_check(inv.entries[0].item != null and inv.entries[0].item.unique_id == "hoe",
		"slot 0 = hoe")
	var filled := 0
	for e in inv.entries:
		if e.item != null:
			filled += 1
	_check(filled == 6, "6 starting items (%d)" % filled)
	_check(inv.equipped_item.unique_id == "hoe", "hoe equipped by default")
	inv.equip_next()
	_check(inv.equipped_index == 1, "equip_next")
	inv.equip_prev()
	inv.equip_prev()
	_check(inv.equipped_index == InventorySystem.SIZE - 1, "equip_prev wraps")
	inv.equip_item(0)

	# add/stack/remove
	var corn: Resource = gm.item_database.get_from_id("corn_cob")
	_check(inv.add_item(corn, 3), "add 3 corn")
	var idx: int = inv.get_index_of_item(corn, false)
	_check(idx >= 0 and inv.entries[idx].stack_size == 3, "corn stacked x3")
	_check(inv.remove(idx, 2) == 2, "remove 2 corn")
	_check(inv.entries[idx].stack_size == 1, "1 corn left")
	inv.remove(idx, 1)

	# EnjinItem regression: catalog .tres still load and extend Item.
	# NOTE: no compile-time `is EnjinItem` here - naming the class forces
	# enjin_item.gd to compile before autoloads register, which fails (it
	# references the EnjinManager global) and poisons the script cache.
	var enjin: Node = root.get_node("/root/EnjinManager")
	_check(enjin.blockchain_tokens.size() == 3, "EnjinManager catalog has 3 tokens")
	if enjin.blockchain_tokens.size() == 3:
		var token: Resource = enjin.blockchain_tokens[0]
		var enjin_script: Script = load("res://scripts/enjin/data/enjin_item.gd")
		var item_script: Script = load("res://scripts/game/items/item.gd")
		_check(token.get_script() == enjin_script, "token is EnjinItem")
		_check(enjin_script.get_base_script() == item_script, "EnjinItem extends Item")
		_check(token.collection_id != "-1", "collection id still stamped")
		_check("rarity" in token, "rarity field present")
		_check("max_stack_size" in token, "inherits base Item fields")

	print("---- %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	quit(0 if _failures == 0 else 1)
