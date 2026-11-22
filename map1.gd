extends Node3D

const REMOTE_PLAYER_SCENE = preload("res://remote_player.tscn")

@onready var remote_players_container: Node3D = $RemotePlayers

var remote_players: Dictionary = {} # id -> RemotePlayer node

func _ready() -> void:
	_connect_network()

func _get_network() -> Node:
	return get_node_or_null("/root/Network")

func _connect_network() -> void:
	var net = _get_network()
	if not net:
		return
	net.connected_to_server.connect(_on_connected)
	net.server_disconnected.connect(_on_disconnected)
	net.player_joined.connect(_on_player_joined)
	net.player_left.connect(_on_player_left)
	net.player_profile_updated.connect(_on_player_profile_updated)
	net.world_state_updated.connect(_on_world_state_updated)
	net.player_shot.connect(_on_player_shot)
	net.player_damaged.connect(_on_player_damaged)
	net.player_killed.connect(_on_player_killed)
	net.player_respawned.connect(_on_player_respawned)
	net.target_hit_synced.connect(_on_target_hit_synced)
	net.crate_damage_synced.connect(_on_crate_damage_synced)

func _on_connected(my_id: String, my_info: Dictionary) -> void:
	# Spawn all existing players that the server sent in init
	_clear_all_remote_players()
	var players_data: Dictionary = my_info.get("players", {})
	for pid in players_data:
		_spawn_remote_player(pid, players_data[pid])

func _on_disconnected() -> void:
	_clear_all_remote_players()

func _on_player_joined(pid: String, info: Dictionary) -> void:
	_spawn_remote_player(pid, info)

func _spawn_remote_player(pid: String, info: Dictionary) -> void:
	if remote_players.has(pid):
		return
	var net = _get_network()
	if net and pid == net.my_id:
		return
		
	var rp := REMOTE_PLAYER_SCENE.instantiate()
	var p_name: String = info.get("name", "Survivor")
	var p_skin: String = info.get("skin", "survivorMaleB")
	var pos_arr: Array = info.get("pos", [0, 2, 0])
	var spawn_pos := Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
	
	remote_players_container.add_child(rp)
	rp.setup(pid, p_name, p_skin, spawn_pos)
	remote_players[pid] = rp

func _on_player_left(pid: String) -> void:
	if remote_players.has(pid):
		var rp = remote_players[pid]
		remote_players.erase(pid)
		if is_instance_valid(rp):
			rp.queue_free()

func _on_player_profile_updated(pid: String, p_name: String, p_skin: String) -> void:
	if remote_players.has(pid):
		var rp = remote_players[pid]
		if is_instance_valid(rp):
			rp.player_name = p_name
			rp.set_skin(p_skin)
			rp._update_hud()

func _on_world_state_updated(players_dict: Dictionary) -> void:
	for pid in players_dict:
		if not remote_players.has(pid):
			var net = _get_network()
			if net and pid != net.my_id:
				_spawn_remote_player(pid, players_dict[pid])
		if remote_players.has(pid):
			var rp = remote_players[pid]
			if is_instance_valid(rp):
				var data: Dictionary = players_dict[pid]
				var pos_arr: Array = data.get("pos", [0, 0, 0])
				var vel_arr: Array = data.get("vel", [0, 0, 0])
				var pos := Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
				var vel := Vector3(vel_arr[0], vel_arr[1], vel_arr[2])
				var yaw: float = float(data.get("yaw", 0.0))
				var pitch: float = float(data.get("pitch", 0.0))
				var anim: String = data.get("anim", "idle")
				var hp: float = float(data.get("hp", 100.0))
				rp.update_net_state(pos, vel, yaw, pitch, anim, hp)

func _on_player_shot(shooter_id: String, origin: Vector3, hit: Vector3, normal: Vector3, is_target: bool) -> void:
	if remote_players.has(shooter_id):
		var rp = remote_players[shooter_id]
		if is_instance_valid(rp):
			rp.play_shoot(origin, hit, normal, is_target)

func _on_player_damaged(victim_id: String, attacker_id: String, damage: float, new_hp: float) -> void:
	if remote_players.has(victim_id):
		var rp = remote_players[victim_id]
		if is_instance_valid(rp):
			rp.apply_damage(damage, new_hp)

func _on_player_killed(victim_id: String, attacker_id: String, killer_name: String, victim_name: String) -> void:
	if remote_players.has(victim_id):
		var rp = remote_players[victim_id]
		if is_instance_valid(rp):
			rp.set_dead(true)

func _on_player_respawned(pid: String, pos: Vector3, hp: float) -> void:
	if remote_players.has(pid):
		var rp = remote_players[pid]
		if is_instance_valid(rp):
			rp.respawn_at(pos, hp)

func _on_target_hit_synced(target_name: String, damage: float) -> void:
	var target = find_child(target_name, true, false)
	if target and target.has_method("take_damage"):
		target.take_damage(damage)

func _on_crate_damage_synced(crate_name: String, damage: float) -> void:
	var crate = find_child(crate_name, true, false)
	if crate and crate.has_method("take_damage"):
		crate.take_damage(damage)

func _clear_all_remote_players() -> void:
	for pid in remote_players:
		var rp = remote_players[pid]
		if is_instance_valid(rp):
			rp.queue_free()
	remote_players.clear()
