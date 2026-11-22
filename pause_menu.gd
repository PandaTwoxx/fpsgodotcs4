extends CanvasLayer

@onready var main_box: Control = $Center/Main
@onready var controls_panel: Control = $Center/ControlsPanel
@onready var settings_menu: Control = $SettingsMenu

func _ready() -> void:
	hide()
	$Center/Main/ResumeButton.pressed.connect(_set_paused.bind(false))
	$Center/Main/ControlsButton.pressed.connect(_show_page.bind(controls_panel))
	$Center/Main/SettingsButton.pressed.connect(_show_page.bind(settings_menu))
	$Center/Main/RestartButton.pressed.connect(_restart)
	$Center/Main/QuitButton.pressed.connect(get_tree().quit)
	$Center/ControlsPanel/Margin/VBox/BackButton.pressed.connect(_show_page.bind(main_box))
	settings_menu.back_pressed.connect(_show_page.bind(main_box))

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	if not visible:
		_set_paused(true)
	elif main_box.visible:
		_set_paused(false)
	else:
		if settings_menu.visible:
			Settings.save()
		_show_page(main_box)

func _set_paused(paused: bool) -> void:
	_show_page(main_box)
	visible = paused
	get_tree().paused = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED

## Show exactly one of: main buttons, controls panel, settings menu.
func _show_page(page: Control) -> void:
	main_box.visible = page == main_box
	controls_panel.visible = page == controls_panel
	settings_menu.visible = page == settings_menu
	if page == main_box:
		$Center/Main/ResumeButton.grab_focus()
	elif page == controls_panel:
		$Center/ControlsPanel/Margin/VBox/BackButton.grab_focus()

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
