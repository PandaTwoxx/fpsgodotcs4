extends RigidBody3D

@export var max_health: float = 75.0
var health: float = 75.0

func _ready() -> void:
	health = max_health

func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		destroy_crate()

func destroy_crate() -> void:
	# Small delay/effect then queue_free
	queue_free()
