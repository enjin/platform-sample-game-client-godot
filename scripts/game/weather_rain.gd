# Rain: viewport-wide particle sheet that follows the camera, plus the rain
# loop. Functional approximation of the Unity VFX-graph rain.
extends WeatherElement


@onready var particles: CPUParticles2D = $Particles


func _ready() -> void:
	super()
	weather_mask = 2 | 4  # Rain | Thunder, matching the Unity farm elements


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam:
		# keep the emitter just above the visible area
		global_position = cam.get_screen_center_position() - Vector2(0, 500)
