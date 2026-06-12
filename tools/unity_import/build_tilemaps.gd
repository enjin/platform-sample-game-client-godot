# One-off builder: turns the extractor's JSON manifests into a shared TileSet
# and packed tilemap scenes. Run headless from the project root:
#   godot --headless --import .
#   godot --headless -s tools/unity_import/build_tilemaps.gd
# Re-runnable: gameplay scenes only *instance* the generated .tscn files.
extends SceneTree

const TILE := 64
const OUT_TILESET := "res://resources/tilesets/world_tileset.tres"
const SCENES := {
	"farm_outdoor": "res://scenes/maps/farm_outdoor_tilemaps.tscn",
	"house_interior": "res://scenes/maps/house_interior_tilemaps.tscn",
}

var _manifest_dir: String


func _init() -> void:
	_manifest_dir = ProjectSettings.globalize_path("res://tools/unity_import/out")
	var textures: Dictionary = _read_json(_manifest_dir + "/textures.json")
	if textures.is_empty():
		push_error("no textures.json - run extract_unity_maps.py first")
		quit(1)
		return

	var manifests := {}
	for scene_name: String in SCENES:
		manifests[scene_name] = _read_json("%s/%s.json" % [_manifest_dir, scene_name])

	var tileset := _build_tileset(manifests, textures)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://resources/tilesets"))
	var err := ResourceSaver.save(tileset, OUT_TILESET)
	print("saved %s (%s)" % [OUT_TILESET, error_string(err)])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/maps"))
	for scene_name: String in SCENES:
		_build_scene(scene_name, manifests[scene_name], tileset, textures)
	quit(0)


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("missing manifest: " + path)
		return {}
	return JSON.parse_string(f.get_as_text())


func _tex_path(textures: Dictionary, key: String) -> String:
	if key.begins_with("res://"):
		return key
	return textures.get(key, {}).get("godot_path", "")


# --------------------------------------------------------------- tileset

# source ids are stable per texture path; tile = atlas cell at rect/64
func _build_tileset(manifests: Dictionary, textures: Dictionary) -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	tileset.add_physics_layer()  # layer 0: world collision
	tileset.set_physics_layer_collision_layer(0, 1)
	tileset.add_custom_data_layer()
	tileset.set_custom_data_layer_name(0, "tillable")
	tileset.set_custom_data_layer_type(0, TYPE_BOOL)
	# soil: "" | "tillable" | "tilled" | "watered" - the TerrainManager finds
	# its working tiles by scanning for these values (ids are not stable)
	tileset.add_custom_data_layer()
	tileset.set_custom_data_layer_name(1, "soil")
	tileset.set_custom_data_layer_type(1, TYPE_STRING)

	# TerrainManager working tiles (tillable dirt / tilled / watered soil),
	# resolved from the Unity TerrainManager component - these may not appear
	# as baked scene cells, so force them into the tileset
	var soil := {}  # "tex|cx|cy" -> soil kind
	var terrain_tiles: Dictionary = _read_json(_manifest_dir + "/terrain_tiles.json")

	# collect (texture res path -> {Vector2i atlas coords -> Vector2i size});
	# everything is keyed by the godot res:// path so soil tiles and scene
	# cells referencing the same png share one atlas source
	var per_tex := {}
	var unity_of := {}  # res path -> unity rel (for physics/tillable lookups)
	var tillable := {}  # "res_path|cx|cy" -> true, from the TilledTilemap layer
	for kind: String in terrain_tiles:
		var tt: Dictionary = terrain_tiles[kind]
		var coords := Vector2i(int(tt.rect[0]) / TILE, int(tt.rect[1]) / TILE)
		var tex_res: String = tt.texture
		if not per_tex.has(tex_res):
			per_tex[tex_res] = {}
		per_tex[tex_res][coords] = Vector2i.ONE
		soil["%s|%d|%d" % [tex_res, coords.x, coords.y]] = kind
	for scene_name: String in manifests:
		for layer: Dictionary in manifests[scene_name]:
			for cell: Dictionary in layer.cells:
				var rect: Array = cell.rect
				var coords := Vector2i(int(rect[0]) / TILE, int(rect[1]) / TILE)
				var size := Vector2i(maxi(1, int(rect[2]) / TILE), maxi(1, int(rect[3]) / TILE))
				var tex := _tex_path(textures, cell.texture)
				if tex.is_empty():
					continue
				unity_of[tex] = cell.texture
				if not per_tex.has(tex):
					per_tex[tex] = {}
				per_tex[tex][coords] = size
				if layer.layer_name == "TilledTilemap":
					tillable["%s|%d|%d" % [tex, coords.x, coords.y]] = true

	# physics polygons keyed "unity_rel|x|y|w|h" (godot rect) from both scenes
	var physics := {}
	for scene_name: String in manifests:
		var p: Dictionary = _read_json("%s/%s_tile_physics.json" % [_manifest_dir, scene_name])
		physics.merge(p)

	var source_id := 0
	for tex: String in per_tex:
		var texture: Texture2D = load(tex)
		if texture == null:
			push_warning("missing texture " + tex)
			continue
		var src := TileSetAtlasSource.new()
		src.texture = texture
		src.texture_region_size = Vector2i(TILE, TILE)
		src.resource_name = tex.get_file()
		tileset.add_source(src, source_id)
		var skipped := 0
		for coords: Vector2i in per_tex[tex]:
			var size: Vector2i = per_tex[tex][coords]
			if src.has_room_for_tile(coords, size, 1, Vector2i.ZERO, 1):
				src.create_tile(coords, size)
			else:
				skipped += 1
				continue
			var data := src.get_tile_data(coords, 0)
			# physics manifests are keyed by the unity-relative texture path
			var key := "%s|%d|%d|%d|%d" % [unity_of.get(tex, tex), coords.x * TILE,
					coords.y * TILE, size.x * TILE, size.y * TILE]
			if physics.has(key):
				var poly_idx := 0
				for path: Array in physics[key]:
					var points := PackedVector2Array()
					for pt: Array in path:
						points.append(Vector2(pt[0], pt[1]))
					data.add_collision_polygon(0)
					data.set_collision_polygon_points(0, poly_idx, points)
					poly_idx += 1
			if tillable.has("%s|%d|%d" % [tex, coords.x, coords.y]):
				data.set_custom_data("tillable", true)
			var soil_kind: String = soil.get("%s|%d|%d" % [tex, coords.x, coords.y], "")
			if soil_kind != "":
				data.set_custom_data("soil", soil_kind)
				if soil_kind == "tillable":
					data.set_custom_data("tillable", true)
		if skipped > 0:
			push_warning("%s: %d tiles skipped (overlap)" % [tex, skipped])
		source_id += 1
	print("tileset: %d atlas sources" % source_id)
	return tileset


func _find_tile(tileset: TileSet, textures: Dictionary, tex: String, coords: Vector2i) -> int:
	for i in tileset.get_source_count():
		var sid := tileset.get_source_id(i)
		var src := tileset.get_source(sid) as TileSetAtlasSource
		if src and src.texture and src.texture.resource_path == _tex_path(textures, tex):
			return sid if src.has_tile(coords) else -1
	return -1


# ----------------------------------------------------------------- scenes

func _build_scene(scene_name: String, layers: Variant, tileset: TileSet,
		textures: Dictionary) -> void:
	var root := Node2D.new()
	root.name = scene_name.to_pascal_case()
	# the whole world y-sorts: props/crops/player at z 0 sort by Y, ground
	# tile layers sit at z -1 below them, Roof/Chimney keep z > 0 above
	root.y_sort_enabled = true

	var missing := 0
	for layer: Dictionary in layers:
		var tml := TileMapLayer.new()
		tml.name = layer.layer_name
		tml.tile_set = tileset
		# Unity sorting layers map to z planes: Bottom/Default (<=0) are
		# ground at z -1; Objects (1: house/warehouse walls, tree tops) share
		# z 0 with props and the player; ObjectsFront (2: roof, chimney)
		# keeps its explicit order above the player.
		var rank := int(layer.get("sorting_layer", 0))
		if rank <= 0:
			tml.z_index = -1
		elif rank == 1:
			tml.z_index = 0
		else:
			tml.z_index = maxi(1, int(layer.sorting_order))
		root.add_child(tml)
		tml.owner = root
		for cell: Dictionary in layer.cells:
			var rect: Array = cell.rect
			var coords := Vector2i(int(rect[0]) / TILE, int(rect[1]) / TILE)
			var sid := _find_tile(tileset, textures, cell.texture, coords)
			if sid < 0:
				missing += 1
				continue
			tml.set_cell(Vector2i(int(cell.x), int(cell.y)), sid, coords)

	_add_props(root, scene_name, textures)
	_add_baked_props(root, scene_name)
	_add_animals(root, scene_name)
	_add_fence_collision(root, scene_name)
	_add_building_collision(root, layers)

	if missing > 0:
		push_warning("%s: %d cells skipped (missing tiles)" % [scene_name, missing])
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, SCENES[scene_name])
	print("saved %s (%s)" % [SCENES[scene_name], error_string(err)])
	root.free()


# Props: Sprite2D per entry under a Y-sorted parent. Position is the Unity
# pivot point; offset shifts the drawn rect so the visual matches while
# Y-sort keys off the pivot, same as Unity's pivot-based sorting.
func _add_props(root: Node2D, scene_name: String, textures: Dictionary) -> void:
	var props: Variant = _read_json("%s/%s_props.json" % [_manifest_dir, scene_name])
	if not props is Array:
		return
	var parent := Node2D.new()
	parent.name = "Props"
	parent.y_sort_enabled = true
	root.add_child(parent)
	parent.owner = root
	var used_names := {}
	for p: Dictionary in props:
		var res_path := _tex_path(textures, p.texture)
		var texture: Texture2D = load(res_path) if res_path else null
		if texture == null:
			continue
		var spr := Sprite2D.new()
		var base: String = str(p.name).validate_node_name()
		var n := base
		var i := 2
		while used_names.has(n):
			n = "%s_%d" % [base, i]
			i += 1
		used_names[n] = true
		spr.name = n
		spr.texture = texture
		var rect: Array = p.rect
		if not (int(rect[0]) == 0 and int(rect[1]) == 0
				and int(rect[2]) == texture.get_width()
				and int(rect[3]) == texture.get_height()):
			spr.region_enabled = true
			spr.region_rect = Rect2(rect[0], rect[1], rect[2], rect[3])
		spr.position = Vector2(p.position[0], p.position[1])
		var pivot: Array = p.pivot
		spr.offset = Vector2((0.5 - float(pivot[0])) * float(rect[2]),
				(float(pivot[1]) - 0.5) * float(rect[3]))
		spr.flip_h = bool(p.flip_x)
		# Unity tints white base art per renderer/instance (couches, chairs)
		var c: Array = p.get("color", [1, 1, 1, 1])
		spr.modulate = Color(c[0], c[1], c[2], c[3])
		spr.flip_v = bool(p.flip_y)
		spr.scale = Vector2(p.scale[0], p.scale[1])
		# same z planes as the tile layers (see _build_scene)
		var rank := int(p.get("sorting_layer", 0))
		if rank <= 0 and rank + int(p.sorting_order) < 0:
			spr.z_index = -1
		elif rank >= 2:
			spr.z_index = maxi(1, int(p.sorting_order))
		parent.add_child(spr)
		spr.owner = root


# PSD-rigged set pieces (market, scarecrows, animals) were baked to single
# PNGs by BakePrefabSprites.cs in the Unity project; place them at the
# positions recorded in the manual-pass prefab list.
func _add_baked_props(root: Node2D, scene_name: String) -> void:
	var baked: Dictionary = _read_json(
		ProjectSettings.globalize_path("res://art/baked_props/baked_props.json"))
	var manual: Variant = _read_json("%s/%s_prefabs.json" % [_manifest_dir, scene_name])
	if baked.is_empty() or not manual is Array:
		return
	var parent := root.get_node_or_null("Props") as Node2D
	if parent == null:
		return
	# scene instance names -> baked prefab file names (typo'd in the scene)
	var aliases := {
		"Prefab_Scarecow": "Prefab_Scarecrow",
		"Prefab_Scarecow2": "Prefab_Scarecrow",
		"piggy": "Prefab_piggy",
	}
	var idx := 1
	for entry: Dictionary in manual:
		var pname: String = entry.get("prefab_name", "")
		if pname.is_empty():
			pname = str(entry.get("name", "")).get_slice(" (", 0)
		pname = aliases.get(pname, pname)
		# animals are live animated scenes now (_add_animals), not static art
		if pname in ["Prefab_Chicken", "Prefab_piggy"]:
			continue
		if not baked.has(pname):
			continue
		var tex: Texture2D = load("res://art/baked_props/%s.png" % pname)
		if tex == null:
			continue
		var spr := Sprite2D.new()
		spr.name = "%s_%d" % [pname.validate_node_name(), idx]
		idx += 1
		spr.texture = tex
		var off: Array = baked[pname].center_offset
		spr.position = Vector2(entry.position[0], entry.position[1])
		spr.offset = Vector2(off[0], off[1])
		parent.add_child(spr)
		spr.owner = root


# Live animated animals (chicken/pig wander scenes), placed from the
# extractor's animals.json (instance position + pen collider rect + params).
func _add_animals(root: Node2D, scene_name: String) -> void:
	var animals: Variant = _read_json("%s/%s_animals.json" % [_manifest_dir, scene_name])
	if not animals is Array or (animals as Array).is_empty():
		return
	var parent := root.get_node_or_null("Props") as Node2D
	if parent == null:
		return
	var scenes := {
		"chicken": load("res://scenes/animals/chicken.tscn"),
		"pig": load("res://scenes/animals/pig.tscn"),
	}
	var idx := 1
	for a: Dictionary in animals:
		var packed: PackedScene = scenes.get(a.kind)
		if packed == null:
			continue
		var inst: Node2D = packed.instantiate()
		inst.name = "%s_%d" % [String(a.kind).capitalize(), idx]
		idx += 1
		inst.position = Vector2(a.position[0], a.position[1])
		inst.area = Rect2(a.area[0], a.area[1], a.area[2], a.area[3])
		parent.add_child(inst)
		inst.owner = root
func _add_building_collision(root: Node2D, layers: Variant) -> void:
	var boxes := []
	for layer: Dictionary in layers:
		boxes.append_array(layer.get("box_colliders", []))
	if boxes.is_empty():
		return
	var body := StaticBody2D.new()
	body.name = "BuildingCollision"
	body.collision_layer = 1
	root.add_child(body)
	body.owner = root
	var idx := 1
	for b: Dictionary in boxes:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(b.size[0], b.size[1])
		shape.shape = rect
		shape.position = Vector2(b.center[0], b.center[1])
		shape.name = "Box_%d" % idx
		idx += 1
		body.add_child(shape)
		shape.owner = root


# Fences are tile-object prefabs in Unity (colliders included); approximate
# with one full-cell box per fence cell on a single StaticBody2D.
func _add_fence_collision(root: Node2D, scene_name: String) -> void:
	var cells: Variant = _read_json("%s/%s_tile_objects.json" % [_manifest_dir, scene_name])
	if not cells is Array or (cells as Array).is_empty():
		return
	var body := StaticBody2D.new()
	body.name = "FenceCollision"
	body.collision_layer = 1
	root.add_child(body)
	body.owner = root
	var idx := 1
	for c: Dictionary in cells:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(TILE, TILE)
		shape.shape = box
		shape.name = "Fence_%d" % idx
		idx += 1
		shape.position = Vector2(float(c.cell[0]) * TILE + TILE / 2.0,
				float(c.cell[1]) * TILE + TILE / 2.0)
		body.add_child(shape)
		shape.owner = root
