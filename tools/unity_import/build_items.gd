# Builds item/product/crop .tres resources from the dump_items.py output.
#   python3 tools/unity_import/dump_items.py
#   godot --headless --import .
#   godot --headless -s tools/unity_import/build_items.gd
extends SceneTree

# loaded in _run() after autoloads register: the item scripts reference the
# GameManager global, which doesn't exist at -s script compile time
var _scripts := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	for cls in ["Hoe", "WaterCan", "SeedBag", "Basket", "Product"]:
		_scripts[cls] = load("res://scripts/game/items/%s.gd" % cls.to_snake_case())
	_scripts["Crop"] = load("res://scripts/game/data/crop.gd")
	var path := ProjectSettings.globalize_path("res://tools/unity_import/out/items.json")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("run dump_items.py first")
		quit(1)
		return
	var items: Array = JSON.parse_string(f.get_as_text())
	for dir in ["res://resources/items", "res://resources/products", "res://resources/crops"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	# two passes: products/crops first so seed bags and crops can reference them
	var by_guid := {}
	for pass_classes in [["Product"], ["Crop"], ["Hoe", "WaterCan", "SeedBag", "Basket"]]:
		for it: Dictionary in items:
			if not (it["class"] in pass_classes):
				continue
			var res: Resource = _build(it, by_guid)
			if res == null:
				continue
			var out := _out_path(it)
			var err := ResourceSaver.save(res, out)
			by_guid[it.guid] = res
			# re-load under its saved path so cross-references serialize as
			# ext_resource instead of inlining
			by_guid[it.guid] = load(out)
			print("saved %s (%s)" % [out, error_string(err)])
	quit(0)


func _out_path(it: Dictionary) -> String:
	var id: String = it.unique_id
	match it["class"]:
		"Product":
			return "res://resources/products/%s.tres" % id
		"Crop":
			return "res://resources/crops/%s.tres" % id
		_:
			return "res://resources/items/%s.tres" % id


func _texture(ref) -> Texture2D:
	if ref == null:
		return null
	var tex: Texture2D = load(ref.texture)
	if tex == null:
		push_warning("missing texture " + str(ref.texture))
		return null
	var rect: Array = ref.rect
	if int(rect[0]) == 0 and int(rect[1]) == 0 \
			and int(rect[2]) == tex.get_width() and int(rect[3]) == tex.get_height():
		return tex
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(rect[0], rect[1], rect[2], rect[3])
	return atlas


func _build(it: Dictionary, by_guid: Dictionary) -> Resource:
	if it["class"] == "Crop":
		var crop: Resource = _scripts["Crop"].new()
		crop.unique_id = it.unique_id
		var stages: Array[Texture2D] = []
		for s in it.growth_stages:
			var t := _texture(s)
			if t:
				stages.append(t)
		crop.growth_stage_textures = stages
		crop.stage_texture_scale = it.get("stage_scale", 1.0)
		crop.produce = by_guid.get(it.produce_guid)
		crop.growth_time = it.growth_time
		crop.number_of_harvest = int(it.number_of_harvest)
		crop.stage_after_harvest = int(it.stage_after_harvest)
		crop.product_per_harvest = int(it.product_per_harvest)
		crop.dry_death_timer = it.dry_death_timer
		return crop

	if not _scripts.has(it["class"]):
		return null
	var item: Resource = _scripts[it["class"]].new()
	item.unique_id = it.unique_id
	item.display_name = it.display_name
	item.item_sprite = _texture(it.item_sprite)
	item.max_stack_size = int(it.max_stack_size)
	item.consumable = bool(it.consumable)
	item.buy_price = int(it.buy_price)
	item.player_animator_trigger_use = it.animator_trigger
	var sounds: Array[AudioStream] = []
	for s in it.use_sounds:
		var stream: AudioStream = load(s)
		if stream:
			sounds.append(stream)
	item.use_sound = sounds
	if it["class"] == "SeedBag":
		item.planted_crop = by_guid.get(it.planted_crop_guid)
	if it["class"] == "Product":
		item.sell_price = int(it.sell_price)
	return item
