extends CharacterBody3D

const SPEED = 4.0
const JUMP_VELOCITY = 4.5
const BASE_SENSITIVITY = 0.0015

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var raycast: RayCast3D = $Head/Camera3D/RayCast3D
@onready var character: Node3D = $characterMedium

const ANIM_DIR := "res://kenney_animated-characters-survivors/Animations/"
# short name -> [source file, clip name inside the file, loops?]
const ANIMATIONS := {
	"idle": ["idle.fbx", "Root|Idle", true],
	"run": ["run.fbx", "Root|Run", true],
	"jump": ["jump.fbx", "Root|Jump", false],
}

var animation_player: AnimationPlayer

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_setup_animations()
	_apply_settings()
	Settings.changed.connect(_apply_settings)

func _apply_settings() -> void:
	camera.fov = Settings.fov

# The character model ships without an AnimationPlayer; its clips live in
# separate FBX files, so collect them into one library at startup.
func _setup_animations() -> void:
	var library := AnimationLibrary.new()
	for anim_name: String in ANIMATIONS:
		var info: Array = ANIMATIONS[anim_name]
		var source: Node = (load(ANIM_DIR + info[0]) as PackedScene).instantiate()
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
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * BASE_SENSITIVITY * Settings.mouse_sensitivity)
		head.rotate_x(-event.relative.y * BASE_SENSITIVITY * Settings.mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _physics_process(delta: float) -> void:
	# Add gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get movement input
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		# Play running animation when moving (replace "run" with your exact animation name if different)
		if animation_player and animation_player.has_animation("run"):
			animation_player.play("run")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		# Play idle animation when standing still
		if animation_player and animation_player.has_animation("idle"):
			animation_player.play("idle")

	move_and_slide()
