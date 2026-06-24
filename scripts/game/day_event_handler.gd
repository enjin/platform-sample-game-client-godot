# Time-range events on the day cycle. Port of DayEventHandler.cs: each event
# fires `started` when the day ratio enters [start, end] and `ended` when it
# leaves; consumers (lamps, ambience) connect in code or the editor.
# GameManager drives tick_ranges every frame while ticking.
class_name DayEventHandler
extends Node

signal event_started(index: int)
signal event_ended(index: int)

# pairs of [start_ratio, end_ratio]; a range with start > end wraps midnight
@export var events: Array[Vector2] = []

var _active: Array[bool] = []


func _ready() -> void:
	_active.resize(events.size())
	GameManager.register_day_event_handler(self)


func _exit_tree() -> void:
	GameManager.unregister_day_event_handler(self)


func is_in_range(index: int, ratio: float) -> bool:
	var ev := events[index]
	if ev.x <= ev.y:
		return ratio >= ev.x and ratio <= ev.y
	return ratio >= ev.x or ratio <= ev.y  # wraps midnight


# Fired once on registration so consumers start in the right state
# (port of GameManager.RegisterEventHandler's immediate invoke).
func fire_initial(ratio: float) -> void:
	for i in events.size():
		_active[i] = is_in_range(i, ratio)
		if _active[i]:
			event_started.emit(i)
		else:
			event_ended.emit(i)


func tick_ranges(_prev_ratio: float, ratio: float) -> void:
	for i in events.size():
		var now := is_in_range(i, ratio)
		if now and not _active[i]:
			event_started.emit(i)
		elif not now and _active[i]:
			event_ended.emit(i)
		_active[i] = now
