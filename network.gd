extends Node

signal connected_to_server(my_id: String, my_info: Dictionary)
signal connection_failed()
signal server_disconnected()
signal player_joined(id: String, player_info: Dictionary)
signal player_left(id: String)
signal player_profile_updated(id: String, player_name: String, skin: String)
signal world_state_updated(players_dict: Dictionary)
signal player_shot(shooter_id: String, origin: Vector3, hit: Vector3, normal: Vector3, is_target: bool)
signal player_damaged(victim_id: String, attacker_id: String, damage: float, new_hp: float)
signal player_killed(victim_id: String, attacker_id: String, killer_name: String, victim_name: String)
signal player_respawned(id: String, pos: Vector3, hp: float)
signal target_hit_synced(target_name: String, damage: float)
signal crate_damage_synced(crate_name: String, damage: float)
signal chat_received(id: String, sender: String, text: String, time_stamp: int)
signal latency_updated(ping_ms: int)

var ws: WebSocketPeer = null
var my_id: String = ""
var my_name: String = "Survivor"
var my_skin: String = "survivorMaleB"
var my_kills: int = 0
var my_deaths: int = 0
var ping_ms: int = 0

var current_server_url: String = "ws://127.0.0.1:8910"
var is_connecting: bool = false
var was_open: bool = false

var _ping_timer: float = 0.0
var _last_ping_send_time: int = 0
var _state_send_timer: float = 0.0
const STATE_SEND_INTERVAL: float = 1.0 / 30.0 # 30Hz

var all_players: Dictionary = {} # id -> Dictionary of player data

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_connected_to_server() -> bool:
	return ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func connect_to_server(url: String, player_name: String = "", skin_name: String = "") -> void:
	if is_connected_to_server():
		disconnect_from_server()
	
	if not player_name.is_empty():
		my_name = player_name
	if not skin_name.is_empty():
		my_skin = skin_name
		
	current_server_url = url
	ws = WebSocketPeer.new()
	is_connecting = true
	was_open = false
	all_players.clear()
	
	var err := ws.connect_to_url(current_server_url)
	if err != OK:
		push_error("Failed to connect to %s with error %d" % [current_server_url, err])
		is_connecting = false
		connection_failed.emit()

func disconnect_from_server() -> void:
	if ws:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.close()
		ws = null
	is_connecting = false
	if was_open:
		was_open = false
		server_disconnected.emit()
	all_players.clear()

func _process(delta: float) -> void:
	if not ws:
		return
		
	ws.poll()
	var state := ws.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not was_open:
			was_open = true
			is_connecting = false
			# Send join handshake
			_send_raw({
				"type": "join",
				"name": my_name,
				"skin": my_skin
			})
		
		# Read all incoming packets
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			var text := pkt.get_string_from_utf8()
			var msg = JSON.parse_string(text)
			if msg is Dictionary:
				_handle_message(msg)
		
		# Heartbeat ping
		_ping_timer += delta
		if _ping_timer >= 1.0:
			_ping_timer = 0.0
			_last_ping_send_time = Time.get_ticks_msec()
			_send_raw({
				"type": "ping",
				"t": _last_ping_send_time,
				"ping": ping_ms
			})
			
	elif state == WebSocketPeer.STATE_CLOSED:
		var code := ws.get_close_code()
		var reason := ws.get_close_reason()
		ws = null
		
		if was_open:
			was_open = false
			server_disconnected.emit()
		elif is_connecting:
			is_connecting = false
			connection_failed.emit()

func _send_raw(data: Dictionary) -> void:
	if is_connected_to_server():
		var json_str := JSON.stringify(data)
		ws.send_text(json_str)

func send_state(pos: Vector3, vel: Vector3, yaw: float, pitch: float, anim: String, on_floor: bool) -> void:
	if not is_connected_to_server():
		return
	
	_state_send_timer += get_process_delta_time()
	if _state_send_timer < STATE_SEND_INTERVAL:
		return
	_state_send_timer = 0.0
	
	_send_raw({
		"type": "state",
		"pos": [pos.x, pos.y, pos.z],
		"vel": [vel.x, vel.y, vel.z],
		"yaw": yaw,
		"pitch": pitch,
		"anim": anim,
		"on_floor": on_floor
	})

func send_shoot(origin: Vector3, hit: Vector3, normal: Vector3, is_target: bool) -> void:
	if not is_connected_to_server():
		return
	_send_raw({
		"type": "shoot",
		"origin": [origin.x, origin.y, origin.z],
		"hit": [hit.x, hit.y, hit.z],
		"normal": [normal.x, normal.y, normal.z],
		"is_target": is_target
	})

func send_hit(target_id: String, damage: float) -> void:
	if not is_connected_to_server():
		return
	_send_raw({
		"type": "hit",
		"target_id": target_id,
		"damage": damage
	})

func send_respawn() -> void:
	if not is_connected_to_server():
		return
	_send_raw({
		"type": "respawn"
	})

func send_target_hit(target_name: String, damage: float) -> void:
	if not is_connected_to_server():
		return
	_send_raw({
		"type": "target_hit",
		"target_name": target_name,
		"damage": damage
	})

func send_crate_damage(crate_name: String, damage: float) -> void:
	if not is_connected_to_server():
		return
	_send_raw({
		"type": "crate_damage",
		"crate_name": crate_name,
		"damage": damage
	})

func send_chat(text: String) -> void:
	if not is_connected_to_server():
		return
	_send_raw({
		"type": "chat",
		"text": text
	})

func _handle_message(msg: Dictionary) -> void:
	var msg_type: String = msg.get("type", "")
	
	match msg_type:
		"init":
			my_id = msg.get("id", "")
			if msg.has("name"):
				my_name = msg.get("name", my_name)
			if msg.has("skin"):
				my_skin = msg.get("skin", my_skin)
			
			var existing_players: Dictionary = msg.get("players", {})
			for pid in existing_players:
				all_players[pid] = existing_players[pid]
			
			connected_to_server.emit(my_id, msg)
		
		"player_join":
			var player_info: Dictionary = msg.get("player", {})
			var pid: String = player_info.get("id", "")
			if not pid.is_empty() and pid != my_id:
				all_players[pid] = player_info
				player_joined.emit(pid, player_info)
		
		"player_leave":
			var pid: String = msg.get("id", "")
			if all_players.has(pid):
				all_players.erase(pid)
			player_left.emit(pid)
		
		"player_profile":
			var pid: String = msg.get("id", "")
			var p_name: String = msg.get("name", "")
			var p_skin: String = msg.get("skin", "")
			if all_players.has(pid):
				all_players[pid]["name"] = p_name
				all_players[pid]["skin"] = p_skin
			player_profile_updated.emit(pid, p_name, p_skin)
		
		"world_state":
			var players_dict: Dictionary = msg.get("players", {})
			for pid in players_dict:
				if pid != my_id:
					if not all_players.has(pid):
						all_players[pid] = players_dict[pid]
					else:
						# Merge snapshot
						for k in players_dict[pid]:
							all_players[pid][k] = players_dict[pid][k]
				else:
					# Update our own stats from server authority (hp, kills, deaths)
					var my_data: Dictionary = players_dict[pid]
					if my_data.has("kills"):
						my_kills = my_data["kills"]
					if my_data.has("deaths"):
						my_deaths = my_data["deaths"]
			world_state_updated.emit(players_dict)
		
		"player_shoot":
			var shooter_id: String = msg.get("shooter_id", "")
			if shooter_id != my_id:
				var orig_arr: Array = msg.get("origin", [0, 0, 0])
				var hit_arr: Array = msg.get("hit", [0, 0, 0])
				var norm_arr: Array = msg.get("normal", [0, 1, 0])
				var origin := Vector3(orig_arr[0], orig_arr[1], orig_arr[2])
				var hit := Vector3(hit_arr[0], hit_arr[1], hit_arr[2])
				var normal := Vector3(norm_arr[0], norm_arr[1], norm_arr[2])
				var is_target: bool = msg.get("is_target", false)
				player_shot.emit(shooter_id, origin, hit, normal, is_target)
		
		"player_damaged":
			var victim_id: String = msg.get("victim_id", "")
			var attacker_id: String = msg.get("attacker_id", "")
			var damage: float = float(msg.get("damage", 0.0))
			var new_hp: float = float(msg.get("hp", 0.0))
			if all_players.has(victim_id):
				all_players[victim_id]["hp"] = new_hp
			player_damaged.emit(victim_id, attacker_id, damage, new_hp)
		
		"player_killed":
			var victim_id: String = msg.get("victim_id", "")
			var attacker_id: String = msg.get("attacker_id", "")
			var killer_name: String = msg.get("killer_name", "")
			var victim_name: String = msg.get("victim_name", "")
			if all_players.has(victim_id):
				all_players[victim_id]["hp"] = 0
			if attacker_id == my_id:
				my_kills = msg.get("killer_kills", my_kills + 1)
			if victim_id == my_id:
				my_deaths = msg.get("victim_deaths", my_deaths + 1)
			player_killed.emit(victim_id, attacker_id, killer_name, victim_name)
		
		"player_respawn":
			var pid: String = msg.get("id", "")
			var pos_arr: Array = msg.get("pos", [0, 2, 0])
			var pos := Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
			var hp: float = float(msg.get("hp", 100.0))
			if all_players.has(pid):
				all_players[pid]["hp"] = hp
				all_players[pid]["pos"] = pos_arr
			player_respawned.emit(pid, pos, hp)
		
		"target_hit":
			var target_name: String = msg.get("target_name", "")
			var damage: float = float(msg.get("damage", 25.0))
			target_hit_synced.emit(target_name, damage)
		
		"crate_damage":
			var crate_name: String = msg.get("crate_name", "")
			var damage: float = float(msg.get("damage", 25.0))
			crate_damage_synced.emit(crate_name, damage)
		
		"chat":
			var sender_id: String = msg.get("id", "")
			var sender: String = msg.get("sender", "Player")
			var text: String = msg.get("text", "")
			var t: int = msg.get("time", 0)
			chat_received.emit(sender_id, sender, text, t)
		
		"pong":
			var send_t: int = msg.get("t", 0)
			if send_t > 0:
				var now := Time.get_ticks_msec()
				ping_ms = maxi(0, now - send_t)
				latency_updated.emit(ping_ms)
