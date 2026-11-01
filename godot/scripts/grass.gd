class_name Grass
extends Node3D
# Prato intorno alla camera: due anelli di ciuffi d'erba (fitto vicino, rado più in là) disegnati con
# MultiMesh. Le istanze sono un reticolo fisso: il nodo segue la camera a passi interi del reticolo e lo
# shader (grass.gdshader) appoggia ogni ciuffo sul terreno, lo dirada dove non c'è prato e lo muove col vento.

const RINGS := [
	{"spacing": 0.4, "radius": 28.0, "inner": 0.0, "clump": 1.0},
	{"spacing": 0.9, "radius": 62.0, "inner": 24.0, "clump": 1.6},
]
const MAX_ALT := 140.0 # sopra questa quota dal suolo l'erba non si vede più

var layers: Array = []


func setup(world: World) -> void:
	var mesh := _clump_mesh()
	var shader: Shader = load("res://shaders/grass.gdshader")
	var vs = world.terrain_material.get_shader_parameter("villages")
	for r in RINGS:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("terrain_data", world.data_tex)
		mat.set_shader_parameter("villages", vs)
		for k in ["spacing", "radius", "inner", "clump"]:
			mat.set_shader_parameter(k, r[k])
		var n := int(ceil(r.radius * 2 / r.spacing))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = n * n
		var buf := PackedFloat32Array()
		buf.resize(n * n * 12)
		var k := 0
		for j in n:
			for i in n:
				buf[k] = 1.0
				buf[k + 3] = (i - n / 2) * r.spacing
				buf[k + 5] = 1.0
				buf[k + 10] = 1.0
				buf[k + 11] = (j - n / 2) * r.spacing
				k += 12
		mm.buffer = buf
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-r.radius - 2, -120, -r.radius - 2), Vector3(r.radius * 2 + 4, 800, r.radius * 2 + 4))
		add_child(mi)
		layers.append({"mi": mi, "mat": mat, "spacing": r.spacing})


func update_grass(cam_pos: Vector3, ground: float, t: float) -> void:
	visible = cam_pos.y - ground < MAX_ALT
	if not visible:
		return
	for l in layers:
		var sp: float = l.spacing
		l.mi.position = Vector3(roundf(cam_pos.x / sp) * sp, 0, roundf(cam_pos.z / sp) * sp)
		l.mat.set_shader_parameter("u_time", t)
		l.mat.set_shader_parameter("focus", cam_pos)


# Ciuffo di 9 fili affusolati e ricurvi (alto 1, scalato dallo shader): UV.y è l'altezza lungo il filo,
# COLOR.r e .g variano tinta e secchezza da filo a filo
static func _clump_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for b in 9:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.18
		var root := Vector3(cos(ang) * r, 0, sin(ang) * r)
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0, sin(face))
		var lean_dir := Vector3(-sin(face), 0, cos(face)) * (1.0 if rng.randf() < 0.5 else -1.0)
		var lean := 0.12 + rng.randf() * 0.3
		var hgt := 0.65 + rng.randf() * 0.35
		var wid := 0.018 + rng.randf() * 0.014
		var col := Color(rng.randf(), rng.randf(), 0)
		var segs := 3
		for k in segs + 1:
			var t := float(k) / segs
			var c := root + lean_dir * lean * t * t + Vector3(0, hgt * t, 0)
			var nrm := lean_dir.lerp(Vector3.UP, 0.3).normalized()
			if k < segs:
				var w := wid * (1.0 - t * 0.75)
				for s in [-1.0, 1.0]:
					st.set_color(col)
					st.set_normal(nrm)
					st.set_uv(Vector2(s * 0.5 + 0.5, t))
					st.add_vertex(c + side * w * s)
			else:
				st.set_color(col)
				st.set_normal(nrm)
				st.set_uv(Vector2(0.5, 1.0))
				st.add_vertex(c)
		for k in segs - 1:
			var i := base + k * 2
			for idx in [i, i + 2, i + 1, i + 1, i + 2, i + 3]:
				st.add_index(idx)
		var last := base + (segs - 1) * 2
		for idx in [last, last + 2, last + 1]:
			st.add_index(idx)
		base += segs * 2 + 1
	return st.commit()
