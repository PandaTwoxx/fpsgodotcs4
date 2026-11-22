class_name CharacterAnimations
## Shared helper: the Kenney character model ships without an AnimationPlayer
## (its clips live in separate FBX files), so build one from those files.

const ANIM_DIR := "res://kenney_animated-characters-survivors/Animations/"
# short name -> [source file, clip name inside the file, loops?]
const ANIMATIONS := {
	"idle": ["idle.fbx", "Root|Idle", true],
	"run": ["run.fbx", "Root|Run", true],
	"jump": ["jump.fbx", "Root|Jump", false],
}

## Adds an AnimationPlayer (idle/run/jump) under `character` and starts "idle".
static func attach(character: Node3D) -> AnimationPlayer:
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
	var player := AnimationPlayer.new()
	character.add_child(player)
	player.add_animation_library("", library)
	player.play("idle")
	return player
