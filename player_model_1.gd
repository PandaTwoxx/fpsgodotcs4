extends CharacterBody3D

const SPEED = 4.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.0015

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@export_group("Combat")
@export var fire_rate: float = 0.18
@export var damage: float = 25.0
@export var impact_force: float = 12.0
@export var recoil_kick: float = 0.05
@export var recoil_rotation: float = 0.04

const BULLET_TRACER_SCENE = preload("res://bullet_tracer.tscn")
const IMPACT_EFFECT_SCENE = preload("res://impact_effect.tscn")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var raycast: RayCast3D = $Head/Camera3D/RayCast3D
@onready var weapon_holder: Node3D = get_node_or_null("Head/Camera3D/WeaponHolder")
@onready var muzzle: Marker3D = get_node_or_null("Head/Camera3D/WeaponHolder/Muzzle")
@onready var muzzle_flash: OmniLight3D = get_node_or_null("Head/Camera3D/WeaponHolder/Muzzle/MuzzleFlash")
@onready var shoot_sound: AudioStreamPlayer = get_node_or_null("ShootSound")
@onready var crosshair_hud: CanvasLayer = get_node_or_null("CrosshairHUD")
@onready var animation_player: AnimationPlayer = get_node_or_null("characterMedium/AnimationPlayer")

var fire_timer: float = 0.0
var weapon_default_pos: Vector3 = Vector3(0.22, -0.22, -0.42)
var weapon_default_rot: Vector3 = Vector3.ZERO
var muzzle_tween: Tween

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Register shoot input action if not present
	if not InputMap.has_action("shoot"):
		InputMap.add_action("shoot")
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("shoot", mouse_event)
	
	if weapon_holder:
		weapon_default_pos = weapon_holder.position
		weapon_default_rot = weapon_holder.rotation

func _unhandled_input(event: InputEvent) -> void:
	# ESC to release mouse
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Click to recapture mouse
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
	
	# Camera mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * SENSITIVITY)
		head.rotate_x(-event.relative.y * SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _process(delta: float) -> void:
	if fire_timer > 0.0:
		fire_timer -= delta
	
	# Check shooting input
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_pressed("shoot") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if fire_timer <= 0.0:
				shoot()
				fire_timer = fire_rate
	
	# Smooth recoil recovery
	if weapon_holder:
		weapon_holder.position = weapon_holder.position.lerp(weapon_default_pos, delta * 14.0)
		weapon_holder.rotation = weapon_holder.rotation.lerp(weapon_default_rot, delta * 16.0)

func shoot() -> void:
	# Play shoot sound
	if shoot_sound:
		shoot_sound.pitch_scale = randf_range(0.95, 1.05)
		shoot_sound.play()
	
	# Weapon recoil kick
	if weapon_holder:
		weapon_holder.position.z += recoil_kick
		weapon_holder.rotation.x += recoil_rotation
	
	# Muzzle flash
	if muzzle_flash:
		if muzzle_tween and muzzle_tween.is_valid():
			muzzle_tween.kill()
		muzzle_flash.light_energy = 2.5
		muzzle_tween = create_tween()
		muzzle_tween.tween_property(muzzle_flash, "light_energy", 0.0, 0.05)
	
	# Determine muzzle world position
	var muzzle_pos: Vector3
	if muzzle:
		muzzle_pos = muzzle.global_position
	elif weapon_holder:
		muzzle_pos = weapon_holder.global_position
	else:
		muzzle_pos = camera.global_position + camera.global_transform.basis * Vector3(0.2, -0.2, -0.4)
	
	# Raycast hit test
	raycast.force_raycast_update()
	var hit_pos: Vector3
	var is_hit := raycast.is_colliding()
	
	if is_hit:
		hit_pos = raycast.get_collision_point()
		var hit_normal := raycast.get_collision_normal()
		var collider := raycast.get_collider()
		
		var is_target := false
		
		# Resolve target with take_damage method
		var damage_target = collider
		if damage_target and not damage_target.has_method("take_damage") and damage_target.get_parent():
			if damage_target.get_parent().has_method("take_damage"):
				damage_target = damage_target.get_parent()
		
		if damage_target and damage_target.has_method("take_damage"):
			damage_target.take_damage(damage)
			is_target = true
			if crosshair_hud and crosshair_hud.has_method("show_hitmarker"):
				crosshair_hud.show_hitmarker()
		elif collider is RigidBody3D:
			var push_dir := (hit_pos - camera.global_position).normalized()
			collider.apply_impulse(push_dir * impact_force, hit_pos - collider.global_position)
		
		# Spawn impact particles & sound
		var impact := IMPACT_EFFECT_SCENE.instantiate()
		_get_effects_container().add_child(impact)
		impact.setup(hit_pos, hit_normal, is_target)
	else:
		hit_pos = camera.global_position - camera.global_transform.basis.z * 100.0
	
	# Spawn visual bullet tracer
	var tracer := BULLET_TRACER_SCENE.instantiate()
	_get_effects_container().add_child(tracer)
	tracer.setup(muzzle_pos, hit_pos)

func _get_effects_container() -> Node:
	if get_tree() and get_tree().current_scene:
		return get_tree().current_scene
	if get_tree() and get_tree().root and get_tree().root.get_child_count() > 0:
		return get_tree().root.get_child(get_tree().root.get_child_count() - 1)
	if owner:
		return owner
	return self

func _physics_process(delta: float) -> void:
	# Add gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get movement input
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		if animation_player and animation_player.has_animation("run"):
			animation_player.play("run")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		if animation_player and animation_player.has_animation("idle"):
			animation_player.play("idle")

	move_and_slide()
