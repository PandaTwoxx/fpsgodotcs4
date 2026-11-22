extends CanvasLayer
## Shown when the player dies: freezes the game and offers Restart / Quit.

func _ready() -> void:
	hide()
	$Center/VBox/RestartButton.pressed.connect(_on_restart)
	$Center/VBox/QuitButton.pressed.connect(get_tree().quit)

func show_screen() -> void:
	var new_best := Game.finish_run()
	var lines := [
		"Reached wave %d" % maxi(Game.wave, 1),
		"%d kills  -  %d points" % [Game.kills, Game.score],
		"NEW BEST SCORE!" if new_best else "Best: %d points (wave %d)" % [Game.best_score, Game.best_wave],
	]
	$Center/VBox/StatsLabel.text = "\n".join(lines)
	show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$Center/VBox/RestartButton.grab_focus()

func _on_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
