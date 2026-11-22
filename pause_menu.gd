extends CanvasLayer

@onready var main_box: Control = $Center/Main
@onready var controls_panel: Control = $Center/ControlsPanel

func _ready() -> void:
	hide()
	$Center/Main/ResumeButton.pressed.connect(_set_paused.bind(false))
	$Center/Main/ControlsButton.pressed.connect(_show_controls.bind(true))
	$Center/Main/RestartButton.pressed.connect(_restart)
	$Center/Main/QuitButton.pressed.connect(get_tree().quit)
	$Center/ControlsPanel/Margin/VBox/BackButton.pressed.connect(_show_controls.bind(false))

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	if not visible:
		_set_paused(true)
	elif controls_panel.visible:
		_show_controls(false)
	else:
		_set_paused(false)

func _set_paused(paused: bool) -> void:
	_show_controls(false)
	visible = paused
	get_tree().paused = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	if paused:
		$Center/Main/ResumeButton.grab_focus()

func _show_controls(show_panel: bool) -> void:
	controls_panel.visible = show_panel
	main_box.visible = not show_panel
	if show_panel:
		$Center/ControlsPanel/Margin/VBox/BackButton.grab_focus()
	elif visible:
		$Center/Main/ResumeButton.grab_focus()

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
