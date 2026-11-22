extends CanvasLayer

@onready var status_label: Label = $Root/TopLeft/HBox/StatusLabel
@onready var menu_button: Button = $Root/TopLeft/HBox/MenuButton
@onready var hp_bar: ProgressBar = $Root/BottomLeft/VBox/HPBar
@onready var hp_label: Label = $Root/BottomLeft/VBox/HPLabel
@onready var damage_vignette: ColorRect = $Root/DamageVignette
@onready var kill_feed_container: VBoxContainer = $Root/TopRight/KillFeed
@onready var scoreboard_panel: Control = $Root/Scoreboard
@onready var scoreboard_list: VBoxContainer = $Root/Scoreboard/Margin/VBox/PlayerList
@onready var chat_container: Control = $Root/Chat
@onready var chat_log: VBoxContainer = $Root/Chat/LogMargin/LogVBox
@onready var chat_input: LineEdit = $Root/Chat/InputMargin/ChatInput
@onready var death_overlay: Control = $Root/DeathOverlay
@onready var death_killer_label: Label = $Root/DeathOverlay/Center/VBox/KillerLabel
@onready var death_timer_label: Label = $Root/DeathOverlay/Center/VBox/TimerLabel
@onready var connect_dialog: Control = $Root/ConnectDialog
@onready var server_input: LineEdit = $Root/ConnectDialog/Margin/VBox/ServerHBox/ServerInput
@onready var name_input: LineEdit = $Root/ConnectDialog/Margin/VBox/NameHBox/NameInput
@onready var skin_option: OptionButton = $Root/ConnectDialog/Margin/VBox/SkinHBox/SkinOption
@onready var connect_btn: Button = $Root/ConnectDialog/Margin/VBox/ButtonsHBox/ConnectBtn
@onready var disconnect_btn: Button = $Root/ConnectDialog/Margin/VBox/ButtonsHBox/DisconnectBtn
@onready var dialog_status: Label = $Root/ConnectDialog/Margin/VBox/DialogStatus

var respawn_countdown: float = 0.0
var damage_flash_alpha: float = 0.0
var is_chatting: bool = false

const SKINS = ["survivorMaleB", "survivorFemaleA", "zombieA", "zombieC"]
const SKIN_DISPLAY = ["Survivor (Male)", "Survivor (Female)", "Zombie A", "Zombie C"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	scoreboard_panel.visible = false
	death_overlay.visible = false
	chat_input.visible = false
	connect_dialog.visible = false
	damage_vignette.modulate.a = 0.0
	
	# Setup skins in dropdown
	skin_option.clear()
	for i in range(SKIN_DISPLAY.size()):
		skin_option.add_item(SKIN_DISPLAY[i], i)
	skin_option.selected = 0
	
	# Default name
	var rng_id := randi() % 900 + 100
	name_input.text = "Survivor_%d" % rng_id
	server_input.text = "ws://127.0.0.1:8910"
	
	# Connect buttons
	menu_button.pressed.connect(toggle_connect_dialog)
	connect_btn.pressed.connect(_on_connect_pressed)
	disconnect_btn.pressed.connect(_on_disconnect_pressed)
	$Root/ConnectDialog/Margin/VBox/HeaderHBox/CloseBtn.pressed.connect(toggle_connect_dialog.bind(false))
	chat_input.text_submitted.connect(_on_chat_submitted)
	
	# Connect Network signals
	var net = _get_network()
	if net:
		net.connected_to_server.connect(_on_connected)
		net.connection_failed.connect(_on_connection_failed)
		net.server_disconnected.connect(_on_disconnected)
		net.player_joined.connect(_on_player_joined)
		net.player_left.connect(_on_player_left)
		net.player_killed.connect(_on_player_killed)
		net.chat_received.connect(_on_chat_received)
		net.latency_updated.connect(_on_latency_updated)
	
	_update_connection_status()
	
	var p = get_tree().get_first_node_in_group("player")
	if p and "health" in p and "max_health" in p:
		update_hp(p.health, p.max_health)
	else:
		update_hp(100.0, 100.0)

func _get_network() -> Node:
	return get_node_or_null("/root/Network")

func _unhandled_input(event: InputEvent) -> void:
	# Toggle scoreboard on Tab
	if event is InputEventKey and event.keycode == KEY_TAB:
		if not is_chatting:
			scoreboard_panel.visible = event.pressed
			if event.pressed:
				_update_scoreboard()
			get_viewport().set_input_as_handled()
			return
			
	# Open chat on T or Enter
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_T and not is_chatting and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_start_chatting()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_ENTER and not is_chatting:
			_start_chatting()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_M and not is_chatting and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			toggle_connect_dialog()
			get_viewport().set_input_as_handled()
			return

func _process(delta: float) -> void:
	# Fade damage vignette
	if damage_flash_alpha > 0.0:
		damage_flash_alpha -= delta * 3.0
		damage_vignette.modulate.a = clamp(damage_flash_alpha, 0.0, 1.0)
	
	# Death respawn timer
	if respawn_countdown > 0.0:
		respawn_countdown -= delta
		death_timer_label.text = "Respawning in %d..." % ceil(respawn_countdown)
		if respawn_countdown <= 0.0:
			_trigger_respawn()

func toggle_connect_dialog(force_state = null) -> void:
	var new_state: bool = not connect_dialog.visible if force_state == null else force_state
	connect_dialog.visible = new_state
	if new_state:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		server_input.grab_focus()
	else:
		if not is_chatting and not death_overlay.visible:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_connect_pressed() -> void:
	var net = _get_network()
	if not net:
		return
	var url: String = server_input.text.strip_edges()
	var p_name: String = name_input.text.strip_edges()
	var skin_key: String = SKINS[skin_option.selected]
	
	if url.is_empty():
		url = "ws://127.0.0.1:8910"
	if p_name.is_empty():
		p_name = "Survivor"
		
	dialog_status.text = "Connecting to %s..." % url
	dialog_status.modulate = Color(1.0, 0.8, 0.2)
	connect_btn.disabled = true
	
	net.connect_to_server(url, p_name, skin_key)

func _on_disconnect_pressed() -> void:
	var net = _get_network()
	if net:
		net.disconnect_from_server()
	_update_connection_status()
	dialog_status.text = "Disconnected from server."
	dialog_status.modulate = Color(0.7, 0.7, 0.7)

func _on_connected(my_id: String, my_info: Dictionary) -> void:
	_update_connection_status()
	dialog_status.text = "Connected! (ID: %s)" % my_id
	dialog_status.modulate = Color(0.2, 0.9, 0.3)
	connect_btn.disabled = false
	# Close dialog after 1.2s
	get_tree().create_timer(1.2).timeout.connect(func():
		if connect_dialog.visible:
			toggle_connect_dialog(false)
	)

func _on_connection_failed() -> void:
	_update_connection_status()
	dialog_status.text = "Failed to connect to server."
	dialog_status.modulate = Color(0.9, 0.2, 0.2)
	connect_btn.disabled = false

func _on_disconnected() -> void:
	_update_connection_status()
	dialog_status.text = "Disconnected from server."
	dialog_status.modulate = Color(0.8, 0.5, 0.2)
	connect_btn.disabled = false

func _on_player_joined(pid: String, info: Dictionary) -> void:
	var pname: String = info.get("name", "Player")
	add_kill_feed_event("%s joined the game" % pname, Color(0.4, 0.8, 1.0))
	_update_connection_status()

func _on_player_left(pid: String) -> void:
	add_kill_feed_event("Player left the game", Color(0.7, 0.7, 0.7))
	_update_connection_status()

func _on_latency_updated(ping: int) -> void:
	_update_connection_status()

func _update_connection_status() -> void:
	var net = _get_network()
	if net and net.is_connected_to_server():
		var p_count: int = net.all_players.size() + 1
		status_label.text = "● Online | %d Players | %dms" % [p_count, net.ping_ms]
		status_label.modulate = Color(0.25, 0.9, 0.35)
		connect_btn.disabled = true
		disconnect_btn.disabled = false
	elif net and net.is_connecting:
		status_label.text = "◌ Connecting..."
		status_label.modulate = Color(1.0, 0.75, 0.2)
		connect_btn.disabled = true
		disconnect_btn.disabled = false
	else:
		status_label.text = "○ Solo (Offline)"
		status_label.modulate = Color(0.65, 0.65, 0.7)
		connect_btn.disabled = false
		disconnect_btn.disabled = true

func update_hp(health: float, max_health: float) -> void:
	if not hp_bar:
		hp_bar = get_node_or_null("Root/BottomLeft/VBox/HPBar")
	if not hp_label:
		hp_label = get_node_or_null("Root/BottomLeft/VBox/HPLabel")
	if not hp_bar or not hp_label:
		return
		
	hp_bar.max_value = max_health
	hp_bar.value = health
	hp_label.text = "%d / %d HP" % [int(health), int(max_health)]
	
	var ratio := health / max_health
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	if ratio > 0.5:
		style.bg_color = Color(0.2, 0.85, 0.3, 0.9)
	elif ratio > 0.25:
		style.bg_color = Color(0.95, 0.75, 0.1, 0.9)
	else:
		style.bg_color = Color(0.95, 0.2, 0.2, 0.9)
	hp_bar.add_theme_stylebox_override("fill", style)

func trigger_damage_flash() -> void:
	damage_flash_alpha = 0.85
	damage_vignette.modulate.a = 0.85

func show_death_screen(killer_name: String) -> void:
	death_overlay.visible = true
	death_killer_label.text = "Eliminated by %s" % killer_name if not killer_name.is_empty() else "Eliminated"
	respawn_countdown = 3.0
	death_timer_label.text = "Respawning in 3..."
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _trigger_respawn() -> void:
	death_overlay.visible = false
	respawn_countdown = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("respawn"):
		player.respawn()

func add_kill_feed_event(text: String, col: Color = Color.WHITE) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = col
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 2)
	kill_feed_container.add_child(lbl)
	
	# Auto remove after 4.5 seconds with fade
	var tw := create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.0)
	tw.tween_callback(lbl.queue_free)

func _on_player_killed(victim_id: String, attacker_id: String, killer_name: String, victim_name: String) -> void:
	var net = _get_network()
	var my_id: String = net.my_id if net else ""
	
	var col := Color.WHITE
	if attacker_id == my_id:
		col = Color(0.3, 1.0, 0.4) # We killed someone!
	elif victim_id == my_id:
		col = Color(1.0, 0.3, 0.3) # We got killed!
		show_death_screen(killer_name)
	
	add_kill_feed_event("%s  💥  %s" % [killer_name, victim_name], col)
	_update_scoreboard()

func _update_scoreboard() -> void:
	for child in scoreboard_list.get_children():
		child.queue_free()
		
	var net = _get_network()
	if not net:
		return
		
	# Header
	var header_hbox := HBoxContainer.new()
	var h_name := Label.new(); h_name.text = "PLAYER"; h_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h_kills := Label.new(); h_kills.text = "KILLS"; h_kills.custom_minimum_size.x = 60; h_kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var h_deaths := Label.new(); h_deaths.text = "DEATHS"; h_deaths.custom_minimum_size.x = 60; h_deaths.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var h_ping := Label.new(); h_ping.text = "PING"; h_ping.custom_minimum_size.x = 60; h_ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_hbox.add_child(h_name); header_hbox.add_child(h_kills); header_hbox.add_child(h_deaths); header_hbox.add_child(h_ping)
	header_hbox.modulate = Color(0.7, 0.8, 1.0)
	scoreboard_list.add_child(header_hbox)
	
	# Local player row
	_add_scoreboard_row(net.my_name + " (You)", net.my_kills, net.my_deaths, net.ping_ms, true)
	
	# Remote players
	for pid in net.all_players:
		var p: Dictionary = net.all_players[pid]
		var p_name: String = p.get("name", pid)
		var p_kills: int = p.get("kills", 0)
		var p_deaths: int = p.get("deaths", 0)
		var p_ping: int = p.get("ping", 0)
		_add_scoreboard_row(p_name, p_kills, p_deaths, p_ping, false)

func _add_scoreboard_row(p_name: String, kills: int, deaths: int, ping: int, is_me: bool) -> void:
	var hbox := HBoxContainer.new()
	var l_name := Label.new(); l_name.text = p_name; l_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l_kills := Label.new(); l_kills.text = str(kills); l_kills.custom_minimum_size.x = 60; l_kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var l_deaths := Label.new(); l_deaths.text = str(deaths); l_deaths.custom_minimum_size.x = 60; l_deaths.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var l_ping := Label.new(); l_ping.text = "%dms" % ping; l_ping.custom_minimum_size.x = 60; l_ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	
	if is_me:
		l_name.modulate = Color(1.0, 0.85, 0.3)
		l_kills.modulate = Color(1.0, 0.85, 0.3)
		l_deaths.modulate = Color(1.0, 0.85, 0.3)
		l_ping.modulate = Color(1.0, 0.85, 0.3)
		
	hbox.add_child(l_name); hbox.add_child(l_kills); hbox.add_child(l_deaths); hbox.add_child(l_ping)
	scoreboard_list.add_child(hbox)

func _start_chatting() -> void:
	is_chatting = true
	chat_input.visible = true
	chat_input.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	chat_input.grab_focus()

func _stop_chatting() -> void:
	is_chatting = false
	chat_input.visible = false
	if not connect_dialog.visible and not death_overlay.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_chat_submitted(text: String) -> void:
	var clean := text.strip_edges()
	if not clean.is_empty():
		var net = _get_network()
		if net:
			net.send_chat(clean)
	_stop_chatting()

func _on_chat_received(sender_id: String, sender: String, text: String, time_stamp: int) -> void:
	var hbox := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = "[%s]: " % sender
	var net = _get_network()
	if net and sender_id == net.my_id:
		name_lbl.modulate = Color(1.0, 0.85, 0.3)
	else:
		name_lbl.modulate = Color(0.4, 0.85, 1.0)
	name_lbl.add_theme_font_size_override("font_size", 14)
	
	var text_lbl := Label.new()
	text_lbl.text = text
	text_lbl.add_theme_font_size_override("font_size", 14)
	
	hbox.add_child(name_lbl)
	hbox.add_child(text_lbl)
	chat_log.add_child(hbox)
	
	# Limit chat log to last 10 messages
	while chat_log.get_child_count() > 10:
		var old = chat_log.get_child(0)
		chat_log.remove_child(old)
		old.queue_free()
		
	# Fade after 8s
	var tw := create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(hbox, "modulate:a", 0.0, 1.5)
	tw.tween_callback(hbox.queue_free)
