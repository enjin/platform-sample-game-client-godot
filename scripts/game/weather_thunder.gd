# Thunder: random-interval clap + screen flash. Active in Thunder weather.
extends WeatherElement

@export var min_wait: float = 8.0
@export var max_wait: float = 20.0

@onready var _timer: Timer = $Timer
@onready var _flash: ColorRect = $FlashLayer/Flash
@onready var _audio: AudioStreamPlayer = $Audio


func _ready() -> void:
	super()
	weather_mask = 4
	_timer.timeout.connect(_clap)
	_arm()


func set_weather_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	_flash.modulate.a = 0.0
	if active:
		_arm()


func _arm() -> void:
	_timer.start(randf_range(min_wait, max_wait))


func _clap() -> void:
	_audio.play()
	var tween := create_tween()
	tween.tween_property(_flash, "modulate:a", 0.55, 0.05)
	tween.tween_property(_flash, "modulate:a", 0.0, 0.25)
	_arm()
