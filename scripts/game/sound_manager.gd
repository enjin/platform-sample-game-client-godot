# Audio autoload. Port of SoundManager.cs: pooled SFX players (16 positional
# + 4 UI/flat, matching Unity's 16-source queue), bus volume control
# persisted to user://sound_settings.cfg.
extends Node

const SETTINGS_PATH := "user://sound_settings.cfg"
const POOL_SIZE := 16
const FLAT_POOL_SIZE := 4

var _sfx_pool: Array[AudioStreamPlayer2D] = []
var _flat_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _flat_next := 0


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)
	for i in FLAT_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_flat_pool.append(p)
	_load_settings()


# Positional one-shot, matching PlaySFXAt(position, clip, spatialized).
func play_sfx_at(pos: Vector2, stream: AudioStream, spatialized := true) -> void:
	if stream == null:
		return
	if not spatialized:
		play_flat(stream)
		return
	var p := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % POOL_SIZE
	p.global_position = pos
	p.stream = stream
	p.play()


func play_flat(stream: AudioStream) -> void:
	if stream == null:
		return
	var p := _flat_pool[_flat_next]
	_flat_next = (_flat_next + 1) % FLAT_POOL_SIZE
	p.stream = stream
	p.play()


func play_ui_sound(stream: AudioStream) -> void:
	play_flat(stream)


# ----------------------------------------------------------------- volumes

func set_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, linear)))
	_save_settings()


func get_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	return db_to_linear(AudioServer.get_bus_volume_db(idx)) if idx >= 0 else 1.0


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for bus_name in ["Master", "BGM", "SFX", "Ambience"]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001,
				cfg.get_value("volumes", bus_name, 1.0))))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for bus_name in ["Master", "BGM", "SFX", "Ambience"]:
		cfg.set_value("volumes", bus_name, get_volume(bus_name))
	cfg.save(SETTINGS_PATH)
