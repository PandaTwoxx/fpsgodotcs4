extends CharacterBody3D

@export var player_id: String = ""
@export var player_name: String = "Survivor"
@export var max_health: float = 100.0
var health: float = 100.0
var is_dead: bool = false

var target_position: Vector3 = Vector3.ZERO
var target_yaw: float = 0.0
var target_pitch: float = 0.0
var target_anim: String = "idle"

var animation_player: AnimationPlayer
var muzzle_tween: Tween

const BULLET_TRACER_SCENE = preload("res://bullet_tracer.tscn")
const IMPACT_EFFECT_SCENE = preload("res://impact_effect.tscn")
const BLASTER_SOUND = preload("res://sounds/blaster_fire.wav")

const SKIN_PATHS := {
	"survivorMaleB": "res://kenney_animated-characters-survivors/Skins/survivorMaleB.png",
	"survivorFemaleA": "res://kenney_animated-characters-survivors/Skins/survivorFemaleA.png",
	"zombieA": "res://kenney_animated-characters-survivors/Skins/zombieA.png",
	"zombieC": "res://kenney_animated-characters-survivors/Skins/zombieC.png"
}

const ANIM_DIR := "res://kenney_animated-characters-survivors/Animations/"
const ANIMATIONS := {
	"idle": ["idle.fbx", "Root|Idle", true],
	"run": ["run.fbx", "Root|Run", true],
	"jump": ["jump.fbx", "Root|Jump", false],
}

@onready var character_node: Node3D = $characterMedium
@onready var shoot_sound_3d: AudioStreamPlayer3D = $ShootSound3D
@onready var muzzle_flash: OmniLight3D = $WeaponHolder/Muzzle/MuzzleFlash
@onready var muzzle_marker: Marker3D = $WeaponHolder/Muzzle
@onready var weapon_holder: Node3D = $WeaponHolder
@onready var overhead_sprite: Sprite3D = $OverheadHUD
@onready var hud_viewport: SubViewport = $SubViewport
@onready var name_label: Label = $SubViewport/Panel/VBox/NameLabel
@onready var hp_bar: ProgressBar = $SubViewport/Panel/VBox/HPBar

func _ready() -> void:
	target_position = global_position
	target_yaw = rotation.y
	_setup_animations()
	_update_hud()

func setup(id: String, p_name: String, skin_key: String, spawn_pos: Vector3) -> void:
	player_id = id
	player_name = p_name
	global_position = spawn_pos
	target_position = spawn_pos
	set_skin(skin_key)
	_update_hud()

func set_skin(skin_key: String) -> void:
	var path: String = SKIN_PATHS.get(skin_key, SKIN_PATHS["survivorMaleB"])
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		# Apply to character mesh
		if character_node:
			var mesh_instance := character_node.find_child("characterMedium", true, false) as GeometryInstance3D
			if mesh_instance:
				mesh_instance.material_override = mat

func _setup_animations() -> void:
	if not character_node:
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
		source.free()
	animation_player = AnimationPlayer.new()
	character_node.add_child(animation_player)
	animation_player.add_animation_library("", library)
	animation_player.play("idle")

func update_net_state(pos: Vector3, vel: Vector3, yaw: float, pitch: float, anim: String, hp: float) -> void:
	target_position = pos
	target_yaw = yaw
	target_pitch = pitch
	target_anim = anim
	if hp != health:
		health = hp
		_update_hud()
	if health <= 0 and not is_dead:
		set_dead(true)
	elif health > 0 and is_dead:
		set_dead(false)

func _process(delta: float) -> void:
	if is_dead:
		return
		
	# Smoothly interpolate position and orientation
	global_position = global_position.lerp(target_position, delta * 20.0)
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * 22.0)
	
	# Pitch weapon holder with aim direction
	if weapon_holder:
		weapon_holder.rotation.x = lerp_angle(weapon_holder.rotation.x, target_pitch, delta * 20.0)
		
	# Play corresponding animation
	if animation_player:
		if target_anim != "" and animation_player.has_animation(target_anim):
			if animation_player.current_animation != target_anim:
				animation_player.play(target_anim)

func play_shoot(origin: Vector3, hit: Vector3, normal: Vector3, is_target: bool) -> void:
	if is_dead:
		return
		
	# Play 3D positional gun sound
	if shoot_sound_3d:
		shoot_sound_3d.pitch_scale = randf_range(0.95, 1.05)
		shoot_sound_3d.play()
		
	# Muzzle flash
	if muzzle_flash:
		if muzzle_tween and muzzle_tween.is_valid():
			muzzle_tween.kill()
		muzzle_flash.light_energy = 2.5
		muzzle_tween = create_tween()
		muzzle_tween.tween_property(muzzle_flash, "light_energy", 0.0, 0.05)
		
	var m_pos := muzzle_marker.global_position if muzzle_marker else (global_position + Vector3(0, 1.2, 0))
	
	# Bullet tracer
	var tracer := BULLET_TRACER_SCENE.instantiate()
	_get_effects_container().add_child(tracer)
	tracer.setup(m_pos, hit)
	
	# Impact particles
	var impact := IMPACT_EFFECT_SCENE.instantiate()
	_get_effects_container().add_child(impact)
	impact.setup(hit, normal, is_target)

func take_damage(amount: float, attacker_id: String = "") -> void:
	# Called locally when raycast hits this RemotePlayer
	# Tell server that we hit this player
	var net = get_node_or_null("/root/Network")
	if net and net.has_method("send_hit"):
		net.send_hit(player_id, amount)

func apply_damage(amount: float, new_hp: float) -> void:
	health = new_hp
	_update_hud()
	
	# Wobble / flash on damage
	var tw := create_tween()
	tw.tween_property(character_node, "scale", Vector3(0.22, 0.18, 0.22), 0.05)
	tw.tween_property(character_node, "scale", Vector3(0.2, 0.2, 0.2), 0.1)
	
	if health <= 0.0:
		set_dead(true)

func set_dead(dead: bool) -> void:
	is_dead = dead
	if dead:
		health = 0
		_update_hud()
		if overhead_sprite:
			overhead_sprite.visible = false
		var tw := create_tween()
		tw.tween_property(character_node, "rotation:x", -PI * 0.5, 0.2)
		tw.parallel().tween_property(character_node, "position:y", -0.9, 0.2)
	else:
		health = max_health
		_update_hud()
		if overhead_sprite:
			overhead_sprite.visible = true
		character_node.rotation.x = 0
		character_node.position.y = -0.3385
		visible = true

func respawn_at(new_pos: Vector3, new_hp: float) -> void:
	global_position = new_pos
	target_position = new_pos
	health = new_hp
	set_dead(false)

func _update_hud() -> void:
	if name_label:
		name_label.text = player_name
	if hp_bar:
		hp_bar.value = health
		var ratio := health / max_health
		var style := StyleBoxFlat.new()
		style.corner_radius_top_left = 3
		style.corner_radius_top_right = 3
		style.corner_radius_bottom_left = 3
		style.corner_radius_bottom_right = 3
		if ratio > 0.5:
			style.bg_color = Color(0.2, 0.8, 0.2, 0.9)
		elif ratio > 0.25:
			style.bg_color = Color(0.9, 0.7, 0.1, 0.9)
		else:
			style.bg_color = Color(0.9, 0.15, 0.15, 0.9)
		hp_bar.add_theme_stylebox_override("fill", style)

func _get_effects_container() -> Node:
	if get_tree() and get_tree().current_scene:
		return get_tree().current_scene
	return self
