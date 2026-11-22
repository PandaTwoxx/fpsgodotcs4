extends NavigationRegion3D
## Bakes a navigation mesh at startup. Blocking geometry comes from the map's
## static colliders (what physically stops a zombie); the walkable floor comes
## from the CSGBox3D floor, whose top face is added explicitly.

signal baked

var is_baked := false
## World-space height of the floor surface (set when a CSG floor is found).
var floor_y := 0.0

func _ready() -> void:
	# CSG shapes and collision bodies finish setting up a frame after _ready.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var navmesh := NavigationMesh.new()
	navmesh.cell_size = 0.125
	navmesh.cell_height = 0.125
	navmesh.agent_radius = 0.25
	navmesh.agent_height = 1.0
	navmesh.agent_max_climb = 0.25
	navmesh.agent_max_slope = 50.0
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS

	# Parse first: parsing replaces the data, so the floor must be added afterwards.
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, get_parent())
	for node in get_parent().get_children():
		if node is CSGBox3D:
			_add_floor(source, node)
	if not source.has_data():
		push_warning("NavmeshBaker: no source geometry found; zombies will chase in a straight line.")
		_finish(null)
		return
	NavigationServer3D.bake_from_source_geometry_data_async(navmesh, source, _finish.bind(navmesh))

## Adds the top face of a CSG box as two upward-facing triangles.
func _add_floor(source: NavigationMeshSourceGeometryData3D, box: CSGBox3D) -> void:
	var h := box.size * 0.5
	var xf := box.global_transform
	var a := xf * Vector3(-h.x, h.y, -h.z)
	var b := xf * Vector3(h.x, h.y, -h.z)
	var c := xf * Vector3(h.x, h.y, h.z)
	var d := xf * Vector3(-h.x, h.y, h.z)
	source.add_faces(PackedVector3Array([a, b, c, a, c, d]), Transform3D.IDENTITY)
	floor_y = a.y

func _finish(navmesh: NavigationMesh) -> void:
	if navmesh:
		# The navigation map must use the same cell sizes the mesh was baked with.
		var map := get_navigation_map()
		NavigationServer3D.map_set_cell_size(map, navmesh.cell_size)
		NavigationServer3D.map_set_cell_height(map, navmesh.cell_height)
		navigation_mesh = navmesh
	is_baked = true
	baked.emit()
