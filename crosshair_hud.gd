extends CanvasLayer

@onready var hitmarker: Control = get_node_or_null("Root/Hitmarker")

var hitmarker_timer: float = 0.0

func _ready() -> void:
	# Keep running while the tree is paused so the crosshair can hide itself.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if hitmarker:
		hitmarker.modulate.a = 0.0

func show_hitmarker() -> void:
	hitmarker_timer = 0.18
	if hitmarker:
		hitmarker.modulate.a = 1.0

func _process(delta: float) -> void:
	# The pause menu has its own cursor; a crosshair behind it is just clutter.
	visible = not get_tree().paused
	if hitmarker_timer > 0.0:
		hitmarker_timer -= delta
		if hitmarker:
			hitmarker.modulate.a = clamp(hitmarker_timer / 0.18, 0.0, 1.0)
