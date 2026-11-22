extends CanvasLayer

@onready var hitmarker: Control = get_node_or_null("Root/Hitmarker")
@onready var ammo_label: Label = get_node_or_null("Root/Ammo/AmmoLabel")
@onready var reload_label: Label = get_node_or_null("Root/Ammo/ReloadLabel")
@onready var wave_label: Label = get_node_or_null("Root/WaveInfo/WaveLabel")
@onready var left_label: Label = get_node_or_null("Root/WaveInfo/LeftLabel")
@onready var score_label: Label = get_node_or_null("Root/ScoreInfo/ScoreLabel")
@onready var kills_label: Label = get_node_or_null("Root/ScoreInfo/KillsLabel")
@onready var banner: Control = get_node_or_null("Root/Banner")
@onready var banner_title: Label = get_node_or_null("Root/Banner/BannerTitle")
@onready var banner_sub: Label = get_node_or_null("Root/Banner/BannerSub")

const AMMO_NORMAL := Color(1, 1, 1, 0.95)
const AMMO_LOW := Color(1.0, 0.35, 0.3, 1.0)

var hitmarker_timer: float = 0.0
var _reloading := false
var _banner_tween: Tween

func _ready() -> void:
	# Keep running while the tree is paused so the crosshair can hide itself.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if hitmarker:
		hitmarker.modulate.a = 0.0
	if banner:
		banner.modulate.a = 0.0
	Game.changed.connect(_refresh_run_stats)
	Game.banner.connect(show_banner)
	_refresh_run_stats()

func _refresh_run_stats() -> void:
	if wave_label:
		wave_label.text = "WAVE %d" % maxi(Game.wave, 1)
	if left_label:
		left_label.text = "Zombies left: %d" % Game.zombies_left
	if score_label:
		score_label.text = "SCORE  %d" % Game.score
	if kills_label:
		kills_label.text = "KILLS  %d" % Game.kills

## Big centered announcement that fades out ("WAVE 3", "WAVE CLEARED", ...).
func show_banner(title: String, subtitle: String = "") -> void:
	if not banner:
		return
	banner_title.text = title
	banner_sub.text = subtitle
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	banner.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(2.2)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.8)

func set_ammo(current: int, max_ammo: int) -> void:
	if ammo_label:
		ammo_label.text = "%d / %d" % [current, max_ammo]
		var low := current <= int(ceil(max_ammo * 0.25))
		ammo_label.add_theme_color_override("font_color", AMMO_LOW if low else AMMO_NORMAL)
	if reload_label and not _reloading:
		reload_label.text = "Press R to reload" if current == 0 else ""

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
