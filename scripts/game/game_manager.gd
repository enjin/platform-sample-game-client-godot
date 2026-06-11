# Global game state autoload. Port of HappyHarvest's GameManager.cs:
# owns the day clock, day-event registry, scene transitions (MoveTo) and
# cross-scene player state (coins/inventory survive scene swaps here).
extends Node

signal day_ratio_changed(ratio: float)
signal coins_changed(amount: int)
signal paused_changed(paused: bool)

# Values from Unity's Resources/GameManager.prefab (120s day, start 09:12).
@export var day_duration_seconds: float = 120.0
@export var starting_time_seconds: float = 46.0

# Day index (Day 1, Day 2, ...). Game logic increments this on sleep/wake.
var day: int = 1

var is_ticking: bool = true
var paused: bool = false

# Per-scene registrations (set by the active game scene, null in menus).
var player: Node2D = null
var terrain: Node = null
var day_cycle: Node = null
var weather: Node = null
var current_scene_data: Node = null  # game_scene.gd root, has unique_scene_name

# Cross-scene player state. The player node pulls these on _ready and the
# setters keep them current; they outlive scene swaps (Unity used a
# DontDestroyOnLoad player instead).
var coins: int = 10:
	set(value):
		coins = value
		coins_changed.emit(coins)
var inventory: InventorySystem = null  # created on first ensure_inventory()

var item_database: ResourceDatabase
var crop_database: ResourceDatabase

# Starting loadout from Unity's Resources/Character.prefab.
const STARTING_ITEMS := [
	["hoe", 1], ["water_can", 1], ["basket", 1],
	["corn_seed", 10], ["wheat_seed", 10], ["carrot_seed", 10],
]


# Creates the shared inventory on first use (first player _ready).
func ensure_inventory() -> InventorySystem:
	if inventory == null:
		inventory = InventorySystem.new()
		for entry in STARTING_ITEMS:
			var item: Resource = item_database.get_from_id(entry[0])
			if item != null:
				inventory.add_item(item, entry[1])
	return inventory

var _current_time_seconds: float = 46.0
var _event_handlers: Array[Node] = []
var _spawn_points: Dictionary = {}  # spawn_index -> Node2D
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _transitioning := false


# Ratio of the current day in 0..1 (0 = 00:00, 1 = 23:59).
var current_day_ratio: float:
	get:
		return _current_time_seconds / day_duration_seconds


func _ready() -> void:
	_current_time_seconds = starting_time_seconds
	item_database = ResourceDatabase.new(
		["res://resources/items", "res://resources/products"])
	crop_database = ResourceDatabase.new(["res://resources/crops"])
	_setup_fade_overlay()


func _process(delta: float) -> void:
	if not is_ticking:
		return
	var previous_ratio := current_day_ratio
	_current_time_seconds += delta
	while _current_time_seconds > day_duration_seconds:
		_current_time_seconds -= day_duration_seconds
		day += 1

	# Day-event transitions (port of GameManager.Update's range walk).
	for handler in _event_handlers:
		handler.tick_ranges(previous_ratio, current_day_ratio)

	day_ratio_changed.emit(current_day_ratio)


func pause() -> void:
	is_ticking = false
	paused = true
	if player and player.has_method("toggle_control"):
		player.toggle_control(false)
	paused_changed.emit(true)


func resume() -> void:
	is_ticking = true
	paused = false
	if player and player.has_method("toggle_control"):
		player.toggle_control(true)
	paused_changed.emit(false)


# ------------------------------------------------------------ time helpers

func current_time_as_string() -> String:
	return get_time_as_string(current_day_ratio)


static func get_time_as_string(ratio: float) -> String:
	var time := ratio * 24.0
	var hour := int(time)
	var minute := int((time - hour) * 60.0)
	return "%d:%02d" % [hour, minute]


# ------------------------------------------------------- day event handlers

# handler must expose tick_ranges(prev_ratio, ratio) and fire_initial(ratio);
# see scripts/game/day_event_handler.gd
func register_day_event_handler(handler: Node) -> void:
	handler.fire_initial(current_day_ratio)
	_event_handlers.append(handler)


func unregister_day_event_handler(handler: Node) -> void:
	_event_handlers.erase(handler)


# ------------------------------------------------------- spawns/transitions

func register_spawn(spawn: Node2D) -> void:
	_spawn_points[spawn.spawn_index] = spawn


func unregister_spawn(spawn: Node2D) -> void:
	if _spawn_points.get(spawn.spawn_index) == spawn:
		_spawn_points.erase(spawn.spawn_index)


func get_spawn(index: int) -> Node2D:
	return _spawn_points.get(index)


# Port of GameManager.MoveTo: pause -> persist scene state -> fade ->
# swap scene -> place player at spawn -> restore -> fade in -> resume.
func move_to(scene_path: String, target_spawn: int = 0) -> void:
	if _transitioning:
		return
	_transitioning = true
	if player:
		pause()
	if current_scene_data and current_scene_data.has_method("save_scene_state"):
		current_scene_data.save_scene_state()
	await fade_to_black()
	_spawn_points.clear()
	player = null
	terrain = null
	current_scene_data = null
	get_tree().change_scene_to_file(scene_path)
	# wait for the new scene's _ready chain (spawn points register there)
	await get_tree().process_frame
	await get_tree().process_frame
	var spawn: Node2D = _spawn_points.get(target_spawn)
	if spawn and spawn.has_method("spawn_here"):
		spawn.spawn_here()
	if current_scene_data and current_scene_data.has_method("load_scene_state"):
		current_scene_data.load_scene_state()
	await fade_from_black()
	resume()
	_transitioning = false


# ------------------------------------------------------------- fade overlay

func _setup_fade_overlay() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)
	add_child(_fade_layer)


func fade_to_black(duration: float = 0.4) -> void:
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, duration)
	await tween.finished


func fade_from_black(duration: float = 0.4) -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 0.0, duration)
	await tween.finished
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
