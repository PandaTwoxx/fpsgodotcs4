extends Node3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var lifetime: float = 0.08
var current_time: float = 0.0
var material: StandardMaterial3D

func setup(start: Vector3, end: Vector3) -> void:
	var diff := end - start
	var length := diff.length()
	if length < 0.01:
		queue_free()
		return
	
	global_position = start + diff * 0.5
	if diff.normalized().cross(Vector3.UP).length_squared() > 0.001:
		look_at(end, Vector3.UP)
	else:
		look_at(end, Vector3.RIGHT)
	
	# Rotate 90 degrees around X because CylinderMesh default orientation is along Y
	rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.015
	cylinder.bottom_radius = 0.015
	cylinder.height = length
	
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.7, 0.15, 0.95)
	cylinder.material = material
	
	mesh_instance.mesh = cylinder

func _process(delta: float) -> void:
	current_time += delta
	var progress := current_time / lifetime
	if progress >= 1.0:
		queue_free()
	elif material:
		material.albedo_color.a = (1.0 - progress) * 0.95
		scale = Vector3(1.0 - progress * 0.5, 1.0, 1.0 - progress * 0.5)
