# Alberi procedurali: tronco e rami con corteccia fotografica, chioma fatta di ciuffi di foglie (piani con
# trasparenza ritagliata, texture disegnata all'avvio) attorno a un nucleo scuro che le dà volume.
# Ogni modello ha due superfici: 0 corteccia (e nucleo), 1 foglie. Due livelli di dettaglio per tipo.
class_name Foliage

const ATLAS_W := 512
const ATLAS_H := 256
const LEAF_RECT := Rect2(0, 0, 0.5, 1) # ciuffo di foglie (metà sinistra dell'atlante)
const NEEDLE_RECT := Rect2(0.5, 0.25, 0.5, 0.5) # ramo di abete (metà destra, fascia centrale)


class MeshData:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()

	# Triangolo con la faccia anteriore dalla parte di n (Godot vuole il senso orario)
	func tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ca: Color, cb: Color, cc: Color) -> void:
		if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
			pos.append_array([a, c, b])
			nrm.append_array([na, nc, nb])
			uv.append_array([ua, uc, ub])
			col.append_array([ca, cc, cb])
		else:
			pos.append_array([a, b, c])
			nrm.append_array([na, nb, nc])
			uv.append_array([ua, ub, uc])
			col.append_array([ca, cb, cc])

	func arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_COLOR] = col
		return arr


static var _atlas: ImageTexture
static var _materials: Array = []


# Materiali condivisi: corteccia PBR e foglie (shaders/foliage.gdshader)
static func materials() -> Array:
	if _materials.is_empty():
		var bark := ORMMaterial3D.new()
		bark.vertex_color_use_as_albedo = true
		bark.albedo_texture = load("res://textures/bark_diff.jpg")
		bark.normal_enabled = true
		bark.normal_texture = load("res://textures/bark_nor.jpg")
		bark.orm_texture = load("res://textures/bark_arm.jpg")
		bark.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var leaves := ShaderMaterial.new()
		leaves.shader = load("res://shaders/foliage.gdshader")
		leaves.set_shader_parameter("atlas", atlas())
		_materials = [bark, leaves]
	return _materials


static func _mesh(bark: MeshData, leaves: MeshData) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bark.arrays())
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaves.arrays())
	var mats := materials()
	m.surface_set_material(0, mats[0])
	m.surface_set_material(1, mats[1])
	return m


# Latifoglia: tronco, rami principali e chioma tondeggiante (circa 9 m)
static func broadleaf(detail: bool) -> ArrayMesh:
	var r := Mulberry32.new(4242)
	var bark := MeshData.new()
	var leaves := MeshData.new()
	_limb(bark, Vector3(0, -1, 0), Vector3(0, 4.8, 0), 0.42, 0.2, 8 if detail else 5)
	var center := Vector3(0, 6.3, 0)
	var rad := Vector3(3.3, 2.7, 3.3)
	if detail:
		for i in 6:
			var a := i * TAU / 6 + r.next() * 0.5
			var y := 2.8 + r.next() * 1.5
			var dir := Vector3(cos(a) * 0.85, 0.7 + r.next() * 0.4, sin(a) * 0.85).normalized()
			_limb(bark, Vector3(0, y, 0), Vector3(0, y, 0) + dir * (2.2 + r.next()), 0.16, 0.05, 5)
	_core(bark, "blob", center, rad * 0.78, Color(0.05, 0.08, 0.028))
	var n := 90 if detail else 26
	var size := 2.9 if detail else 4.4
	for i in n:
		var d := Vector3(r.next() * 2 - 1, r.next() * 1.6 - 0.6, r.next() * 2 - 1).normalized()
		var k := 0.62 + r.next() * 0.38
		var p := center + d * rad * k
		# ciuffi quasi tangenti alla chioma (inclinati a caso fino a 50°): sagoma piena e tondeggiante
		var tilt := Basis(Vector3(r.next() - 0.5, r.next() - 0.5, r.next() - 0.5).normalized(), (r.next() - 0.5) * 1.7)
		var basis := tilt * Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)
		basis = basis * Basis(Vector3.BACK, r.next() * TAU)
		var s := size * (0.8 + r.next() * 0.4)
		# più scuri i ciuffi in basso e verso l'interno
		var shade := clampf(0.55 + d.y * 0.25 + (k - 0.55) * 0.9, 0.45, 1.0)
		_card(leaves, p, basis.x * s, basis.y * s, LEAF_RECT, (d + Vector3(0, 0.45, 0)).normalized(), shade, shade)
	return _mesh(bark, leaves)


# Abete: tronco slanciato e palchi di rami piatti e spioventi che si accorciano verso la cima (circa 11 m)
static func conifer(detail: bool) -> ArrayMesh:
	var r := Mulberry32.new(9191)
	var bark := MeshData.new()
	var leaves := MeshData.new()
	_limb(bark, Vector3(0, -1, 0), Vector3(0, 10.4, 0), 0.34, 0.04, 7 if detail else 5)
	_core(bark, "cone8", Vector3(0, 1.3, 0), Vector3(1.7, 8.8, 1.7), Color(0.022, 0.04, 0.022))
	var levels := 15 if detail else 7
	var per := 9 if detail else 6
	for k in levels:
		var rel := k / (levels - 1.0)
		var y := lerpf(1.3, 9.7, rel)
		var length := lerpf(3.1, 0.7, pow(rel, 0.85)) * (1.0 if detail else 1.15)
		for j in per:
			var a := j * TAU / per + k * 0.9 + r.next() * 0.4
			var dir := Vector3(cos(a), 0, sin(a))
			var droop := 0.22 + r.next() * 0.25
			var along := dir * cos(droop) - Vector3.UP * sin(droop)
			var side := dir.cross(Vector3.UP).normalized().rotated(along, (r.next() - 0.5) * 1.3)
			var width := length * 0.8 + 0.4
			var start := Vector3(0, y, 0) + dir * 0.15
			_card(leaves, start + along * length / 2, along * length, side * width, NEEDLE_RECT, (dir + Vector3(0, 0.6, 0)).normalized(), 0.5, 1.0)
	# cima: due rametti verticali incrociati
	for a in [0.0, PI / 2]:
		var side := Vector3(cos(a), 0, sin(a)) * 0.9
		_card(leaves, Vector3(0, 10.3, 0), Vector3(0, 1.6, 0), side, NEEDLE_RECT, Vector3.UP, 0.8, 1.0)
	return _mesh(bark, leaves)


# Ramo o tronco: cilindro rastremato con coordinate per la corteccia (una ripetizione ogni 1,5 m)
static func _limb(m: MeshData, p0: Vector3, p1: Vector3, r0: float, r1: float, seg: int) -> void:
	var axis := (p1 - p0).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.y) > 0.9 else Vector3.UP).normalized()
	var other := axis.cross(side)
	var length := p0.distance_to(p1)
	var wrap := maxf(1.0, roundf(TAU * r0 / 1.5))
	var white := Color.WHITE
	for i in seg:
		var a0 := float(i) / seg * TAU
		var a1 := float(i + 1) / seg * TAU
		var d0 := side * cos(a0) + other * sin(a0)
		var d1 := side * cos(a1) + other * sin(a1)
		var u0 := float(i) / seg * wrap
		var u1 := float(i + 1) / seg * wrap
		var v := length / 1.5
		var A := p0 + d0 * r0
		var B := p0 + d1 * r0
		var C := p1 + d1 * r1
		var D := p1 + d0 * r1
		m.tri(A, B, C, d0, d1, d1, Vector2(u0, v), Vector2(u1, v), Vector2(u1, 0), white, white, white)
		m.tri(A, C, D, d0, d1, d0, Vector2(u0, v), Vector2(u1, 0), Vector2(u0, 0), white, white, white)


# Nucleo pieno della chioma (sfera o cono dalle primitive) con la corteccia tinta di verde scuro
static func _core(m: MeshData, kind: String, at: Vector3, scale: Vector3, color: Color) -> void:
	var prim := Prims.get_prim(kind)
	var P: PackedVector3Array = prim.pos
	var Nn: PackedVector3Array = prim.nrm
	for t in range(0, P.size(), 3):
		var v := [P[t] * scale + at, P[t + 1] * scale + at, P[t + 2] * scale + at]
		var n := [(Nn[t] / scale).normalized(), (Nn[t + 1] / scale).normalized(), (Nn[t + 2] / scale).normalized()]
		m.tri(v[0], v[1], v[2], n[0], n[1], n[2], Vector2(v[0].x, v[0].y), Vector2(v[1].x, v[1].y), Vector2(v[2].x, v[2].y), color, color, color)


# Piano rettangolare centrato in c con lati ax (lungo u) e ay (lungo v); n è la normale della chioma,
# shade0/shade1 l'ombreggiatura all'inizio e alla fine lungo u
static func _card(m: MeshData, c: Vector3, ax: Vector3, ay: Vector3, rect: Rect2, n: Vector3, shade0: float, shade1: float) -> void:
	var p := [c - ax / 2 - ay / 2, c + ax / 2 - ay / 2, c + ax / 2 + ay / 2, c - ax / 2 + ay / 2]
	var u := [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]
	var k := [Color(shade0, shade0, shade0), Color(shade1, shade1, shade1), Color(shade1, shade1, shade1), Color(shade0, shade0, shade0)]
	var ns := []
	for q in p:
		ns.append((n + (q - c).normalized() * 0.35).normalized())
	m.tri(p[0], p[1], p[2], ns[0], ns[1], ns[2], u[0], u[1], u[2], k[0], k[1], k[2])
	m.tri(p[0], p[2], p[3], ns[0], ns[2], ns[3], u[0], u[2], u[3], k[0], k[2], k[3])


# Atlante delle foglie disegnato una volta: a sinistra un ciuffo di foglie ovali, a destra un ramo di abete
static func atlas() -> ImageTexture:
	if _atlas:
		return _atlas
	var img := Image.create(ATLAS_W, ATLAS_H, false, Image.FORMAT_RGBA8)
	# fondo trasparente del colore medio, così le mipmap non fanno aloni scuri
	img.fill(Color(0.24, 0.36, 0.12, 0.0))
	var r := Mulberry32.new(31337)
	for i in 520:
		var a := r.next() * TAU
		var d := sqrt(r.next()) * 112.0
		var c := Vector2(128, 128) + Vector2(cos(a), sin(a)) * d
		var length := 11.0 + r.next() * 7.0
		var base := Color(0.27, 0.42, 0.12).lerp(Color(0.42, 0.5, 0.16), r.next() * r.next())
		_leaf(img, c, a + (r.next() - 0.5) * 1.8, length, length * 0.4, base * (0.75 + r.next() * 0.45))
	# ramo di abete: rachide orizzontale e aghi su due file, più corti verso la punta
	var x0 := 262.0
	var x1 := 506.0
	var t := 0.0
	while t < 1.0:
		var x := lerpf(x0, x1, t)
		var nl := 52.0 * pow(1.0 - t, 0.6) + 7.0
		for s in [-1.0, 1.0]:
			for layer in 3:
				var ang: float = [0.6, 0.95, 1.3][layer] * s
				var tip: Vector2 = Vector2(x, 128) + Vector2(cos(ang), sin(ang)) * nl * [1.0, 0.85, 0.6][layer] * (0.85 + r.next() * 0.3)
				var g: Color = Color(0.15, 0.3, 0.13).lerp(Color(0.24, 0.4, 0.17), r.next()) * [1.0, 0.9, 0.8][layer]
				_line(img, Vector2(x, 128), tip, 1.6, g)
		t += 0.007
	_line(img, Vector2(x0, 128), Vector2(x1, 128), 3.0, Color(0.25, 0.18, 0.1))
	img.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(img)
	return _atlas


# Foglia ovale con nervatura centrale, più chiara verso la punta (bordi sfumati di un pixel)
static func _leaf(img: Image, c: Vector2, ang: float, length: float, width: float, color: Color) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var nrm := Vector2(-dir.y, dir.x)
	var ext := ceili(length / 2 + 2)
	for y in range(maxi(0, int(c.y) - ext), mini(ATLAS_H, int(c.y) + ext + 1)):
		for x in range(maxi(0, int(c.x) - ext), mini(ATLAS_W / 2, int(c.x) + ext + 1)):
			var q := Vector2(x + 0.5, y + 0.5) - c
			var u := q.dot(dir) / length + 0.5
			if u <= 0.0 or u >= 1.0:
				continue
			var v := absf(q.dot(nrm))
			var half := width / 2 * pow(sin(PI * u), 0.75)
			var a := clampf(half - v + 0.5, 0.0, 1.0)
			if a <= 0.0:
				continue
			var k := (0.8 + 0.35 * u) * (0.75 if v < 0.7 else 1.0) * (1.0 - 0.15 * v / maxf(half, 0.01))
			_blend(img, x, y, Color(color.r * k, color.g * k, color.b * k), a)


static func _line(img: Image, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var lo := a.min(b) - Vector2(width, width)
	var hi := a.max(b) + Vector2(width, width)
	var ab := b - a
	var l2 := maxf(ab.length_squared(), 0.001)
	for y in range(maxi(0, int(lo.y)), mini(ATLAS_H, int(hi.y) + 1)):
		for x in range(maxi(0, int(lo.x)), mini(ATLAS_W, int(hi.x) + 1)):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			# gli aghi si assottigliano verso la punta
			var al := clampf(width / 2 * (1.0 - t * 0.6) - d + 0.5, 0.0, 1.0)
			if al > 0.0:
				_blend(img, x, y, color * (0.85 + 0.3 * t), al)


static func _blend(img: Image, x: int, y: int, c: Color, a: float) -> void:
	var o := img.get_pixel(x, y)
	img.set_pixel(x, y, Color(lerpf(o.r, c.r, a), lerpf(o.g, c.g, a), lerpf(o.b, c.b, a), maxf(o.a, a)))
