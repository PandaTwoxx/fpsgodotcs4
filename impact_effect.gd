extends Node3D

@onready var particles: CPUParticles3D = $CPUParticles3D
@onready var audio: AudioStreamPlayer3D = $AudioStreamPlayer3D

func setup(pos: Vector3, normal: Vector3, is_target: bool = false) -> void:
	global_position = pos
	if normal.length_squared() > 0.001:
		if abs(normal.dot(Vector3.UP)) < 0.99:
			look_at(global_position + normal, Vector3.UP)
		else:
			look_at(global_position + normal, Vector3.FORWARD)
	
	if is_target:
		audio.stream = preload("res://sounds/target_hit.wav")
	else:
		audio.stream = preload("res://sounds/impact.wav")
	
	audio.pitch_scale = randf_range(0.9, 1.1)
	audio.play()
	particles.emitting = true
	
	var timer := get_tree().create_timer(0.6)
	timer.timeout.connect(queue_free)
