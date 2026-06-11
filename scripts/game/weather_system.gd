# Weather state for a scene. Port of WeatherSystem.cs: a flags mask toggles
# every node in the "weather_elements" group whose own mask overlaps.
# Unity has no scheduler - weather is static unless change_weather is called;
# auto_cycle adds an optional random re-roll for demos.
class_name WeatherSystem
extends Node

signal weather_changed(mask: int)

const SUN := 1
const RAIN := 2
const THUNDER := 4

@export_flags("Sun", "Rain", "Thunder") var starting_weather: int = SUN
@export var auto_cycle: bool = false
@export var cycle_interval_seconds: float = 90.0

var current: int = SUN


func _ready() -> void:
	GameManager.weather = self
	# wait a frame so weather elements have registered in the group
	await get_tree().process_frame
	change_weather(starting_weather)
	if auto_cycle:
		var timer := Timer.new()
		timer.wait_time = cycle_interval_seconds
		timer.timeout.connect(_random_weather)
		add_child(timer)
		timer.start()


func _exit_tree() -> void:
	if GameManager.weather == self:
		GameManager.weather = null


func change_weather(mask: int) -> void:
	current = mask
	for element in get_tree().get_nodes_in_group("weather_elements"):
		element.set_weather_active(element.weather_mask & current != 0)
	weather_changed.emit(current)


func _random_weather() -> void:
	change_weather([SUN, SUN, RAIN, RAIN | THUNDER].pick_random())
