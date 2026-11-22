extends StaticBody3D

@export var max_health: float = 60.0
var health: float = 60.0
var is_down: bool = false
var initial_rot: Vector3
var wobble_tween: Tween

@onready var model_node: Node3D = $Model
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	health = max_health
	if model_node:
		initial_rot = model_node.rotation

func take_damage(amount: float) -> void:
	if is_down:
		return
	
	health -= amount
	
	# Hit wobble reaction
	if model_node:
		if wobble_tween and wobble_tween.is_valid():
			wobble_tween.kill()
		wobble_tween = create_tween()
		wobble_tween.tween_property(model_node, "rotation:x", initial_rot.x - deg_to_rad(20.0), 0.05)
		wobble_tween.tween_property(model_node, "rotation:x", initial_rot.x + deg_to_rad(10.0), 0.1)
		wobble_tween.tween_property(model_node, "rotation:x", initial_rot.x, 0.15)
	
	if health <= 0.0:
		knock_down()

func knock_down() -> void:
	is_down = true
	# Knock down flat
	if model_node:
		if wobble_tween and wobble_tween.is_valid():
			wobble_tween.kill()
		wobble_tween = create_tween()
		wobble_tween.tween_property(model_node, "rotation:x", initial_rot.x - deg_to_rad(85.0), 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	# Schedule respawn
	get_tree().create_timer(3.0).timeout.connect(respawn)

func respawn() -> void:
	health = max_health
	is_down = false
	if model_node:
		if wobble_tween and wobble_tween.is_valid():
			wobble_tween.kill()
		wobble_tween = create_tween()
		wobble_tween.tween_property(model_node, "rotation:x", initial_rot.x, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
