# Mare: mesh radiale che segue la camera (più fitta vicino, più rada lontano)
class_name Water
extends MeshInstance3D

const NP := 24

var pulses := PackedVector4Array()
var pulse_idx := 0
var time := 0.0
var mat: ShaderMaterial


func setup(terrain_data: Texture2D) -> void:
	for i in NP:
		pulses.append(Vector4(0, 0, -100, 0))
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("terrain_data", terrain_data)
	mat.set_shader_parameter("u_pulses", pulses)
	mesh = _radial_mesh(140, 200)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-60000, -50, -60000), Vector3(120000, 100, 120000))


func _radial_mesh(rings: int, segs: int) -> ArrayMesh:
	var pos := PackedVector3Array([Vector3.ZERO])
	for n in range(1, rings + 1):
		var r := 2.0 * (pow(1.045, n) - 1.0) / 0.045
		for s in segs:
			var a := float(s) / segs * TAU
			pos.append(Vector3(cos(a) * r, 0, sin(a) * r))
	var idx := PackedInt32Array()
	# facce in senso orario viste dall'alto (convenzione di Godot)
	for s in segs:
		idx.append_array([0, 1 + s, 1 + (s + 1) % segs])
	for n in rings - 1:
		var a0 := 1 + n * segs
		var b0 := 1 + (n + 1) * segs
		for s in segs:
			var s1 := (s + 1) % segs
			idx.append_array([a0 + s, b0 + s, a0 + s1, a0 + s1, b0 + s, b0 + s1])
	var nrm := PackedVector3Array()
	nrm.resize(pos.size())
	nrm.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func add_pulse(x: float, z: float, amp: float) -> void:
	pulses[pulse_idx] = Vector4(x, z, time, amp)
	pulse_idx = (pulse_idx + 1) % NP
	mat.set_shader_parameter("u_pulses", pulses)


# Altezza approssimata della superficie (onde lunghe) per spruzzi e camera
func height_at(x: float, z: float) -> float:
	return _w(x, z, 1, 0.3, 170, 1.5, 11) + _w(x, z, 0.6, 1, 104, 0.95, 9) + _w(x, z, -0.4, 0.9, 63, 0.55, 7)


func _w(x: float, z: float, dx: float, dy: float, length: float, amp: float, spd: float) -> float:
	var l := Vector2(dx, dy).length()
	var k := TAU / length
	return amp * sin((dx / l * x + dy / l * z) * k + time * spd * k)


func update_water(dt: float, cam_pos: Vector3, down_x: float, down_z: float, strength: float) -> void:
	time += dt
	mat.set_shader_parameter("u_time", time)
	mat.set_shader_parameter("u_down", Vector4(down_x, down_z, strength, 0))
	position = Vector3(cam_pos.x, 0, cam_pos.z)
