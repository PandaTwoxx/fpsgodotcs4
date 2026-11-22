extends CharacterBody3D
## A zombie that paths toward the player and bites when close.

signal died(zombie: Node3D)

@export var max_health: float = 60.0
@export var speed: float = 2.0
@export var attack_damage: float = 10.0
@export var attack_range: float = 0.85
@export var attack_cooldown: float = 1.0

const SKINS := [
	"res://kenney_animated-characters-survivors/Skins/zombieA.png",
	"res://kenney_animated-characters-survivors/Skins/zombieC.png",
]
# Which way the Kenney model faces at rotation 0 (yaw offset, radians).
const MODEL_YAW_OFFSET := 0.0
const REPATH_INTERVAL := 0.25
const TURN_SPEED := 10.0
const PUSH_IMPULSE := 2.5
const STUCK_TIME := 0.8        # seconds of trying to move without getting anywhere
const UNSTICK_DURATION := 0.7  # seconds spent sidestepping

var health: float
var is_dead := false
var _attack_timer := 0.0
var _repath_timer := 0.0
var _stuck_timer := 0.0
var _unstick_left := 0.0
var _unstick_dir := Vector3.ZERO
var _hit_tween: Tween
var _material: StandardMaterial3D
var _anim: AnimationPlayer
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var model: Node3D = $Model
@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	health = max_health
	add_to_group("zombie")
	_anim = CharacterAnimations.attach(model)
	_apply_skin()

func _apply_skin() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_texture = load(SKINS.pick_random())
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.set_surface_override_material(0, _material)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_attack_timer = maxf(_attack_timer - delta, 0.0)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var move_dir := Vector3.ZERO
	if player:
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > attack_range * 0.8:
			move_dir = _path_direction(player, delta)
		if to_player.length() <= attack_range and _attack_timer <= 0.0:
			_bite(player)
		_face(to_player if move_dir == Vector3.ZERO else move_dir, delta)

	move_dir = _apply_unstick(move_dir, delta)
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed
	move_and_slide()
	_push_rigid_bodies()
	_track_progress(move_dir, delta)
	_play("run" if move_dir != Vector3.ZERO else "idle")

## Zombies shove movable props (crates) out of their way.
func _push_rigid_bodies() -> void:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var body := hit.get_collider() as RigidBody3D
		if body:
			body.apply_central_impulse(-hit.get_normal() * PUSH_IMPULSE)

## If the zombie keeps trying to move but barely does, sidestep for a moment.
func _track_progress(move_dir: Vector3, delta: float) -> void:
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if move_dir != Vector3.ZERO and flat_speed < speed * 0.25:
		_stuck_timer += delta
		if _stuck_timer >= STUCK_TIME:
			_stuck_timer = 0.0
			_unstick_left = UNSTICK_DURATION
			_unstick_dir = move_dir.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	else:
		_stuck_timer = 0.0

func _apply_unstick(move_dir: Vector3, delta: float) -> Vector3:
	if _unstick_left <= 0.0:
		return move_dir
	_unstick_left -= delta
	return (move_dir * 0.3 + _unstick_dir).normalized() if move_dir != Vector3.ZERO else move_dir

## Direction (flat) toward the next navmesh waypoint; straight at the player
## if there is no navmesh path.
func _path_direction(player: Node3D, delta: float) -> Vector3:
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = REPATH_INTERVAL
		agent.target_position = player.global_position
	var dir := Vector3.ZERO
	if not agent.is_navigation_finished():
		dir = agent.get_next_path_position() - global_position
	if dir.length() < 0.05:
		dir = player.global_position - global_position
	dir.y = 0.0
	return dir.normalized()

func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var target_yaw := atan2(dir.x, dir.z) + MODEL_YAW_OFFSET
	model.rotation.y = lerp_angle(model.rotation.y, target_yaw, minf(delta * TURN_SPEED, 1.0))

func _play(anim: String) -> void:
	if _anim and _anim.current_animation != anim and _anim.has_animation(anim):
		_anim.play(anim, 0.15)

func _bite(player: Node) -> void:
	_attack_timer = attack_cooldown
	if player.has_method("take_damage"):
		player.take_damage(attack_damage)
	# Little lunge toward the player
	var tween := create_tween()
	tween.tween_property(model, "position:z", model.position.z + 0.08, 0.06)
	tween.tween_property(model, "position:z", model.position.z, 0.12)

func take_damage(amount: float) -> void:
	if is_dead:
		return
	health -= amount
	_flash_red()
	if health <= 0.0:
		_die()

func _flash_red() -> void:
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	_material.albedo_color = Color(1.0, 0.35, 0.35)
	_hit_tween = create_tween()
	_hit_tween.tween_property(_material, "albedo_color", Color.WHITE, 0.2)

func _die() -> void:
	is_dead = true
	collision_shape.set_deferred("disabled", true)
	remove_from_group("zombie")
	died.emit(self)
	var tween := create_tween()
	tween.tween_property(model, "rotation:x", -deg_to_rad(88.0), 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.2)
	tween.tween_property(model, "scale", Vector3.ZERO, 0.3)
	tween.tween_callback(queue_free)
