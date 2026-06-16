# Attaches night-time PointLight2Ds (with flicker) to every lamp prop in the
# generated Props node, gated by a day range. Replaces the per-prefab Light2D
# children the Unity streetlamp/houselamp prefabs carried.
extends Node

const FLICKER := preload("res://scripts/game/effects/light_flicker.gd")

@export var props_root: Node2D
@export var day_handler: DayEventHandler
@export var light_color: Color = Color(1.0, 0.85, 0.6)
@export var light_radius: float = 220.0

var _lights: Array[PointLight2D] = []


func _ready() -> void:
	if props_root == null:
		return
	var tex := GradientTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = grad

	for child in props_root.get_children():
		if not child is Sprite2D or child.texture == null:
			continue
		# attach the light to the lantern visual itself (the hanging lantern
		# nested in the streetlamp prefab, or a wall-mounted house lamp)
		var tex_path: String = child.texture.resource_path.to_lower()
		if child.texture is CanvasTexture:
			tex_path = (child.texture as CanvasTexture).diffuse_texture.resource_path.to_lower()
		if not ("lantern" in tex_path.get_file() or "houselamp" in tex_path.get_file()):
			continue
		var light: PointLight2D = FLICKER.new()
		light.texture = tex
		light.color = light_color
		light.energy = 1.0
		light.blend_mode = Light2D.BLEND_MODE_ADD
		light.texture_scale = light_radius / 128.0
		light.position = Vector2(0, 6)  # lantern sprite anchors at its top
		light.visible = false
		child.add_child(light)
		_lights.append(light)

	if day_handler:
		# lamps on when OUTSIDE the day range
		day_handler.event_started.connect(func(_i: int) -> void: _set_lamps(false))
		day_handler.event_ended.connect(func(_i: int) -> void: _set_lamps(true))


func _set_lamps(on: bool) -> void:
	for light in _lights:
		light.visible = on
