# Footstep sounds by ground surface. Port of StepSoundHandler: picks a clip
# set from the tile under the player. Surfaces map by tile texture path
# keywords since the imported tileset has no per-surface custom data.
extends Node

const STEP_INTERVAL := 0.34  # seconds between steps while walking

var _surfaces := {
	"grass": [],
	"mud": [],
	"path": [],
	"wood": [],
}
var _cooldown := 0.0

@onready var player: CharacterBody2D = get_parent()


func _ready() -> void:
	for surface in _surfaces:
		var dir := DirAccess.open("res://audio/character")
		if dir == null:
			return
		for f in dir.get_files():
			f = f.trim_suffix(".remap")
			if f.ends_with(".wav") and ("_" + surface) in f:
				_surfaces[surface].append(load("res://audio/character/" + f))


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if player.velocity == Vector2.ZERO or _cooldown > 0.0:
		return
	_cooldown = STEP_INTERVAL
	var clips: Array = _surfaces[_surface_under_player()]
	if not clips.is_empty() and player.has_node("/root/SoundManager"):
		player.get_node("/root/SoundManager").play_sfx_at(
			player.global_position, clips.pick_random())


func _surface_under_player() -> String:
	var terrain = GameManager.terrain
	if terrain == null:
		return "wood"  # interior floors
	var ground: TileMapLayer = terrain.ground_layer
	var cell: Vector2i = ground.local_to_map(ground.to_local(player.global_position))
	if terrain.is_tilled(cell):
		return "mud"
	# the farm is mostly grass; paths/mud refinement would need per-tile data
	return "grass"
