# Fortezza di Monte Nero: anelli di mura e torri che seguono le curve di livello della vetta più alta, dalla costa
# fino al mastio sulla cima. È lei il nemico: dorme finché non la attacchi, poi cannoni, trabucchi, balestre su
# ruote, arcieri, sifoni di fuoco greco e la torre arcana del mastio bersagliano il drago. Ogni postazione si
# distrugge col fuoco (o incendiando la sua torre); quando non ne resta nessuna, la fortezza cade.
class_name Fortress
extends Node3D

const TITLE := "Fortezza di Monte Nero"
# anelli di mura: quota rispetto alla vetta, distanza tra le torri e armi a rotazione ("" = torre di guardia)
const RINGS := [
	{"level": 0.8, "spacing": 55.0, "arms": ["trebuchet", "cannon"]},
	{"level": 0.58, "spacing": 70.0, "arms": ["cannon", "ballista", "cannon", "trebuchet"]},
	{"level": 0.36, "spacing": 85.0, "arms": ["ballista", "archers", "", "cannon", "archers", ""]},
	{"level": 0.16, "spacing": 100.0, "arms": ["archers", "greek", "", "ballista", "greek", ""]},
]
# vita, gittata (m), ricarica (s), velocità e gravità del proiettile, rotazione (rad/s), imprecisione (rad)
const ARMS := {
	"cannon": {"down": "Cannone distrutto!", "name": "Cannone", "hp": 60.0, "range": 900.0, "reload": 6.0, "speed": 240.0, "grav": 18.0, "turn": 1.2, "spread": 0.012},
	"trebuchet": {"down": "Trabucco distrutto!", "name": "Trabucco", "hp": 90.0, "range": 1150.0, "reload": 10.0, "speed": 150.0, "grav": 22.0, "turn": 0.6, "spread": 0.02},
	"ballista": {"down": "Balestra distrutta!", "name": "Balestra su ruote", "hp": 45.0, "range": 760.0, "reload": 4.0, "speed": 330.0, "grav": 6.0, "turn": 1.8, "spread": 0.008},
	"archers": {"down": "Arcieri sbaragliati!", "name": "Arcieri", "hp": 35.0, "range": 420.0, "reload": 3.5, "speed": 190.0, "grav": 14.0, "turn": 3.0, "spread": 0.05},
	"greek": {"down": "Sifone di fuoco greco distrutto!", "name": "Fuoco greco", "hp": 50.0, "range": 140.0, "reload": 3.0, "speed": 0.0, "grav": 0.0, "turn": 1.6, "spread": 0.0},
	"arcane": {"down": "La torre arcana si spegne!", "name": "Torre arcana", "hp": 160.0, "range": 1100.0, "reload": 5.0, "speed": 85.0, "grav": 0.0, "turn": 9.0, "spread": 0.0},
}
# proiettili: raggio, danno diretto, raggio e dimensione dell'esplosione
const SHOTS := {
	"ball": {"r": 0.9, "dmg": 12.0, "splash": 16.0, "boom": 0.35},
	"boulder": {"r": 2.2, "dmg": 20.0, "splash": 26.0, "boom": 0.6},
	"bolt": {"r": 0.6, "dmg": 10.0, "splash": 0.0, "boom": 0.0},
	"arrow": {"r": 0.4, "dmg": 2.0, "splash": 0.0, "boom": 0.0},
	"orb": {"r": 1.6, "dmg": 11.0, "splash": 12.0, "boom": 0.3},
}
const CALM_DIST := 2600.0 # oltre questa distanza dalla vetta la fortezza, dopo un po', torna a vegliare
const CALM_TIME := 45.0
const IRON := Color(0.035, 0.035, 0.04)
const BRONZE := Color(0.32, 0.18, 0.07)
const CLOTH := Color(0.3, 0.05, 0.04)
const ARM_SCALE := 1.6 # le armi sono più grandi del vero, per leggerle da lontano

var world: World
var fx: FX
var hud: HUD
var audio: GameAudio
var on_player_damage := Callable() # (danno)
var built := false
var center := Vector3.ZERO # vetta
var radius := 0.0
var home := {} # come un villaggio: nome ed edifici
var weapons: Array = []
var projectiles: Array = []
var awake := false
var fallen := false
var calm_t := 0.0
var near := false
var rng: Mulberry32
var crystal: MeshInstance3D
var crystal_y := 0.0
var keep_ids: Array = []
var collapse_booms: Array = []
var shot_meshes := {}
var shot_mats := {}


# ---------------- COSTRUZIONE ----------------
func build(w: World) -> void:
	world = w
	center = _find_peak()
	home = {"x": center.x, "z": center.z, "h": center.y, "r": 0.0, "kind": "fortress", "name": TITLE, "ids": [], "placed": []}
	rng = Mulberry32.new(7331)
	# le torri e le case della fortezza usano un generatore a parte: il resto del mondo non cambia
	var saved := world.rng
	world.rng = rng
	var B := World.GeoBuilder.new()
	var placed: Array = [Vector3(center.x, center.z, 42)]
	_build_keep(B)
	for k in RINGS.size():
		_build_ring(B, k, placed)
	_build_barracks(B, placed)
	world._add_mesh(B)
	world.rng = saved
	for p in placed:
		radius = maxf(radius, Vector2(p.x - center.x, p.y - center.z).length() + p.z)
	home.r = radius
	home.placed = placed
	_make_shot_meshes()
	built = true
	print("Fortezza: vetta (%d, %d) a %d m, %d postazioni, %d edifici" % [center.x, center.z, center.y, weapons.size(), home.ids.size()])


# La vetta più alta lontana dai villaggi
func _find_peak() -> Vector3:
	var cands := []
	for j in range(4, World.N - 4, 3):
		for i in range(4, World.N - 4, 3):
			var h := world.hgrid[j * World.N + i]
			if h > 150:
				cands.append(Vector3(i, h, j))
	cands.sort_custom(func(a, b): return a.y > b.y)
	var pick: Vector3 = cands[0]
	for c in cands:
		var x: float = -World.HALF + c.x * World.STEP
		var z: float = -World.HALF + c.z * World.STEP
		var ok := true
		for v in world.villages:
			if Vector2(v.x - x, v.z - z).length() < v.r + 520:
				ok = false
				break
		if ok:
			pick = c
			break
	# rifinitura sul punto più alto dei dintorni
	var bi := int(pick.x)
	var bj := int(pick.z)
	for j in range(int(pick.z) - 3, int(pick.z) + 4):
		for i in range(int(pick.x) - 3, int(pick.x) + 4):
			if world.hgrid[j * World.N + i] > world.hgrid[bj * World.N + bi]:
				bi = i
				bj = j
	var px := -World.HALF + bi * World.STEP
	var pz := -World.HALF + bj * World.STEP
	return Vector3(px, world.ground_height(px, pz), pz)


# Curva di livello attorno alla vetta: per ogni direzione, la distanza a cui il terreno scende sotto la quota
func _contour(level: float) -> PackedVector2Array:
	var rays := 72
	var rs := PackedFloat32Array()
	for a in rays:
		var ang := TAU * a / rays
		var r := 12.0
		while r < 720 and world.ground_height(center.x + cos(ang) * r, center.z + sin(ang) * r) > level:
			r += 4
		rs.append(r)
	var pts := PackedVector2Array()
	for a in rays:
		var r := (rs[(a + rays - 1) % rays] + 2 * rs[a] + rs[(a + 1) % rays]) / 4
		pts.append(Vector2(center.x + cos(TAU * a / rays) * r, center.z + sin(TAU * a / rays) * r))
	return pts


func _site_ok(p: Vector2, placed: Array, gap: float) -> bool:
	if world.ground_height(p.x, p.y) < 6:
		return false
	# niente torri su pareti a strapiombo: le fondamenta diventerebbero pilastri altissimi
	var gr := world._ground_range(p.x, p.y, 0, 9, 9)
	if gr.y - gr.x > 70:
		return false
	for v in world.villages:
		if Vector2(v.x - p.x, v.z - p.y).length() < v.r + 60:
			return false
	for q in placed:
		if Vector2(q.x - p.x, q.y - p.y).length() < q.z + gap:
			return false
	return true


func _build_ring(B: World.GeoBuilder, k: int, placed: Array) -> void:
	var ring: Dictionary = RINGS[k]
	var pts := _contour(center.y * ring.level)
	var cand: Array = [0]
	var acc := 0.0
	for i in range(1, pts.size()):
		acc += pts[i].distance_to(pts[i - 1])
		if acc >= ring.spacing:
			cand.append(i)
			acc = 0.0
	var built_at: Array = []
	var arm_i := 0
	for ci in cand:
		# se il punto è su uno strapiombo prova quelli vicini lungo la curva
		var p = null
		for o in [0, 1, -1, 2, -2]:
			var q: Vector2 = pts[(ci + o + pts.size()) % pts.size()]
			if _site_ok(q, placed, 22):
				p = q
				break
		if p == null:
			built_at.append(null)
			continue
		var arm: String = ring.arms[arm_i % ring.arms.size()]
		arm_i += 1
		if arm == "":
			world._add_tower(B, p.x, p.y, home, 6, 28 + rng.next() * 8, World.COLORS.castle_roof)
			placed.append(Vector3(p.x, p.y, 9))
		else:
			_gun_tower(B, p, arm, k)
			placed.append(Vector3(p.x, p.y, 13))
		built_at.append(p)
	for i in built_at.size():
		var a = built_at[i]
		var b = built_at[(i + 1) % built_at.size()]
		if a != null and b != null and a.distance_to(b) < 170:
			_rugged_wall(B, a, b)


# Muro a gradoni che segue il terreno (come la Grande Muraglia); salta mare e dirupi
func _rugged_wall(B: World.GeoBuilder, a: Vector2, b: Vector2) -> void:
	var dir := (b - a).normalized()
	var a2 := a + dir * 9
	var b2 := b - dir * 9
	var length := a2.distance_to(b2)
	if length < 8:
		return
	var n := ceili(length / 8.0)
	var seg := length / n
	var rot := atan2(dir.x, dir.y)
	var circles := []
	var ranges := []
	var gmin := INF
	var gmax := -INF
	for i in n:
		var c := a2.lerp(b2, (i + 0.5) / n)
		var lo := INF
		var hi := -INF
		for t in [-0.5, 0.0, 0.5]:
			var g := world.ground_height(c.x + dir.x * seg * t, c.y + dir.y * seg * t)
			lo = minf(lo, g)
			hi = maxf(hi, g)
		ranges.append(Vector2(lo, hi))
		circles.append(Vector3(c.x, c.y, 5.5))
		gmin = minf(gmin, lo)
		gmax = maxf(gmax, hi)
	var bld := world._new_building(circles, gmin, gmax + 21, home)
	var stone: Color = World.COLORS.stone
	var dark: Color = World.COLORS.stone_dark
	for i in n:
		var r: Vector2 = ranges[i]
		if r.y < 5 or r.y - r.x > 22:
			continue
		var c := a2.lerp(b2, (i + 0.5) / n)
		var P := World.PartMaker.new(B, world._frame(c.x, c.y, rot), bld.id, gmin, rng)
		var top := r.y + 18
		P.p("box", 0, r.x - 8, 0, 6, top - r.x + 8, seg + 0.3, 0, stone)
		P.p("box", 0, top - 1.2, 0, 6.8, 1.0, seg + 0.3, 0, dark) # cornice del camminamento
		for m in int(seg / 3.4):
			var s := -seg / 2 + 1.7 + m * 3.4
			P.p("box", 2.4, top, s, 1.2, 2.4, 1.8, 0, stone)
			P.p("box", -2.4, top, s, 1.2, 2.4, 1.8, 0, stone)


# Bastione (quadrato per le armi pesanti, tondo per le altre) con l'arma sulla piattaforma
func _gun_tower(B: World.GeoBuilder, p: Vector2, arm: String, ring_k: int) -> void:
	var square := arm == "trebuchet" or arm == "cannon"
	var r := 11.0 if arm == "trebuchet" else (9.0 if square else 7.5)
	var rot := atan2(p.x - center.x, p.y - center.z)
	var gr := world._ground_range(p.x, p.y, rot, r, r)
	var top := gr.y + (24.0 if ring_k > 0 else 18.0) + rng.next() * 6
	var b := world._new_building([Vector3(p.x, p.y, r + 1)], gr.y, top + 4, home)
	var P := World.PartMaker.new(B, world._frame(p.x, p.y, rot), b.id, gr.y, rng)
	var dark: Color = World.COLORS.stone_dark
	var stone: Color = World.COLORS.stone
	if square:
		P.p("box", 0, gr.x - 8, 0, 2 * r, top - gr.x + 8, 2 * r, 0, stone)
		P.p("box", 0, gr.x - 8, 0, 2 * r + 3, gr.y - gr.x + 12, 2 * r + 3, 0, dark) # scarpa alla base
		P.p("box", 0, top - 0.9, 0, 2 * r + 1.2, 1.0, 2 * r + 1.2, 0, dark)
		var m := -r + 0.8
		while m < r - 0.4:
			for e in [Vector3(m, 0, r), Vector3(m, 0, -r), Vector3(r, 0, m), Vector3(-r, 0, m)]:
				P.p("box", e.x, top, e.z, 1.6, 2.2, 1.6, 0, stone)
			m += 3.2
	else:
		P.p("prism", 0, gr.x - 8, 0, r, top - gr.x + 8, r, 0, stone)
		P.p("prism", 0, gr.x - 8, 0, r + 1.5, gr.y - gr.x + 12, r + 1.5, 0, dark)
		P.p("cyl", 0, top - 0.9, 0, r + 0.8, 1.0, r + 0.8, 0, dark)
		for k in 12:
			var a := k * TAU / 12
			P.p("box", sin(a) * (r + 0.1), top, cos(a) * (r + 0.1), 1.6, 2.2, 1.6, a, stone)
	# feritoie (si accendono quando la torre brucia)
	for f in 2:
		for k in 4:
			var a := k * PI / 2 + 0.4 + f * 0.8
			P.p("box", sin(a) * r * 0.98, top - 7 - f * 8, cos(a) * r * 0.98, 0.8, 2.6, 0.8, a, World.COLORS.window, 1)
	_make_weapon(arm, Vector3(p.x, top + 0.3, p.y), b, rot)


# Mastio sulla vetta: basamento, torre a più piani con torrette e guglia della torre arcana
func _build_keep(B: World.GeoBuilder) -> void:
	var x := center.x
	var z := center.z
	var rot := rng.next() * PI / 2
	var gr := world._ground_range(x, z, rot, 28, 28)
	var y0 := center.y + 8
	var dark: Color = World.COLORS.stone_dark
	var stone: Color = World.COLORS.stone
	var roof: Color = World.COLORS.castle_roof
	# basamento con le armi agli angoli
	var circles := []
	for q in [Vector2(-14, -14), Vector2(14, -14), Vector2(14, 14), Vector2(-14, 14)]:
		var wq := world._local_to_world(x, z, rot, q.x, q.y)
		circles.append(Vector3(wq.x, wq.y, 20))
	var podium := world._new_building(circles, gr.y, y0 + 3, home)
	var P := World.PartMaker.new(B, world._frame(x, z, rot), podium.id, gr.y, rng)
	P.p("box", 0, gr.x - 10, 0, 56, y0 - gr.x + 10, 56, 0, stone)
	P.p("box", 0, gr.x - 10, 0, 60, minf(gr.y + 6, y0 - 4) - gr.x + 10, 60, 0, dark)
	P.p("box", 0, y0 - 1, 0, 57.5, 1.2, 57.5, 0, dark)
	var m := -27.0
	while m < 27.5:
		for e in [Vector3(m, 0, 28), Vector3(m, 0, -28), Vector3(28, 0, m), Vector3(-28, 0, m)]:
			if absf(e.x) < 19 or absf(e.z) < 19:
				P.p("box", e.x, y0, e.z, 1.8, 2.4, 1.8, 0, stone)
		m += 3.4
	# torre principale con torrette agli angoli
	var tower := world._new_building([Vector3(x, z, 21)], y0, y0 + 60, home)
	var T := World.PartMaker.new(B, world._frame(x, z, rot), tower.id, y0, rng)
	T.p("box", 0, y0, 0, 34, 44, 34, 0, stone)
	T.p("box", 0, y0 + 43, 0, 35.6, 1.2, 35.6, 0, dark)
	for s in range(-15, 16, 3):
		for e in [Vector3(s, 0, 17.2), Vector3(s, 0, -17.2), Vector3(17.2, 0, s), Vector3(-17.2, 0, s)]:
			T.p("box", e.x, y0 + 44, e.z, 1.6, 2.4, 1.6, 0, stone)
	for c in [Vector2(17, 17), Vector2(-17, 17), Vector2(17, -17), Vector2(-17, -17)]:
		T.p("prism", c.x, y0, c.y, 5, 56, 5, 0, stone)
		T.p("cyl", c.x, y0 + 55, c.y, 5.8, 1.2, 5.8, 0, dark)
		T.p("cone", c.x, y0 + 56, c.y, 6.6, 15, 6.6, 0, roof)
	for f in 4:
		for s in [-9.0, 0.0, 9.0]:
			var y := y0 + 7 + f * 9
			T.p("box", s, y, 17, 1.6, 3.4, 0.4, 0, World.COLORS.window, 1)
			T.p("box", s, y, -17, 1.6, 3.4, 0.4, 0, World.COLORS.window, 1)
			T.p("box", 17, y, s, 0.4, 3.4, 1.6, 0, World.COLORS.window, 1)
			T.p("box", -17, y, s, 0.4, 3.4, 1.6, 0, World.COLORS.window, 1)
	# guglia della torre arcana
	var spire := world._new_building([Vector3(x, z, 9)], y0 + 44, y0 + 80, home)
	var S := World.PartMaker.new(B, world._frame(x, z, rot), spire.id, y0 + 44, rng)
	S.p("prism", 0, y0 + 44, 0, 8, 30, 8, 0, stone)
	S.p("cyl", 0, y0 + 73, 0, 9.2, 1.2, 9.2, 0, dark)
	for k in 14:
		var a := k * TAU / 14
		S.p("box", sin(a) * 8.6, y0 + 74, cos(a) * 8.6, 1.4, 2.0, 1.4, a, stone)
	for k in 4:
		var a := k * PI / 2 + PI / 4
		S.pt("box", Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -0.25) * Basis.from_scale(Vector3(1.0, 11, 1.0)), Vector3(sin(a) * 6.5, y0 + 74, cos(a) * 6.5)), IRON, 0, 6) # artigli che reggono il cristallo
	keep_ids = [podium.id, tower.id, spire.id]
	var corner := ["cannon", "ballista", "cannon", "ballista"]
	for k in 4:
		var q: Vector2 = [Vector2(23, 23), Vector2(-23, 23), Vector2(-23, -23), Vector2(23, -23)][k]
		var wq := world._local_to_world(x, z, rot, q.x, q.y)
		_make_weapon(corner[k], Vector3(wq.x, y0 + 0.3, wq.y), podium, atan2(wq.x - x, wq.y - z))
	_make_weapon("arcane", Vector3(x, y0 + 84, z), spire, 0)


# Caserme e magazzini sui pochi ripiani della montagna
func _build_barracks(B: World.GeoBuilder, placed: Array) -> void:
	var count := 0
	for i in 400:
		if count >= 10:
			break
		var a := rng.next() * TAU
		var r := 60 + rng.next() * radius_guess()
		var x := center.x + cos(a) * r
		var z := center.z + sin(a) * r
		var g := world.ground_height(x, z)
		if g < center.y * 0.3 or g > center.y * 0.85 or world.flatness(x, z, 7) > 5:
			continue
		if not _site_ok(Vector2(x, z), placed, 12):
			continue
		var hr := world._add_house(B, x, z, atan2(center.x - x, center.z - z), home, rng.next() < 0.5)
		placed.append(Vector3(x, z, hr))
		count += 1


func radius_guess() -> float:
	return 380.0


# ---------------- ARMI ----------------
func _make_weapon(type: String, pos: Vector3, b: World.Building, face: float) -> void:
	var t: Dictionary = ARMS[type]
	var root := Node3D.new()
	root.position = pos
	if type != "arcane":
		root.scale = Vector3.ONE * ARM_SCALE
	add_child(root)
	var yaw_n := Node3D.new()
	yaw_n.rotation.y = face
	root.add_child(yaw_n)
	var pitch_n := Node3D.new()
	yaw_n.add_child(pitch_n)
	var w := {"type": type, "arm": t, "pos": pos, "b": b, "hp": t.hp, "alive": true, "cd": 1.5 + randf() * t.reload,
		"root": root, "yaw_n": yaw_n, "pitch_n": pitch_n, "muzzle": Vector3.ZERO, "muzzle_on_yaw": false,
		"swing": -1.0, "recoil": 0.0, "burst": 0.0, "lead": 1.0, "acc": {}, "pending": null}
	var Yb := World.GeoBuilder.new()
	var Pb := World.GeoBuilder.new()
	var Y := World.PartMaker.new(Yb, Transform3D.IDENTITY, b.id, 0, null)
	var Pp := World.PartMaker.new(Pb, Transform3D.IDENTITY, b.id, 0, null)
	match type:
		"cannon":
			_cannon(Y, Pp, w)
		"trebuchet":
			_trebuchet(Y, Pp, w)
		"ballista":
			_ballista(Y, Pp, w)
		"archers":
			_archers(Y, w)
		"greek":
			_greek(Y, Pp, w)
		"arcane":
			_arcane(w)
	for pair in [[Yb, yaw_n], [Pb, pitch_n]]:
		var gb: World.GeoBuilder = pair[0]
		if gb.pos.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = gb.build()
		mi.material_override = world.building_material
		mi.visibility_range_end = 2600
		pair[1].add_child(mi)
	weapons.append(w)


static func _tube(P: World.PartMaker, x: float, y: float, z0: float, r: float, length: float, col: Color) -> void:
	P.pt("cyl", Transform3D(Basis(Vector3.RIGHT, PI / 2) * Basis.from_scale(Vector3(r, length, r)), Vector3(x, y, z0)), col, 0, 6)


static func _wheel(P: World.PartMaker, x: float, y: float, z: float, r: float, thick: float) -> void:
	P.pt("cyl", Transform3D(Basis(Vector3.BACK, -PI / 2) * Basis.from_scale(Vector3(r, thick, r)), Vector3(x - thick / 2, y, z)), World.COLORS.timber)
	P.pt("cyl", Transform3D(Basis(Vector3.BACK, -PI / 2) * Basis.from_scale(Vector3(r * 0.25, thick + 0.2, r * 0.25)), Vector3(x - thick / 2 - 0.1, y, z)), IRON, 0, 6)


func _cannon(Y: World.PartMaker, Pp: World.PartMaker, w: Dictionary) -> void:
	var wood: Color = World.COLORS.timber
	for s in [-1, 1]:
		Y.p("box", s * 0.95, 0.5, -0.4, 0.45, 1.5, 4.0, 0, wood) # guance dell'affusto
		_wheel(Y, s * 1.45, 1.0, 0.6, 1.0, 0.35)
	Y.p("box", 0, 0.85, 0.6, 2.9, 0.3, 0.3, 0, IRON, 0, 6) # assale
	Y.p("box", 0, 0.1, -2.9, 0.8, 0.4, 2.2, 0, wood) # coda
	w.pitch_n.position = Vector3(0, 2.0, 0.4)
	_tube(Pp, 0, 0, -1.7, 0.55, 5.4, IRON)
	_tube(Pp, 0, 0, 3.2, 0.68, 0.45, IRON) # bocca
	_tube(Pp, 0, 0, -0.2, 0.64, 0.3, IRON)
	_tube(Pp, 0, 0, 1.4, 0.62, 0.3, IRON)
	Pp.p("blob", 0, 0, -1.75, 0.6, 0.6, 0.6, 0, IRON, 0, 6)
	w.muzzle = Vector3(0, 0, 3.9)


# Trabucco: il braccio (pitch_n) è armato all'indietro e scatta in avanti quando tira
func _trebuchet(Y: World.PartMaker, Pp: World.PartMaker, w: Dictionary) -> void:
	var wood: Color = World.COLORS.timber
	for s in [-1, 1]:
		Y.p("box", s * 2.4, 0, 0, 0.7, 0.7, 9, 0, wood)
		Y.p("box", s * 2.0, 0, 0, 0.6, 8.6, 0.6, 0, wood)
		Y.pt("box", Transform3D(Basis(Vector3.RIGHT, 0.42) * Basis.from_scale(Vector3(0.45, 8.8, 0.45)), Vector3(s * 2.0, 0.3, -3.5)), wood)
		Y.pt("box", Transform3D(Basis(Vector3.RIGHT, -0.42) * Basis.from_scale(Vector3(0.45, 8.8, 0.45)), Vector3(s * 2.0, 0.3, 3.5)), wood)
	for zz in [-4.0, 0.0, 4.0]:
		Y.p("box", 0, 0.05, zz, 5.4, 0.55, 0.7, 0, wood)
	Y.p("box", 0, 8.3, 0, 4.8, 0.45, 0.45, 0, IRON, 0, 6) # perno
	w.pitch_n.position = Vector3(0, 8.5, 0)
	w.pitch_n.rotation.x = 2.29
	Pp.p("box", 0, -0.28, 3, 0.55, 0.55, 14, 0, wood) # braccio
	Pp.p("box", 0, -3.4, -4, 2.6, 2.6, 2.6, 0, World.COLORS.door, 0, 4) # contrappeso
	Pp.p("box", 0, -2.2, -4, 2.7, 0.3, 2.7, 0, IRON, 0, 6)
	Pp.p("box", 0, -0.5, 10, 0.9, 0.6, 1.1, 0, World.COLORS.door, 0, 4) # fionda
	w.muzzle = Vector3(0, 16.5, 6)
	w.muzzle_on_yaw = true


func _ballista(Y: World.PartMaker, Pp: World.PartMaker, w: Dictionary) -> void:
	var wood: Color = World.COLORS.timber
	Y.p("box", 0, 1.0, 0, 3.0, 0.5, 4.6, 0, wood) # carro
	for s in [-1, 1]:
		for zz in [-1.5, 1.5]:
			_wheel(Y, s * 1.75, 0.8, zz, 0.8, 0.3)
	Y.p("box", 0, 1.5, 0, 0.7, 1.6, 0.7, 0, wood)
	w.pitch_n.position = Vector3(0, 3.3, 0)
	Pp.p("box", 0, -0.25, 0.75, 0.55, 0.5, 6.5, 0, wood) # fusto
	for s in [-1, 1]:
		var a: float = s * 1.9
		var d := Vector3(sin(a), 0, cos(a))
		Pp.pt("box", Transform3D(Basis(Vector3.UP, a) * Basis.from_scale(Vector3(0.32, 0.32, 3.0)), Vector3(0, -0.16, 3.6) + d * 1.5), wood) # archi
		Pp.p("cyl", s * 0.5, -0.6, 3.6, 0.35, 1.2, 0.35, 0, BRONZE, 0, 6) # matasse di torsione
	Pp.p("box", 0, -0.04, 2.65, 5.6, 0.08, 0.08, 0, Color(0.6, 0.55, 0.45)) # corda
	Pp.p("box", 0, 0.25, 2.2, 0.16, 0.16, 4.0, 0, World.COLORS.door) # dardo
	Pp.p("cone", 0, 0.25, 4.2, 0.22, 0.6, 0.22, 0, IRON, 0, 6)
	w.muzzle = Vector3(0, 0.3, 4.3)


func _archers(Y: World.PartMaker, w: Dictionary) -> void:
	for i in 5:
		var x := (i - 2) * 1.4
		var z := 0.6 - absf(i - 2) * 0.4
		Y.p("cyl", x, 0, z, 0.38, 1.5, 0.38, 0, CLOTH)
		Y.p("blob", x, 1.8, z, 0.3, 0.3, 0.3, 0, Color(0.55, 0.4, 0.3))
		Y.p("cone", x, 1.92, z, 0.34, 0.4, 0.34, 0, IRON, 0, 6)
		Y.p("box", x + 0.35, 0.6, z + 0.4, 0.08, 1.7, 0.08, 0.2, World.COLORS.timber)
	Y.p("cyl", 0, 0, -1.6, 0.6, 0.7, 0.6, 0, IRON, 0, 6) # braciere per le frecce incendiarie
	w.muzzle = Vector3(0, 2.0, 1.0)
	w.muzzle_on_yaw = true


func _greek(Y: World.PartMaker, Pp: World.PartMaker, w: Dictionary) -> void:
	Y.p("box", 0, 0, -1.6, 2.2, 1.0, 2.2, 0, World.COLORS.stone_dark) # fornace
	Y.p("cyl", 0, 1.0, -1.6, 1.1, 2.0, 1.1, 0, BRONZE, 0, 6) # serbatoio
	Y.p("box", 1.7, 0.3, -1.6, 1.0, 0.5, 1.6, 0, World.COLORS.timber) # mantice
	w.pitch_n.position = Vector3(0, 1.9, -0.6)
	_tube(Pp, 0, 0, 0, 0.28, 4.4, BRONZE)
	Pp.p("blob", 0, 0, 4.5, 0.45, 0.45, 0.6, 0, BRONZE, 0, 6) # bocca a testa di drago
	w.muzzle = Vector3(0, 0, 4.9)


# Torre arcana: un cristallo che fluttua sopra la guglia e lancia sfere a ricerca
func _arcane(w: Dictionary) -> void:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.radius = 1
	mesh.height = 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.1, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.2, 1)
	mat.emission_energy_multiplier = 4
	mat.roughness = 0.1
	mat.metallic = 0.5
	crystal = MeshInstance3D.new()
	crystal.mesh = mesh
	crystal.material_override = mat
	crystal.scale = Vector3(2.2, 4.5, 2.2)
	w.root.add_child(crystal)
	var light := OmniLight3D.new()
	light.light_color = Color(0.7, 0.35, 1)
	light.light_energy = 6
	light.omni_range = 90
	w.root.add_child(light)
	w.light = light
	w.muzzle = Vector3.ZERO


func _muzzle(w: Dictionary) -> Vector3:
	var n: Node3D = w.yaw_n if w.muzzle_on_yaw else w.pitch_n
	return n.global_transform * w.muzzle


# ---------------- PROIETTILI ----------------
func _make_shot_meshes() -> void:
	var ball := SphereMesh.new()
	ball.radius = 1
	ball.height = 2
	ball.radial_segments = 12
	ball.rings = 6
	var stick := BoxMesh.new()
	stick.size = Vector3(1, 1, 1)
	shot_meshes = {"ball": ball, "boulder": ball, "orb": ball, "bolt": stick, "arrow": stick}
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.05, 0.05, 0.055)
	iron.metallic = 0.8
	iron.roughness = 0.35
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.3, 0.27, 0.24)
	rock.roughness = 0.95
	rock.emission_enabled = true
	rock.emission = Color(1, 0.4, 0.1)
	rock.emission_energy_multiplier = 0.6
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.25, 0.16, 0.09)
	var orb := StandardMaterial3D.new()
	orb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb.albedo_color = Color(0.85, 0.5, 1)
	orb.emission_enabled = true
	orb.emission = Color(0.7, 0.3, 1)
	orb.emission_energy_multiplier = 6
	shot_mats = {"ball": iron, "boulder": rock, "bolt": wood, "arrow": wood, "orb": orb}


func _spawn(kind: String, pos: Vector3, vel: Vector3, grav: float) -> void:
	var s: Dictionary = SHOTS[kind]
	var mi := MeshInstance3D.new()
	mi.mesh = shot_meshes[kind]
	mi.material_override = shot_mats[kind]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	match kind:
		"bolt":
			mi.scale = Vector3(0.25, 0.25, 4.5)
		"arrow":
			mi.scale = Vector3(0.12, 0.12, 2.2)
		_:
			mi.scale = Vector3.ONE * s.r
	add_child(mi)
	projectiles.append({"kind": kind, "mi": mi, "vel": vel, "grav": grav, "t": 0.0, "acc": 0.0, "shot": s, "sc": mi.scale})


# Angolo di tiro per colpire un punto (traiettoria bassa o alta) e tempo di volo; x = INF se fuori portata
static func _solve(from: Vector3, to: Vector3, v: float, g: float, high: bool) -> Vector2:
	var dx := Vector2(to.x - from.x, to.z - from.z).length()
	var dy := to.y - from.y
	if g < 0.01:
		return Vector2(atan2(dy, dx), Vector2(dx, dy).length() / v)
	var v2 := v * v
	var disc := v2 * v2 - g * (g * dx * dx + 2 * dy * v2)
	if disc < 0 or dx < 1:
		return Vector2(INF, 0)
	var s := sqrt(disc)
	var ang := atan((v2 + s) / (g * dx)) if high else atan((v2 - s) / (g * dx))
	return Vector2(ang, dx / (v * cos(ang)))


# Il terreno nasconde il bersaglio?
func _los(a: Vector3, b: Vector3) -> bool:
	for k in range(1, 10):
		var p := a.lerp(b, k / 10.0)
		if world.ground_height(p.x, p.z) > p.y + 2:
			return false
	return true


# ---------------- COMPORTAMENTO ----------------
func setup(f: FX, h: HUD, a: GameAudio) -> void:
	fx = f
	hud = h
	audio = a


func owns(b: World.Building) -> bool:
	return b != null and is_same(b.village, home)


# Il punto è dentro una torre o un muro della fortezza? (niente alberi lì)
func covers(x: float, z: float) -> bool:
	var list = world.grid.get(floori(x / 32) * 100003 + floori(z / 32))
	if list == null:
		return false
	for b in list:
		if is_same(b.village, home):
			for c in b.circles:
				if (x - c.x) * (x - c.x) + (z - c.y) * (z - c.y) < (c.z + 3) * (c.z + 3):
					return true
	return false


func alive_count() -> int:
	var n := 0
	for w in weapons:
		if w.alive:
			n += 1
	return n


func awaken(reason: String) -> void:
	calm_t = 0
	if awake or fallen or not built:
		return
	awake = true
	hud.show_msg("La %s si risveglia!" % TITLE, "bad")
	if reason == "fire":
		hud.show_msg("Hai dato fuoco alle sue mura", "small")
	audio.shot("horn", 0, 1.2)


func damage(w: Dictionary, amount: float) -> void:
	if not w.alive:
		return
	w.hp -= amount
	awaken("attack")
	if w.hp <= 0:
		_destroy(w)


# Danno ad area (esplosioni del giocatore)
func splash(pos: Vector3, r: float, amount: float) -> void:
	for w in weapons:
		var d: float = w.pos.distance_to(pos)
		if w.alive and d < r:
			damage(w, amount * (1 - d / r * 0.6))


# Soffio del giocatore sulle postazioni
func breath_hit(mouth: Vector3, dir: Vector3, dt: float) -> void:
	for w in weapons:
		if w.alive and Enemies.in_breath(mouth, dir, w.pos + Vector3(0, 3, 0), 7):
			damage(w, 34 * dt)


# Bersaglio per la mira assistita: la postazione più vicina davanti al giocatore
func target(player: Dragon, max_dist := 450.0, cone := 0.45):
	var best = null
	var best_d := INF
	for w in weapons:
		if not w.alive:
			continue
		var to: Vector3 = w.pos - player.position
		var d := to.length()
		if d > max_dist or d < 1 or (to / d).dot(player.forward) < cos(cone):
			continue
		if d < best_d:
			best = w
			best_d = d
	return best


func _destroy(w: Dictionary, explode := true) -> void:
	w.alive = false
	w.burst = 0.0
	if explode:
		fx.explode(w.pos + Vector3(0, 2, 0), 0.7, "fortress")
	world.ignite(w.b)
	# l'arma rovesciata resta sulla torre e brucia con lei
	w.yaw_n.rotation.z = (randf() - 0.5) * 0.9
	w.yaw_n.rotation.x = (randf() - 0.5) * 0.5
	if w.has("light"):
		w.light.visible = false
		crystal.visible = false
	hud.show_msg(w.arm.down, "small")
	if alive_count() == 0:
		_fall()


func _fall() -> void:
	fallen = true
	awake = false
	hud.show_msg("La %s è caduta!" % TITLE)
	for id in keep_ids:
		world.ignite(world.buildings[id], randf() * 2)
	for k in 8:
		collapse_booms.append({"t": 0.4 + k * 0.55, "pos": center + Vector3((randf() - 0.5) * 30, 8 + randf() * 40, (randf() - 0.5) * 30)})


func update_fortress(dt: float, player: Dragon, player_alive: bool, cam_pos: Vector3) -> void:
	if not built:
		return
	var P := player.position
	var dist := Vector2(P.x - center.x, P.z - center.z).length()
	for w in weapons:
		# la torre in fiamme mette fuori uso la sua arma
		if w.alive and w.b.state != 0 and w.b.fire > 0.5:
			_destroy(w, false)
	if awake:
		calm_t = calm_t + dt if dist > CALM_DIST else 0.0
		if calm_t > CALM_TIME:
			awake = false
			calm_t = 0
			hud.show_msg("La %s torna a vegliare" % TITLE, "small")
	for w in weapons:
		if w.alive:
			_animate(w, dt)
			if awake and player_alive:
				_aim_and_fire(w, dt, player, cam_pos)
	_update_projectiles(dt, player, player_alive, cam_pos)
	for i in range(collapse_booms.size() - 1, -1, -1):
		var c: Dictionary = collapse_booms[i]
		c.t -= dt
		if c.t <= 0:
			fx.explode(c.pos, 1.2, "fortress")
			collapse_booms.remove_at(i)
	if crystal != null and crystal.visible:
		crystal.rotation.y += dt * 0.8
		crystal.position.y = sin(Time.get_ticks_msec() * 0.0015) * 1.2
	# barra della fortezza quando è vicina o sveglia
	var show := (dist < radius + 900 or awake) and not fallen
	var n := alive_count()
	hud.set_boss(show, TITLE, ("ALL'ATTACCO · " if awake else "dormiente · ") + "%d / %d postazioni" % [n, weapons.size()],
		float(n) / maxi(1, weapons.size()), awake)


func _animate(w: Dictionary, dt: float) -> void:
	w.recoil = maxf(0, w.recoil - dt * 2.5)
	if w.type == "cannon":
		w.pitch_n.position.z = 0.4 - w.recoil * 0.8
	elif w.type == "trebuchet" and w.swing >= 0:
		# scatto del braccio in 0,6 s, poi lenta ricarica
		w.swing += dt
		var th := 2.29
		if w.swing < 0.6:
			th = lerpf(2.29, 5.36, pow(w.swing / 0.6, 2))
		else:
			th = lerpf(5.36, 2.29 + TAU, minf((w.swing - 0.6) / 4.0, 1))
			if w.swing > 4.6:
				w.swing = -1.0
		w.pitch_n.rotation.x = th
	if w.pending != null:
		w.pending.t -= dt
		if w.pending.t <= 0:
			_spawn(w.pending.kind, _muzzle(w), w.pending.vel, w.pending.grav)
			w.pending = null


func _aim_and_fire(w: Dictionary, dt: float, player: Dragon, cam_pos: Vector3) -> void:
	var t: Dictionary = w.arm
	w.cd -= dt
	var muzzle := _muzzle(w)
	var P := player.position
	var d := Vector2(P.x - muzzle.x, P.z - muzzle.z).length()
	if d > t.range:
		return
	var high: bool = w.type == "trebuchet"
	# previsione: dove sarà il drago quando arriva il colpo (con un errore diverso a ogni tiro)
	var aim := P
	var sol := Vector2(atan2(P.y - muzzle.y, d), 0)
	if t.speed > 0:
		for it in 2:
			sol = _solve(muzzle, aim, t.speed, t.grav, high)
			if sol.x == INF:
				return
			aim = P + player.velocity * sol.y * w.lead
	var yaw_t := atan2(aim.x - muzzle.x, aim.z - muzzle.z)
	var yaw_n: Node3D = w.yaw_n
	var err := wrapf(yaw_t - yaw_n.global_rotation.y, -PI, PI)
	if w.type != "arcane":
		yaw_n.rotation.y += clampf(err, -t.turn * dt, t.turn * dt)
		if w.type in ["cannon", "ballista", "greek"]:
			w.pitch_n.rotation.x = move_toward(w.pitch_n.rotation.x, -clampf(sol.x, -0.6, 1.1), dt)
	var dist_cam := muzzle.distance_to(cam_pos)
	if w.type == "greek":
		_greek_fire(w, dt, muzzle, P, absf(err) < 0.1 and d < t.range)
		return
	if absf(err) > 0.05 and w.type != "arcane" or w.cd > 0:
		return
	if not high and not _los(muzzle, P):
		return
	w.cd = t.reload * (0.8 + randf() * 0.4)
	w.lead = 0.7 + randf() * 0.45
	var dir := Vector3(sin(yaw_t) * cos(sol.x), sin(sol.x), cos(yaw_t) * cos(sol.x))
	dir = (dir + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2 * t.spread).normalized()
	match w.type:
		"cannon":
			_spawn("ball", muzzle, dir * t.speed, t.grav)
			w.recoil = 1.0
			for k in 10:
				fx.smoke.spawn(muzzle + dir * 2, dir * (8 + randf() * 10) + Vector3(randf() - 0.5, randf(), randf() - 0.5) * 5, 2.5 + randf(), 3, 12, 0)
				fx.fire.spawn(muzzle + dir, dir * (20 + randf() * 20), 0.15 + randf() * 0.1, 1.5, 3, 2)
			audio.shot("cannon", dist_cam)
		"trebuchet":
			w.swing = 0.0
			w.pending = {"t": 0.4, "kind": "boulder", "vel": dir * t.speed, "grav": t.grav}
			audio.shot("twang", dist_cam, 0.8, 0.6)
		"ballista":
			_spawn("bolt", muzzle, dir * t.speed, t.grav)
			audio.shot("twang", dist_cam, 0.7)
		"archers":
			for k in 7:
				var a := dir + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.12
				var off: Vector3 = w.yaw_n.global_basis * Vector3((k - 3) * 0.9, 0, 0)
				_spawn("arrow", muzzle + off, a.normalized() * t.speed * (0.95 + randf() * 0.1), t.grav)
			audio.shot("whoosh", dist_cam, 0.6, 1.6)
		"arcane":
			_spawn("orb", muzzle + Vector3(0, -3, 0), (P - muzzle).normalized() * t.speed, 0)
			audio.shot("magic", dist_cam, 1.2)


# Sifone di fuoco greco: raffiche di fiamme a corto raggio
func _greek_fire(w: Dictionary, dt: float, muzzle: Vector3, P: Vector3, ready_to_fire: bool) -> void:
	if w.burst <= 0 and w.cd <= 0 and ready_to_fire:
		w.burst = 1.6
		w.cd = w.arm.reload
	if w.burst <= 0:
		return
	w.burst -= dt
	var dir: Vector3 = (w.pitch_n.global_basis * Vector3(0, 0, 1)).normalized()
	fx.emit_breath(dt, muzzle, dir, Vector3.ZERO, 0.55, w.acc, 0)
	if Enemies.in_breath(muzzle, dir, P, 9, 150) and on_player_damage.is_valid():
		on_player_damage.call(16 * dt)


func _update_projectiles(dt: float, player: Dragon, player_alive: bool, cam_pos: Vector3) -> void:
	var P := player.position
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		var mi: MeshInstance3D = p.mi
		p.t += dt
		if p.kind == "orb":
			# sfera a ricerca: piega verso il drago, ma lentamente
			var want := (P - mi.position).normalized()
			p.vel = p.vel.normalized().slerp(want, minf(1, 1.1 * dt)) * p.vel.length()
		else:
			p.vel.y -= p.grav * dt
		var pos: Vector3 = mi.position + p.vel * dt
		mi.position = pos
		if (p.kind == "bolt" or p.kind == "arrow") and absf(p.vel.normalized().y) < 0.99:
			mi.basis = Basis.looking_at(p.vel.normalized(), Vector3.UP, true) * Basis.from_scale(p.sc)
		# scie
		p.acc += dt * (40.0 if p.kind == "boulder" else 25.0)
		while p.acc >= 1:
			p.acc -= 1
			match p.kind:
				"ball":
					fx.smoke.spawn(pos, Vector3.ZERO, 0.8, 1, 3, 0)
				"boulder":
					fx.fire.spawn(pos + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 3, p.vel * 0.2, 0.4, 2.5, 5, 2)
					if randf() < 0.3:
						fx.smoke.spawn(pos, Vector3(0, 2, 0), 2, 3, 9, 0)
				"arrow":
					if randf() < 0.3:
						fx.fire.spawn(pos, p.vel * 0.1, 0.25, 0.6, 1.2, 2)
				"orb":
					fx.embers.spawn(pos, Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 6, 0.6, 1.2, 0.5, 0)
		var s: Dictionary = p.shot
		var hit: bool = player_alive and pos.distance_to(P) < 7 + s.r
		var g := world.ground_height(pos.x, pos.z)
		var boom: bool = hit or pos.y < maxf(g, 0.3) + s.r * 0.5 or (p.t > 0.35 and world.building_at(pos.x, pos.y, pos.z) != null)
		if p.t > (9.0 if p.kind == "orb" else 14.0):
			mi.queue_free()
			projectiles.remove_at(i)
			continue
		if not boom:
			continue
		if hit and on_player_damage.is_valid():
			on_player_damage.call(s.dmg)
		if s.boom > 0:
			fx.explode(pos, s.boom, "fortress", false)
			if not hit and player_alive and s.splash > 0 and pos.distance_to(P) < s.splash and on_player_damage.is_valid():
				on_player_damage.call(s.dmg * 0.6 * (1 - pos.distance_to(P) / s.splash))
		else:
			for k in 6:
				fx.embers.spawn(pos, Vector3(randf() - 0.5, randf(), randf() - 0.5) * 12, 0.5, 0.5, 0.3, 0)
		mi.queue_free()
		projectiles.remove_at(i)
