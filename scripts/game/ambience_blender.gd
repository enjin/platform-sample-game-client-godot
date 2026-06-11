# Day/night ambience crossfade. Port of AmbienceBlender: two looping players,
# 1-second linear blend, driven by a DayEventHandler's day range.
extends Node

@export var day_handler: DayEventHandler

@onready var day_player: AudioStreamPlayer = $Day
@onready var night_player: AudioStreamPlayer = $Night

var _tween: Tween


func _ready() -> void:
	day_player.volume_db = -80.0
	night_player.volume_db = -80.0
	day_player.play()
	night_player.play()
	if day_handler:
		day_handler.event_started.connect(func(_i: int) -> void: blend_to_day())
		day_handler.event_ended.connect(func(_i: int) -> void: blend_to_night())


func blend_to_day() -> void:
	_blend(day_player, night_player)


func blend_to_night() -> void:
	_blend(night_player, day_player)


func _blend(to_player: AudioStreamPlayer, from_player: AudioStreamPlayer) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel()
	_tween.tween_property(to_player, "volume_db", 0.0, 1.0)
	_tween.tween_property(from_player, "volume_db", -80.0, 1.0)
