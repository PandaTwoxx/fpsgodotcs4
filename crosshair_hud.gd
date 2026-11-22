extends CanvasLayer

@onready var hitmarker: Control = get_node_or_null("Root/Hitmarker")

var hitmarker_timer: float = 0.0

func _ready() -> void:
	if hitmarker:
		hitmarker.modulate.a = 0.0

func show_hitmarker() -> void:
	hitmarker_timer = 0.18
	if hitmarker:
		hitmarker.modulate.a = 1.0

func _process(delta: float) -> void:
	if hitmarker_timer > 0.0:
		hitmarker_timer -= delta
		if hitmarker:
			hitmarker.modulate.a = clamp(hitmarker_timer / 0.18, 0.0, 1.0)
