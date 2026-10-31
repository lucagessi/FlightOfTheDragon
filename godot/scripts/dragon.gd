# Il drago: modello procedurale animato (corpo flessibile, ali con membrana, testa con mascella)
# e fisica di volo arcade con manovre speciali (porting di src/dragon.js)
class_name Dragon
extends Node3D

const RINGS := 64
const RAD := 16
const RADIUS_KEYS := [[0.0, 0.08], [0.1, 0.32], [0.3, 0.95], [0.45, 1.75], [0.58, 2.3], [0.68, 2.2], [0.76, 1.5], [0.85, 1.05], [0.97, 0.95], [1.0, 0.7]]
const STAND := 3.7 # altezza del corpo sopra il suolo quando è sulle zampe
const N_SPIKES := 30
const DYING_CTRL := {"steer": 0.0, "climb": -1.0, "throttle": -1.0, "fire": false}
const MEMBRANE_IDX := [2, 3, 9, 2, 9, 4, 2, 4, 10, 2, 10, 5, 2, 5, 11, 2, 11, 6, 2, 6, 1, 1, 6, 12, 1, 12, 7, 1, 7, 8, 1, 8, 0]

# Colori del drago del giocatore (back/ridge/belly/eye lineari, gli altri esadecimali sRGB)
const RED_PALETTE := {
	"back": Color(0.42, 0.05, 0.035), "ridge": Color(0.2, 0.02, 0.02), "belly": Color(0.85, 0.6, 0.28),
	"skin": 0x5a0a07, "dark": 0x3a0806, "membrane": 0x6a120c, "membrane_glow": 0x240402, "eye": Color(1, 0.75, 0.15),
}

var palette: Dictionary
var model := Node3D.new()
var velocity := Vector3.ZERO
var forward := Vector3(0, 0, 1)
var up := Vector3.UP

var yaw := 0.0
var pitch := 0.0
var roll := 0.0
var speed := 55.0
var throttle := 0.3
var steer := 0.0
var climb := 0.0
var flap_phase := 0.0
var flap_freq := 1.0
var flap_amp := 0.8
var fold := 0.0
var power := 0.5
var jaw := 0.0
var neck_down := 0.0
var time := 0.0
var maneuver = null
var extra_pitch := 0.0
var extra_roll := 0.0
var breathing := false
var roaring := 0.0
var altitude := 60.0
var ground_y := 0.0
var tail_turn := 0.0
var tail_lift := 0.0
var neck_turn := 0.0
var out_of_bounds := false
var dying := false
var death_spin := 0.0
var aim_target = null
var aim_weight := 0.0
var aim_ok := false
# a terra: "air" | "landing" | "ground" | "takeoff"
var mode := "air"
var mode_t := 0.0
var land_from_y := 0.0
var ground_blend := 0.0
var walk_amount := 0.0
var gait_phase := 0.0
var neck_lift := 0.0
var head_yaw := 0.0
var head_pitch := 0.0
var aim_dir := Vector3(0, 0, 1)
var aim_point := Vector3.ZERO
var idle_t := 0.0
var idle_base = null

var mats := {}
var body_mat: ShaderMaterial
var spikes: MultiMesh
var head := Node3D.new()
var jaw_pivot := Node3D.new()
var mouth := Node3D.new()
var wings: Array = []
var legs: Array = []
var centers := PackedVector3Array()
var tangents := PackedVector3Array()
var sides := PackedVector3Array()
var ups_arr := PackedVector3Array()
var radii := PackedFloat32Array()
var inv := Transform3D.IDENTITY


static func radius_at(t: float) -> float:
	for i in range(1, RADIUS_KEYS.size()):
		var t1: float = RADIUS_KEYS[i][0]
		if t <= t1:
			var t0: float = RADIUS_KEYS[i - 1][0]
			var k := (t - t0) / (t1 - t0)
			return lerpf(RADIUS_KEYS[i - 1][1], RADIUS_KEYS[i][1], k * k * (3 - 2 * k))
	return 0.7


func _init(scale_factor := 0.62, pal: Dictionary = RED_PALETTE) -> void:
	palette = pal
	model.scale = Vector3.ONE * scale_factor
	add_child(model)
	centers.resize(RINGS)
	tangents.resize(RINGS)
	sides.resize(RINGS)
	ups_arr.resize(RINGS)
	radii.resize(RINGS)
	for i in RINGS:
		radii[i] = radius_at(float(i) / (RINGS - 1))
	_build_materials()
	_build_body()
	_build_head()
	wings = [_build_wing(1), _build_wing(-1)]
	_build_legs()


func _ready() -> void:
	_update_body()
	_update_membranes()


# ---------------- COSTRUZIONE ----------------
static func _hex(c: int) -> Color:
	return Color.hex((c << 8) | 0xFF)


func _skin(color: Color, use_map: bool, bump: float, rough: float, uv_scale := 2.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/dragon_skin.gdshader")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("use_map", use_map)
	m.set_shader_parameter("bump", bump)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("uv_scale", uv_scale)
	return m


func _build_materials() -> void:
	mats.skin = _skin(_hex(palette.skin), true, 0.35, 0.4)
	mats.dark = _skin(_hex(palette.dark), false, 0.25, 0.45, 4.0)
	var mem := ShaderMaterial.new()
	mem.shader = load("res://shaders/membrane.gdshader")
	mem.set_shader_parameter("color", _hex(palette.membrane))
	mem.set_shader_parameter("glow", _hex(palette.membrane_glow))
	mats.membrane = mem
	var horn := StandardMaterial3D.new()
	horn.albedo_color = Color.hex(0xd8c8a8ff)
	horn.roughness = 0.35
	mats.horn = horn
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color.BLACK
	eye.emission_enabled = true
	eye.emission = (palette.eye as Color).linear_to_srgb()
	eye.emission_energy_multiplier = 6.0
	mats.eye = eye
	var mth := StandardMaterial3D.new()
	mth.albedo_color = Color.hex(0x200000ff)
	mth.emission_enabled = true
	mth.emission = Color(1, 0.3, 0.05).linear_to_srgb()
	mth.emission_energy_multiplier = 0.0
	mats.mouth = mth


func _build_body() -> void:
	var count := RINGS * (RAD + 1)
	var pos := PackedVector3Array()
	pos.resize(count)
	var nrm := PackedVector3Array()
	nrm.resize(count)
	nrm.fill(Vector3.UP)
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var back: Color = palette.back
	var ridge: Color = palette.ridge
	var belly: Color = palette.belly
	for i in RINGS:
		for j in RAD + 1:
			var s := sin(float(j) / RAD * TAU)
			col.append(back.lerp(ridge, U.smooth(0.75, 1, s)).lerp(belly, U.smooth(-0.25, -0.75, s)))
			uv.append(Vector2(float(j) / RAD * 2, float(i) / (RINGS - 1) * 9))
			uv2.append(Vector2(i, float(j) / RAD * TAU))
	var idx := PackedInt32Array()
	for i in RINGS - 1:
		for j in RAD:
			var a := i * (RAD + 1) + j
			var b := a + RAD + 1
			idx.append_array([a, b, a + 1, b, b + 1, a + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	body_mat = ShaderMaterial.new()
	body_mat.shader = load("res://shaders/dragon_body.gdshader")
	body_mat.set_shader_parameter("radii", radii)
	var body := MeshInstance3D.new()
	body.mesh = m
	body.material_override = body_mat
	body.custom_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	model.add_child(body)

	spikes = MultiMesh.new()
	spikes.transform_format = MultiMesh.TRANSFORM_3D
	spikes.mesh = _cyl(0.0, 0.32, 1.6, 6)
	spikes.instance_count = N_SPIKES
	spikes.visible_instance_count = int((RINGS - 6 - 6) / 2.0) + 1
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = spikes
	smi.material_override = mats.horn
	smi.custom_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	model.add_child(smi)


static func _sphere(r: float, w: int, h: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2
	m.radial_segments = w
	m.rings = h
	return m


static func _cyl(rt: float, rb: float, h: float, seg: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


static func _box(w: float, h: float, d: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(w, h, d)
	return m


static func _capsule(r: float, length: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = length + r * 2
	m.radial_segments = 8
	m.rings = 4
	return m


func _add(mesh: Mesh, mat: Material, p: Vector3, rot := Vector3.ZERO, sc := Vector3.ONE, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = p
	mi.rotation_order = EULER_ORDER_XYZ
	mi.rotation = rot
	mi.scale = sc
	(parent if parent else head).add_child(mi)
	return mi


func _build_head() -> void:
	model.add_child(head)
	var skin: Material = mats.skin
	_add(_sphere(1, 18, 14), skin, Vector3(0, 0.25, 0.4), Vector3.ZERO, Vector3(1.25, 1.05, 1.7))
	_add(_cyl(0.5, 0.95, 3.4, 10), skin, Vector3(0, 0.2, 2.6), Vector3(PI / 2, 0, 0), Vector3(1.2, 1, 0.75))
	_add(_sphere(0.55, 10, 8), skin, Vector3(0, 0.15, 4.25), Vector3.ZERO, Vector3(1.15, 0.7, 0.9))
	for s in [1.0, -1.0]:
		# creste sopraccigliari
		_add(_box(0.35, 0.3, 2.0), mats.dark, Vector3(s * 0.75, 0.95, 1.2), Vector3(0.25, s * 0.15, 0))
		_add(_sphere(0.22, 10, 8), mats.eye, Vector3(s * 0.82, 0.62, 1.35))
		# corna
		_add(_cyl(0, 0.38, 3.6, 8), mats.horn, Vector3(s * 0.7, 1.15, -0.6), Vector3(-1.15, 0, -s * 0.28))
		_add(_cyl(0, 0.22, 1.8, 6), mats.horn, Vector3(s * 1.1, 0.5, -0.4), Vector3(-1.3, 0, -s * 0.9))
		# narici
		_add(_sphere(0.13, 8, 6), mats.mouth, Vector3(s * 0.3, 0.45, 4.6))
	# mascella mobile
	jaw_pivot.position = Vector3(0, -0.35, 0.7)
	jaw_pivot.rotation_order = EULER_ORDER_XYZ
	head.add_child(jaw_pivot)
	_add(_cyl(0.42, 0.75, 3.3, 10), skin, Vector3(0, -0.25, 1.75), Vector3(PI / 2, 0, 0), Vector3(1.1, 1, 0.55), jaw_pivot)
	_add(_box(1.0, 0.1, 2.8), mats.mouth, Vector3(0, 0.08, 1.8), Vector3.ZERO, Vector3.ONE, jaw_pivot)
	var tooth := _cyl(0, 0.08, 0.35, 5)
	for i in 5:
		for s in [1.0, -1.0]:
			_add(tooth, mats.horn, Vector3(s * (0.42 - i * 0.04), 0.2, 0.7 + i * 0.6), Vector3.ZERO, Vector3.ONE, jaw_pivot)
			_add(tooth, mats.horn, Vector3(s * (0.45 - i * 0.04), -0.2, 1.4 + i * 0.6), Vector3(PI, 0, 0))
	# corona di spine dietro la testa
	for i in 5:
		var a := (i - 2) * 0.35
		_add(_cyl(0, 0.18, 1.3, 5), mats.horn, Vector3(sin(a) * 1.0, 0.9 + cos(a) * 0.3, -1.1), Vector3(-1.9, 0, -a))
	mouth.position = Vector3(0, -0.15, 4.8)
	head.add_child(mouth)


func _bone(parent: Node3D, length: float, r0: float, r1: float, s: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _cyl(r1, r0, length, 7)
	mi.material_override = mats.dark
	mi.rotation = Vector3(0, 0, -s * PI / 2)
	mi.position = Vector3(s * length / 2, 0, 0)
	parent.add_child(mi)


func _group(parent: Node3D, p := Vector3.ZERO) -> Node3D:
	var g := Node3D.new()
	g.rotation_order = EULER_ORDER_XYZ
	g.position = p
	parent.add_child(g)
	return g


func _build_wing(s: float) -> Dictionary:
	var w := {"s": s}
	w.shoulder = _group(model, Vector3(s * 1.3, 1.5, 1.4))
	w.flap = _group(w.shoulder)
	_bone(w.flap, 5.5, 0.55, 0.4, s)
	var joint := _sphere(0.5, 10, 8)
	w.elbow = _group(w.flap, Vector3(s * 5.5, 0, 0))
	_add(joint, mats.dark, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, w.elbow)
	_bone(w.elbow, 7.2, 0.42, 0.28, s)
	w.wrist = _group(w.elbow, Vector3(s * 7.2, 0, 0))
	_add(joint, mats.dark, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.75, w.wrist)
	# artiglio del pollice
	_add(_cyl(0, 0.18, 1.2, 6), mats.horn, Vector3(s * 0.2, 0.3, 0.6), Vector3(PI / 2, 0, 0), Vector3.ONE, w.wrist)
	w.alphas = [-0.12, 0.42, 0.92, 1.42]
	var lens := [11.5, 13.0, 11.5, 9.0]
	w.fingers = []
	w.tips = []
	for i in 4:
		var f := _group(w.wrist)
		_bone(f, lens[i], 0.26, 0.07, s)
		var tip := _group(f, Vector3(s * lens[i], 0, 0))
		w.fingers.append(f)
		w.tips.append(tip)
	w.m_s = _group(w.flap, Vector3(s * 0.6, 0, 1.3))
	w.hip = Vector3(s * 1.4, 0.7, -9.5)
	w.mid = Vector3(s * 1.6, 1.3, -3.5)
	w.uv = PackedVector2Array()
	var mi := MeshInstance3D.new()
	mi.mesh = ArrayMesh.new()
	mi.material_override = mats.membrane
	mi.custom_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	model.add_child(mi)
	w.mesh = mi.mesh
	return w


func _build_legs() -> void:
	# passo diagonale: posteriore sinistra con anteriore destra
	for s in [1.0, -1.0]:
		_leg(Vector3(s * 1.7, -0.8, -7.5), 1.0, 1.1, 0.0 if s > 0 else PI)
		_leg(Vector3(s * 1.6, -1.2, 1.8), 0.92, 1.3, PI if s > 0 else 0.0)


func _leg(p: Vector3, sc: float, tuck: float, phase: float) -> void:
	var g := _group(model, p)
	g.rotation.x = tuck
	g.scale = Vector3.ONE * sc
	_add(_capsule(0.7, 2.2), mats.dark, Vector3(0, -1.3, 0), Vector3.ZERO, Vector3.ONE, g)
	var shin := _group(g, Vector3(0, -2.6, 0))
	shin.rotation.x = -1.2
	_add(_capsule(0.45, 2.0), mats.dark, Vector3(0, -1.2, 0), Vector3.ZERO, Vector3.ONE, shin)
	for i in range(-1, 2):
		_add(_cyl(0, 0.15, 0.9, 5), mats.horn, Vector3(i * 0.3, -2.6, 0.2), Vector3(PI * 0.85, 0, 0), Vector3.ONE, shin)
	legs.append({"g": g, "shin": shin, "tuck": tuck, "phase": phase})


# Zampe: ripiegate in volo, distese e in movimento a terra
func _update_legs() -> void:
	var gb := ground_blend
	var walk := walk_amount
	for l in legs:
		var sw := sin(gait_phase + l.phase)
		var lift := maxf(0, cos(gait_phase + l.phase))
		l.g.rotation.x = lerpf(l.tuck, 0.08 + sw * 0.38 * walk, gb)
		l.shin.rotation.x = lerpf(-1.2, -0.22 - lift * 0.6 * walk, gb)


# ---------------- ANIMAZIONE ----------------
func _spine(t: float) -> Vector3:
	var x := 0.0
	var y := 0.0
	var z := -26 + t * 40
	if t < 0.5:
		var k := (0.5 - t) / 0.5
		var kk := k * k
		x += sin(time * 1.7 - t * 9) * 0.9 * kk + tail_turn * kk * 5
		y += -k * 1.0 + sin(time * 1.3 - t * 7) * 0.35 * kk + tail_lift * kk * 3 - ground_blend * k * 2.2
	if t > 0.72:
		var k := (t - 0.72) / 0.28
		var kk := k * k
		y += pow(k, 1.4) * 2.6 - neck_down * kk * 3.2 + neck_lift * kk * 3
		x += neck_turn * kk * 3.5
	return Vector3(x, y, z)


func _update_body() -> void:
	for i in RINGS:
		centers[i] = _spine(float(i) / (RINGS - 1))
	for i in RINGS:
		tangents[i] = (centers[mini(RINGS - 1, i + 1)] - centers[maxi(0, i - 1)]).normalized()
	for i in RINGS:
		var S := Vector3.UP.cross(tangents[i]).normalized()
		var Uv := tangents[i].cross(S)
		sides[i] = S
		ups_arr[i] = Uv
		# spine dorsali
		if i >= 6 and i <= RINGS - 6 and (i - 6) % 2 == 0:
			var t := float(i) / (RINGS - 1)
			var r := radii[i]
			var hr := 1.12 if t > 0.4 and t < 0.72 else 1.0
			var dir := (Uv * 0.7 - tangents[i] * 0.7).normalized()
			var sc := 0.45 + r * 0.45
			var p := centers[i] + Uv * (r * hr * 0.9) + dir * (0.8 * sc)
			spikes.set_instance_transform((i - 6) / 2, Transform3D(Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3.ONE * sc), p))
	body_mat.set_shader_parameter("centers", centers)
	body_mat.set_shader_parameter("sides", sides)
	body_mat.set_shader_parameter("ups", ups_arr)

	# testa all'estremità del collo
	var n := RINGS - 1
	head.position = centers[n] + tangents[n] * 0.2
	# la testa guarda un po' in basso, e ancora di più quando sputa fuoco
	var v := tangents[n]
	v.y -= 0.12 + neck_down * 0.3
	v = v.normalized()
	# mira assistita: il collo si piega verso il bersaglio se è davanti
	if aim_target != null:
		var v2: Vector3 = ((inv * aim_target) - head.position).normalized()
		aim_ok = v.angle_to(v2) < 0.8
		if aim_weight > 0.001:
			v = v.lerp(v2, aim_weight).normalized()
	else:
		aim_ok = false
	head.basis = Basis.looking_at(v, Vector3.UP, true)
	jaw_pivot.rotation.x = jaw


func _update_wings() -> void:
	var ph := flap_phase
	var sn := sin(ph)
	var cs := cos(ph)
	var amp := flap_amp * (1 - fold)
	var gb := ground_blend
	for w in wings:
		var s: float = w.s
		# a terra le ali sono raccolte lungo i fianchi
		w.flap.rotation.z = s * lerpf(0.15 + amp * 0.85 * sn - fold * 0.2, 0.55, gb)
		w.flap.rotation.x = lerpf(amp * 0.18 * cs, 0, gb)
		w.elbow.rotation.y = s * lerpf(0.28 + fold * 0.9 + 0.35 * maxf(0, cs) * amp, 2.15, gb)
		w.wrist.rotation.y = -s * lerpf(0.08 + fold * 0.95 + 0.25 * maxf(0, cs) * amp, 2.45, gb)
		w.wrist.rotation.z = s * lerpf(0.3 * amp * sin(ph - 1.0), -0.25, gb)
		for i in 4:
			w.fingers[i].rotation.y = s * w.alphas[i] * lerpf(1 - fold * 0.7 - maxf(0, cs) * 0.15 * amp, 0.12, gb)


func _update_membranes() -> void:
	inv = model.global_transform.affine_inverse()
	for w in wings:
		var p: Array[Vector3] = []
		p.resize(13)
		p[0] = inv * (w.m_s as Node3D).global_position
		p[1] = inv * (w.elbow as Node3D).global_position
		p[2] = inv * (w.wrist as Node3D).global_position
		for i in 4:
			p[3 + i] = inv * (w.tips[i] as Node3D).global_position
		p[7] = w.hip
		p[8] = w.mid
		for i in 3:
			p[9 + i] = p[3 + i].lerp(p[4 + i], 0.5).lerp(p[2], 0.2)
		p[12] = p[6].lerp(p[7], 0.5).lerp(p[1], 0.22)
		var pos := PackedVector3Array(p)
		# UV fisse, ricavate dalla posa iniziale (ala distesa): u lungo l'apertura, v dal braccio al bordo
		if w.uv.is_empty():
			for i in 13:
				w.uv.append(Vector2(clampf(absf(p[i].x) / 26, 0, 1), clampf((p[i].z + 16) / 19, 0, 1)))
		var nrm := PackedVector3Array()
		nrm.resize(13)
		var idx := PackedInt32Array()
		for t in range(0, MEMBRANE_IDX.size(), 3):
			var a: int = MEMBRANE_IDX[t]
			var b: int = MEMBRANE_IDX[t + 1]
			var c: int = MEMBRANE_IDX[t + 2]
			var fn := (p[b] - p[a]).cross(p[c] - p[a])
			nrm[a] += fn
			nrm[b] += fn
			nrm[c] += fn
			idx.append_array([a, c, b])
		for i in 13:
			nrm[i] = nrm[i].normalized()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_TEX_UV] = w.uv
		arrays[Mesh.ARRAY_INDEX] = idx
		var m: ArrayMesh = w.mesh
		m.clear_surfaces()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func start_roll(dir: float) -> bool:
	if maneuver != null or mode != "air":
		return false
	maneuver = {"type": "roll", "t": 0.0, "dur": 0.85, "dir": dir}
	return true


func start_loop() -> bool:
	if maneuver != null or mode != "air":
		return false
	maneuver = {"type": "loop", "t": 0.0, "dur": 2.6}
	return true


# Posizione e direzione della bocca nel mondo
func get_mouth() -> Array:
	var dir := (head.global_basis * Vector3(0, -0.05, 1).normalized()).normalized()
	return [mouth.global_position, dir]


# ---------------- VOLO ----------------
func update_dragon(dt: float, ctrl: Dictionary, world: World, animate := true) -> Dictionary:
	time += dt
	var events := {"downstroke": false, "touchdown": false}
	# colpito a morte: precipita avvitandosi
	if dying:
		ctrl = DYING_CTRL
		maneuver = null
		death_spin += dt * 4.5
	else:
		death_spin = 0
	aim_weight = U.damp(aim_weight, 0.85 if aim_target != null and aim_ok else 0.0, 6, dt)
	throttle = clampf(throttle + ctrl.throttle * 0.5 * dt, 0, 1)
	steer = U.damp(steer, ctrl.steer, 4, dt)
	climb = U.damp(climb, ctrl.climb, 3, dt)
	if mode != "air":
		return _update_ground(dt, ctrl, world, animate, events)
	ground_blend = U.damp(ground_blend, 0, 5, dt)
	walk_amount = 0
	neck_lift = U.damp(neck_lift, 0, 4, dt)
	head_yaw = U.damp(head_yaw, 0, 4, dt)
	head_pitch = U.damp(head_pitch, 0, 4, dt)

	# confine del mondo: oltre una certa distanza il drago vira verso il centro
	var dist_c := Vector2(position.x, position.z).length()
	var auto_steer := 0.0
	if dist_c > 5200:
		var desired := atan2(-position.x, -position.z)
		var d := desired - yaw
		d = atan2(sin(d), cos(d))
		auto_steer = -clampf(d * 2, -1, 1) * U.smooth(5200, 5800, dist_c)
	out_of_bounds = dist_c > 5200
	var st := clampf(steer + auto_steer, -1, 1)

	pitch = U.damp(pitch, -0.85 if dying else climb * 0.62, 1.2 if dying else 2.5, dt)
	var base := 26 + throttle * 124
	speed = U.damp(speed, base - sin(pitch) * 50, 0.9, dt)
	yaw -= st * (1.15 - throttle * 0.45) * dt
	roll = U.damp(roll, st * 0.85, 4, dt)

	var lateral := 0.0
	extra_pitch = 0
	extra_roll = death_spin
	var m = maneuver
	if m != null:
		m.t += dt
		var p := clampf(m.t / m.dur, 0, 1)
		var e := U.ease_in_out(p)
		if m.type == "roll":
			extra_roll = m.dir * TAU * e
			lateral = m.dir * sin(PI * p) * 45
		else:
			extra_pitch = TAU * e
		if p >= 1:
			maneuver = null
	var pt := pitch + extra_pitch
	var cy := cos(yaw)
	var sy := sin(yaw)
	forward = Vector3(sy * cos(pt), sin(pt), cy * cos(pt))
	up = Vector3(-sy * sin(pt), cos(pt), -cy * sin(pt))
	var loop_boost := 1.15 if m != null and m.type == "loop" else 1.0
	velocity = forward * speed * loop_boost
	velocity.x += -cy * lateral
	velocity.z += sy * lateral
	position += velocity * dt

	# niente atterraggio: quota minima sopra terra/mare
	var g := maxf(world.ground_height(position.x, position.z), 0)
	var ahead := maxf(world.ground_height(position.x + forward.x * 60, position.z + forward.z * 60), 0)
	var min_y := g + (1.5 if dying else 8.0)
	if position.y < ahead + 14 and pitch < 0.35 and m == null and not dying:
		pitch = U.damp(pitch, 0.4, 2, dt)
	if position.y < min_y:
		position.y = min_y
		if pitch < 0:
			pitch *= exp(-8 * dt)
		velocity.y = maxf(0, velocity.y)
	if position.y > 1500:
		position.y = 1500
		pitch = minf(pitch, 0)
	altitude = position.y - g
	ground_y = g

	rotation = Vector3(-pt, yaw, roll + extra_roll)

	# battito d'ali: frequenza e potenza dipendono da velocità e salita
	var climbing := maxf(0, sin(pt))
	var diving := maxf(0, -sin(pitch))
	var glide: bool = diving > 0.25 and ctrl.throttle <= 0 and m == null
	fold = U.damp(fold, 0.8 if glide else 0.0, 2.5, dt)
	var accel := 0.5 if ctrl.throttle > 0 else 0.0
	power = clampf(0.25 + throttle * 0.75 + climbing * 0.6 + accel * 0.3 + (0.4 if m != null and m.type == "loop" else 0.0), 0.2, 1.4)
	flap_freq = U.damp(flap_freq, 0.6 + throttle * 2.0 + climbing * 1.0 + accel, 2, dt)
	flap_amp = U.damp(flap_amp, 0.5 + power * 0.42, 2, dt)
	var prev_cos := cos(flap_phase)
	flap_phase += dt * flap_freq * TAU * (1 - fold * 0.92)
	if prev_cos > 0 and cos(flap_phase) <= 0 and fold < 0.5:
		events.downstroke = true
	model.position.y = -sin(flap_phase - 0.6) * 0.35 * flap_amp * (1 - fold)

	# collo e coda
	tail_turn = steer * 1.0
	tail_lift = -climb * 0.5 + diving * 0.4
	neck_turn = -steer * 0.9
	neck_down = U.damp(neck_down, 0.75 if breathing else 0.1, 4, dt)
	return _finish_frame(dt, animate, events)


func _finish_frame(dt: float, animate: bool, events: Dictionary) -> Dictionary:
	jaw = U.damp(jaw, 0.55 if breathing else (0.7 if roaring > 0 else 0.04), 10, dt)
	roaring = maxf(0, roaring - dt)
	mats.mouth.emission_energy_multiplier = U.damp(mats.mouth.emission_energy_multiplier, 8.0 if breathing else 0.3, 8, dt)
	if animate:
		_update_body()
		_update_wings()
		_update_legs()
		_update_membranes()
	return events


# ---------------- A TERRA ----------------
# Prova ad atterrare: restituisce "ok" oppure il motivo per cui non si può
func land(world: World) -> String:
	if mode != "air" or dying or maneuver != null:
		return "busy"
	var g := world.ground_height(position.x, position.z)
	if g < 1:
		return "water"
	if position.y - g > 70:
		return "high"
	mode = "landing"
	mode_t = 0
	land_from_y = position.y
	head_yaw = 0
	head_pitch = 0
	return "ok"


func take_off() -> bool:
	if mode != "ground" or dying:
		return false
	mode = "takeoff"
	mode_t = 0
	return true


func _update_ground(dt: float, ctrl: Dictionary, world: World, animate: bool, events: Dictionary) -> Dictionary:
	mode_t += dt
	var fx := sin(yaw)
	var fz := cos(yaw)
	var g := world.ground_height(position.x, position.z)
	var flapping := false

	if mode == "landing":
		# planata finale: rallenta, frena con le ali e appoggia le zampe
		var p := clampf(mode_t / 1.6, 0, 1)
		speed = U.damp(speed, 0, 2.2, dt)
		position.x += fx * speed * dt
		position.z += fz * speed * dt
		g = world.ground_height(position.x, position.z)
		position.y = lerpf(land_from_y, g + STAND, U.ease_in_out(p))
		pitch = sin(PI * p) * 0.35
		ground_blend = U.smooth(0.55, 1, p)
		flapping = true
		if p >= 1:
			if g < 1: # finito in acqua: riparte
				mode = "takeoff"
				mode_t = 0
			else:
				mode = "ground"
				speed = 0
				throttle = 0
				events.touchdown = true
	elif mode == "takeoff":
		# balzo e battiti potenti
		var p := clampf(mode_t / 1.1, 0, 1)
		speed = U.damp(speed, 45, 2, dt)
		position.x += fx * speed * dt
		position.z += fz * speed * dt
		g = world.ground_height(position.x, position.z)
		position.y = maxf(position.y + (12 + 30 * p) * dt, maxf(g, 0) + STAND)
		pitch = 0.35 * p
		ground_blend = 1 - U.smooth(0, 0.45, p)
		flapping = true
		if p >= 1:
			mode = "air"
			pitch = 0.35
			throttle = maxf(throttle, 0.35)
			climb = 0.5
	else:
		# camminata: A/D ruota il corpo, W/S avanti e indietro, Shift corre
		var turn := 0.0
		if not dying:
			turn = -ctrl.steer * 1.1
			# la testa girata troppo trascina anche il corpo
			if absf(head_yaw) > 0.6:
				var ex := head_yaw - signf(head_yaw) * 0.6
				turn += ex * 4
				head_yaw -= ex * 4 * dt
		yaw += turn * dt
		var target := 0.0
		if not dying:
			target = ctrl.climb * (18.0 if ctrl.throttle > 0 else 9.0) if ctrl.climb > 0 else ctrl.climb * 4.5
		speed = U.damp(speed, target, 4, dt)
		var dir := signf(speed)
		var nx := position.x + fx * speed * dt
		var nz := position.z + fz * speed * dt
		# davanti (o dietro): acqua, edifici o pareti ripide bloccano il passo
		var px := nx + fx * 8 * dir
		var pz := nz + fz * 8 * dir
		var gp := world.ground_height(px, pz)
		var blocked := gp < 0.8 or absf(gp - g) > 7 or world.building_at(px, gp + 3, pz) != null
		if blocked:
			speed = 0
		else:
			position.x = nx
			position.z = nz
			g = world.ground_height(position.x, position.z)
		position.y = U.damp(position.y, g + STAND, 10, dt)
		var h_f := world.ground_height(position.x + fx * 7, position.z + fz * 7)
		var h_b := world.ground_height(position.x - fx * 7, position.z - fz * 7)
		pitch = U.damp(pitch, atan2(h_f - h_b, 14) * 0.8, 6, dt)
		ground_blend = U.damp(ground_blend, 1, 6, dt)
		walk_amount = U.damp(walk_amount, minf(1, absf(speed) / 8 + absf(turn) * 0.4), 6, dt)
		gait_phase += (absf(speed) * 0.55 + absf(turn) * 2.5) * dt
		tail_turn = U.damp(tail_turn, turn * 0.6 + sin(time * 0.7) * 0.25, 3, dt)

		# la testa si guarda intorno: frecce/levetta destra/mouse; da ferma esplora da sola
		var ax: float = ctrl.get("aim_x", 0.0)
		var ay: float = ctrl.get("aim_y", 0.0)
		var mdx: float = ctrl.get("mouse_dx", 0.0)
		var mdy: float = ctrl.get("mouse_dy", 0.0)
		var any_input: bool = absf(ax) + absf(ay) + absf(mdx) + absf(mdy) > 0.01 or breathing \
			or absf(ctrl.climb) > 0.1 or absf(ctrl.steer) > 0.1
		if any_input:
			idle_t = 0
			idle_base = null
		else:
			idle_t += dt
		if not dying:
			# levetta/frecce con risposta progressiva: precisa vicino al centro, rapida a fondo corsa
			var cx := signf(ax) * ax * ax
			var cy2 := signf(ay) * ay * ay
			head_yaw += -cx * 2.6 * dt - mdx * 0.003
			head_pitch += cy2 * 1.8 * dt - mdy * 0.003
			# da fermo, dopo un po', si guarda intorno vicino a dove stava mirando
			if idle_t > 6:
				if idle_base == null:
					idle_base = {"yaw": head_yaw, "pitch": head_pitch, "t": time}
				var t: float = time - idle_base.t
				head_yaw = U.damp(head_yaw, idle_base.yaw + sin(t * 0.37) * 0.35, 0.8, dt)
				head_pitch = U.damp(head_pitch, idle_base.pitch + sin(t * 0.23) * 0.12, 0.8, dt)
		head_yaw = clampf(head_yaw, -1.4, 1.4)
		head_pitch = clampf(head_pitch, -0.75, 0.9)

	roll = U.damp(roll, 0, 5, dt)
	var pt := pitch
	var cy := cos(yaw)
	var sy := sin(yaw)
	forward = Vector3(sy * cos(pt), sin(pt), cy * cos(pt))
	up = Vector3(-sy * sin(pt), cos(pt), -cy * sin(pt))
	velocity = Vector3(sy * speed, 0, cy * speed)
	altitude = position.y - maxf(g, 0)
	ground_y = maxf(g, 0)
	out_of_bounds = false
	rotation = Vector3(-pt, yaw, roll)

	# direzione di mira (testa) nel mondo
	var ay2 := yaw + head_yaw
	var hp := head_pitch
	aim_dir = Vector3(sin(ay2) * cos(hp), sin(hp), cos(ay2) * cos(hp))
	aim_point = head.global_position + aim_dir * 200
	aim_target = aim_point
	aim_ok = true
	aim_weight = ground_blend

	# ali: battiti forti in atterraggio/decollo, ferme a terra
	if flapping:
		flap_freq = U.damp(flap_freq, 2.6, 4, dt)
		flap_amp = U.damp(flap_amp, 1.05, 4, dt)
		power = 1.2
		fold = U.damp(fold, 0, 6, dt)
		var prev_cos := cos(flap_phase)
		flap_phase += dt * flap_freq * TAU
		if prev_cos > 0 and cos(flap_phase) <= 0:
			events.downstroke = true
	else:
		flap_amp = U.damp(flap_amp, 0, 4, dt)
		power = 0.3
	model.position.y = lerpf(-sin(flap_phase - 0.6) * 0.35 * flap_amp,
		sin(time * 1.4) * 0.08 + absf(sin(gait_phase)) * 0.18 * walk_amount, ground_blend)

	# collo alzato e girato verso la mira
	tail_lift = 0
	neck_lift = U.damp(neck_lift, ground_blend * (0.7 + head_pitch * 0.9), 5, dt)
	neck_turn = U.damp(neck_turn, head_yaw * 0.9 * ground_blend, 6, dt)
	neck_down = U.damp(neck_down, 0, 4, dt)
	return _finish_frame(dt, animate, events)
