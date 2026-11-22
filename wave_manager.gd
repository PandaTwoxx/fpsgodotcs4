extends Node3D
## Runs the wave loop: spawn a batch of zombies, wait until they are all dead,
## short breather, next (bigger, tougher) wave. Spawns on the navmesh, away from the player.

signal zombie_spawned(zombie: Node3D)

const ZOMBIE_SCENE := preload("res://zombie.tscn")
const WAVE_CLEAR_BONUS := 250

@export var navigation: NavigationRegion3D
@export var first_wave_delay: float = 3.0
@export var intermission: float = 6.0
@export var min_distance: float = 9.0
@export var max_distance: float = 18.0
@export var map_half_extent: float = 22.0

enum Phase { WAITING, INTERMISSION, ACTIVE }

var _phase := Phase.WAITING
var _timer := 0.0
var _spawn_timer := 0.0
var _to_spawn := 0
var _alive := 0
var _max_alive := 0
var _spawn_interval := 2.0
var _health_scale := 1.0
var _speed := 2.0

func _ready() -> void:
	Game.reset()
	if navigation and not navigation.is_baked:
		await navigation.baked
	_start_intermission(first_wave_delay, "GET READY")

func _process(delta: float) -> void:
	match _phase:
		Phase.INTERMISSION:
			_timer -= delta
			if _timer <= 0.0:
				_begin_wave()
		Phase.ACTIVE:
			_spawn_timer -= delta
			if _to_spawn > 0 and _alive < _max_alive and _spawn_timer <= 0.0:
				if spawn_zombie():
					_to_spawn -= 1
					_spawn_timer = _spawn_interval
				else:
					_spawn_timer = 0.5  # no valid spot this time; retry shortly
			if _to_spawn == 0 and _alive == 0:
				_end_wave()

func _start_intermission(seconds: float, title: String) -> void:
	_phase = Phase.INTERMISSION
	_timer = seconds
	if title != "":
		Game.show_banner(title, "Wave %d starts in %d..." % [Game.wave + 1, ceili(seconds)])

func _begin_wave() -> void:
	var n := Game.wave + 1
	var total := 4 + 3 * (n - 1)
	_max_alive = mini(4 + n, 12)
	_spawn_interval = maxf(2.5 - 0.2 * (n - 1), 0.8)
	_health_scale = 1.0 + 0.1 * (n - 1)
	_speed = minf(2.0 + 0.1 * (n - 1), 3.0)
	_to_spawn = total
	_spawn_timer = 0.5
	_phase = Phase.ACTIVE
	Game.set_wave(n, total)
	Game.show_banner("WAVE %d" % n, "%d zombies incoming" % total)

func _end_wave() -> void:
	Game.add_bonus(WAVE_CLEAR_BONUS)
	_start_intermission(intermission, "")
	Game.show_banner("WAVE %d CLEARED" % Game.wave, "+%d bonus - next wave in %d..." % [WAVE_CLEAR_BONUS, ceili(intermission)])

func _on_zombie_died(_zombie: Node3D) -> void:
	_alive = maxi(_alive - 1, 0)
	Game.add_kill()
	Game.set_zombies_left(_to_spawn + _alive)

## Spawns one zombie scaled to the current wave; returns it, or null if no valid spot was found.
func spawn_zombie() -> Node3D:
	var pos := _pick_spawn_point()
	if pos == Vector3.INF:
		return null
	var zombie := ZOMBIE_SCENE.instantiate() as Node3D
	zombie.max_health *= _health_scale
	zombie.speed = _speed
	zombie.died.connect(_on_zombie_died)
	get_parent().add_child(zombie)
	zombie.global_position = pos + Vector3(0, 0.45, 0)
	_alive += 1
	zombie_spawned.emit(zombie)
	return zombie

func _pick_spawn_point() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return Vector3.INF
	var nav_map := navigation.get_navigation_map() if navigation else RID()
	for attempt in 12:
		var angle := randf() * TAU
		var dist := randf_range(min_distance, max_distance)
		var candidate := player.global_position + Vector3(cos(angle), 0, sin(angle)) * dist
		candidate.x = clampf(candidate.x, -map_half_extent, map_half_extent)
		candidate.z = clampf(candidate.z, -map_half_extent, map_half_extent)
		if nav_map.is_valid() and navigation.navigation_mesh:
			# Snap to the navmesh at floor height; reject spots it can't place
			# nearby (inside buildings, or only reachable via a roof).
			candidate.y = navigation.floor_y
			var snapped := NavigationServer3D.map_get_closest_point(nav_map, candidate)
			if snapped.distance_to(candidate) > 0.6:
				continue
			candidate = snapped
		if candidate.distance_to(player.global_position) >= min_distance * 0.7:
			return candidate
	return Vector3.INF
