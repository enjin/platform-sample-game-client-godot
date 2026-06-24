# Applies a gentle wind-sway shader to foliage props (bush, tree, grass,
# flowers, lily), reproducing Unity's Material_Plants "MoveVertices" wind.
# Mirrors lamp_lights.gd / lamp_sway.gd: a runtime pass over the generated
# Maps/Props node that assigns a shared ShaderMaterial to matching sprites. The
# shader phases each plant by its world position, so one material is enough.
extends Node

@export var props_root: Node2D
@export var wind_speed: float = 1.8
# fraction of each sprite's height the top leans (size-proportional)
@export var lean: float = 0.04
# trees are tall, so the same fraction reads as a big sway; they're also
# stiffer in reality -- give them a much smaller lean
@export var tree_lean: float = 0.012

# matched against each sprite's texture filename (foreground props only; the
# pinetree BACKGROUND band is a TileMapLayer, not a Sprite2D in Props)
const FOLIAGE_KEYS := ["bush", "pinetree", "grass", "flower", "lilly"]
const TREE_KEYS := ["pinetree"]
const WIND_SHADER := preload("res://shaders/foliage_wind.gdshader")


func _ready() -> void:
	if props_root == null:
		return
	var mat := _make_material(lean)
	var tree_mat := _make_material(tree_lean)
	for child in props_root.get_children():
		var spr := child as Sprite2D
		if spr == null or spr.texture == null:
			continue
		var f := _texture_file(spr)
		var matched := false
		for key in FOLIAGE_KEYS:
			if key in f:
				matched = true
				break
		if not matched:
			continue
		# trees (tall) get a gentler lean than ground foliage
		spr.material = tree_mat if _is_tree(f) else mat


func _make_material(lean_amount: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WIND_SHADER
	mat.set_shader_parameter("wind_speed", wind_speed)
	mat.set_shader_parameter("lean", lean_amount)
	return mat


func _is_tree(f: String) -> bool:
	for key in TREE_KEYS:
		if key in f:
			return true
	return false


func _texture_file(spr: Sprite2D) -> String:
	var t: Texture2D = spr.texture
	if t is CanvasTexture:
		t = (t as CanvasTexture).diffuse_texture
	return "" if t == null else t.resource_path.get_file().to_lower()
