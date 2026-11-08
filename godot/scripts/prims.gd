# Primitive unitarie con la base a y=0 (equivalenti di UNIT in src/world.js).
# Ogni primitiva è un dizionario {pos, nrm} di triangoli con le facce verso l'esterno
# in senso antiorario (convenzione Three.js); GeoBuilder li inverte per Godot.
class_name Prims

static var _cache := {}


static func get_prim(kind: String) -> Dictionary:
	if not _cache.has(kind):
		match kind:
			"box": _cache[kind] = _box()
			"cyl": _cache[kind] = _cylinder(14)
			"prism": _cache[kind] = _prism(16)
			"cone": _cache[kind] = _cone(14, 1.0)
			"cone8": _cache[kind] = _cone(8, 1.0)
			"pyr": _cache[kind] = _pyramid()
			"roof": _cache[kind] = _roof()
			"blob": _cache[kind] = _icosphere()
	return _cache[kind]


# Aggiunge un triangolo con normale piatta, orientato verso l'esterno rispetto a center
static func _tri(d: Dictionary, a: Vector3, b: Vector3, c: Vector3, center: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.dot((a + b + c) / 3.0 - center) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	d.pos.append_array([a, b, c])
	d.nrm.append_array([n, n, n])


# Triangolo con normali per vertice (superfici lisce)
static func _tri_smooth(d: Dictionary, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, center: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.dot((a + b + c) / 3.0 - center) < 0.0:
		d.pos.append_array([a, c, b])
		d.nrm.append_array([na, nc, nb])
	else:
		d.pos.append_array([a, b, c])
		d.nrm.append_array([na, nb, nc])


static func _new() -> Dictionary:
	return {"pos": PackedVector3Array(), "nrm": PackedVector3Array()}


static func _box() -> Dictionary:
	var d := _new()
	var c := Vector3(0, 0.5, 0)
	var v := []
	for i in 8:
		v.append(Vector3(0.5 if i & 1 else -0.5, 1.0 if i & 2 else 0.0, 0.5 if i & 4 else -0.5))
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_tri(d, v[f[0]], v[f[1]], v[f[2]], c)
		_tri(d, v[f[0]], v[f[2]], v[f[3]], c)
	return d


static func _ring(seg: int, i: int) -> Vector3:
	var a := float(i) / seg * TAU
	return Vector3(sin(a), 0, cos(a))


static func _cylinder(seg: int) -> Dictionary:
	var d := _new()
	var c := Vector3(0, 0.5, 0)
	var up := Vector3(0, 1, 0)
	for i in seg:
		var p0 := _ring(seg, i)
		var p1 := _ring(seg, i + 1)
		_tri_smooth(d, p0, p1, p1 + up, p0, p1, p1, c)
		_tri_smooth(d, p0, p1 + up, p0 + up, p0, p1, p0, c)
		_tri(d, up, p0 + up, p1 + up, c)
		_tri(d, Vector3.ZERO, p1, p0, c)
	return d


# Cilindro a facce piatte: ogni faccia riceve la texture dritta (torri in pietra)
static func _prism(seg: int) -> Dictionary:
	var d := _new()
	var c := Vector3(0, 0.5, 0)
	var up := Vector3(0, 1, 0)
	for i in seg:
		var p0 := _ring(seg, i)
		var p1 := _ring(seg, i + 1)
		_tri(d, p0, p1, p1 + up, c)
		_tri(d, p0, p1 + up, p0 + up, c)
		_tri(d, up, p0 + up, p1 + up, c)
		_tri(d, Vector3.ZERO, p1, p0, c)
	return d


static func _cone(seg: int, radius: float) -> Dictionary:
	var d := _new()
	var c := Vector3(0, 0.5, 0)
	var apex := Vector3(0, 1, 0)
	for i in seg:
		var p0 := _ring(seg, i) * radius
		var p1 := _ring(seg, i + 1) * radius
		var n0 := (p0.normalized() + Vector3(0, radius, 0)).normalized()
		var n1 := (p1.normalized() + Vector3(0, radius, 0)).normalized()
		var nm := ((n0 + n1) * 0.5).normalized()
		_tri_smooth(d, p0, p1, apex, n0, n1, nm, c)
		_tri(d, Vector3.ZERO, p1, p0, c)
	return d


static func _pyramid() -> Dictionary:
	var d := _new()
	var c := Vector3(0, 0.3, 0)
	var apex := Vector3(0, 1, 0)
	var b := [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]
	for i in 4:
		_tri(d, b[i], b[(i + 1) % 4], apex, c)
	_tri(d, b[0], b[1], b[2], c)
	_tri(d, b[0], b[2], b[3], c)
	return d


static func _roof() -> Dictionary:
	var d := _new()
	var c := Vector3(0, 0.35, 0)
	var A := Vector3(-0.5, 0, 0.5)
	var B := Vector3(0.5, 0, 0.5)
	var C := Vector3(0, 1, 0.5)
	var D := Vector3(-0.5, 0, -0.5)
	var E := Vector3(0.5, 0, -0.5)
	var F := Vector3(0, 1, -0.5)
	for t in [[A, B, C], [E, D, F], [D, A, C], [D, C, F], [B, E, F], [B, F, C], [A, D, E], [A, E, B]]:
		_tri(d, t[0], t[1], t[2], c)
	return d


# Icosaedro suddiviso una volta (IcosahedronGeometry(1, 1)) con normali lisce: chiome tondeggianti
static func _icosphere() -> Dictionary:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	var d := _new()
	for f in faces:
		var a: Vector3 = v[f[0]].normalized()
		var b: Vector3 = v[f[1]].normalized()
		var c: Vector3 = v[f[2]].normalized()
		var ab := ((a + b) * 0.5).normalized()
		var bc := ((b + c) * 0.5).normalized()
		var ca := ((c + a) * 0.5).normalized()
		for tri in [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]:
			_tri_smooth(d, tri[0], tri[1], tri[2], tri[0], tri[1], tri[2], Vector3.ZERO)
	return d
