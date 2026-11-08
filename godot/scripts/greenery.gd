# Verde attorno alle case: edera che risale i muri e cespugli alla base, fatti di ciuffi di foglie (l'atlante di
# Foliage) raccolti in un'unica mesh per villaggio. Ogni ciuffo porta l'id dell'edificio (UV2.x), così lo
# shader (greenery.gdshader) lo annerisce e lo fa sparire quando la casa brucia.
class_name Greenery

var pos := PackedVector3Array()
var nrm := PackedVector3Array()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()
var col := PackedColorArray()


func is_empty() -> bool:
	return pos.is_empty()


# Macchia d'edera su una parete. frame: sistema della casa; la parete sta sul piano locale z = 0 di at, con la
# faccia verso +Z e u lungo X. Parte dal suolo a u0, larga width e alta fino a top (quote assolute), più stretta
# e sfrangiata verso l'alto; holes: rettangoli (u, y) di porte e finestre da lasciare scoperti.
func ivy(frame: Transform3D, at: Transform3D, bid: int, u0: float, width: float, y0: float, top: float, umin: float, umax: float, holes: Array, r: Mulberry32) -> void:
	var xf := frame * at
	var n := (xf.basis * Vector3.BACK).normalized()
	var t := (xf.basis * Vector3.RIGHT).normalized()
	var h := top - y0
	var count := int(width * h * 4.5)
	# rami: a ogni quota la macchia copre una fascia che si stringe e ondeggia, con qualche tralcio più alto
	var lean := (r.next() - 0.5) * 0.5
	var phase := r.next() * TAU
	for i in count:
		var v := pow(r.next(), 1.25)
		var y := y0 + v * h
		var half := width / 2 * (1.0 - 0.55 * v * v) * (0.75 + 0.25 * sin(v * 7.0 + phase))
		var u := u0 + lean * v * h + (r.next() * 2.0 - 1.0) * half
		if v > 0.75 and absf(u - u0 - lean * v * h) > half * (0.4 + 0.6 * absf(sin(u * 3.1 + phase))):
			continue
		if u < umin or u > umax:
			continue
		var blocked := false
		for hole: Rect2 in holes:
			if hole.grow(0.12).has_point(Vector2(u, y)):
				blocked = true
				break
		if blocked:
			continue
		var s := 0.75 + r.next() * 0.45
		var off := 0.06 + r.next() * 0.16
		var c := xf * Vector3(u, y, off)
		# ciuffi quasi paralleli al muro, ruotati a caso e piegati in fuori in basso
		var spin := r.next() * TAU
		var ax := (t * cos(spin) + Vector3.UP * sin(spin)) * s
		var ay := (Vector3.UP * cos(spin) - t * sin(spin))
		ay = (ay + n * (r.next() - 0.35) * 0.9).normalized() * s
		var shade := 0.55 + 0.45 * v + (r.next() - 0.5) * 0.2
		_card(c, ax, ay, (n + Vector3.UP * 0.35).normalized(), Color(0.62, 0.78, 0.5) * shade, bid, 0.15)


# Cespuglio tondo appoggiato sul terreno in c (coordinate del mondo), raggio rad
func bush(c: Vector3, rad: float, bid: int, r: Mulberry32) -> void:
	var count := int(10 + rad * rad * 26)
	var hue := Color(0.6, 0.78, 0.48) if r.next() < 0.6 else Color(0.5, 0.72, 0.5)
	var center := c + Vector3(0, rad * 0.55, 0)
	var sc := Vector3(rad, rad * 0.8, rad)
	for i in count:
		var d := Vector3(r.next() * 2 - 1, r.next() * 1.5 - 0.4, r.next() * 2 - 1).normalized()
		var k := 0.45 + r.next() * 0.55
		var p := center + d * sc * k
		var basis := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)
		basis = Basis(Vector3(r.next() - 0.5, r.next() - 0.5, r.next() - 0.5).normalized(), (r.next() - 0.5) * 1.6) * basis
		basis = basis * Basis(Vector3.BACK, r.next() * TAU)
		var s := rad * (0.9 + r.next() * 0.5)
		var shade := clampf(0.5 + d.y * 0.25 + (k - 0.5) * 0.7, 0.35, 1.0)
		_card(p, basis.x * s, basis.y * s, (d + Vector3(0, 0.5, 0)).normalized(), hue * shade, bid, 1.0)


# Ciuffo quadrato centrato in c; COLOR.a: quanto lo muove il vento
func _card(c: Vector3, ax: Vector3, ay: Vector3, n: Vector3, tint: Color, bid: int, sway: float) -> void:
	var rect := Foliage.LEAF_RECT
	var p := [c - ax / 2 - ay / 2, c + ax / 2 - ay / 2, c + ax / 2 + ay / 2, c - ax / 2 + ay / 2]
	var u := [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]
	var ns := []
	for q in p:
		ns.append((n + (q - c).normalized() * 0.3).normalized())
	tint.a = sway
	for k in [0, 2, 1, 0, 3, 2]:
		pos.append(p[k])
		nrm.append(ns[k])
		uv.append(u[k])
		uv2.append(Vector2(bid, 0))
		col.append(tint)


func build(material: Material) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = col
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visibility_range_end = 700.0
	mi.visibility_range_end_margin = 60.0
	return mi
