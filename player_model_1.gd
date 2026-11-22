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

@export_group("Health")
@export var max_health: float = 100.0
@export var regen_delay: float = 6.0   # seconds without damage before healing starts
@export var regen_rate: float = 3.0    # health per second while healing

var health: float = 100.0
var is_dead: bool = false

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
@onready var death_screen: CanvasLayer = get_node_or_null("DeathScreen")

const SPAWN_POINTS: Array[Vector3] = [
	Vector3(0, 2.0, 2.5),
	Vector3(-12.0, 2.0, 8.0),
	Vector3(12.0, 2.0, 8.0),
	Vector3(-10.0, 2.0, -12.0),
	Vector3(10.0, 2.0, -12.0),
	Vector3(0, 2.0, -16.0),
	Vector3(-16.0, 2.0, -2.0),
	Vector3(16.0, 2.0, -2.0)
]

var animation_player: AnimationPlayer
var fire_timer: float = 0.0
var ammo: int = 0
var reload_left: float = 0.0  # > 0 while a reload is in progress
var _since_damage := 0.0
var _shake := 0.0
var weapon_default_pos: Vector3 = Vector3(0.22, -0.22, -0.42)
var weapon_default_rot: Vector3 = Vector3.ZERO
var muzzle_tween: Tween

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health = max_health
	
	if weapon_holder:
		weapon_default_pos = weapon_holder.position
		weapon_default_rot = weapon_holder.rotation
	
	if character:
		animation_player = CharacterAnimations.attach(character)
	_connect_network()
	
	# Initial health update to HUD
	var hud = _get_multiplayer_hud()
	if hud and hud.has_method("update_hp"):
		hud.update_hp(health, max_health)
	
	_apply_settings()
	Settings.changed.connect(_apply_settings)
	ammo = magazine_size
	_update_ammo_hud()

func _apply_settings() -> void:
	camera.fov = Settings.fov

func _get_network() -> Node:
	return get_node_or_null("/root/Network")

func _get_multiplayer_hud() -> Node:
	if get_tree():
		var node = get_tree().get_first_node_in_group("multiplayer_hud")
		if node:
			return node
		if get_tree().current_scene:
			node = get_tree().current_scene.get_node_or_null("MultiplayerHUD")
			if node:
				return node
	return null

func _connect_network() -> void:
	var net = _get_network()
	if not net:
		return
	net.connected_to_server.connect(_on_net_connected)
	net.player_damaged.connect(_on_net_player_damaged)
	net.player_respawned.connect(_on_net_player_respawned)

func _on_net_connected(id: String, info: Dictionary) -> void:
	if info.has("spawn_pos"):
		var sp: Array = info["spawn_pos"]
		global_position = Vector3(sp[0], sp[1], sp[2])
	if info.has("skin"):
		set_skin(info["skin"])

func _on_net_player_damaged(victim_id: String, attacker_id: String, dmg: float, new_hp: float) -> void:
	var net = _get_network()
	if net and victim_id == net.my_id:
		health = new_hp
		var hud = _get_multiplayer_hud()
		if hud:
			hud.update_hp(health, max_health)
			hud.trigger_damage_flash()
		if health <= 0.0 and not is_dead:
			var attacker_name = "Enemy"
			if net.all_players.has(attacker_id):
				attacker_name = net.all_players[attacker_id].get("name", "Enemy")
			die(attacker_name)

func _on_net_player_respawned(pid: String, pos: Vector3, hp: float) -> void:
	var net = _get_network()
	if net and pid == net.my_id:
		global_position = pos
		health = hp
		is_dead = false
		velocity = Vector3.ZERO
		var hud = _get_multiplayer_hud()
		if hud:
			hud.update_hp(health, max_health)

func set_skin(skin_key: String) -> void:
	const SKIN_PATHS := {
		"survivorMaleB": "res://kenney_animated-characters-survivors/Skins/survivorMaleB.png",
		"survivorFemaleA": "res://kenney_animated-characters-survivors/Skins/survivorFemaleA.png",
		"zombieA": "res://kenney_animated-characters-survivors/Skins/zombieA.png",
		"zombieC": "res://kenney_animated-characters-survivors/Skins/zombieC.png"
	}
	var path: String = SKIN_PATHS.get(skin_key, SKIN_PATHS["survivorMaleB"])
	if ResourceLoader.exists(path) and character:
		var tex: Texture2D = load(path)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		var mesh_instance := character.find_child("characterMedium", true, false) as GeometryInstance3D
		if mesh_instance:
			mesh_instance.material_override = mat

func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	# Click to recapture mouse
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not is_dead:
			var hud = _get_multiplayer_hud()
			# Don't capture mouse if dialog or chat is open
			if not (hud and (hud.connect_dialog.visible or hud.is_chatting)):
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				get_viewport().set_input_as_handled()
				return
	
	if is_dead:
		return
		
	# Camera mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * BASE_SENSITIVITY * Settings.mouse_sensitivity)
		head.rotate_x(-event.relative.y * BASE_SENSITIVITY * Settings.mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _process(delta: float) -> void:
	if is_dead:
		return
	_update_health(delta)
	
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
	if is_dead:
		return
	
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
	var hit_normal := Vector3.UP
	var is_hit := raycast.is_colliding()
	var is_target := false
	
	if is_hit:
		hit_pos = raycast.get_collision_point()
		hit_normal = raycast.get_collision_normal()
		var collider := raycast.get_collider()
		
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
			
			# Sync target hit with server
			var net = _get_network()
			if net and net.is_connected_to_server():
				if damage_target is StaticBody3D and "target" in damage_target.name.to_lower():
					net.send_target_hit(damage_target.name, damage)
		elif collider is RigidBody3D:
			var push_dir := (hit_pos - camera.global_position).normalized()
			collider.apply_impulse(push_dir * impact_force, hit_pos - collider.global_position)
			var net = _get_network()
			if net and net.is_connected_to_server() and collider.has_method("take_damage"):
				net.send_crate_damage(collider.name, damage)
		
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
	
	# Broadcast shot to multiplayer peers
	var net = _get_network()
	if net and net.is_connected_to_server():
		net.send_shoot(muzzle_pos, hit_pos, hit_normal, is_target)

## Called by zombies and by the multiplayer layer. Flashes the screen, shakes the
## camera, and may kill the player.
func take_damage(amount: float, attacker_id: String = "") -> void:
	if is_dead:
		return
	health = maxf(0.0, health - amount)
	_since_damage = 0.0
	_shake = 1.0
	var hud = _get_multiplayer_hud()
	if hud:
		hud.update_hp(health, max_health)
		hud.trigger_damage_flash()
	if health <= 0.0:
		die(attacker_id)

func die(killer_name: String = "") -> void:
	is_dead = true
	velocity = Vector3.ZERO
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	var net = _get_network()
	var hud = _get_multiplayer_hud()
	if net and net.is_connected_to_server() and hud:
		hud.show_death_screen(killer_name)  # multiplayer: arena-style auto-respawn
	elif death_screen and death_screen.has_method("show_screen"):
		death_screen.show_screen()  # solo vs zombies: game over with wave stats

func respawn() -> void:
	health = max_health
	is_dead = false
	velocity = Vector3.ZERO
	# Fresh magazine on respawn (cancel any reload that was in progress)
	reload_left = 0.0
	ammo = magazine_size
	if crosshair_hud and crosshair_hud.has_method("set_reloading"):
		crosshair_hud.set_reloading(false)
	_update_ammo_hud()
	global_position = _get_random_spawn_point()
	var hud = _get_multiplayer_hud()
	if hud:
		hud.update_hp(health, max_health)
	var net = _get_network()
	if net and net.is_connected_to_server():
		net.send_respawn()

func _get_random_spawn_point() -> Vector3:
	var idx := randi() % SPAWN_POINTS.size()
	return SPAWN_POINTS[idx] + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))

func _get_effects_container() -> Node:
	if get_tree() and get_tree().current_scene:
		return get_tree().current_scene
	if get_tree() and get_tree().root and get_tree().root.get_child_count() > 0:
		return get_tree().root.get_child(get_tree().root.get_child_count() - 1)
	if owner:
		return owner
	return self

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
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
	
	# Send state to multiplayer server
	var current_anim := "idle"
	if animation_player:
		current_anim = animation_player.current_animation
	var net = _get_network()
	if net and net.is_connected_to_server():
		net.send_state(global_position, velocity, rotation.y, head.rotation.x, current_anim, is_on_floor())

## Slow regeneration after a quiet spell, plus the decaying camera shake after a hit.
func _update_health(delta: float) -> void:
	_since_damage += delta
	if _since_damage >= regen_delay and health < max_health:
		health = minf(health + regen_rate * delta, max_health)
		var hud = _get_multiplayer_hud()
		if hud and hud.has_method("update_hp"):
			hud.update_hp(health, max_health)
	_shake = maxf(_shake - delta * 4.0, 0.0)
	camera.h_offset = randf_range(-1.0, 1.0) * 0.03 * _shake
	camera.v_offset = randf_range(-1.0, 1.0) * 0.03 * _shake
