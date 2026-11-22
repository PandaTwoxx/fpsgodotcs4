extends Node
## Autoload ("Game"): wave / kill / score tracking for the current run, plus
## the best result across runs (saved to user://stats.cfg).

signal changed
signal banner(title: String, subtitle: String)

const PATH := "user://stats.cfg"
const POINTS_PER_KILL := 100

var wave := 0
var kills := 0
var score := 0
var zombies_left := 0
var best_score := 0
var best_wave := 0

func _ready() -> void:
	_load_best()

## Start of a run (called by the wave manager each time the map loads).
func reset() -> void:
	wave = 0
	kills = 0
	score = 0
	zombies_left = 0
	changed.emit()

func add_kill() -> void:
	kills += 1
	score += POINTS_PER_KILL
	changed.emit()

func add_bonus(points: int) -> void:
	score += points
	changed.emit()

func set_wave(number: int, total_zombies: int) -> void:
	wave = number
	zombies_left = total_zombies
	changed.emit()

func set_zombies_left(count: int) -> void:
	zombies_left = maxi(count, 0)
	changed.emit()

func show_banner(title: String, subtitle: String = "") -> void:
	banner.emit(title, subtitle)

## Called when the player dies. Saves the best result; returns true if it is a new best score.
func finish_run() -> bool:
	var is_new_best := score > best_score
	if is_new_best:
		best_score = score
	best_wave = maxi(best_wave, wave)
	var cfg := ConfigFile.new()
	cfg.set_value("best", "score", best_score)
	cfg.set_value("best", "wave", best_wave)
	cfg.save(PATH)
	return is_new_best

func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	best_score = cfg.get_value("best", "score", 0)
	best_wave = cfg.get_value("best", "wave", 0)
