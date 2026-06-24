# Swings each streetlamp's hanging lantern like the Unity Prefab_Lantern_Hanging
# "Swing" animation (legacy Animation clip Anim_Lantern_Hanging_Swing): a gentle
# pendulum rotating +/- 5 degrees about the chain's top on a 4-second loop.
#
# The chain and lantern bake as separate Sprite2D props (see build_tilemaps), so
# this mirrors lamp_lights.gd: a runtime pass over the generated Props node that
# pairs each chain sprite with its nearest lantern and rotates them rigidly about
# the chain's top each frame. No reparenting, so y-sort/z/modulate are untouched
# and any night light attached to the lantern swings along with it.
extends Node

@export var props_root: Node2D
# matches the Unity clip: +/-5 deg, full -5 -> +5 -> -5 cycle every 4 s
@export var amplitude_degrees: float = 5.0
@export var period_seconds: float = 4.0

# per lamp: { chain, lantern, pivot (chain top), lantern_rest (resting pos) }
var _swingers: Array = []
var _time: float = 0.0


func _ready() -> void:
	if props_root == null or period_seconds <= 0.0:
		return
	var chains: Array[Sprite2D] = []
	var lanterns: Array[Sprite2D] = []
	for child in props_root.get_children():
		if not (child is Sprite2D) or (child as Sprite2D).texture == null:
			continue
		var f := _texture_file(child)
		if "chain" in f:
			chains.append(child)
		elif "lantern" in f:
			lanterns.append(child)
	for chain in chains:
		var lantern: Sprite2D = _nearest(chain, lanterns)
		_swingers.append({
			"chain": chain,
			"lantern": lantern,
			"pivot": chain.position,  # chain's node origin sits at its top (pivot 0.96)
			"lantern_rest": lantern.position if lantern else Vector2.ZERO,
		})
	set_process(not _swingers.is_empty())


func _process(delta: float) -> void:
	_time += delta
	# -5 at t=0, +5 at t=period/2, back to -5 at t=period: an eased cosine,
	# matching the clip's smooth (zero-tangent) keyframes.
	var angle := deg_to_rad(-amplitude_degrees * cos(_time * TAU / period_seconds))
	for s in _swingers:
		var chain: Sprite2D = s.chain
		chain.rotation = angle  # rotates about its origin = the chain's top
		var lantern: Sprite2D = s.lantern
		if lantern != null:
			# orbit the lantern rigidly about the same pivot so it hangs true
			lantern.position = s.pivot + (s.lantern_rest - s.pivot).rotated(angle)
			lantern.rotation = angle


func _nearest(from: Sprite2D, candidates: Array[Sprite2D]) -> Sprite2D:
	var best: Sprite2D = null
	var best_d := INF
	for c in candidates:
		var d := from.position.distance_to(c.position)
		if d < best_d:
			best_d = d
			best = c
	return best


func _texture_file(spr: Sprite2D) -> String:
	var t: Texture2D = spr.texture
	if t is CanvasTexture:
		t = (t as CanvasTexture).diffuse_texture
	return "" if t == null else t.resource_path.get_file().to_lower()
