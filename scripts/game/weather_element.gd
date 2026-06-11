# A scene element active only in certain weather (rain particles, audio,
# thunder driver). Port of WeatherSystemElement.cs.
class_name WeatherElement
extends Node2D

@export_flags("Sun", "Rain", "Thunder") var weather_mask: int = 1


func _ready() -> void:
	add_to_group("weather_elements")
	set_weather_active(false)


func set_weather_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	_propagate_audio_particles(self, active)


func _propagate_audio_particles(node: Node, active: bool) -> void:
	for child in node.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer2D:
			if active:
				child.play()
			else:
				child.stop()
		elif child is GPUParticles2D or child is CPUParticles2D:
			child.emitting = active
		_propagate_audio_particles(child, active)
