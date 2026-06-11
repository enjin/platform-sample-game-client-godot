# Noise-driven lamp flicker. Port of LightFlicker.cs (rotation jitter
# dropped - meaningless for a PointLight2D).
extends PointLight2D

@export var position_jitter_scale: float = 2.0
@export var energy_jitter_scale: float = 0.15
@export var timescale: float = 2.0

var _noise := FastNoiseLite.new()
var _base_position: Vector2
var _base_energy: float


func _ready() -> void:
	_noise.seed = int(get_instance_id()) & 0x7FFFFFFF
	_base_position = position
	_base_energy = energy


func _process(_delta: float) -> void:
	if not visible:
		return
	var t := Time.get_ticks_msec() / 1000.0 * timescale
	energy = _base_energy + _noise.get_noise_1d(t) * energy_jitter_scale
	position = _base_position + Vector2(
		_noise.get_noise_2d(t, 13.7), _noise.get_noise_2d(t, 71.3)) * position_jitter_scale
