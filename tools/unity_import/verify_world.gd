# M6 verification: day tint, day events, weather toggles, sound manager.
#   godot --headless -s tools/unity_import/verify_world.gd
extends SceneTree

var _failures := 0


func _init() -> void:
	_run.call_deferred()


func _check(cond: bool, label: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + label)
	if not cond:
		_failures += 1


func _run() -> void:
	await process_frame
	var gm: Node = root.get_node("/root/GameManager")
	var sm: Node = root.get_node_or_null("/root/SoundManager")
	_check(sm != null, "SoundManager autoload present")
	_check(AudioServer.get_bus_index("SFX") >= 0, "SFX bus exists")
	_check(AudioServer.get_bus_index("Ambience") >= 0, "Ambience bus exists")
	sm.set_volume("SFX", 0.5)
	_check(absf(sm.get_volume("SFX") - 0.5) < 0.01, "volume set/get round-trip")
	sm.set_volume("SFX", 1.0)

	gm.day_duration_seconds = 10.0  # fast day for the test
	await gm.move_to("res://scenes/farm_outdoor.tscn", 0)
	await process_frame
	await process_frame

	var day_night: CanvasModulate = current_scene.get_node("DayNight")
	_check(day_night != null, "DayNight modulate present")
	var c0 := day_night.color
	gm._current_time_seconds = 0.0  # midnight
	await process_frame
	await process_frame
	var c_night := day_night.color
	_check(c_night.r < 0.5 and c_night.b > c_night.r, "midnight tint is dark blue (%s)" % c_night)
	gm._current_time_seconds = 5.0  # noon on a 10s day
	await process_frame
	await process_frame
	var c_noon := day_night.color
	_check(c_noon.r > 0.9, "noon tint is near white (%s)" % c_noon)

	# day events fire across the dawn boundary
	var events: Node = current_scene.get_node("DayEvents")
	var fired := {"on": 0, "off": 0}
	events.event_started.connect(func(_i: int) -> void: fired["on"] += 1)
	events.event_ended.connect(func(_i: int) -> void: fired["off"] += 1)
	gm._current_time_seconds = 2.0  # 0.2 ratio: before dawn (0.25)
	await process_frame
	gm._current_time_seconds = 3.0  # 0.3: day
	await process_frame
	gm._current_time_seconds = 8.5  # 0.85: night
	await process_frame
	_check(fired["on"] >= 1 and fired["off"] >= 1,
		"day events fired (on=%d off=%d)" % [fired["on"], fired["off"]])

	# weather toggling
	var weather: Node = current_scene.get_node("Weather")
	var rain: Node2D = current_scene.get_node("Rain")
	_check(not rain.visible, "rain hidden in sun")
	weather.change_weather(2 | 4)
	_check(rain.visible, "rain visible in rain weather")
	var thunder: Node2D = current_scene.get_node("Thunder")
	_check(thunder.visible, "thunder element active")
	weather.change_weather(1)
	_check(not rain.visible, "rain stops on sun")

	# ambience players exist and are looping streams
	var amb_day: AudioStreamPlayer = current_scene.get_node("Ambience/Day")
	_check(amb_day.stream != null and amb_day.playing, "day ambience playing")
	var wav := amb_day.stream as AudioStreamWAV
	_check(wav != null and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, "ambience loops")

	# lamp lights attached to street lamp props
	var lamps: Node = current_scene.get_node("LampLights")
	_check(lamps._lights.size() >= 9, "lamp lights attached (%d)" % lamps._lights.size())

	print("---- %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	quit(0 if _failures == 0 else 1)
