# Root script for playable scenes (farm, house). Port of SceneData.cs:
# identifies the scene for the save system and registers itself with the
# GameManager. Terrain/player register themselves separately.
extends Node2D

@export var unique_scene_name: String = ""

# Camera bounds in px; (0,0,0,0) = no limits (computed from the map in editor).
@export var camera_limits: Rect2i = Rect2i()


func _enter_tree() -> void:
	GameManager.current_scene_data = self


func _ready() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam and camera_limits.size != Vector2i.ZERO:
		cam.limit_left = camera_limits.position.x
		cam.limit_top = camera_limits.position.y
		cam.limit_right = camera_limits.end.x
		cam.limit_bottom = camera_limits.end.y


# Persist/restore this scene's mutable state across scene swaps. Terrain
# state arrives with Phase 4's TerrainManager; the hooks exist so
# GameManager.move_to can call them unconditionally.
func save_scene_state() -> void:
	if GameManager.terrain and GameManager.terrain.has_method("store_state"):
		GameManager.terrain.store_state(unique_scene_name)


func load_scene_state() -> void:
	if GameManager.terrain and GameManager.terrain.has_method("restore_state"):
		GameManager.terrain.restore_state(unique_scene_name)
