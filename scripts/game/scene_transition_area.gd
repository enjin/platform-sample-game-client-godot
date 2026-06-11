# Port of SceneTransition.cs: an Area2D the player walks into to change
# scenes (e.g. the house door). Uses scene paths instead of build indices.
extends Area2D

@export_file("*.tscn") var target_scene: String
@export var target_spawn: int = 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body == GameManager.player:
		GameManager.move_to(target_scene, target_spawn)
