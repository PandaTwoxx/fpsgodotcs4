extends CharacterBody3D

const SPEED = 4.0
const JUMP_VELOCITY = 4.5
const BASE_SENSITIVITY = 0.0015

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@export_group("Combat")
@export var fire_rate: float = 0.18
@export var damage: float = 25.0
@export var impact_force: float = 12.0
@export var recoil_kick: float = 0.05
@export var recoil_rotation: float = 0.04
@export var magazine_size: int = 12
@export var reload_time: float = 1.3

const BULLET_TRACER_SCENE = preload("res://bullet_tracer.tscn")
const IMPACT_EFFECT_SCENE = preload("res://impact_effect.tscn")
const RELOAD_DIP_POS := Vector3(0.0, -0.22, 0.06)
const RELOAD_DIP_ROT := Vector3(0.7, 0.0, 0.0)

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var raycast: RayCast3D = $Head/Camera3D/RayCast3D
@onready var character: Node3D = $characterMedium
@onready var weapon_holder: Node3D = get_node_or_null("Head/Camera3D/WeaponHolder")
@onready var muzzle: Marker3D = get_node_or_null("Head/Camera3D/WeaponHolder/Muzzle")
@onready var muzzle_flash: OmniLight3D = get_node_or_null("Head/Camera3D/WeaponHolder/Muzzle/MuzzleFlash")
@onready var shoot_sound: AudioStreamPlayer = get_node_or_null("ShootSound")
@onready var crosshair_hud: CanvasLayer = get_node_or_null("CrosshairHUD")

const ANIM_DIR := "res://kenney_animated-characters-survivors/Animations/"
# short name -> [source file, clip name inside the file, loops?]
const ANIMATIONS := {
	"idle": ["idle.fbx", "Root|Idle", true],
	"run": ["run.fbx", "Root|Run", true],
	"jump": ["jump.fbx", "Root|Jump", false],
}

var animation_player: AnimationPlayer
var fire_timer: float = 0.0
var ammo: int = 0
var reload_left: float = 0.0  # > 0 while a reload is in progress
var weapon_default_pos: Vector3 = Vector3(0.22, -0.22, -0.42)
var weapon_default_rot: Vector3 = Vector3.ZERO
var muzzle_tween: Tween

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	if weapon_holder:
		weapon_default_pos = weapon_holder.position
		weapon_default_rot = weapon_holder.rotation
	
	_setup_animations()
	_apply_settings()
	Settings.changed.connect(_apply_settings)
	ammo = magazine_size
	_update_ammo_hud()

func _apply_settings() -> void:
	camera.fov = Settings.fov

# The character model ships without an AnimationPlayer; its clips live in
# separate FBX files, so collect them into one library at startup.
func _setup_animations() -> void:
	if not character:
		return
	var library := AnimationLibrary.new()
	for anim_name: String in ANIMATIONS:
		var info: Array = ANIMATIONS[anim_name]
		var path: String = ANIM_DIR + info[0]
		if not ResourceLoader.exists(path):
			continue
		var source: Node = (load(path) as PackedScene).instantiate()
		var source_player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if source_player and source_player.has_animation(info[1]):
			var clip := source_player.get_animation(info[1]).duplicate() as Animation
			clip.loop_mode = Animation.LOOP_LINEAR if info[2] else Animation.LOOP_NONE
			library.add_animation(anim_name, clip)
		else:
			push_warning("Animation '%s' not found in %s" % [info[1], info[0]])
		source.free()
	animation_player = AnimationPlayer.new()
	character.add_child(animation_player)
	animation_player.add_animation_library("", library)
	animation_player.play("idle")

func _unhandled_input(event: InputEvent) -> void:
	# Click to recapture mouse
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
	
	# Camera mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * BASE_SENSITIVITY * Settings.mouse_sensitivity)
		head.rotate_x(-event.relative.y * BASE_SENSITIVITY * Settings.mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _process(delta: float) -> void:
	if fire_timer > 0.0:
		fire_timer -= delta
	
	# Reload progress
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			_finish_reload()
	
	if Input.is_action_just_pressed("reload"):
		start_reload()
	
	# Check shooting input
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_pressed("shoot") and fire_timer <= 0.0 and reload_left <= 0.0:
			if ammo > 0:
				shoot()
				fire_timer = fire_rate
			else:
				start_reload()  # trigger pulled on an empty magazine
	
	# Smooth recoil recovery; the weapon dips while reloading
	if weapon_holder:
		var reloading := reload_left > 0.0
		var target_pos := weapon_default_pos + (RELOAD_DIP_POS if reloading else Vector3.ZERO)
		var target_rot := weapon_default_rot + (RELOAD_DIP_ROT if reloading else Vector3.ZERO)
		weapon_holder.position = weapon_holder.position.lerp(target_pos, delta * 14.0)
		weapon_holder.rotation = weapon_holder.rotation.lerp(target_rot, delta * 16.0)

func start_reload() -> void:
	if reload_left > 0.0 or ammo >= magazine_size:
		return
	reload_left = reload_time
	if crosshair_hud and crosshair_hud.has_method("set_reloading"):
		crosshair_hud.set_reloading(true)

func _finish_reload() -> void:
	ammo = magazine_size
	if crosshair_hud and crosshair_hud.has_method("set_reloading"):
		crosshair_hud.set_reloading(false)
	_update_ammo_hud()

func _update_ammo_hud() -> void:
	if crosshair_hud and crosshair_hud.has_method("set_ammo"):
		crosshair_hud.set_ammo(ammo, magazine_size)

func shoot() -> void:
	ammo -= 1
	_update_ammo_hud()
	
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
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		if animation_player and animation_player.has_animation("jump"):
			animation_player.play("jump")

	# Get movement input
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		if animation_player and animation_player.has_animation("run") and is_on_floor():
			animation_player.play("run")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		if animation_player and animation_player.has_animation("idle") and is_on_floor():
			animation_player.play("idle")

	move_and_slide()