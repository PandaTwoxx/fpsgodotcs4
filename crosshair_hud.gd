extends CanvasLayer

@onready var hitmarker: Control = get_node_or_null("Root/Hitmarker")
@onready var ammo_label: Label = get_node_or_null("Root/Ammo/AmmoLabel")
@onready var reload_label: Label = get_node_or_null("Root/Ammo/ReloadLabel")
@onready var health_label: Label = get_node_or_null("Root/Health/HealthLabel")
@onready var health_bar: Control = get_node_or_null("Root/Health/Bar")
@onready var health_fill: ColorRect = get_node_or_null("Root/Health/Bar/Fill")
@onready var damage_flash: ColorRect = get_node_or_null("Root/DamageFlash")

const AMMO_NORMAL := Color(1, 1, 1, 0.95)
const AMMO_LOW := Color(1.0, 0.35, 0.3, 1.0)

var hitmarker_timer: float = 0.0
var _reloading := false
var _flash_tween: Tween

func _ready() -> void:
	# Keep running while the tree is paused so the crosshair can hide itself.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if hitmarker:
		hitmarker.modulate.a = 0.0

func set_ammo(current: int, max_ammo: int) -> void:
	if ammo_label:
		ammo_label.text = "%d / %d" % [current, max_ammo]
		var low := current <= int(ceil(max_ammo * 0.25))
		ammo_label.add_theme_color_override("font_color", AMMO_LOW if low else AMMO_NORMAL)
	if reload_label and not _reloading:
		reload_label.text = "Press R to reload" if current == 0 else ""

func set_health(current: float, max_health: float) -> void:
	var ratio := clampf(current / max_health, 0.0, 1.0)
	if health_label:
		health_label.text = "HEALTH  %d" % ceili(current)
	if health_fill and health_bar:
		health_fill.size.x = health_bar.size.x * ratio
		# green -> yellow -> red as health drops
		health_fill.color = Color(1.0, 0.25, 0.2).lerp(Color(0.3, 0.9, 0.35), ratio) if ratio > 0.5 \
				else Color(1.0, 0.25, 0.2).lerp(Color(1.0, 0.85, 0.25), ratio * 2.0)

## Brief red screen flash when the player takes damage.
func flash_damage() -> void:
	if not damage_flash:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	damage_flash.color.a = 0.28
	_flash_tween = create_tween()
	_flash_tween.tween_property(damage_flash, "color:a", 0.0, 0.4)

func set_reloading(reloading: bool) -> void:
	_reloading = reloading
	if reload_label:
		reload_label.text = "RELOADING..." if reloading else ""

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
