# Boot scene (run/main_scene). Port of Loader.cs - in Unity it only ensured
# the GameManager existed before gameplay; here autoloads already guarantee
# that, so this just shows the logo for a beat and opens the main menu.
extends Control

const MAIN_MENU := "res://scenes/main_menu.tscn"


func _ready() -> void:
	await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file(MAIN_MENU)
