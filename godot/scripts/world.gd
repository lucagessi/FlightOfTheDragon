# Mondo: isole, terreno, villaggi medievali, castello, alberi e gestione degli incendi
# (porting di src/world.js; altezze e rumore vengono da data/terrain.bin)
class_name World
extends Node3D

const TERRAIN_SIZE := 7600.0
const TERRAIN_SEGS := 480
const N := TERRAIN_SEGS + 1
const HALF := TERRAIN_SIZE / 2.0
const STEP := TERRAIN_SIZE / TERRAIN_SEGS
const SEABED := -55.0
const BURN_TEX_SIZE := 1024
const CHUNKS := 16
const LOD_SEGS := [128, 64, 32, 16] # suddivisioni di un blocco per livello (passo 3,7 / 7,4 / 15 / 30 m)
const LOD_DIST := [650.0, 1400.0, 2800.0]

# isole: x, z, raggio
const ISLANDS := [
	Vector3(0, 0, 1900), Vector3(2650, -1650, 820), Vector3(-2500, 1950, 720),
	Vector3(-2350, -2150, 540), Vector3(2250, 2300, 700), Vector3(350, 3150, 420),
]

const VILLAGE_NAMES := [
	"Borgo Rosso", "Valdifiume", "Montecorvo", "Rocca Bruna", "Pietralta", "Castelmare",
	"Fontebella", "Querceto", "Torrevecchia", "Marinella", "Acquaviva", "Spinalunga",
]

static var COLORS := {
	"plaster": [U.lin(0.86, 0.82, 0.72), U.lin(0.8, 0.74, 0.62), U.lin(0.9, 0.88, 0.8), U.lin(0.76, 0.68, 0.55), U.lin(0.84, 0.76, 0.6)],
	"stone": U.lin(0.56, 0.54, 0.5),
	"stone_dark": U.lin(0.42, 0.41, 0.39),
	"timber": U.lin(0.27, 0.17, 0.1),
	"door": U.lin(0.22, 0.13, 0.07),
	"window": U.lin(0.07, 0.06, 0.05),
	"roofs": [U.lin(0.62, 0.25, 0.15), U.lin(0.55, 0.3, 0.18), U.lin(0.6, 0.5, 0.28), U.lin(0.32, 0.33, 0.37), U.lin(0.68, 0.32, 0.18)],
	"slate": U.lin(0.28, 0.3, 0.35),
	"castle_roof": U.lin(0.5, 0.14, 0.12),
	"shutters": [U.lin(0.32, 0.4, 0.3), U.lin(0.45, 0.3, 0.18), U.lin(0.3, 0.36, 0.45), U.lin(0.5, 0.42, 0.3)],
}


class Building:
	var id: int
	var inert := false
	var circles: Array = [] # Vector3(x, z, r)
	var base := 0.0
	var top := 0.0
	var state := 0 # 0 intatto, 1 in fiamme, 2 distrutto
	var t := 0.0
	var fire := 0.0
	var charred := 0.0
	var collapse := 0.0
	var emit_acc := 0.0
	var smoke_acc := 0.0
	var village = null
	var x := 0.0
	var z := 0.0
	var size := 0.0


# Accumula primitive in un'unica mesh con gli attributi per l'incendio (CUSTOM0)
class GeoBuilder:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var col := PackedColorArray()
	var cus := PackedFloat32Array()

	# mat: 0 intonaco, 1 tegole/ardesia, 2 pietra, 3 legno, 4 finestre e porte
	func add(prim: Dictionary, xf: Transform3D, color: Color, bid: int, base_y: float, glow := 0.0, rng: Mulberry32 = null, mat := 0) -> void:
		var nb := xf.basis.inverse().transposed()
		var j := 0.9 + rng.next() * 0.2 if rng else 1.0
		var P: PackedVector3Array = prim.pos
		var Nn: PackedVector3Array = prim.nrm
		var use_ao := base_y > -1e5
		# Godot vuole le facce in senso orario: si scambiano il secondo e il terzo vertice
		for t in range(0, P.size(), 3):
			for o in 3:
				var k: int = t + (0 if o == 0 else 3 - o)
				var v := xf * P[k]
				var ao := lerpf(0.55, 1.0, U.smooth(base_y - 1.0, base_y + 3.5, v.y)) if use_ao else 1.0
				pos.append(v)
				nor.append((nb * Nn[k]).normalized())
				col.append(Color(color.r * j * ao, color.g * j * ao, color.b * j * ao))
				cus.append_array([bid, base_y, glow, mat])

	func build() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nor
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_CUSTOM0] = cus
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		return m


# Parti di un edificio posizionate nel suo sistema locale (y assoluta)
class PartMaker:
	var b: GeoBuilder
	var frame: Transform3D
	var bid: int
	var base: float
	var rng: Mulberry32

	func _init(builder: GeoBuilder, f: Transform3D, building_id: int, base_y: float, r: Mulberry32) -> void:
		b = builder
		frame = f
		bid = building_id
		base = base_y
		rng = r

	func p(kind: String, lx: float, ly: float, lz: float, sx: float, sy: float, sz: float, ry: float, color: Color, glow := 0.0) -> void:
		var xf := frame * Transform3D(Basis(Vector3.UP, ry) * Basis.from_scale(Vector3(sx, sy, sz)), Vector3(lx, ly, lz))
		b.add(Prims.get_prim(kind), xf, color, bid, base, glow, rng, World.material_of(color))

	# Parte con una trasformazione locale qualsiasi (travi inclinate, imposte aperte)
	func pt(kind: String, local: Transform3D, color: Color, glow := 0.0) -> void:
		b.add(Prims.get_prim(kind), frame * local, color, bid, base, glow, rng, World.material_of(color))


var data: PackedFloat32Array # per vertice: altezza, rumore fine, foresta
var hgrid: PackedFloat32Array
var data_tex: ImageTexture
var rng := Mulberry32.new(2024)
var buildings: Array[Building] = []
var grid := {}
var burning: Array[Building] = []
var tree_fires: Array = []
var stats := {"total": 0, "burning": 0, "destroyed": 0}
var villages: Array = []
var trees: Array = []
var tree_grid := {}
var tree_meshes: Array[MultiMesh] = []
var time := 0.0
var fx = null

var burn_image: Image
var burn_tex: ImageTexture
var building_material: ShaderMaterial
var terrain_material: ShaderMaterial
var terrain_lods: Array[ArrayMesh] = []
var terrain_chunks: Array[MeshInstance3D] = []
var smooth_ground := false # dopo la generazione l'altezza segue la superficie morbida disegnata


# 0 intonaco, 1 tegole, 2 pietra, 3 travi, 4 vetro, 5 ardesia, 6 assi di legno (porte, imposte)
static func material_of(color: Color) -> int:
	if color == COLORS.slate or color == COLORS.roofs[3]:
		return 5
	if COLORS.roofs.has(color) or color == COLORS.castle_roof:
		return 1
	if color == COLORS.stone or color == COLORS.stone_dark:
		return 2
	if color == COLORS.timber:
		return 3
	if color == COLORS.window:
		return 4
	if color == COLORS.door or COLORS.shutters.has(color):
		return 6
	return 0


func generate() -> void:
	var inert := Building.new()
	inert.id = 0
	inert.inert = true
	buildings.append(inert) # id 0 = elementi non infiammabili
	_load_terrain()
	villages = _place_villages()
	_build_terrain_mesh()
	burn_image = Image.create(BURN_TEX_SIZE, 1, false, Image.FORMAT_RGBA8)
	burn_tex = ImageTexture.create_from_image(burn_image)
	building_material = ShaderMaterial.new()
	building_material.shader = load("res://shaders/building.gdshader")
	building_material.set_shader_parameter("burn_tex", burn_tex)
	building_material.set_shader_parameter("burn_size", float(BURN_TEX_SIZE))
	set_textures(building_material, ["plaster", "roof_tiles", "roof_slate", "stone_wall", "timber", "shutter"])
	for v in villages:
		if v.kind == "castle":
			_build_castle(v)
		else:
			_build_village(v)
	stats.total = buildings.size() - 1
	_build_trees()
	smooth_ground = true


# ---------------- TERRENO ----------------
func _load_terrain() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://data/terrain.bin")
	assert(bytes.size() == N * N * 12, "data/terrain.bin mancante: esegui node godot/tools/export_world.mjs")
	data = bytes.to_float32_array()
	hgrid.resize(N * N)
	for k in N * N:
		hgrid[k] = data[k * 3]
	data_tex = ImageTexture.create_from_image(Image.create_from_data(N, N, false, Image.FORMAT_RGBF, bytes))


func ground_height(x: float, z: float) -> float:
	var fx := (x + HALF) / STEP
	var fz := (z + HALF) / STEP
	if fx < 0 or fz < 0 or fx >= N - 1 or fz >= N - 1:
		return SEABED
	if smooth_ground:
		return _catmull(fx, fz)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * N + i
	var a := hgrid[k] + (hgrid[k + 1] - hgrid[k]) * tx
	var b := hgrid[k + N] + (hgrid[k + N + 1] - hgrid[k + N]) * tx
	return a + (b - a) * tz


# Interpolazione Catmull-Rom (passa per i punti della griglia): la stessa dello shader del terreno
func _catmull(fx: float, fz: float) -> float:
	var i := int(fx)
	var j := int(fz)
	var wx := _cr_weights(fx - i)
	var wz := _cr_weights(fz - j)
	var h := 0.0
	for b in 4:
		var row := clampi(j + b - 1, 0, N - 1) * N
		var s := 0.0
		for a in 4:
			s += wx[a] * hgrid[row + clampi(i + a - 1, 0, N - 1)]
		h += wz[b] * s
	return h


static func _cr_weights(t: float) -> PackedFloat32Array:
	var t2 := t * t
	var t3 := t2 * t
	return PackedFloat32Array([-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0, -1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2])


# Rumore della foresta (fbm a bassa frequenza) interpolato dalla griglia
func forest_at(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / STEP, 0, N - 1.001)
	var fz := clampf((z + HALF) / STEP, 0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := (j * N + i) * 3 + 2
	var a := lerpf(data[k], data[k + 3], tx)
	var b := lerpf(data[k + N * 3], data[k + N * 3 + 3], tx)
	return lerpf(a, b, tz)


func flatness(x: float, z: float, r: float) -> float:
	var mn := INF
	var mx := -INF
	for a in 8:
		var h := ground_height(x + cos(a * 0.785) * r, z + sin(a * 0.785) * r)
		mn = minf(mn, h)
		mx = maxf(mx, h)
	var h0 := ground_height(x, z)
	return maxf(mx, h0) - minf(mn, h0)


func _place_villages() -> Array:
	var out := []
	var attempt := 0
	while attempt < 6000 and out.size() < 11:
		var isl: Vector3 = ISLANDS[1 + int(rng.next() * (ISLANDS.size() - 1))] if attempt % 3 == 0 else ISLANDS[0]
		attempt += 1
		var a := rng.next() * TAU
		var r := sqrt(rng.next()) * isl.z * 0.72
		var x := isl.x + cos(a) * r
		var z := isl.y + sin(a) * r
		var h := ground_height(x, z)
		if h < 6 or h > 60:
			continue
		if flatness(x, z, 60) > 14:
			continue
		var near := false
		for v in out:
			if Vector2(v.x - x, v.z - z).length() < 620:
				near = true
				break
		if near:
			continue
		out.append({"x": x, "z": z, "h": h, "r": 70 + rng.next() * 40, "kind": "village", "name": VILLAGE_NAMES[out.size()], "ids": [], "placed": []})
	# Castello su un'altura
	var best = null
	for i in 6000:
		var a := rng.next() * TAU
		var r := sqrt(rng.next()) * 1300
		var x := cos(a) * r
		var z := sin(a) * r
		var h := ground_height(x, z)
		if h < 25 or h > 170:
			continue
		var near := false
		for v in out:
			if Vector2(v.x - x, v.z - z).length() < 450:
				near = true
				break
		if near:
			continue
		var f := flatness(x, z, 55)
		if f > 20:
			continue
		var score := h - f * 3
		if best == null or score > best.score:
			best = {"x": x, "z": z, "h": h, "score": score}
	if best != null:
		out.append({"x": best.x, "z": best.z, "h": best.h, "r": 75.0, "kind": "castle", "name": "Castello di Roccaforte", "ids": [], "placed": []})
	return out


# Il terreno è diviso in blocchi con più livelli di dettaglio: le altezze (interpolate in modo
# morbido tra i punti della griglia, con rilievo roccioso fine) le calcola lo shader da data_tex
func _build_terrain_mesh() -> void:
	for n in LOD_SEGS:
		terrain_lods.append(_chunk_mesh(n))
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = load("res://shaders/terrain.gdshader")
	terrain_material.set_shader_parameter("terrain_data", data_tex)
	set_textures(terrain_material, ["grass", "dirt", "rock", "sand", "snow", "cobble"])
	var vs := PackedVector4Array()
	for i in 12:
		if i < villages.size():
			var v = villages[i]
			vs.append(Vector4(v.x, v.z, v.r, 2.0 if v.kind == "castle" else 1.0))
		else:
			vs.append(Vector4.ZERO)
	terrain_material.set_shader_parameter("villages", vs)
	var size := TERRAIN_SIZE / CHUNKS
	for j in CHUNKS:
		for i in CHUNKS:
			var mi := MeshInstance3D.new()
			mi.mesh = terrain_lods[LOD_SEGS.size() - 1]
			mi.material_override = terrain_material
			mi.position = Vector3(-HALF + (i + 0.5) * size, 0, -HALF + (j + 0.5) * size)
			mi.custom_aabb = AABB(Vector3(-size / 2, SEABED - 30, -size / 2), Vector3(size, 560, size))
			add_child(mi)
			terrain_chunks.append(mi)


# Collega a un materiale le texture fotografiche (textures/<nome>_diff.jpg e _nor.jpg) come <nome>_d e <nome>_n
static func set_textures(mat: ShaderMaterial, names: Array) -> void:
	for n in names:
		mat.set_shader_parameter(n + "_d", load("res://textures/%s_diff.jpg" % n))
		mat.set_shader_parameter(n + "_n", load("res://textures/%s_nor.jpg" % n))


# Griglia di un blocco con "gonne" verticali sui bordi che coprono le fessure tra livelli diversi
func _chunk_mesh(n: int) -> ArrayMesh:
	var size := TERRAIN_SIZE / CHUNKS
	var step := size / n
	var pos := PackedVector3Array()
	var skirt := PackedVector2Array()
	for j in n + 1:
		for i in n + 1:
			pos.append(Vector3(-size / 2 + i * step, 0, -size / 2 + j * step))
			skirt.append(Vector2.ZERO)
	var idx := PackedInt32Array()
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			idx.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	# bordo percorso in senso orario: ogni vertice ha un gemello abbassato dallo shader
	var edge := PackedInt32Array()
	for i in n:
		edge.append(i)
	for j in n:
		edge.append(j * (n + 1) + n)
	for i in range(n, 0, -1):
		edge.append(n * (n + 1) + i)
	for j in range(n, 0, -1):
		edge.append(j * (n + 1))
	var base := pos.size()
	for k in edge:
		pos.append(pos[k])
		skirt.append(Vector2(1, 0))
	for e in edge.size():
		var e1 := (e + 1) % edge.size()
		idx.append_array([edge[e], edge[e1], base + e, edge[e1], base + e1, base + e])
	var nrm := PackedVector3Array()
	nrm.resize(pos.size())
	nrm.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV2] = skirt
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# Livello di dettaglio di ogni blocco in base alla distanza dalla camera
func update_terrain(cam_pos: Vector3) -> void:
	terrain_material.set_shader_parameter("focus", cam_pos)
	for mi in terrain_chunks:
		var d := Vector2(mi.position.x - cam_pos.x, mi.position.z - cam_pos.z).length()
		var lod := LOD_SEGS.size() - 1
		for k in LOD_DIST.size():
			if d < LOD_DIST[k]:
				lod = k
				break
		mi.mesh = terrain_lods[lod]


# ---------------- EDIFICI ----------------
func _new_building(circles: Array, base: float, top: float, village) -> Building:
	var b := Building.new()
	b.id = buildings.size()
	b.circles = circles
	b.base = base
	b.top = top
	b.village = village
	var sx := 0.0
	var sz := 0.0
	var mr := 0.0
	for c in circles:
		sx += c.x
		sz += c.y
		mr = maxf(mr, c.z)
	b.x = sx / circles.size()
	b.z = sz / circles.size()
	b.size = mr * sqrt(circles.size())
	buildings.append(b)
	if village != null:
		village.ids.append(b.id)
	for c in circles:
		for gx in range(floori((c.x - c.z) / 32), floori((c.x + c.z) / 32) + 1):
			for gz in range(floori((c.y - c.z) / 32), floori((c.y + c.z) / 32) + 1):
				var key := gx * 100003 + gz
				if not grid.has(key):
					grid[key] = []
				if not grid[key].has(b):
					grid[key].append(b)
	return b


func _frame(x: float, z: float, rot: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rot), Vector3(x, 0, z))


func _local_to_world(x: float, z: float, rot: float, lx: float, lz: float) -> Vector2:
	var c := cos(rot)
	var s := sin(rot)
	return Vector2(x + lx * c + lz * s, z - lx * s + lz * c)


func _ground_range(x: float, z: float, rot: float, hw: float, hd: float) -> Vector2:
	var mn := INF
	var mx := -INF
	for l in [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd), Vector2.ZERO]:
		var w := _local_to_world(x, z, rot, l.x, l.y)
		var h := ground_height(w.x, w.y)
		mn = minf(mn, h)
		mx = maxf(mx, h)
	return Vector2(mn, mx)


func _add_house(B: GeoBuilder, x: float, z: float, rot: float, village, big := false) -> float:
	var w := (9.0 if big else 6.0) + rng.next() * 3.5
	var d := (7.0 if big else 5.0) + rng.next() * 2.5
	var floors := 2 if rng.next() < 0.4 else 1
	var wh := 3.3 * floors + rng.next() * 1.0
	var gr := _ground_range(x, z, rot, w / 2, d / 2)
	var gmin := gr.x
	var gmax := gr.y
	var floor_y := gmax + 0.5
	var wall_top := floor_y + wh
	var rh := 2.4 + rng.next() * 2.2 + minf(w, d) * 0.15
	var b := _new_building([Vector3(x, z, Vector2(w, d).length() / 2 + 0.5)], gmax, wall_top + rh, village)
	var P := PartMaker.new(B, _frame(x, z, rot), b.id, gmax, rng)
	var plaster: Color = COLORS.plaster[int(rng.next() * COLORS.plaster.size())]
	var roof_col: Color = COLORS.roofs[int(rng.next() * COLORS.roofs.size())]
	var timbered := rng.next() < 0.6

	P.p("box", 0, gmin - 2, 0, w + 0.3, floor_y - gmin + 2, d + 0.3, 0, COLORS.stone_dark)
	var wall_col: Color = plaster if timbered else (COLORS.stone if rng.next() < 0.5 else plaster)
	P.p("box", 0, floor_y, 0, w, wh, d, 0, wall_col)
	if timbered:
		for cx in [-w / 2, w / 2]:
			for cz in [-d / 2, d / 2]:
				P.p("box", cx, floor_y, cz, 0.45, wh, 0.45, 0, COLORS.timber)
		P.p("box", 0, wall_top - 0.35, 0, w + 0.14, 0.35, d + 0.14, 0, COLORS.timber)
		if floors == 2:
			P.p("box", 0, floor_y + 3.2, 0, w + 0.14, 0.32, d + 0.14, 0, COLORS.timber)
		P.p("box", 0, floor_y, 0, w + 0.14, 0.3, d + 0.14, 0, COLORS.timber)
	# dettagli costruttivi: generatore separato, così la sequenza principale (villaggi, alberi) resta quella originale
	var D := PartMaker.new(B, _frame(x, z, rot), b.id, gmax, Mulberry32.new(b.id * 7919 + 13))
	var jetty := 0.4 if timbered and floors == 2 else 0.0
	var upper_y := floor_y + 3.2
	if jetty > 0:
		# piano superiore sporgente sulla facciata e sul retro, con la trave che lo regge
		D.p("box", 0, upper_y, 0, w, wall_top - upper_y, d + jetty * 2, 0, plaster)
		D.p("box", 0, upper_y - 0.3, 0, w + 0.14, 0.32, d + jetty * 2 + 0.14, 0, COLORS.timber)
	if w >= d:
		P.p("roof", 0, wall_top, 0, d + 1.3 + jetty * 2, rh, w + 1.0, PI / 2, roof_col)
		D.p("box", 0, wall_top + rh - 0.12, 0, w + 1.1, 0.24, 0.32, 0, roof_col.darkened(0.25))
	else:
		P.p("roof", 0, wall_top, 0, w + 1.3, rh, d + 1.0 + jetty * 2, 0, roof_col)
		D.p("box", 0, wall_top + rh - 0.12, 0, 0.32, 0.24, d + 1.1 + jetty * 2, 0, roof_col.darkened(0.25))
	if rng.next() < 0.65:
		var chx := (rng.next() - 0.5) * w * 0.5
		P.p("box", chx, wall_top, -d * 0.2, 0.9, rh * 0.95, 0.9, 0, COLORS.stone_dark)
		D.p("box", chx, wall_top + rh * 0.95, -d * 0.2, 1.2, 0.16, 1.2, 0, COLORS.stone)
	# porta e finestre (le finestre si illuminano quando la casa brucia)
	var door_x := (rng.next() - 0.5) * w * 0.3
	P.p("box", door_x, floor_y - 0.2, d / 2, 1.3, 2.3, 0.3, 0, COLORS.door, 0.5)
	for s in [-1.0, 1.0]:
		D.p("box", door_x + s * 0.74, floor_y - 0.2, d / 2, 0.16, 2.5, 0.4, 0, COLORS.timber)
	D.p("box", door_x, floor_y + 2.1, d / 2, 1.66, 0.2, 0.42, 0, COLORS.timber)
	D.p("box", door_x, floor_y - 0.55, d / 2 + 0.35, 1.8, 0.35, 0.8, 0, COLORS.stone)
	var shutter: Color = COLORS.shutters[int(D.rng.next() * COLORS.shutters.size())]
	for f in floors:
		var y := floor_y + 1.2 + f * 3.2
		var j := jetty if f == 1 else 0.0
		for sx in [-0.3, 0.3]:
			P.p("box", sx * w, y, d / 2 + j, 1.0, 1.0, 0.28, 0, COLORS.window, 1)
			P.p("box", sx * w, y, -d / 2 - j, 1.0, 1.0, 0.28, 0, COLORS.window, 1)
			_window_trim(D, Transform3D(Basis.IDENTITY, Vector3(sx * w, y, d / 2 + j)), shutter)
			_window_trim(D, Transform3D(Basis(Vector3.UP, PI), Vector3(sx * w, y, -d / 2 - j)), shutter)
		P.p("box", w / 2, y, 0, 0.28, 1.0, 1.0, 0, COLORS.window, 1)
		P.p("box", -w / 2, y, 0, 0.28, 1.0, 1.0, 0, COLORS.window, 1)
		_window_trim(D, Transform3D(Basis(Vector3.UP, PI / 2), Vector3(w / 2, y, 0)), shutter)
		_window_trim(D, Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(-w / 2, y, 0)), shutter)
	if timbered:
		# graticcio: montanti e controventi su ogni parete e per ogni piano
		for f in floors:
			var y0 := floor_y if f == 0 else upper_y
			var y1 := upper_y if f == 0 and floors == 2 else wall_top
			var j := jetty if f == 1 else 0.0
			var openings := [-0.3 * w, 0.3 * w]
			_timber_wall(D, Transform3D(Basis.IDENTITY, Vector3(0, 0, d / 2 + j)), w, y0, y1, openings + ([door_x] if f == 0 else []))
			_timber_wall(D, Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -d / 2 - j)), w, y0, y1, openings)
			_timber_wall(D, Transform3D(Basis(Vector3.UP, PI / 2), Vector3(w / 2, 0, 0)), d + j * 2, y0, y1, [0.0])
			_timber_wall(D, Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(-w / 2, 0, 0)), d + j * 2, y0, y1, [0.0])
	return Vector2(w, d).length() / 2


# Cornice, davanzale, croce e imposte aperte di una finestra (sistema locale: finestra verso +Z, base a y=0)
func _window_trim(D: PartMaker, at: Transform3D, shutter: Color) -> void:
	var parts := [
		[Vector3(0, 1.0, 0.02), Vector3(1.3, 0.12, 0.36), COLORS.timber],
		[Vector3(-0.56, 0, 0.02), Vector3(0.12, 1.0, 0.36), COLORS.timber],
		[Vector3(0.56, 0, 0.02), Vector3(0.12, 1.0, 0.36), COLORS.timber],
		[Vector3(0, -0.12, 0.1), Vector3(1.4, 0.12, 0.5), COLORS.stone],
		[Vector3(0, 0, 0.02), Vector3(0.06, 1.0, 0.32), COLORS.timber],
		[Vector3(0, 0.47, 0.02), Vector3(1.0, 0.06, 0.32), COLORS.timber],
		[Vector3(-0.9, 0, 0.16), Vector3(0.52, 1.02, 0.06), shutter],
		[Vector3(0.9, 0, 0.16), Vector3(0.52, 1.02, 0.06), shutter],
	]
	for p in parts:
		D.pt("box", at * Transform3D(Basis.from_scale(p[1]), p[0]), p[2])


# Montanti verticali (evitando porte e finestre) e due controventi inclinati agli angoli
func _timber_wall(D: PartMaker, at: Transform3D, length: float, y0: float, y1: float, openings: Array) -> void:
	var h := y1 - y0
	var x := -length / 2 + 1.5
	while x < length / 2 - 1.2:
		var free := true
		for o in openings:
			if absf(x - o) < 0.95:
				free = false
		if free:
			D.pt("box", at * Transform3D(Basis.from_scale(Vector3(0.2, h, 0.14)), Vector3(x, y0, 0.03)), COLORS.timber)
		x += 1.35
	var run := minf(1.4, length * 0.2)
	var lean := atan2(run, h * 0.75)
	var size := Vector3(0.18, Vector2(run, h * 0.75).length(), 0.12)
	for s in [-1.0, 1.0]:
		var bx: float = s * (length / 2 - 0.3)
		var basis := Basis(Vector3.BACK, s * lean) * Basis.from_scale(size)
		D.pt("box", at * Transform3D(basis, Vector3(bx, y0, 0.04)), COLORS.timber)


func _add_church(B: GeoBuilder, x: float, z: float, rot: float, village) -> void:
	var w := 10.0
	var d := 22.0
	var h := 10.0
	var gr := _ground_range(x, z, rot, w / 2 + 1, d / 2 + 4)
	var gmin := gr.x
	var gmax := gr.y
	var a := _local_to_world(x, z, rot, 0, d / 4)
	var bb := _local_to_world(x, z, rot, 0, -d / 4)
	var nave := _new_building([Vector3(a.x, a.y, 7.5), Vector3(bb.x, bb.y, 7.5)], gmax, gmax + h + 7, village)
	var P := PartMaker.new(B, _frame(x, z, rot), nave.id, gmax, rng)
	P.p("box", 0, gmin - 2, 0, w, gmax + h - gmin + 2, d, 0, COLORS.stone)
	P.p("roof", 0, gmax + h, 0, w + 1.4, 7, d + 0.8, 0, COLORS.slate)
	P.p("box", 0, gmax, d / 2, 2.2, 4, 0.4, 0, COLORS.door, 0.6)
	for i in range(-2, 3):
		P.p("box", w / 2, gmax + 3.5, i * 4, 0.3, 3.2, 1.1, 0, COLORS.window, 1)
		P.p("box", -w / 2, gmax + 3.5, i * 4, 0.3, 3.2, 1.1, 0, COLORS.window, 1)
	P.p("cyl", 0, gmax + 7, d / 2, 1.2, 0.4, 0.5, 0, COLORS.window, 1)
	var t := _local_to_world(x, z, rot, 0, -d / 2 - 3.2)
	var tower := _new_building([Vector3(t.x, t.y, 4.5)], gmax, gmax + 38, village)
	var T := PartMaker.new(B, _frame(x, z, rot), tower.id, gmax, rng)
	T.p("box", 0, gmin - 2, -d / 2 - 3.2, 6.4, gmax + 25 - gmin + 2, 6.4, 0, COLORS.stone)
	T.p("box", 0, gmax + 25, -d / 2 - 3.2, 7.2, 0.8, 7.2, 0, COLORS.stone_dark)
	T.p("pyr", 0, gmax + 25.8, -d / 2 - 3.2, 7.0, 13, 7.0, 0, COLORS.slate)
	for sz in [3.25, -3.25]:
		T.p("box", 0, gmax + 20, -d / 2 - 3.2 + sz, 1.4, 2.6, 0.3, 0, COLORS.window, 1)
	for sx in [3.25, -3.25]:
		T.p("box", sx, gmax + 20, -d / 2 - 3.2, 0.3, 2.6, 1.4, 0, COLORS.window, 1)


func _add_tower(B: GeoBuilder, x: float, z: float, village, r := 3.6, h := 16.0, roof_col = null) -> Building:
	if roof_col == null:
		roof_col = COLORS.castle_roof
	var g := ground_height(x, z)
	var gmin := minf(minf(g, ground_height(x + r, z)), minf(minf(ground_height(x - r, z), ground_height(x, z + r)), ground_height(x, z - r)))
	var b := _new_building([Vector3(x, z, r + 0.5)], g, g + h + r * 2, village)
	var P := PartMaker.new(B, _frame(x, z, 0), b.id, g, rng)
	P.p("cyl", 0, gmin - 2, 0, r, g + h - gmin + 2, r, 0, COLORS.stone)
	P.p("cyl", 0, g + h - 0.6, 0, r + 0.6, 0.8, r + 0.6, 0, COLORS.stone_dark)
	P.p("cone", 0, g + h + 0.2, 0, r + 1.2, r * 2.2, r + 1.2, 0, roof_col)
	for a in 4:
		P.p("box", cos(a * 1.57 + 0.4) * r, g + h * 0.65, sin(a * 1.57 + 0.4) * r, 0.9, 1.6, 0.9, 0, COLORS.window, 1)
	return b


func _add_wall(B: GeoBuilder, x1: float, z1: float, x2: float, z2: float, village, h := 12.0, thick := 3.6) -> void:
	var length := Vector2(x2 - x1, z2 - z1).length()
	var rot := atan2(x2 - x1, z2 - z1)
	var cx := (x1 + x2) / 2
	var cz := (z1 + z2) / 2
	var mn := INF
	var mx := -INF
	var circles := []
	var nc := maxi(2, ceili(length / 7))
	for i in nc + 1:
		var t := float(i) / nc
		var g := ground_height(lerpf(x1, x2, t), lerpf(z1, z2, t))
		mn = minf(mn, g)
		mx = maxf(mx, g)
		if i < nc:
			circles.append(Vector3(lerpf(x1, x2, t + 0.5 / nc), lerpf(z1, z2, t + 0.5 / nc), 4))
	var b := _new_building(circles, mx, mx + h + 2, village)
	var P := PartMaker.new(B, _frame(cx, cz, rot), b.id, mx, rng)
	P.p("box", 0, mn - 3, 0, thick, mx + h - mn + 3, length, 0, COLORS.stone)
	var s := -length / 2 + 1.2
	while s < length / 2 - 0.6:
		P.p("box", thick / 2 - 0.5, mx + h, s, 1.0, 1.6, 1.4, 0, COLORS.stone)
		P.p("box", -thick / 2 + 0.5, mx + h, s, 1.0, 1.6, 1.4, 0, COLORS.stone)
		s += 3


func _build_village(v: Dictionary) -> void:
	var B := GeoBuilder.new()
	var placed: Array = []
	var free := func(x: float, z: float, r: float) -> bool:
		for p in placed:
			if Vector2(p.x - x, p.y - z).length() <= p.z + r + 2.5:
				return false
		return true
	# pozzo al centro
	var g0 := ground_height(v.x, v.z)
	var W := PartMaker.new(B, _frame(v.x, v.z, 0), 0, g0, rng)
	W.p("cyl", 0, g0 - 1, 0, 1.6, 2.2, 1.6, 0, COLORS.stone)
	W.p("pyr", 0, g0 + 3.2, 0, 3.6, 1.6, 3.6, 0, COLORS.roofs[0])
	W.p("box", 1.4, g0, 0, 0.3, 3.3, 0.3, 0, COLORS.timber)
	W.p("box", -1.4, g0, 0, 0.3, 3.3, 0.3, 0, COLORS.timber)
	placed.append(Vector3(v.x, v.z, 6))

	# chiesa
	var ca := rng.next() * TAU
	var cx: float = v.x + cos(ca) * 24
	var cz: float = v.z + sin(ca) * 24
	_add_church(B, cx, cz, atan2(v.x - cx, v.z - cz), v)
	placed.append(Vector3(cx, cz, 15))

	# torre di guardia ai margini
	var ta := rng.next() * TAU
	var tx: float = v.x + cos(ta) * (v.r * 0.85)
	var tz: float = v.z + sin(ta) * (v.r * 0.85)
	if ground_height(tx, tz) > 3:
		_add_tower(B, tx, tz, v, 3.6, 15 + rng.next() * 6)
		placed.append(Vector3(tx, tz, 5))

	var target := int(v.r * 0.3 + rng.next() * 8)
	var count := 0
	var i := 0
	while i < 600 and count < target:
		i += 1
		var a := rng.next() * TAU
		var rr: float = 13 + sqrt(rng.next()) * (v.r - 13)
		var x: float = v.x + cos(a) * rr
		var z: float = v.z + sin(a) * rr
		if not free.call(x, z, 6.5):
			continue
		if ground_height(x, z) < 3 or flatness(x, z, 6) > 4:
			continue
		var rot: float = atan2(v.x - x, v.z - z) + (rng.next() - 0.5) * 0.5
		var r := _add_house(B, x, z, rot, v, rng.next() < 0.2)
		placed.append(Vector3(x, z, r))
		count += 1
	# fattorie sparse tra i campi
	var farms := 0
	i = 0
	while i < 80 and farms < 5:
		i += 1
		var a := rng.next() * TAU
		var rr: float = v.r + 30 + rng.next() * 140
		var x: float = v.x + cos(a) * rr
		var z: float = v.z + sin(a) * rr
		if ground_height(x, z) < 4 or flatness(x, z, 8) > 5 or not free.call(x, z, 12):
			continue
		var rot := rng.next() * TAU
		var r := _add_house(B, x, z, rot, v, true)
		placed.append(Vector3(x, z, r))
		farms += 1
	v.placed = placed
	_add_mesh(B)


func _build_castle(v: Dictionary) -> void:
	var B := GeoBuilder.new()
	var rot := rng.next() * PI
	var R := 44.0
	var cs := [
		_local_to_world(v.x, v.z, rot, -R, -R), _local_to_world(v.x, v.z, rot, R, -R),
		_local_to_world(v.x, v.z, rot, R, R), _local_to_world(v.x, v.z, rot, -R, R),
	]
	for c in cs:
		_add_tower(B, c.x, c.y, v, 6.5, 24, COLORS.castle_roof)
	for i in 4:
		var p1: Vector2 = cs[i]
		var p2: Vector2 = cs[(i + 1) % 4]
		var dx := (p2.x - p1.x) / (2 * R)
		var dz := (p2.y - p1.y) / (2 * R)
		var o := 6.0
		if i == 2:
			# lato con il portale d'ingresso
			var mx := (p1.x + p2.x) / 2
			var mz := (p1.y + p2.y) / 2
			_add_wall(B, p1.x + dx * o, p1.y + dz * o, mx - dx * 7, mz - dz * 7, v, 13)
			_add_wall(B, mx + dx * 7, mz + dz * 7, p2.x - dx * o, p2.y - dz * o, v, 13)
			_add_tower(B, mx - dx * 8, mz - dz * 8, v, 4.2, 20, COLORS.castle_roof)
			_add_tower(B, mx + dx * 8, mz + dz * 8, v, 4.2, 20, COLORS.castle_roof)
		else:
			_add_wall(B, p1.x + dx * o, p1.y + dz * o, p2.x - dx * o, p2.y - dz * o, v, 13)
	# mastio
	var gr := _ground_range(v.x, v.z, rot, 10, 10)
	var gmin := gr.x
	var gmax := gr.y
	var keep := _new_building([Vector3(v.x, v.z, 13)], gmax, gmax + 42, v)
	var P := PartMaker.new(B, _frame(v.x, v.z, rot), keep.id, gmax, rng)
	P.p("box", 0, gmin - 3, 0, 20, gmax + 30 - gmin + 3, 20, 0, COLORS.stone)
	for s in range(-9, 10, 3):
		for ab in [Vector2(s, 9.6), Vector2(s, -9.6), Vector2(9.6, s), Vector2(-9.6, s)]:
			P.p("box", ab.x, gmax + 30, ab.y, 1.3, 1.8, 1.3, 0, COLORS.stone)
	for ab in [Vector2(10, 10), Vector2(-10, 10), Vector2(10, -10), Vector2(-10, -10)]:
		P.p("cyl", ab.x, gmax + 20, ab.y, 2.6, 16, 2.6, 0, COLORS.stone)
		P.p("cone", ab.x, gmax + 36, ab.y, 3.4, 8, 3.4, 0, COLORS.castle_roof)
	for f in 3:
		for s in [-5, 0, 5]:
			var y := gmax + 6 + f * 8
			P.p("box", s, y, 10, 1.2, 2.2, 0.3, 0, COLORS.window, 1)
			P.p("box", s, y, -10, 1.2, 2.2, 0.3, 0, COLORS.window, 1)
			P.p("box", 10, y, s, 0.3, 2.2, 1.2, 0, COLORS.window, 1)
			P.p("box", -10, y, s, 0.3, 2.2, 1.2, 0, COLORS.window, 1)
	# case nel cortile
	for l in [Vector2(-28, 22), Vector2(26, -26), Vector2(28, 18), Vector2(-26, -24)]:
		var w := _local_to_world(v.x, v.z, rot, l.x, l.y)
		_add_house(B, w.x, w.y, rot + (-PI / 2 if l.x > 0 else PI / 2), v)
	v.placed = [Vector3(v.x, v.z, R + 12)]
	_add_mesh(B)


func _add_mesh(B: GeoBuilder) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = B.build()
	mi.material_override = building_material
	add_child(mi)


# ---------------- ALBERI ----------------
func _merge(parts: Array) -> ArrayMesh:
	var B := GeoBuilder.new()
	for part in parts:
		B.add(Prims.get_prim(part[0]), part[1], part[2], 0, -1e6)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = B.pos
	arrays[Mesh.ARRAY_NORMAL] = B.nor
	arrays[Mesh.ARRAY_COLOR] = B.col
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _M(x: float, y: float, z: float, sx: float, sy: float, sz: float) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3(sx, sy, sz)), Vector3(x, y, z))


func _build_trees() -> void:
	var trunk := U.lin(0.3, 0.2, 0.12)
	var pine := U.lin(0.12, 0.24, 0.11)
	var leaf := U.lin(0.24, 0.38, 0.13)
	var leaf2 := U.lin(0.3, 0.42, 0.15)
	var conifer := _merge([
		["cyl", _M(0, -1, 0, 0.35, 3.5, 0.35), trunk],
		["cone8", _M(0, 1.6, 0, 2.6, 4.6, 2.6), pine],
		["cone8", _M(0, 3.9, 0, 2.0, 3.9, 2.0), pine],
		["cone8", _M(0, 6.0, 0, 1.3, 3.2, 1.3), pine],
	])
	var broad := _merge([
		["cyl", _M(0, -1, 0, 0.42, 5, 0.42), trunk],
		["blob", _M(0, 5.2, 0, 3.0, 2.6, 3.0), leaf],
		["blob", _M(1.2, 6.6, 0.5, 2.0, 1.8, 2.0), leaf2],
		["blob", _M(-1.0, 6.2, -0.8, 2.0, 1.8, 2.0), leaf],
	])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	var max_each := 4200
	var counts := [0, 0]
	var exclusion := []
	for v in villages:
		for p in v.placed:
			exclusion.append(Vector3(p.x, p.y, p.z + 4))
	var xforms := [[], []]
	var colors := [[], []]
	var i := 0
	while i < 60000 and counts[0] + counts[1] < max_each * 2 - 2:
		i += 1
		var x := (rng.next() - 0.5) * TERRAIN_SIZE * 0.96
		var z := (rng.next() - 0.5) * TERRAIN_SIZE * 0.96
		var h := ground_height(x, z)
		if h < 4.5 or h > 210:
			continue
		var forest := forest_at(x, z)
		if forest < 0.05 and rng.next() > 0.07:
			continue
		if absf(ground_height(x + 5, z) - ground_height(x - 5, z)) + absf(ground_height(x, z + 5) - ground_height(x, z - 5)) > 9:
			continue
		var excluded := false
		for e in exclusion:
			if (x - e.x) * (x - e.x) + (z - e.y) * (z - e.y) < e.z * e.z:
				excluded = true
				break
		if not excluded:
			for v in villages:
				if v.kind == "village" and Vector2(x - v.x, z - v.z).length() < v.r * 0.7:
					excluded = true
					break
		if excluded:
			continue
		var type := 0 if (rng.next() < 0.85 if (h > 85 or forest > 0.28) else rng.next() < 0.25) else 1
		if counts[type] >= max_each:
			continue
		var s := 0.8 + rng.next() * 0.8
		var ry := rng.next() * 6.28
		var sy := s * (0.85 + rng.next() * 0.35)
		var idx: int = counts[type]
		counts[type] += 1
		xforms[type].append(Transform3D(Basis(Vector3.UP, ry) * Basis.from_scale(Vector3(s, sy, s)), Vector3(x, h, z)))
		var tint := 0.8 + rng.next() * 0.4
		colors[type].append(Color(tint, tint * (0.95 + rng.next() * 0.1), tint))
		var tree := {"x": x, "z": z, "y": h, "s": s, "type": type, "idx": idx, "charred": false}
		trees.append(tree)
		var key := floori(x / 40) * 100003 + floori(z / 40)
		if not tree_grid.has(key):
			tree_grid[key] = []
		tree_grid[key].append(tree)
	for t in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = conifer if t == 0 else broad
		mm.instance_count = counts[t]
		for k in counts[t]:
			mm.set_instance_transform(k, xforms[t][k])
			mm.set_instance_color(k, colors[t][k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		add_child(mmi)
		tree_meshes.append(mm)


func char_trees(x: float, z: float, r: float, max_n := 30) -> Array:
	var out := []
	var col := Color(0.06, 0.05, 0.045)
	for gx in range(floori((x - r) / 40), floori((x + r) / 40) + 1):
		for gz in range(floori((z - r) / 40), floori((z + r) / 40) + 1):
			var list = tree_grid.get(gx * 100003 + gz)
			if list == null:
				continue
			for t in list:
				if t.charred or (t.x - x) * (t.x - x) + (t.z - z) * (t.z - z) > r * r:
					continue
				t.charred = true
				tree_meshes[t.type].set_instance_color(t.idx, col)
				if tree_fires.size() < 260:
					tree_fires.append({"x": t.x, "y": t.y + 5 * t.s, "z": t.z, "t": 0.0, "s": t.s, "acc": 0.0, "sacc": 0.0})
				out.append(t)
				if out.size() >= max_n:
					return out
	return out


# ---------------- INCENDI ----------------
func building_at(x: float, y: float, z: float) -> Building:
	var list = grid.get(floori(x / 32) * 100003 + floori(z / 32))
	if list == null:
		return null
	for b in list:
		if y > b.top + 1 or y < b.base - 3:
			continue
		for c in b.circles:
			if (x - c.x) * (x - c.x) + (z - c.y) * (z - c.y) < c.z * c.z:
				return b
	return null


func buildings_near(x: float, z: float, r: float) -> Array[Building]:
	var out: Array[Building] = []
	for gx in range(floori((x - r) / 32), floori((x + r) / 32) + 1):
		for gz in range(floori((z - r) / 32), floori((z + r) / 32) + 1):
			var list = grid.get(gx * 100003 + gz)
			if list == null:
				continue
			for b in list:
				if out.has(b):
					continue
				if (b.x - x) * (b.x - x) + (b.z - z) * (b.z - z) < (r + b.size) * (r + b.size):
					out.append(b)
	return out


func ignite(b: Building, delay := 0.0) -> bool:
	if b == null or b.inert or b.state != 0:
		return false
	b.state = 1
	b.t = -delay
	burning.append(b)
	return true


func update(dt: float, t_now: float, cam_pos: Vector3) -> void:
	time = t_now
	building_material.set_shader_parameter("u_time", t_now)
	terrain_material.set_shader_parameter("u_time", t_now)
	var dirty := false
	var burning_count := 0
	for i in range(burning.size() - 1, -1, -1):
		var b := burning[i]
		b.t += dt
		if b.t < 0:
			continue
		var t := b.t
		if t < 3:
			b.fire = t / 3
		elif t < 32:
			b.fire = 1
		elif t < 48:
			b.fire = lerpf(1, 0.15, (t - 32) / 16)
		elif t < 95:
			b.fire = 0.15 * (1 - (t - 48) / 47)
		else:
			b.fire = 0
		b.charred = minf(1, t / 24)
		b.collapse = U.smooth(16, 30, t)
		if b.fire > 0.15:
			burning_count += 1
		if b.state == 1 and t > 22:
			b.state = 2
			stats.destroyed += 1
		if t > 95:
			burning.remove_at(i)
			b.fire = 0
		dirty = true
		_write_burn(b)

		# propagazione alle case vicine
		if b.fire > 0.6 and randf() < dt * 0.22:
			for n in buildings_near(b.x, b.z, 18):
				if n.state == 0 and randf() < 0.5:
					ignite(n)

		# emissione di fiamme e fumo
		var dist := Vector2(b.x - cam_pos.x, b.z - cam_pos.z).length()
		var top := lerpf(b.top, b.base + (b.top - b.base) * 0.4, b.collapse)
		if dist < 2200 and b.fire > 0.02:
			var lod := 1.0 if dist < 900 else 0.35
			b.emit_acc += dt * b.fire * (10 + b.size * 4.5) * lod
			while b.emit_acc >= 1:
				b.emit_acc -= 1
				var c: Vector3 = b.circles[randi() % b.circles.size()]
				var a := randf() * TAU
				var rr := sqrt(randf()) * c.z * 0.8
				var y := lerpf(b.base + 1, top, 0.35 + randf() * 0.65)
				var s := (3 + randf() * 4) * (0.7 + b.size * 0.06) * (1.0 if dist < 900 else 2.0)
				fx.fire.spawn(Vector3(c.x + cos(a) * rr, y, c.y + sin(a) * rr),
					Vector3((randf() - 0.5) * 3 + 2, 7 + randf() * 8, (randf() - 0.5) * 3 + 1),
					0.8 + randf() * 0.8, s * 0.8, s * 1.5, 1)
			if randf() < dt * b.fire * 3 * lod:
				fx.embers.spawn(Vector3(b.x + (randf() - 0.5) * b.size, top, b.z + (randf() - 0.5) * b.size),
					Vector3((randf() - 0.5) * 8, 10 + randf() * 15, (randf() - 0.5) * 8), 2 + randf() * 2, 0.5, 0.3, 2)
		if dist < 4500 and t > 0.5:
			var smoke_rate := (b.fire * 3.5 + (0.6 if b.charred > 0.5 else 0.0)) * (1.0 if dist < 1500 else 0.4)
			b.smoke_acc += dt * smoke_rate
			while b.smoke_acc >= 1:
				b.smoke_acc -= 1
				var big := 1.0 if dist < 1500 else 2.2
				fx.smoke.spawn(Vector3(b.x + (randf() - 0.5) * b.size, top + 2, b.z + (randf() - 0.5) * b.size),
					Vector3(3 + randf() * 2, 9 + randf() * 6, 1.5 + randf() * 2),
					7 + randf() * 4, (6 + b.size * 0.5) * big, (35 + b.size * 2) * big, 0)
	stats.burning = burning_count

	# alberi in fiamme
	for i in range(tree_fires.size() - 1, -1, -1):
		var f = tree_fires[i]
		f.t += dt
		if f.t > 16:
			tree_fires.remove_at(i)
			continue
		if Vector2(f.x - cam_pos.x, f.z - cam_pos.z).length() > 2000:
			continue
		var k: float = f.t if f.t < 1 else (1.0 if f.t < 7 else maxf(0, 1 - (f.t - 7) / 4))
		f.acc += dt * 14 * k
		while f.acc >= 1:
			f.acc -= 1
			fx.fire.spawn(Vector3(f.x + (randf() - 0.5) * 4 * f.s, f.y - 3 + randf() * 5, f.z + (randf() - 0.5) * 4 * f.s),
				Vector3((randf() - 0.5) * 2, 6 + randf() * 6, (randf() - 0.5) * 2), 0.6 + randf() * 0.6, 3 * f.s, 5 * f.s, 1)
		f.sacc += dt * (k * 1.5 + 0.3)
		while f.sacc >= 1:
			f.sacc -= 1
			fx.smoke.spawn(Vector3(f.x, f.y + 3, f.z), Vector3(2 + randf() * 2, 7 + randf() * 4, 1 + randf()), 6, 5, 22, 0)

	if dirty:
		burn_tex.update(burn_image)


# Stato dell'incendio letto dallo shader: R carbonizzato, G fuoco, B crollo
func _write_burn(b: Building) -> void:
	if b.id < BURN_TEX_SIZE:
		burn_image.set_pixel(b.id, 0, Color(b.charred, clampf(b.fire, 0, 1), b.collapse, 1))


# Edifici in fiamme più vicini (per le luci dinamiche)
func nearest_fires(pos: Vector3, n: int) -> Array:
	var list := []
	for b in burning:
		if b.fire < 0.25:
			continue
		list.append([(b.x - pos.x) * (b.x - pos.x) + (b.z - pos.z) * (b.z - pos.z), b])
	list.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	for k in mini(n, list.size()):
		out.append(list[k][1])
	return out
