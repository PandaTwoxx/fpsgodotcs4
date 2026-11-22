extends Node3D
## Keeps zombies coming: spawns on the navmesh, away from the player.

signal zombie_spawned(zombie: Node3D)

const ZOMBIE_SCENE := preload("res://zombie.tscn")

@export var navigation: NavigationRegion3D
@export var spawn_interval: float = 4.0
@export var max_alive: int = 6
@export var min_distance: float = 9.0
@export var max_distance: float = 18.0
@export var map_half_extent: float = 22.0

var _timer := 0.0
var _ready_to_spawn := false

func _ready() -> void:
	if navigation and not navigation.is_baked:
		await navigation.baked
	_ready_to_spawn = true

func _process(delta: float) -> void:
	if not _ready_to_spawn:
		return
	_timer -= delta
	if _timer <= 0.0 and get_tree().get_nodes_in_group("zombie").size() < max_alive:
		_timer = spawn_interval
		spawn_zombie()

## Spawns one zombie; returns it, or null if no valid spot was found.
func spawn_zombie() -> Node3D:
	var pos := _pick_spawn_point()
	if pos == Vector3.INF:
		return null
	var zombie := ZOMBIE_SCENE.instantiate() as Node3D
	get_parent().add_child(zombie)
	zombie.global_position = pos + Vector3(0, 0.45, 0)
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
