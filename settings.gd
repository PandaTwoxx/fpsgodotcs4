extends Node
## Autoload ("Settings"): player-adjustable options, saved to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

var mouse_sensitivity := 1.0  # multiplier on the player's base sensitivity
var fov := 110.0
var master_volume := 1.0  # linear, 0.0 - 1.0

func _ready() -> void:
	_load()
	apply()

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mouse_sensitivity = clampf(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity), 0.2, 3.0)
	fov = clampf(cfg.get_value("video", "fov", fov), 70.0, 120.0)
	master_volume = clampf(cfg.get_value("audio", "master_volume", master_volume), 0.0, 1.0)

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.save(PATH)

## Push current values to the engine and notify listeners (e.g. the player camera).
func apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(master_volume))
	AudioServer.set_bus_mute(bus, master_volume <= 0.0)
	changed.emit()
