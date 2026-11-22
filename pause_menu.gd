extends CanvasLayer

@onready var main_box: Control = $Center/Main
@onready var controls_panel: Control = $Center/ControlsPanel
@onready var resume_btn: Button = $Center/Main/ResumeButton
@onready var mp_btn: Button = $Center/Main/MultiplayerButton
@onready var controls_btn: Button = $Center/Main/ControlsButton
@onready var restart_btn: Button = $Center/Main/RestartButton
@onready var quit_btn: Button = $Center/Main/QuitButton
@onready var back_btn: Button = $Center/ControlsPanel/Margin/VBox/BackButton
@onready var settings_menu: Control = $SettingsMenu

func _ready() -> void:
	hide()
	resume_btn.pressed.connect(_set_paused.bind(false))
	mp_btn.pressed.connect(_open_multiplayer)
	controls_btn.pressed.connect(_show_page.bind(controls_panel))
	$Center/Main/SettingsButton.pressed.connect(_show_page.bind(settings_menu))
	restart_btn.pressed.connect(_restart)
	quit_btn.pressed.connect(get_tree().quit)
	back_btn.pressed.connect(_show_page.bind(main_box))
	settings_menu.back_pressed.connect(_show_page.bind(main_box))

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	var player := get_tree().get_first_node_in_group("player")
	if player and player.get("is_dead"):
		return  # the death screen owns the game now
	
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
	elif main_box.visible:
		_set_paused(false)
	else:
		if settings_menu.visible:
			Settings.save()
		_show_page(main_box)

func _is_multiplayer_active() -> bool:
	var net = get_node_or_null("/root/Network")
	return net and net.is_connected_to_server()

func _set_paused(paused: bool) -> void:
	_show_page(main_box)
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

## Show exactly one of: main buttons, controls panel, settings menu.
func _show_page(page: Control) -> void:
	main_box.visible = page == main_box
	controls_panel.visible = page == controls_panel
	settings_menu.visible = page == settings_menu
	if page == main_box:
		resume_btn.grab_focus()
	elif page == controls_panel:
		back_btn.grab_focus()

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
