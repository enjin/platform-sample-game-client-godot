# Port of SpawnPoint.cs. Place as a Marker2D in game scenes; index 0 is the
# default spawn, others are targets for scene transitions.
extends Marker2D

@export var spawn_index: int = 0


func _ready() -> void:
	GameManager.register_spawn(self)


func _exit_tree() -> void:
	GameManager.unregister_spawn(self)


func spawn_here() -> void:
	var player := GameManager.player
	if player == null:
		return
	player.global_position = global_position
	var cam := get_viewport().get_camera_2d()
	if cam:
		cam.reset_smoothing()
