extends CanvasLayer

@onready var main_box: Control = $Center/Main
@onready var controls_panel: Control = $Center/ControlsPanel
@onready var resume_btn: Button = $Center/Main/ResumeButton
@onready var mp_btn: Button = $Center/Main/MultiplayerButton
@onready var controls_btn: Button = $Center/Main/ControlsButton
@onready var restart_btn: Button = $Center/Main/RestartButton
@onready var quit_btn: Button = $Center/Main/QuitButton
@onready var back_btn: Button = $Center/ControlsPanel/Margin/VBox/BackButton

func _ready() -> void:
	hide()
	resume_btn.pressed.connect(_set_paused.bind(false))
	mp_btn.pressed.connect(_open_multiplayer)
	controls_btn.pressed.connect(_show_controls.bind(true))
	restart_btn.pressed.connect(_restart)
	quit_btn.pressed.connect(get_tree().quit)
	back_btn.pressed.connect(_show_controls.bind(false))

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	
	# If multiplayer connect dialog or chat is open, let that close first
	var mp_hud = _get_multiplayer_hud()
	if mp_hud:
		if mp_hud.connect_dialog.visible:
			mp_hud.toggle_connect_dialog(false)
			get_viewport().set_input_as_handled()
			return
		if mp_hud.is_chatting:
			mp_hud._stop_chatting()
			get_viewport().set_input_as_handled()
			return

	get_viewport().set_input_as_handled()
	if not visible:
		_set_paused(true)
	elif controls_panel.visible:
		_show_controls(false)
	else:
		_set_paused(false)

func _is_multiplayer_active() -> bool:
	var net = get_node_or_null("/root/Network")
	return net and net.is_connected_to_server()

func _set_paused(paused: bool) -> void:
	_show_controls(false)
	visible = paused
	
	# Don't freeze scene tree if connected to multiplayer server!
	if not _is_multiplayer_active():
		get_tree().paused = paused
	else:
		get_tree().paused = false
		
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	if paused:
		resume_btn.grab_focus()

func _open_multiplayer() -> void:
	_set_paused(false)
	var mp_hud = _get_multiplayer_hud()
	if mp_hud:
		mp_hud.toggle_connect_dialog(true)

func _get_multiplayer_hud() -> Node:
	if get_tree() and get_tree().current_scene:
		return get_tree().current_scene.get_node_or_null("MultiplayerHUD")
	return null

func _show_controls(show_panel: bool) -> void:
	controls_panel.visible = show_panel
	main_box.visible = not show_panel
	if show_panel:
		back_btn.grab_focus()
	elif visible:
		resume_btn.grab_focus()

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
