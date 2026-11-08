# Tana del drago protagonista: la vetta più alta del mondo, sull'isola a nord-est senza villaggi. In cima uno spiazzo
# largo e piano per atterrare, con i nidi e le uova (alcune già schiuse), e una grotta gigante scavata nella roccia:
# dentro è buia, il soffio di fuoco accende le lanterne che poi restano accese; tra le pareti ossa, carri, relitti di
# navi e in fondo un immenso tesoro.
# Il terreno a griglia non può avere volte, quindi la cima con la grotta è una mesh: due ellissoidi (parete interna
# ed esterna) deformati dallo stesso rumore usato per le collisioni di drago, fiamme e camera, con la bocca ritagliata
# verso ovest (il sole del pomeriggio non entra). Ha un generatore casuale proprio: il resto del mondo non cambia.
class_name Lair
extends Node3D

const PEAK := Vector2(2330, 2300)
const MOUTH_DIR := Vector2(-0.906, 0.423) # verso cui si apre la bocca
const FLOOR := 780.0 # quota dello spiazzo e del pavimento della grotta
const A := 150.0 # semiassi dell'interno: lungo l'asse, in altezza, in larghezza
const H := 88.0
const W := 100.0
const K := 1.3 # guscio esterno rispetto a quello interno
const PLATEAU_R := 125.0
const SUMMIT_H := 1350.0 # vetta del massiccio, alle spalle della grotta
const STREAM_BOX := 2600.0 # lato del quadrato della maschera del ruscello per il terreno
const MOUTH_W := 58.0 # semilarghezza e altezza della bocca
const MOUTH_H := 52.0
const NT := 180 # suddivisioni del guscio: attorno, in altezza e nella gonna che scende nel monte
const NP := 54
const NS := 6
const PH0 := -0.22
const S := 2.0 # le lanterne sono a misura di drago
const LANTERN_ENERGY := 16.0
const LANTERN_RANGE := 58.0
const SHADOWED := 4 # lanterne accese più vicine alla camera che proiettano ombre
const DARK := Color(0.012, 0.011, 0.012) # luce ambiente nella grotta: spenta e con tutte le lanterne accese
const WARM := Color(0.2, 0.12, 0.07)

# materiali (CUSTOM0.x, vedi shaders/lair.gdshader)
const ROCK := 0
const WOOD := 1
const PLANKS := 2
const BONE := 3
const GOLD := 4
const IRON := 5
const GEM := 6
const EGG := 7
const STRAW := 8
const CLOTH := 9
const SILVER := 10
const GLASS := 11
const SHELL_IN := 12
const HOARD := 13 # superficie dei cumuli di monete: oro opaco, non uno specchio

# cumuli d'oro del tesoro: x, z (sistema della grotta), raggio, altezza
const HEAPS := [Vector4(100, 0, 30, 13), Vector4(118, -32, 14, 6), Vector4(112, 34, 15, 7),
	Vector4(76, -24, 11, 4), Vector4(78, 27, 10, 4.5), Vector4(128, 6, 12, 8)]

static var C := {
	"rock": U.lin(0.62, 0.6, 0.57),
	"bone": U.lin(0.86, 0.81, 0.7),
	"gold": Color(1.0, 0.64, 0.22),
	"silver": Color(0.8, 0.8, 0.83),
	"iron": U.lin(0.24, 0.23, 0.22),
	"wood": U.lin(0.5, 0.42, 0.33),
	"planks": U.lin(0.56, 0.47, 0.37),
	"straw": U.lin(0.56, 0.46, 0.3),
	"sail": U.lin(0.62, 0.57, 0.47),
	"shell_in": U.lin(0.86, 0.8, 0.68),
	"eggs": [U.lin(0.58, 0.14, 0.09), U.lin(0.22, 0.4, 0.24), U.lin(0.6, 0.42, 0.2), U.lin(0.34, 0.2, 0.46), U.lin(0.18, 0.3, 0.5)],
	"gems": [Color(0.8, 0.02, 0.05), Color(0.02, 0.6, 0.16), Color(0.04, 0.14, 0.85), Color(0.45, 0.06, 0.75), Color(0.9, 0.75, 0.1)],
	"paint": [U.lin(0.55, 0.12, 0.1), U.lin(0.15, 0.25, 0.5), U.lin(0.2, 0.4, 0.22)],
}

var axis: Vector2 # verso l'interno della grotta
var side: Vector2
var cc: Vector3 # centro del pavimento della grotta
var pc: Vector2 # centro dello spiazzo
var summit: Vector2
var stream := PackedVector3Array() # percorso del ruscello (y: pelo dell'acqua)
var falls: Array = [] # piedi delle cascate: da lì sale la nebbiolina
var frame: Transform3D # sistema della grotta: x verso il fondo, y in alto, z di lato
var inv: Transform3D
var n_in := _noise(11, 4)
var n_out := _noise(23, 3)
var rng := Mulberry32.new(4242)
var world: World
var material: ShaderMaterial
var water_material: ShaderMaterial
var lit_image: Image
var lit_tex: ImageTexture
var lanterns: Array = []
var probe: ReflectionProbe
var lit_count := 0
var on_lit := Callable() # (accese, totale)

# buffer del guscio in costruzione
var _pos := PackedVector3Array()
var _nacc := PackedVector3Array()
var _idx := PackedInt32Array()


func _init() -> void:
	axis = -MOUTH_DIR.normalized()
	side = Vector2(-axis.y, axis.x)
	cc = Vector3(PEAK.x + axis.x * 130.0, FLOOR, PEAK.y + axis.y * 130.0)
	pc = PEAK - axis * 90.0
	summit = Vector2(cc.x, cc.z) + axis * 330.0
	var x := Vector3(axis.x, 0, axis.y)
	frame = Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), cc)
	inv = frame.affine_inverse()


static func _noise(s: int, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 1.0
	n.fractal_octaves = octaves
	return n


# ---------------- FORMA ----------------
# Le pareti in una direzione d (normalizzata sui semiassi): distanza dal centro, 1 = ellissoide medio
func r_in(d: Vector3) -> float:
	return 1.0 + n_in.get_noise_3dv(d * 1.7) * 0.26


func r_out(d: Vector3) -> float:
	var r := K * (1.0 + n_out.get_noise_3dv(d * 1.4) * 0.3)
	# creste e spuntoni verso l'alto: è la cima del monte
	r += maxf(d.y, 0.0) * maxf(0.0, n_out.get_noise_3dv(d * 3.1 + Vector3(5, 0, 0))) * 0.35
	return maxf(r, r_in(d) + 0.2)


static func _ell(d: Vector3) -> Vector3:
	return Vector3(d.x * A, d.y * H, d.z * W)


static func _dir(th: float, ph: float) -> Vector3:
	return Vector3(cos(ph) * cos(th), sin(ph), cos(ph) * sin(th))


# Punto (sistema della grotta) dentro il profilo della bocca: arco sul lato verso lo spiazzo
static func _mouth_local(p: Vector3) -> bool:
	if p.x >= 0.0:
		return false
	var y := maxf(p.y, 0.0)
	return (p.z / MOUTH_W) * (p.z / MOUTH_W) + (y / MOUTH_H) * (y / MOUTH_H) < 1.0


func _mouth(d: Vector3) -> bool:
	return _mouth_local(_ell(d) * r_in(d))


# ---------------- COLLISIONI ----------------
func near(p: Vector3, extra := 0.0) -> bool:
	return absf(p.x - cc.x) < 330.0 + extra and absf(p.z - cc.z) < 330.0 + extra and p.y > FLOOR - 30.0 and p.y < FLOOR + 280.0 + extra


# Roccia del guscio (sotto il pavimento decide il terreno)
func solid(p: Vector3) -> bool:
	if not near(p):
		return false
	var q := inv * p
	if q.y < 0.0:
		return false
	var qn := Vector3(q.x / A, q.y / H, q.z / W)
	var L := qn.length()
	if L < 0.7 or L > K * 2.2:
		return false
	var d := qn / L
	return L > r_in(d) and L < r_out(d) and not _mouth(d)


# Dentro la grotta (aria tra il pavimento e la volta, bocca compresa)
func inside(p: Vector3) -> bool:
	if not near(p):
		return false
	var q := inv * p
	if q.y < -4.0:
		return false
	var qn := Vector3(q.x / A, q.y / H, q.z / W)
	var L := qn.length()
	return L < 0.7 or (L < 1.4 and L < r_in(qn / L))


# Spinge fuori dalla roccia un punto (drago, camera) lasciando margin metri dalla parete
func push_out(p: Vector3, margin: float) -> Vector3:
	if not near(p, margin):
		return p
	var q := inv * p
	if q.y < 0.0:
		return p
	var qn := Vector3(q.x / A, q.y / H, q.z / W)
	var L := qn.length()
	if L < 0.6 or L > K * 2.2:
		return p
	var d := qn / L
	if _mouth(d):
		return p
	var m := margin / _ell(d).length()
	var ri := r_in(d)
	var ro := r_out(d)
	if L <= ri - m or L >= ro + m:
		return p
	return frame * (_ell(d) * (ri - m if L < (ri + ro) * 0.5 else ro + m))


# La camera non entra nella roccia: si ferma prima, lungo il segmento dal drago
func clip_segment(from: Vector3, to: Vector3) -> Vector3:
	if not near(from, 120.0) and not near(to, 120.0):
		return to
	var len := from.distance_to(to)
	var n := int(ceil(len / 2.0))
	for k in range(1, n + 1):
		if solid(from.lerp(to, float(k) / n)):
			return from.lerp(to, maxf(0.0, (float(k - 1) / n * len - 1.5) / len))
	return to


# Pilota automatico in grotta: se poco più avanti c'è roccia vira verso il centro e scende o sale.
# Restituisce (sterzata, salita) da sommare ai comandi; zero fuori dalla grotta.
func avoid(p: Vector3, fwd: Vector3, yaw: float) -> Vector2:
	if not inside(p):
		return Vector2.ZERO
	var hit := false
	for dist in [16.0, 32.0, 48.0]:
		if solid(p + fwd * dist):
			hit = true
			break
	if not hit:
		return Vector2.ZERO
	var target := cc + Vector3(0, 35, 0)
	var dyaw := atan2(target.x - p.x, target.z - p.z) - yaw
	dyaw = atan2(sin(dyaw), cos(dyaw))
	var q := inv * (p + fwd * 32.0)
	var climb := -0.8 if q.y > H * 0.55 else (0.6 if q.y < 14.0 else 0.0)
	return Vector2(-clampf(dyaw * 2.0, -1.0, 1.0), climb)


# Quanto è buio dove sta la camera: 0 fuori, quasi 1 in fondo alla grotta
func darkness(p: Vector3) -> float:
	if not inside(p):
		return 0.0
	var depth := Vector2(p.x - cc.x, p.z - cc.z).dot(axis) + A
	return smoothstep(-10.0, 95.0, depth) * 0.975


# Fuoco vicino: accende le lanterne entro r metri
func heat(p: Vector3, r: float) -> void:
	if lit_count == lanterns.size() or not near(p, r):
		return
	for l in lanterns:
		if not l.lit and l.pos.distance_squared_to(p) < (r + 4.0) * (r + 4.0):
			l.lit = true
			l.t = 0.0
			l.light.visible = true
			lit_image.set_pixel(l.idx, 0, Color(1, 0, 0))
			lit_tex.update(lit_image)
			lit_count += 1
			# il riverbero delle lanterne sulle pareti schiarisce un po' tutta la grotta
			probe.ambient_color = DARK.lerp(WARM, float(lit_count) / lanterns.size())
			# la fiamma prende con uno sbuffo di scintille
			if world.fx != null:
				for i in 24:
					world.fx.embers.spawn(l.pos, Vector3(randf() - 0.5, randf() * 0.8, randf() - 0.5) * 14.0, 0.8 + randf() * 0.6, 0.6, 0.3, 0)
				world.fx.audio.crackle()
			if on_lit.is_valid():
				on_lit.call(lit_count, lanterns.size())


# Ghiaccio vicino: spegne le lanterne entro r metri (con uno sbuffo di vapore)
func chill(p: Vector3, r: float) -> void:
	if lit_count == 0 or not near(p, r):
		return
	for l in lanterns:
		if l.lit and l.pos.distance_squared_to(p) < (r + 4.0) * (r + 4.0):
			l.lit = false
			l.light.visible = false
			l.light.light_energy = 0.0
			lit_image.set_pixel(l.idx, 0, Color(0, 0, 0))
			lit_tex.update(lit_image)
			lit_count -= 1
			probe.ambient_color = DARK.lerp(WARM, float(lit_count) / lanterns.size())
			if world.fx != null:
				world.fx._steam(l.pos, 6)
			if on_lit.is_valid():
				on_lit.call(lit_count, lanterns.size())


func update_lair(dt: float, t: float, cam: Vector3) -> void:
	material.set_shader_parameter("u_time", t)
	if water_material != null:
		water_material.set_shader_parameter("u_time", t)
	# nebbiolina ai piedi delle cascate
	if world.fx != null:
		for f in falls:
			if f.pos.distance_to(cam) < 700.0:
				f.acc += dt * 5.0 * f.k
				while f.acc >= 1.0:
					f.acc -= 1.0
					world.fx.smoke.spawn(f.pos + Vector3((randf() - 0.5) * 6, 1, (randf() - 0.5) * 6),
						Vector3((randf() - 0.5) * 3, 2 + randf() * 3, (randf() - 0.5) * 3), 2.0 + randf(), 3, 11, 1)
	if lit_count == 0:
		return
	var close := cam.distance_to(cc) < 750.0
	var lit := []
	for l in lanterns:
		if not l.lit:
			continue
		l.t += dt
		var fl: float = 0.84 + 0.1 * sin(t * 9.0 + l.ph) + 0.06 * sin(t * 23.0 + l.ph * 3.0)
		l.light.light_energy = LANTERN_ENERGY * l.big * smoothstep(0.0, 0.8, l.t) * fl
		l.light.visible = close
		lit.append(l)
	if close:
		lit.sort_custom(func(a, b): return a.pos.distance_squared_to(cam) < b.pos.distance_squared_to(cam))
		for k in lit.size():
			lit[k].light.shadow_enabled = k < SHADOWED


# ---------------- TERRENO ----------------
# Il massiccio: una vetta principale alle spalle della grotta (verso est), creste e canaloni, un rilievo che
# avvolge la grotta e le fa da cornice di pareti a picco ai lati della bocca, e due piani a FLOOR (spiazzo e
# pavimento della grotta). Lo spiazzo è un balcone: verso ovest il monte precipita. Poi un ruscello parte da
# sotto la vetta e scende fino al mare scavandosi il letto. Si chiama dopo aver piantato gli alberi, così il
# resto del bosco non cambia.
func shape_terrain(w: World) -> void:
	var m := _noise(37, 4)
	var hg := w.hgrid
	var dd := w.data
	var reach := 1250.0
	var i0 := maxi(0, int((summit.x - reach + World.HALF) / World.STEP))
	var i1 := mini(World.N - 1, int((summit.x + reach + World.HALF) / World.STEP) + 1)
	var j0 := maxi(0, int((summit.y - reach + World.HALF) / World.STEP))
	var j1 := mini(World.N - 1, int((summit.y + reach + World.HALF) / World.STEP) + 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var x := -World.HALF + i * World.STEP
			var z := -World.HALF + j * World.STEP
			var fd := _footprint_dist(x, z)
			var pd := _plateau_dist(x, z, m)
			var h := _massif(x, z, m)
			# spiazzo e pavimento della grotta piani; attorno il monte sale ripido verso la vetta oppure scende
			# con un pendio di roccia fin dove incontra il resto del massiccio
			var d := minf(fd, pd)
			if d <= 0.0:
				h = FLOOR
			else:
				# sotto lo spiazzo un pendio di roccia irregolare, con speroni e canaloni
				var gully := (1.0 - absf(m.get_noise_2d(x * 0.009 + 70.0, z * 0.009))) - 0.6
				var drop := d * (1.5 + 0.6 * m.get_noise_2d(x * 0.004, z * 0.004)) - gully * minf(d, 120.0) * 0.9
				h = clampf(h, FLOOR - drop, FLOOR + d * 3.0)
			var k := j * World.N + i
			if h > hg[k] or fd < 60.0 or pd < 60.0:
				hg[k] = h
	_carve_stream(hg)
	for k in hg.size():
		dd[k * 3] = hg[k]
	w.hgrid = hg
	w.data = dd
	w.data_tex.update(Image.create_from_data(World.N, World.N, false, Image.FORMAT_RGBF, dd.to_byte_array()))


func _massif(x: float, z: float, m: FastNoiseLite) -> float:
	var p := Vector2(x, z)
	var ang := atan2(z - summit.y, x - summit.x)
	var reach := 920.0 + 170.0 * m.get_noise_2d(cos(ang) * 1.8, sin(ang) * 1.8)
	var h := SUMMIT_H * pow(maxf(0.0, 1.0 - p.distance_to(summit) / reach), 1.25)
	var dc := p.distance_to(Vector2(cc.x, cc.z)) / 360.0
	h += 430.0 * pow(maxf(0.0, 1.0 - dc * dc), 2.0)
	# creste e canaloni (rumore "ridged"), più marcati in quota, e scabrosità fine
	var ridge := 1.0 - absf(m.get_noise_2d(x * 0.0045, z * 0.0045))
	var ridge2 := 1.0 - absf(m.get_noise_2d(x * 0.012 + 50.0, z * 0.012))
	h += ((ridge - 0.6) * 330.0 + (ridge2 - 0.6) * 90.0) * clampf(h / 700.0, 0.15, 1.0)
	h += m.get_noise_2d(x * 0.03, z * 0.03) * 18.0
	return h - 45.0


# Metri fuori dall'impronta della grotta (negativi dentro), con un margine oltre la parete interna
func _footprint_dist(x: float, z: float) -> float:
	var q := Vector2(x - cc.x, z - cc.z)
	var ea := A * 1.15 + 18.0
	var ew := W * 1.15 + 18.0
	return (Vector2(q.dot(axis) / ea, q.dot(side) / ew).length() - 1.0) * ew


# Metri fuori dallo spiazzo, dal contorno un po' irregolare
func _plateau_dist(x: float, z: float, m: FastNoiseLite) -> float:
	var ang := atan2(z - pc.y, x - pc.x)
	return Vector2(x, z).distance_to(pc) - (PLATEAU_R + 22.0 * m.get_noise_2d(cos(ang) * 1.5 + 9.0, sin(ang) * 1.5))


static func _grid_h(hg: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x + World.HALF) / World.STEP, 0.0, World.N - 1.001)
	var fz := clampf((z + World.HALF) / World.STEP, 0.0, World.N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var k := j * World.N + i
	var a := lerpf(hg[k], hg[k + 1], fx - i)
	var b := lerpf(hg[k + World.N], hg[k + World.N + 1], fx - i)
	return lerpf(a, b, fz - j)


# Il ruscello: nasce sotto la vetta e cerca la strada più comoda fino al mare (Dijkstra sulla griglia: ogni metro
# di risalita costa molto, così segue le valli ed esce dalle conche dal valico più basso, scavandosi una gola),
# lontano da grotta e spiazzo. Poi il letto viene inciso nella griglia.
func _carve_stream(hg: PackedFloat32Array) -> void:
	var reach := 1250.0
	var i0 := maxi(1, int((summit.x - reach + World.HALF) / World.STEP))
	var i1 := mini(World.N - 2, int((summit.x + reach + World.HALF) / World.STEP))
	var j0 := maxi(1, int((summit.y - reach + World.HALF) / World.STEP))
	var j1 := mini(World.N - 2, int((summit.y + reach + World.HALF) / World.STEP))
	var w := i1 - i0 + 1
	var hgt := j1 - j0 + 1
	var cost := PackedFloat32Array()
	cost.resize(w * hgt)
	cost.fill(INF)
	var from := PackedInt32Array()
	from.resize(w * hgt)
	from.fill(-1)
	var blocked := PackedByteArray()
	blocked.resize(w * hgt)
	# quanto un punto sta più in alto dei dintorni: l'acqua evita i dossi e cerca i canaloni
	var bump := PackedFloat32Array()
	bump.resize(w * hgt)
	for j in hgt:
		for i in w:
			var x := -World.HALF + (i + i0) * World.STEP
			var z := -World.HALF + (j + j0) * World.STEP
			if _footprint_dist(x, z) < 70.0 or Vector2(x, z).distance_to(pc) < PLATEAU_R + 60.0:
				blocked[j * w + i] = 1
			var gk := (j + j0) * World.N + i + i0
			var around := 0.0
			for d in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3), Vector2i(2, 2), Vector2i(-2, 2), Vector2i(2, -2), Vector2i(-2, -2)]:
				var ai := clampi(i + i0 + d.x, 0, World.N - 1)
				var aj := clampi(j + j0 + d.y, 0, World.N - 1)
				around += hg[aj * World.N + ai]
			bump[j * w + i] = maxf(0.0, hg[gk] - around / 8.0)
	var src := summit - side * 150.0 + axis * 40.0
	var si := clampi(int(round((src.x + World.HALF) / World.STEP)) - i0, 0, w - 1)
	var sj := clampi(int(round((src.y + World.HALF) / World.STEP)) - j0, 0, hgt - 1)
	var start := sj * w + si
	cost[start] = 0.0
	# coda con priorità (heap binario di [costo, nodo])
	var hk := PackedFloat32Array([0.0])
	var hn := PackedInt32Array([start])
	var goal := -1
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
	while hk.size() > 0:
		var c := hk[0]
		var node := hn[0]
		var last := hk.size() - 1
		hk[0] = hk[last]
		hn[0] = hn[last]
		hk.resize(last)
		hn.resize(last)
		var k := 0
		while true:
			var l := k * 2 + 1
			if l >= hk.size():
				break
			var r := l + 1
			var m := r if r < hk.size() and hk[r] < hk[l] else l
			if hk[m] >= hk[k]:
				break
			var tk := hk[k]
			hk[k] = hk[m]
			hk[m] = tk
			var tn := hn[k]
			hn[k] = hn[m]
			hn[m] = tn
			k = m
		if c > cost[node]:
			continue
		var ni := node % w
		var nj := node / w
		var h0 := hg[(nj + j0) * World.N + ni + i0]
		if h0 < -1.5:
			goal = node
			break
		for d: Vector2i in dirs:
			var ai := ni + d.x
			var aj := nj + d.y
			if ai < 0 or aj < 0 or ai >= w or aj >= hgt:
				continue
			var a := aj * w + ai
			if blocked[a]:
				continue
			var h1 := hg[(aj + j0) * World.N + ai + i0]
			var nc := c + (1.414 if d.x != 0 and d.y != 0 else 1.0) * (1.0 + bump[a] * 0.35) + maxf(0.0, h1 - h0) * 3.0
			if nc < cost[a]:
				cost[a] = nc
				from[a] = node
				# risale nell'heap
				var q := hk.size()
				hk.append(nc)
				hn.append(a)
				while q > 0:
					var pq := (q - 1) / 2
					if hk[pq] <= hk[q]:
						break
					var tk := hk[pq]
					hk[pq] = hk[q]
					hk[q] = tk
					var tn := hn[pq]
					hn[pq] = hn[q]
					hn[q] = tn
					q = pq
	stream = PackedVector3Array()
	if goal < 0:
		return
	var cells := []
	var node := goal
	while node >= 0:
		cells.push_front(node)
		node = from[node]
	# pelo dell'acqua sempre in discesa: dove il terreno risale la gola lo taglia
	var y := INF
	for cnode: int in cells:
		var x := -World.HALF + (cnode % w + i0) * World.STEP
		var z := -World.HALF + (cnode / w + j0) * World.STEP
		y = minf(y - 0.3, hg[(cnode / w + j0) * World.N + cnode % w + i0])
		stream.append(Vector3(x, y, z))
	# letto: i punti della griglia vicini scendono sotto il pelo dell'acqua, sfumando sulle sponde
	for p in stream:
		var gi := int(round((p.x + World.HALF) / World.STEP))
		var gj := int(round((p.z + World.HALF) / World.STEP))
		for j in range(gj - 2, gj + 3):
			for i in range(gi - 2, gi + 3):
				if i < 0 or j < 0 or i >= World.N or j >= World.N:
					continue
				var d := Vector2(-World.HALF + i * World.STEP - p.x, -World.HALF + j * World.STEP - p.z).length()
				var k := j * World.N + i
				var target := p.y - 1.8
				if hg[k] > target:
					hg[k] = lerpf(target, hg[k], smoothstep(8.0, 30.0, d))


# ---------------- RUSCELLO ----------------
# Nastro d'acqua adagiato sul letto scavato (corrente più veloce e schiuma dove scende ripido), la maschera che
# toglie al terreno il rilievo roccioso fine lungo il letto e i piedi delle cascate
func _build_stream() -> void:
	if stream.size() < 4:
		return
	var pts: Array = []
	for p in stream:
		pts.append(Vector2(p.x, p.z))
	for it in 3:
		var q: Array = [pts[0]]
		for i in pts.size() - 1:
			q.append(pts[i].lerp(pts[i + 1], 0.25))
			q.append(pts[i].lerp(pts[i + 1], 0.75))
		q.append(pts[pts.size() - 1])
		pts = q
	var n := pts.size()
	var ys := PackedFloat32Array()
	for p in pts:
		ys.append(world._catmull((p.x + World.HALF) / World.STEP, (p.y + World.HALF) / World.STEP) + 0.4)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var along := 0.0
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_c := Color()
	var prev_v := 0.0
	var steep_run := 0.0
	for i in n:
		var a: Vector2 = pts[maxi(i - 1, 0)]
		var b: Vector2 = pts[mini(i + 1, n - 1)]
		var t2 := (b - a).normalized()
		var lat := Vector2(-t2.y, t2.x)
		var width := lerpf(3.0, 10.0, float(i) / n)
		var p: Vector2 = pts[i]
		var y := maxf(ys[i], 0.15)
		var run := maxf(a.distance_to(b), 0.01)
		var slope := (ys[maxi(i - 1, 0)] - ys[mini(i + 1, n - 1)]) / run
		# piede di una cascata: dopo un tratto ripido il letto torna dolce
		if slope > 0.8:
			steep_run += run * 0.5
		elif steep_run > 12.0 and slope < 0.35:
			falls.append({"pos": Vector3(p.x, y, p.y), "acc": 0.0, "k": clampf(steep_run / 40.0, 0.4, 2.0)})
			steep_run = 0.0
		else:
			steep_run = maxf(0.0, steep_run - run)
		if i > 0:
			along += pts[i - 1].distance_to(p)
		var l := Vector3(p.x + lat.x * width * 0.5, y, p.y + lat.y * width * 0.5)
		var r := Vector3(p.x - lat.x * width * 0.5, y, p.y - lat.y * width * 0.5)
		var c := Color(clampf(slope, 0.0, 2.0) * 0.5, 0, 0)
		var v := along / 8.0
		if i > 0 and ys[i] > -0.2:
			for tri in [[prev_l, prev_r, r, Vector2(0, prev_v), Vector2(1, prev_v), Vector2(1, v), prev_c, prev_c, c],
					[prev_l, r, l, Vector2(0, prev_v), Vector2(1, v), Vector2(0, v), prev_c, c, c]]:
				# in senso orario visto dall'alto
				var order := [0, 1, 2]
				if (tri[1] - tri[0]).cross(tri[2] - tri[0]).y > 0.0:
					order = [0, 2, 1]
				for o in order:
					pos.append(tri[o])
					nrm.append(Vector3.UP)
					uv.append(tri[3 + o])
					col.append(tri[6 + o])
		prev_l = l
		prev_r = r
		prev_c = c
		prev_v = v
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = col
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	water_material = ShaderMaterial.new()
	water_material.shader = load("res://shaders/stream.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = water_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# maschera del letto (1 al centro, 0 oltre 16 m) per il terreno e l'erba
	var res := 1024
	var img := Image.create(res, res, false, Image.FORMAT_L8)
	var origin := summit - Vector2.ONE * STREAM_BOX * 0.5
	var px := STREAM_BOX / res
	var rad := int(ceil(16.0 / px))
	for p in stream:
		var cx := (p.x - origin.x) / px
		var cz := (p.z - origin.y) / px
		for j in range(int(cz) - rad, int(cz) + rad + 1):
			for i in range(int(cx) - rad, int(cx) + rad + 1):
				if i < 0 or j < 0 or i >= res or j >= res:
					continue
				var d := Vector2(i + 0.5 - cx, j + 0.5 - cz).length() * px
				var v := 1.0 - smoothstep(7.0, 16.0, d)
				if v > img.get_pixel(i, j).r:
					img.set_pixel(i, j, Color(v, v, v))
	var tex := ImageTexture.create_from_image(img)
	world.terrain_material.set_shader_parameter("stream_tex", tex)
	world.terrain_material.set_shader_parameter("stream_box", Vector4(origin.x, origin.y, STREAM_BOX, 1.0))


# ---------------- COSTRUZIONE ----------------
func build(w: World) -> void:
	world = w
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/lair.gdshader")
	World.set_texture_layers(material, ["rock", "timber", "shutter", "snow"])
	lit_image = Image.create(64, 1, false, Image.FORMAT_RGBA8)
	lit_tex = ImageTexture.create_from_image(lit_image)
	material.set_shader_parameter("lit_tex", lit_tex)
	for mat in [material, w.terrain_material]:
		mat.set_shader_parameter("lair_c", Vector4(cc.x, cc.y, cc.z, 1.0))
		mat.set_shader_parameter("lair_ax", Vector4(axis.x, axis.y, A, W))
		mat.set_shader_parameter("lair_pl", Vector4(pc.x, pc.y, PLATEAU_R, 0.0))
	add_child(_build_shell())
	probe = ReflectionProbe.new()
	probe.transform = frame * Transform3D(Basis.IDENTITY, Vector3(0, 45, 0))
	probe.size = Vector3(A * 2.0, 100.0, W * 2.0)
	probe.origin_offset = Vector3(0, -30, 0)
	probe.interior = true
	probe.box_projection = true
	probe.blend_distance = 18.0
	probe.max_distance = 400.0
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = DARK
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)
	var B := Builder.new() # dentro la grotta
	var G := Builder.new() # vetri delle lanterne (senza ombre: la luce sta dentro)
	var E := Builder.new() # fuori, sullo spiazzo
	E.inside = 0.0
	_spikes(B)
	_treasure(B)
	_bones(B)
	_carts(B)
	_ships(B)
	_lanterns(B, G)
	_plateau(E)
	_add(B, 1600.0, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	_add(G, 1600.0, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_add(E, 1800.0, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	_coins()
	_build_stream()
	print("Tana del drago: vetta a %d m, %d lanterne" % [int(FLOOR + H * K), lanterns.size()])


func _add(b: Builder, range_end: float, shadows: GeometryInstance3D.ShadowCastingSetting) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = b.build()
	mi.material_override = material
	mi.cast_shadow = shadows
	mi.visibility_range_end = range_end
	add_child(mi)


# Trasformazione dal sistema della grotta (pavimento a y = 0) al mondo
func _at(lx: float, lz: float, yaw := 0.0, y := 0.0) -> Transform3D:
	return frame * Transform3D(Basis(Vector3.UP, yaw), Vector3(lx, y, lz))


func _r(a: float, b: float) -> float:
	return lerpf(a, b, rng.next())


# Guscio: parete interna (righe 0..NP-1), poi la gonna che scende nel monte e la parete esterna, la bocca
# ritagliata da entrambe e cucita con le pareti del passaggio
func _build_shell() -> MeshInstance3D:
	_pos = PackedVector3Array()
	var col := PackedColorArray()
	var cus := PackedFloat32Array()
	for j in NP:
		for i in NT:
			var d := _dir(float(i) / NT * TAU, lerpf(PH0, PI / 2, float(j) / (NP - 1)))
			var p := _ell(d) * r_in(d)
			_pos.append(p)
			col.append(_rock_tint(p))
			cus.append_array([ROCK, 1.0, 0.0, 0.0])
	var ob := _pos.size()
	for r in NS + NP:
		for i in NT:
			var th := float(i) / NT * TAU
			var p: Vector3
			if r < NS:
				var t := 1.0 - float(r) / NS
				var d0 := _dir(th, PH0)
				var top := _ell(d0) * r_out(d0)
				var wob := 1.0 + 0.25 * t + n_out.get_noise_3d(top.x * 0.02, t * 2.0, top.z * 0.02) * 0.08
				p = Vector3(top.x * wob, top.y - 190.0 * t, top.z * wob)
			else:
				var d := _dir(th, lerpf(PH0, PI / 2, float(r - NS) / (NP - 1)))
				p = _ell(d) * r_out(d)
			_pos.append(p)
			col.append(_rock_tint(p))
			cus.append_array([ROCK, 0.0, 0.0, 0.0])
	_nacc = PackedVector3Array()
	_nacc.resize(_pos.size())
	_idx = PackedInt32Array()
	var hole := PackedByteArray()
	hole.resize(NP * NT)
	for j in NP - 1:
		for i in NT:
			var i1 := (i + 1) % NT
			var c := (_pos[j * NT + i] + _pos[j * NT + i1] + _pos[(j + 1) * NT + i] + _pos[(j + 1) * NT + i1]) * 0.25
			hole[j * NT + i] = 1 if _mouth_local(c) else 0
	var into := Vector3(0, H * 0.3, 0)
	for j in NP - 1:
		for i in NT:
			if hole[j * NT + i]:
				continue
			var i1 := (i + 1) % NT
			var a := j * NT + i
			var b := j * NT + i1
			var c := (j + 1) * NT + i1
			var e := (j + 1) * NT + i
			var want := into - (_pos[a] + _pos[c]) * 0.5
			_face(a, b, c, want)
			_face(a, c, e, want)
	for r in NS + NP - 1:
		for i in NT:
			if r >= NS and hole[(r - NS) * NT + i]:
				continue
			var i1 := (i + 1) % NT
			var a := ob + r * NT + i
			var b := ob + r * NT + i1
			var c := ob + (r + 1) * NT + i1
			var e := ob + (r + 1) * NT + i
			var m := (_pos[a] + _pos[c]) * 0.5
			var want := Vector3(m.x, maxf(m.y, 0.0), m.z)
			_face(a, b, c, want)
			_face(a, c, e, want)
	# pareti del passaggio: ogni lato tra un quadrilatero ritagliato e uno pieno unisce interno ed esterno
	for j in NP - 1:
		for i in NT:
			if not hole[j * NT + i]:
				continue
			var i1 := (i + 1) % NT
			var edges := []
			if not hole[j * NT + i1]:
				edges.append([j * NT + i1, (j + 1) * NT + i1])
			if not hole[j * NT + (i + NT - 1) % NT]:
				edges.append([j * NT + i, (j + 1) * NT + i])
			if j > 0 and not hole[(j - 1) * NT + i]:
				edges.append([j * NT + i, j * NT + i1])
			if j < NP - 2 and not hole[(j + 1) * NT + i]:
				edges.append([(j + 1) * NT + i, (j + 1) * NT + i1])
			for e in edges:
				var a: int = e[0]
				var b: int = e[1]
				var oa := ob + NS * NT + a
				var obb := ob + NS * NT + b
				var m := (_pos[a] + _pos[obb]) * 0.5
				var want := Vector3(m.x, clampf(m.y, 0.0, MOUTH_H * 0.5), 0.0) - m
				_face(a, b, obb, want)
				_face(a, obb, oa, want)
	var nrm := PackedVector3Array()
	nrm.resize(_pos.size())
	var world_pos := PackedVector3Array()
	world_pos.resize(_pos.size())
	for k in _pos.size():
		var n := _nacc[k]
		nrm[k] = frame.basis * (n.normalized() if n.length_squared() > 0.0 else Vector3.UP)
		world_pos[k] = frame * _pos[k]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = world_pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_CUSTOM0] = cus
	arrays[Mesh.ARRAY_INDEX] = _idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_pos = PackedVector3Array()
	_nacc = PackedVector3Array()
	_idx = PackedInt32Array()
	return mi


# Triangolo del guscio con la faccia (in senso orario, come vuole Godot) rivolta verso want
func _face(a: int, b: int, c: int, want: Vector3) -> void:
	var fn := (_pos[b] - _pos[a]).cross(_pos[c] - _pos[a])
	if fn.dot(want) > 0.0:
		var t := b
		b = c
		c = t
		fn = -fn
	_idx.append_array([a, b, c])
	_nacc[a] -= fn
	_nacc[b] -= fn
	_nacc[c] -= fn


func _rock_tint(p: Vector3) -> Color:
	var k := 0.82 + n_out.get_noise_3d(p.x * 0.05, p.y * 0.05, p.z * 0.05) * 0.35
	return Color(C.rock.r * k, C.rock.g * k * 0.98, C.rock.b * k * 0.95)


# Stalattiti dalla volta, stalagmiti e massi lungo le pareti
func _spikes(B: Builder) -> void:
	for k in 110:
		var d := _dir(rng.next() * TAU, lerpf(0.3, 1.45, sqrt(rng.next())))
		var p := _ell(d) * r_in(d)
		if p.x < -A * 0.75:
			continue
		var len := _r(4.0, 18.0)
		var rad := len * _r(0.1, 0.18)
		B.add(Prims.get_prim("cone8"), frame * Transform3D(Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3(rad, len, rad)), p + Vector3(0, 2.5, 0)), _rock_tint(p), ROCK)
	for k in 70:
		var th := rng.next() * TAU
		var d := Vector3(cos(th), 0, sin(th))
		var rr := r_in(d) * _r(0.74, 0.96)
		var lx := d.x * A * rr
		var lz := d.z * W * rr
		if lx < -A * 0.7 and absf(lz) < MOUTH_W + 12.0:
			continue
		if lx > 55.0 and absf(lz) < 62.0:
			continue
		var p := Vector3(lx, 0, lz)
		if rng.next() < 0.55:
			var len := _r(3.0, 13.0)
			var rad := len * _r(0.18, 0.28)
			B.add(Prims.get_prim("cone8"), frame * Transform3D(Basis(Vector3.UP, rng.next() * TAU) * Basis.from_scale(Vector3(rad, len, rad)), p - Vector3(0, 0.5, 0)), _rock_tint(p), ROCK)
		else:
			var s := _r(1.5, 5.0)
			B.add(Prims.get_prim("blob"), frame * Transform3D(Basis(Vector3.UP, rng.next() * TAU) * Basis.from_scale(Vector3(s * _r(0.8, 1.5), s * _r(0.5, 0.9), s)), p), _rock_tint(p), ROCK)


# ---------------- TESORO ----------------
func _gold_h(x: float, z: float) -> float:
	var h := -0.6
	for m: Vector4 in HEAPS:
		var d := Vector2(x - m.x, z - m.y).length() / m.z
		if d < 1.0:
			h = maxf(h, m.w * pow(1.0 - d * d, 1.4))
	return h + n_in.get_noise_2d(x * 0.15, z * 0.15) * 0.7 * clampf(h, 0.0, 1.0)


func _treasure(B: Builder) -> void:
	# cumuli di monete: una superficie d'oro sopra il pavimento
	var rows := []
	var centers := []
	var x0 := 58.0
	var z0 := -54.0
	var step := 1.2
	var nx := 75
	var nz := 91
	for j in nz:
		var row := []
		for i in nx:
			var x := x0 + i * step
			var z := z0 + j * step
			row.append(frame * Vector3(x, _gold_h(x, z), z))
		rows.append(row)
		centers.append(frame * Vector3(x0, -1000.0, z0 + j * step))
	B.surface(rows, [], C.gold, HOARD, centers, false, func(r, c): return rows[r][c].y < FLOOR and rows[r][c + 1].y < FLOOR and rows[r + 1][c].y < FLOOR and rows[r + 1][c + 1].y < FLOOR)
	# forzieri aperti e chiusi, mezzo sepolti
	for k in 10:
		var m: Vector4 = HEAPS[k % HEAPS.size()]
		var a := rng.next() * TAU
		var lx := m.x + cos(a) * m.z * _r(0.75, 1.05)
		var lz := m.y + sin(a) * m.z * _r(0.75, 1.05)
		var y := maxf(_gold_h(lx, lz), 0.0) - 0.4
		var xf := _at(lx, lz, rng.next() * TAU, y) * Transform3D(Basis(Vector3.FORWARD, _r(-0.15, 0.15)), Vector3.ZERO)
		_chest(B, xf, rng.next() < 0.7)
	# coppe, corone, urne, scudi, spade piantate e gemme
	for k in 16:
		var p := _heap_point(0.9)
		var xf := _at(p.x, p.z, rng.next() * TAU, p.y - 0.1) * Transform3D(Basis(Vector3(1, 0, 0), _r(-0.3, 0.3)), Vector3.ZERO)
		_goblet(B, xf * Transform3D(Basis.from_scale(Vector3.ONE * 1.6), Vector3.ZERO))
	for k in 7:
		var p := _heap_point(0.8)
		_crown(B, _at(p.x, p.z, rng.next() * TAU, p.y - 0.15) * Transform3D(Basis(Vector3(1, 0, 0), _r(-0.35, 0.35)), Vector3.ZERO))
	for k in 8:
		var p := _heap_point(0.95)
		_urn(B, _at(p.x, p.z, 0.0, p.y - 0.3) * Transform3D(Basis(Vector3(0, 0, 1), _r(-0.25, 0.25)) * Basis.from_scale(Vector3.ONE * _r(1.0, 1.8)), Vector3.ZERO))
	for k in 9:
		var p := _heap_point(0.95)
		var xf := _at(p.x, p.z, rng.next() * TAU, p.y + 0.3) * Transform3D(Basis(Vector3(1, 0, 0), _r(1.0, 1.35)), Vector3.ZERO)
		_shield(B, xf)
	for k in 12:
		var p := _heap_point(0.85)
		var xf := _at(p.x, p.z, rng.next() * TAU, p.y - 0.9) * Transform3D(Basis(Vector3(1, 0, 0), _r(-0.45, 0.45)), Vector3.ZERO)
		_sword(B, xf)
	for k in 90:
		var p := _heap_point(1.0)
		var s := _r(0.22, 0.5)
		var c: Color = C.gems[k % C.gems.size()]
		B.add(Prims.get_prim("blob"), _at(p.x, p.z, rng.next() * TAU, p.y) * Transform3D(Basis(Vector3(1, 0, 0), rng.next() * 3.0) * Basis.from_scale(Vector3(s, s * 1.4, s)), Vector3.ZERO), c, GEM)


# Punto a caso sopra i cumuli (frac: quanto lontano dal centro di un cumulo)
func _heap_point(frac: float) -> Vector3:
	var m: Vector4 = HEAPS[int(rng.next() * HEAPS.size())]
	var a := rng.next() * TAU
	var r := sqrt(rng.next()) * m.z * frac
	var x := m.x + cos(a) * r
	var z := m.y + sin(a) * r
	return Vector3(x, maxf(_gold_h(x, z), 0.0), z)


# Monete sparse sul cumulo e sul pavimento (una sola mesh ripetuta)
func _coins() -> void:
	var coin := Builder.new()
	coin.add(Prims.get_prim("cyl"), Transform3D(Basis.from_scale(Vector3(0.24, 0.05, 0.24)), Vector3.ZERO), C.gold, GOLD)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = coin.build()
	var n := 3000
	mm.instance_count = n
	for k in n:
		var p: Vector3
		if k < 1800:
			p = _heap_point(1.0)
		else:
			# rivoli di monete verso il centro della grotta
			var a := rng.next() * TAU
			var r := 30.0 + pow(rng.next(), 1.8) * 70.0
			p = Vector3(98.0 + cos(a) * r * 1.2, 0.0, sin(a) * r * 0.75)
			if Vector2(p.x / (A * 0.92), p.z / (W * 0.92)).length() > 1.0:
				p = _heap_point(1.0)
			p.y = maxf(_gold_h(p.x, p.z), 0.0)
		var b := Basis(Vector3.UP, rng.next() * TAU) * Basis(Vector3.RIGHT, _r(-0.5, 0.5))
		mm.set_instance_transform(k, frame * Transform3D(b, p + Vector3(0, 0.02, 0)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 420.0
	add_child(mi)


func _chest(B: Builder, xf: Transform3D, open: bool) -> void:
	var box := Prims.get_prim("box")
	B.add(box, xf * Transform3D(Basis.from_scale(Vector3(2.4, 1.2, 1.5)), Vector3.ZERO), C.wood, WOOD)
	for bx in [-0.85, 0.0, 0.85]:
		B.add(box, xf * Transform3D(Basis.from_scale(Vector3(0.14, 1.24, 1.56)), Vector3(bx, -0.01, 0)), C.iron, IRON)
	if open:
		var hinge := xf * Transform3D(Basis(Vector3.RIGHT, -_r(1.7, 2.1)), Vector3(0, 1.2, -0.75))
		B.add(box, hinge * Transform3D(Basis.from_scale(Vector3(2.4, 0.45, 1.5)), Vector3(0, 0, 0.75)), C.wood, WOOD)
		B.add(Prims.get_prim("blob"), xf * Transform3D(Basis.from_scale(Vector3(1.05, 0.4, 0.6)), Vector3(0, 1.1, 0)), C.gold, GOLD)
	else:
		B.add(Prims.get_prim("roof"), xf * Transform3D(Basis(Vector3.UP, PI / 2) * Basis.from_scale(Vector3(1.5, 0.45, 2.4)), Vector3(0, 1.2, 0)), C.wood, WOOD)


func _goblet(B: Builder, xf: Transform3D) -> void:
	B.add(Prims.get_prim("cyl"), xf * Transform3D(Basis.from_scale(Vector3(0.22, 0.04, 0.22)), Vector3.ZERO), C.gold, GOLD)
	B.add(Prims.get_prim("cyl"), xf * Transform3D(Basis.from_scale(Vector3(0.05, 0.4, 0.05)), Vector3.ZERO), C.gold, GOLD)
	B.add(Prims.get_prim("cone"), xf * Transform3D(Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3(0.26, 0.4, 0.26)), Vector3(0, 0.8, 0)), C.gold, GOLD)
	B.add(Prims.get_prim("blob"), xf * Transform3D(Basis.from_scale(Vector3.ONE * 0.07), Vector3(0.26, 0.72, 0)), C.gems[int(rng.next() * 4)], GEM)


func _crown(B: Builder, xf: Transform3D) -> void:
	for k in 12:
		var a := k * TAU / 12
		B.add(Prims.get_prim("box"), xf * Transform3D(Basis(Vector3.UP, -a - PI / 2) * Basis.from_scale(Vector3(0.22, 0.3, 0.05)), Vector3(cos(a) * 0.48, 0, sin(a) * 0.48) * -1.0), C.gold, GOLD)
		if k % 2 == 0:
			B.add(Prims.get_prim("cone8"), xf * Transform3D(Basis.from_scale(Vector3(0.07, 0.3, 0.07)), Vector3(-cos(a) * 0.48, 0.3, -sin(a) * 0.48)), C.gold, GOLD)
			B.add(Prims.get_prim("blob"), xf * Transform3D(Basis.from_scale(Vector3.ONE * 0.06), Vector3(-cos(a) * 0.5, 0.15, -sin(a) * 0.5)), C.gems[k % 4], GEM)


func _urn(B: Builder, xf: Transform3D) -> void:
	B.add(Prims.get_prim("blob"), xf * Transform3D(Basis.from_scale(Vector3(0.55, 0.62, 0.55)), Vector3(0, 0.55, 0)), C.gold, GOLD)
	B.add(Prims.get_prim("cyl"), xf * Transform3D(Basis.from_scale(Vector3(0.2, 0.45, 0.2)), Vector3(0, 0.95, 0)), C.gold, GOLD)
	B.add(Prims.get_prim("cyl"), xf * Transform3D(Basis.from_scale(Vector3(0.32, 0.06, 0.32)), Vector3(0, 1.38, 0)), C.gold, GOLD)


func _shield(B: Builder, xf: Transform3D) -> void:
	var paint: Color = C.paint[int(rng.next() * C.paint.size())]
	B.add(Prims.get_prim("cyl"), xf * Transform3D(Basis.from_scale(Vector3(1.0, 0.1, 1.0)), Vector3.ZERO), C.gold if rng.next() < 0.4 else C.iron, GOLD if rng.next() < 0.5 else IRON)
	B.add(Prims.get_prim("cyl"), xf * Transform3D(Basis.from_scale(Vector3(0.9, 0.12, 0.9)), Vector3(0, 0.01, 0)), paint, WOOD)
	B.add(Prims.get_prim("blob"), xf * Transform3D(Basis.from_scale(Vector3(0.22, 0.14, 0.22)), Vector3(0, 0.13, 0)), C.gold, GOLD)


# Spada piantata: la punta nell'origine, la lama in su lungo y
func _sword(B: Builder, xf: Transform3D) -> void:
	B.add(Prims.get_prim("pyr"), xf * Transform3D(Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3(0.16, 0.35, 0.04)), Vector3(0, 0.35, 0)), C.silver, SILVER)
	B.add(Prims.get_prim("box"), xf * Transform3D(Basis.from_scale(Vector3(0.16, 2.2, 0.04)), Vector3(0, 0.35, 0)), C.silver, SILVER)
	B.add(Prims.get_prim("box"), xf * Transform3D(Basis.from_scale(Vector3(0.8, 0.1, 0.12)), Vector3(0, 2.55, 0)), C.gold, GOLD)
	B.add(Prims.get_prim("cyl"), xf * Transform3D(Basis.from_scale(Vector3(0.05, 0.5, 0.05)), Vector3(0, 2.65, 0)), C.wood, WOOD)
	B.add(Prims.get_prim("blob"), xf * Transform3D(Basis.from_scale(Vector3.ONE * 0.1), Vector3(0, 3.2, 0)), C.gold, GOLD)


# ---------------- OSSA ----------------
func _bones(B: Builder) -> void:
	# lo scheletro di una bestia gigantesca: spina dorsale a S, costole ad arco e il cranio cornuto
	var spine := []
	for k in 30:
		var t := float(k) / 29.0
		spine.append(Vector3(lerpf(-48.0, 30.0, t), 0.9, 62.0 - sin(t * PI * 1.3) * 8.0))
	for k in spine.size():
		var p: Vector3 = spine[k]
		var s := 1.3 * (1.0 - absf(float(k) / 29.0 - 0.4) * 0.8)
		B.add(Prims.get_prim("blob"), frame * Transform3D(Basis.from_scale(Vector3(s * 1.1, s, s)), p), C.bone, BONE)
		B.add(Prims.get_prim("cone8"), frame * Transform3D(Basis(Vector3.RIGHT, -0.5) * Basis.from_scale(Vector3(s * 0.25, s * 2.2, s * 0.25)), p + Vector3(0, s * 0.6, 0)), C.bone, BONE)
		if k >= 6 and k <= 20 and k % 2 == 0:
			var tang: Vector3 = (spine[mini(k + 1, 29)] - spine[k - 1]).normalized()
			var out := Vector3.UP.cross(tang).normalized()
			if out.z < 0.0:
				out = -out
			var rr := 7.5 * (1.0 - absf(k - 12.0) / 12.0)
			var stop := 0.15 if rng.next() < 0.7 else _r(0.6, 1.6)
			var prev := p
			var n := 9
			for a in range(1, n + 1):
				var ang := PI - (PI - stop) * float(a) / n
				var q: Vector3 = p + out * rr * (1.0 + cos(ang)) + Vector3.UP * rr * sin(ang) * 1.3
				_seg(B, frame * prev, frame * q, 0.3 * (1.0 - float(a) / n * 0.5), C.bone, BONE)
				prev = q
	var head: Vector3 = spine[29]
	_skull(B, frame * Transform3D(Basis(Vector3.UP, 1.75) * Basis(Vector3.FORWARD, 0.35), head + Vector3(5.5, 1.2, -1.0)), 2.2)
	# un cranio di drago all'ingresso, come avvertimento
	_skull(B, _at(-112.0, -40.0, 0.9, 1.0), 2.8)
	# mucchi di ossa sparse
	for spot in [Vector2(-95, -55), Vector2(-20, 32), Vector2(45, -75), Vector2(-60, 5), Vector2(20, 82), Vector2(-120, 60), Vector2(70, 8)]:
		_bone_pile(B, spot.x, spot.y, 12)


func _skull(B: Builder, xf: Transform3D, s: float) -> void:
	var blob := Prims.get_prim("blob")
	B.add(blob, xf * Transform3D(Basis.from_scale(Vector3(1.3, 1.0, 1.5) * s), Vector3.ZERO), C.bone, BONE)
	B.add(blob, xf * Transform3D(Basis.from_scale(Vector3(0.75, 0.6, 1.6) * s), Vector3(0, -0.15, 1.6) * s), C.bone, BONE)
	var dark := Color(0.03, 0.025, 0.02)
	for sx in [-1.0, 1.0]:
		B.add(blob, xf * Transform3D(Basis.from_scale(Vector3(0.35, 0.3, 0.35) * s), Vector3(sx * 0.75, 0.3, 0.9) * s), dark, BONE)
		B.add(blob, xf * Transform3D(Basis.from_scale(Vector3(0.12, 0.1, 0.12) * s), Vector3(sx * 0.25, -0.05, 3.1) * s), dark, BONE)
		# corna all'indietro, in due pezzi
		var base := xf * (Vector3(sx * 0.8, 0.7, -0.6) * s)
		var mid := xf * (Vector3(sx * 1.4, 1.3, -2.4) * s)
		var tip := xf * (Vector3(sx * 1.6, 2.3, -3.6) * s)
		_seg(B, base, mid, 0.32 * s, C.bone, BONE)
		B.add(Prims.get_prim("cone8"), _aligned(mid, tip, 0.3 * s), C.bone, BONE)
		# denti
		for k in 5:
			var tz := 1.4 + k * 0.38
			B.add(Prims.get_prim("cone8"), xf * Transform3D(Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3(0.09, 0.45, 0.09) * s), Vector3(sx * 0.55, -0.35, tz) * s), C.bone, BONE)
	# mandibola staccata, a terra accanto
	B.add(blob, xf * Transform3D(Basis(Vector3.UP, 0.4) * Basis.from_scale(Vector3(0.5, 0.25, 2.2) * s), Vector3(1.6, -0.9, 0.8) * s), C.bone, BONE)


func _bone_pile(B: Builder, lx: float, lz: float, n: int) -> void:
	for k in n:
		var a := rng.next() * TAU
		var r := sqrt(rng.next()) * 4.0
		var c := Vector3(lx + cos(a) * r, _r(0.2, 0.9), lz + sin(a) * r)
		var dir := Vector3(cos(rng.next() * TAU), _r(-0.25, 0.35), sin(rng.next() * TAU)).normalized()
		var len := _r(1.5, 3.6)
		var p0 := frame * (c - dir * len * 0.5)
		var p1 := frame * (c + dir * len * 0.5)
		var rad := len * 0.06
		_seg(B, p0, p1, rad, C.bone, BONE)
		for p in [p0, p1]:
			B.add(Prims.get_prim("blob"), Transform3D(Basis.from_scale(Vector3.ONE * rad * 2.0), p), C.bone, BONE)
	for k in 2:
		var a := rng.next() * TAU
		_skull(B, _at(lx + cos(a) * 3.0, lz + sin(a) * 3.0, rng.next() * TAU, 0.6), _r(0.45, 0.7))


# Cilindro (o cono) da a a b con raggio rad
func _aligned(a: Vector3, b: Vector3, rad: float) -> Transform3D:
	var y := b - a
	var up := y.normalized()
	var x := up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(up)
	return Transform3D(Basis(x * rad, y, z * rad), a)


func _seg(B: Builder, a: Vector3, b: Vector3, rad: float, c: Color, mat: int) -> void:
	B.add(Prims.get_prim("cyl"), _aligned(a, b, rad), c, mat)


# ---------------- CARRI ----------------
func _carts(B: Builder) -> void:
	# x, z, direzione, 0 dritto / 1 rovesciato su un fianco / 2 con una ruota rotta
	for c in [Vector4(-85, -22, 0.6, 0), Vector4(-60, -72, 1.1, 2), Vector4(40, 70, -0.4, 1), Vector4(-18, -12, 2.6, 0), Vector4(58, -70, 0.3, 1)]:
		var xf := _at(c.x, c.y, c.z)
		if c.w == 1:
			xf = xf * Transform3D(Basis(Vector3.FORWARD, PI / 2 - 0.15), Vector3(0, 0.95, 0))
		elif c.w == 2:
			xf = xf * Transform3D(Basis(Vector3.FORWARD, 0.22), Vector3.ZERO)
		_cart(B, xf, c.w == 2)


func _cart(B: Builder, xf: Transform3D, broken: bool) -> void:
	var box := Prims.get_prim("box")
	B.add(box, xf * Transform3D(Basis.from_scale(Vector3(4.2, 0.25, 2.2)), Vector3(0, 1.3, 0)), C.wood, WOOD)
	for sz in [-1.0, 1.0]:
		B.add(box, xf * Transform3D(Basis.from_scale(Vector3(4.2, 0.8, 0.12)), Vector3(0, 1.55, sz * 1.05)), C.wood, WOOD)
	for sx in [-1.0, 1.0]:
		B.add(box, xf * Transform3D(Basis.from_scale(Vector3(0.12, 0.8, 2.2)), Vector3(sx * 2.05, 1.55, 0)), C.wood, WOOD)
	# timone
	for sz in [-0.4, 0.4]:
		B.add(box, xf * Transform3D(Basis(Vector3.FORWARD, 0.12) * Basis.from_scale(Vector3(4.0, 0.12, 0.12)), Vector3(3.8, 1.0, sz)), C.wood, WOOD)
	for sx in [-1.2, 1.2]:
		for sz in [-1.25, 1.25]:
			if broken and sx > 0 and sz > 0:
				# ruota rotta, a terra accanto al carro
				_wheel(B, xf * Transform3D(Basis.IDENTITY, Vector3(2.2, 0.25, 2.9)), true)
				continue
			_wheel(B, xf * Transform3D(Basis.IDENTITY, Vector3(sx, 0.95, sz)), false)


# Ruota a raggi con l'asse lungo z (flat: appoggiata al suolo)
func _wheel(B: Builder, xf: Transform3D, flat: bool) -> void:
	var rot := Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO) if not flat else Transform3D.IDENTITY
	var r := 0.95
	for k in 12:
		var a := k * TAU / 12
		B.add(Prims.get_prim("box"), xf * rot * Transform3D(Basis(Vector3.UP, -a - PI / 2) * Basis.from_scale(Vector3(0.52, 0.14, 0.2)), Vector3(cos(a) * r, -0.07, sin(a) * r)), C.wood, WOOD)
	for k in 6:
		var a := k * PI / 6
		B.add(Prims.get_prim("box"), xf * rot * Transform3D(Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(r * 2.0, 0.08, 0.08)), Vector3(0, -0.04, 0)), C.wood, WOOD)
	B.add(Prims.get_prim("cyl"), xf * rot * Transform3D(Basis.from_scale(Vector3(0.2, 0.3, 0.2)), Vector3(0, -0.15, 0)), C.iron, IRON)


# ---------------- NAVI ----------------
func _ships(B: Builder) -> void:
	# x, z, direzione, inclinazione; lunghezza, larghezza, profondità; quanto è sfasciata
	_ship(B, _at(8.0, -42.0, 0.3), 0.45, 36.0, 9.0, 5.5, 0.15)
	_ship(B, _at(-88.0, 42.0, -0.45), -1.0, 25.0, 7.0, 4.2, 0.45)


# Scafo a doppia curvatura con il fasciame lungo l'UV, ordinate, chiglia, albero spezzato e una vela a brandelli
func _ship(B: Builder, base: Transform3D, roll: float, length: float, beam: float, depth: float, wreck: float) -> void:
	var xf := base * Transform3D(Basis(Vector3.RIGHT, roll), Vector3(0, depth * 0.85, 0))
	var nu := 30
	var nv := 14
	var rows := []
	var uvs := []
	var centers := []
	var holes := {}
	for i in nu + 1:
		var u := lerpf(-1.0, 1.0, float(i) / nu)
		var hw := beam * 0.5 * pow(maxf(0.0, 1.0 - pow(absf(u), 2.2)), 0.5)
		var d := depth * (1.0 - 0.25 * u * u)
		var sheer := depth * 0.35 * u * u
		var row := []
		var uvr := []
		var arc := 0.0
		var prev := Vector3.ZERO
		for k in nv + 1:
			var t := lerpf(-1.0, 1.0, float(k) / nv)
			var p := Vector3(u * length * 0.5, sheer - d * pow(cos(t * PI * 0.5), 0.6), hw * sin(t * PI * 0.5))
			if k > 0:
				arc += p.distance_to(prev)
			prev = p
			row.append(xf * p)
			uvr.append(Vector2(u * length * 0.5, arc))
		rows.append(row)
		uvs.append(uvr)
		centers.append(xf * Vector3(u * length * 0.5, sheer + 0.5, 0))
	# falle nel fasciame: si vedono le ordinate
	for i in nu:
		for k in nv:
			if rng.next() < wreck and absf(float(k) / nv - 0.5) > 0.12:
				holes[i * 1000 + k] = true
	B.surface(rows, uvs, C.planks, PLANKS, centers, false, func(r, c): return holes.has(r * 1000 + c))
	# ordinate e chiglia
	for i in range(2, nu - 1, 2):
		var row: Array = rows[i]
		for k in nv:
			_seg(B, row[k], row[k + 1], 0.16, C.wood, WOOD)
	var keel := []
	for i in nu + 1:
		keel.append(rows[i][nv / 2])
	for i in nu:
		_seg(B, keel[i], keel[i + 1], 0.3, C.wood, WOOD)
	# ponte a poppa e albero spezzato con la vela strappata
	var deck_y := depth * 0.02
	B.add(Prims.get_prim("box"), xf * Transform3D(Basis.from_scale(Vector3(length * 0.22, 0.25, beam * 0.75)), Vector3(-length * 0.36, deck_y + depth * 0.25, 0)), C.wood, WOOD)
	B.add(Prims.get_prim("box"), xf * Transform3D(Basis.from_scale(Vector3(length * 0.16, depth * 0.45, beam * 0.6)), Vector3(-length * 0.37, deck_y + depth * 0.25, 0)), C.planks, WOOD)
	var mast_base := xf * Vector3(length * 0.05, -depth * 0.8, 0)
	var mast_top := xf * Vector3(length * 0.05 + 1.0, depth * 1.6, 0.6)
	_seg(B, mast_base, mast_top, 0.42, C.wood, WOOD)
	# il resto dell'albero, a terra
	var fallen := base * Vector3(length * 0.1, 0.5, beam * 0.9 + 4.0)
	var fallen_end := base * Vector3(length * 0.1 + length * 0.55, 0.6, beam * 0.9 + 9.0)
	_seg(B, fallen, fallen_end, 0.38, C.wood, WOOD)
	var sail := []
	var sail_uv := []
	for r in 6:
		var row := []
		var uvr := []
		for c in 8:
			var along := float(c) / 7.0
			var drop := float(r) / 5.0
			var p := fallen.lerp(fallen_end, along * 0.8 + 0.1) + Vector3(0, -drop * 0.4, 0) + (base.basis.z.normalized()) * drop * 5.0
			p.y = maxf(p.y + sin(along * 9.0 + drop * 4.0) * 0.35, FLOOR + 0.05)
			row.append(p)
			uvr.append(Vector2(along, drop))
		sail.append(row)
		sail_uv.append(uvr)
	B.surface(sail, sail_uv, C.sail, CLOTH, [], false, func(r, c): return rng.next() < 0.18)


# ---------------- LANTERNE ----------------
func _lanterns(B: Builder, G: Builder) -> void:
	# appese alle pareti con un braccio di ferro, all'altezza di 13 m
	for k in 18:
		var th := lerpf(-2.45, 2.45, float(k) / 17.0)
		var ph := asin(13.0 / H)
		var p := Vector3.ZERO
		for it in 4:
			var d := _dir(th, ph)
			p = _ell(d) * r_in(d)
			ph = clampf(ph * 13.0 / maxf(p.y, 1.0), 0.02, 1.2)
		var inward := -Vector3(p.x / (A * A), 0, p.z / (W * W)).normalized()
		var anchor := p - inward * 1.0
		var arm_end := p + inward * 4.2
		_seg(B, frame * anchor, frame * arm_end, 0.16, C.iron, IRON)
		_seg(B, frame * (anchor - Vector3(0, 2.2, 0)), frame * (p + inward * 2.6), 0.1, C.iron, IRON)
		_seg(B, frame * arm_end, frame * (arm_end - Vector3(0, 1.2, 0)), 0.05, C.iron, IRON)
		_lantern(B, G, frame * Transform3D(Basis.IDENTITY, arm_end - Vector3(0, 1.2 + 1.35 * S, 0)))
	# grandi lanterne appese alla volta con le catene, sopra il passaggio centrale
	for spot in [Vector2(-95, 22), Vector2(-60, -24), Vector2(-20, 26), Vector2(20, -20), Vector2(58, 18), Vector2(96, -30), Vector2(110, 26)]:
		var d := Vector3(spot.x / A, 0.0, spot.y / W)
		var up := Vector3(spot.x, 0, spot.y)
		# punto della volta sopra: si sale finché si esce dall'interno
		var top := 30.0
		while top < H * 1.3:
			var qn := Vector3(spot.x / A, top / H, spot.y / W)
			if qn.length() > r_in(qn.normalized()):
				break
			top += 2.0
		var hang := 28.0
		_seg(B, frame * (up + Vector3(0, top + 2.0, 0)), frame * (up + Vector3(0, hang + 1.6 * 1.6 * S, 0)), 0.09, C.iron, IRON)
		_lantern(B, G, frame * Transform3D(Basis.from_scale(Vector3.ONE * 1.6), up + Vector3(0, hang, 0)), 1.6)
	# su pali di ferro lungo il passaggio e attorno al tesoro
	for spot in [Vector2(-118, 34), Vector2(-118, -34), Vector2(-42, 30), Vector2(-42, -26), Vector2(60, 52), Vector2(60, -52), Vector2(138, -25), Vector2(136, 28)]:
		var yaw := atan2(-spot.x, -spot.y)
		var at := _at(spot.x, spot.y, yaw)
		B.add(Prims.get_prim("cone8"), at * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 1.0)), Vector3.ZERO), C.iron, IRON)
		_seg(B, at * Vector3(0, 0, 0), at * Vector3(0, 8.0, 0), 0.18, C.iron, IRON)
		_seg(B, at * Vector3(0, 7.6, 0), at * Vector3(0, 7.6, 2.0), 0.12, C.iron, IRON)
		_seg(B, at * Vector3(0, 7.6, 2.0), at * Vector3(0, 7.0, 2.0), 0.05, C.iron, IRON)
		_lantern(B, G, at * Transform3D(Basis.IDENTITY, Vector3(0, 7.0 - 1.35 * S, 2.0)))


# Lanterna: gabbia di ferro con il tetto a punta, vetri che si illuminano e una luce dentro
func _lantern(B: Builder, G: Builder, at: Transform3D, big := 1.0) -> void:
	var idx := lanterns.size()
	var box := Prims.get_prim("box")
	B.add(box, at * Transform3D(Basis.from_scale(Vector3(0.85, 0.1, 0.85) * S), Vector3.ZERO), C.iron, IRON)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			B.add(box, at * Transform3D(Basis.from_scale(Vector3(0.07, 1.05, 0.07) * S), Vector3(sx, 0, sz) * 0.36 * S + Vector3(0, 0.1 * S, 0)), C.iron, IRON)
	B.add(box, at * Transform3D(Basis.from_scale(Vector3(0.05, 1.0, 0.8) * S), Vector3(0, 0.12 * S, 0)), C.iron, IRON)
	B.add(Prims.get_prim("pyr"), at * Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.0) * S), Vector3(0, 1.15 * S, 0)), C.iron, IRON)
	B.add(Prims.get_prim("cyl"), at * Transform3D(Basis.from_scale(Vector3(0.1, 0.12, 0.1) * S), Vector3(0, 1.6 * S, 0)), C.iron, IRON)
	G.add(box, at * Transform3D(Basis.from_scale(Vector3(0.62, 1.0, 0.62) * S), Vector3(0, 0.12 * S, 0)), Color.WHITE, GLASS, idx)
	var light := OmniLight3D.new()
	light.position = at * Vector3(0, 0.62 * S, 0)
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 0.0
	light.omni_range = LANTERN_RANGE * (1.0 + (big - 1.0) * 0.5)
	light.omni_attenuation = 0.9
	light.light_specular = 0.6
	light.light_volumetric_fog_energy = 1.2
	light.shadow_bias = 0.15
	light.visible = false
	add_child(light)
	lanterns.append({"idx": idx, "pos": light.position, "lit": false, "t": 0.0, "ph": rng.next() * 10.0, "light": light, "big": big})


# ---------------- SPIAZZO ----------------
# Nidi con le uova di drago (alcune schiuse), massi sul bordo e ossa delle prede
func _plateau(E: Builder) -> void:
	var eggs: Array = C.eggs
	_nest(E, -236.0, 58.0, [[eggs[0], false], [eggs[1], false], [eggs[2], true], [eggs[3], true]])
	_nest(E, -208.0, -64.0, [[eggs[4], false], [eggs[0], true], [eggs[2], false]])
	# un uovo schiuso rotolato fuori dal nido, coricato
	_egg(E, _at(-262.0, -12.0, 0.7, 1.1) * Transform3D(Basis(Vector3.FORWARD, 1.35), Vector3.ZERO), 3.4, 1.35, eggs[1], true)
	_shards(E, -262.0, -12.0, 9)
	for k in 26:
		var a := rng.next() * TAU
		var r := _r(96.0, 122.0)
		var lx := -220.0 + cos(a) * r
		var lz := sin(a) * r
		if lx > -110.0 or (lx > -190.0 and absf(lz) < MOUTH_W + 25.0):
			continue
		var s := _r(2.0, 6.5)
		E.add(Prims.get_prim("blob"), _at(lx, lz, rng.next() * TAU, -s * 0.3) * Transform3D(Basis.from_scale(Vector3(s * _r(0.9, 1.6), s * _r(0.5, 0.8), s)), Vector3.ZERO), _rock_tint(Vector3(lx, 0, lz)), ROCK)
	_bone_pile(E, -180.0, 38.0, 8)
	_bone_pile(E, -255.0, -55.0, 6)
	# cespugli lungo il bordo e accanto ai nidi
	var bushes := Greenery.new()
	for k in 40:
		var a := rng.next() * TAU
		var r := _r(70.0, 118.0) if k < 30 else _r(9.0, 16.0)
		var c := Vector2(-220.0 + cos(a) * r, sin(a) * r) if k < 30 else Vector2(-236.0 + cos(a) * r, 58.0 + sin(a) * r)
		if c.x > -175.0 and absf(c.y) < MOUTH_W + 30.0:
			continue
		var bush_rng := Mulberry32.new(k + 99)
		bushes.bush(frame * Vector3(c.x, 0, c.y), _r(0.8, 1.8), 0, bush_rng)
	add_child(bushes.build(world.greenery_material))


func _nest(E: Builder, lx: float, lz: float, eggs: Array) -> void:
	E.add(Prims.get_prim("cyl"), _at(lx, lz, 0.0, -0.2) * Transform3D(Basis.from_scale(Vector3(6.2, 0.6, 6.2)), Vector3.ZERO), C.straw, STRAW)
	for layer in 3:
		for k in 24:
			var a := k * TAU / 24 + layer * 0.13 + rng.next() * 0.1
			var r := 6.0 - layer * 0.5 + rng.next() * 0.6
			var c := _at(lx, lz) * Vector3(cos(a) * r, 0.5 + layer * 0.55, sin(a) * r)
			var t := _at(lx, lz).basis * Vector3(-sin(a), _r(-0.25, 0.25), cos(a)).normalized()
			var len := _r(3.5, 5.5)
			_seg(E, c - t * len * 0.5, c + t * len * 0.5, _r(0.12, 0.22), C.straw * _r(0.7, 1.1), STRAW)
	for k in 10:
		var a := rng.next() * TAU
		var s := _r(1.0, 1.8)
		E.add(Prims.get_prim("blob"), _at(lx + cos(a) * 7.4, lz + sin(a) * 7.4, rng.next() * TAU, 0.2) * Transform3D(Basis.from_scale(Vector3(s * 1.3, s * 0.7, s)), Vector3.ZERO), _rock_tint(Vector3(lx, 0, lz)), ROCK)
	for k in eggs.size():
		var a := k * TAU / eggs.size() + 0.4
		var r := 2.3 if eggs.size() > 1 else 0.0
		var ex := lx + cos(a) * r
		var ez := lz + sin(a) * r
		var tilt := Transform3D(Basis(Vector3(cos(a + 1.57), 0, sin(a + 1.57)), _r(0.1, 0.3)), Vector3.ZERO)
		_egg(E, _at(ex, ez, rng.next() * TAU, 0.3) * tilt, _r(3.1, 3.6), _r(1.25, 1.4), eggs[k][0], eggs[k][1])
		if eggs[k][1]:
			_shards(E, ex, ez, 7)


# Uovo di drago (profilo ovale, squame dall'UV); open: rotto in cima con il bordo seghettato e l'interno chiaro
func _egg(E: Builder, xf: Transform3D, hh: float, rr: float, c: Color, open: bool) -> void:
	var na := 26
	var nv := 18
	var jag := []
	for i in na:
		jag.append(hh * (0.5 + 0.1 * rng.next() + (0.12 if i % 2 == 0 else 0.0)))
	var rows := []
	var rows_in := []
	var uvs := []
	var centers := []
	for v in nv + 1:
		var y := hh * float(v) / nv
		var row := []
		var row_in := []
		var uvr := []
		for i in na + 1:
			var a := float(i) / na * TAU
			var yy := minf(y, jag[i % na]) if open else y
			var r := _egg_r(yy, hh, rr)
			row.append(xf * Vector3(cos(a) * r, yy, sin(a) * r))
			row_in.append(xf * Vector3(cos(a) * r * 0.92, maxf(yy, hh * 0.08), sin(a) * r * 0.92))
			uvr.append(Vector2(float(i) / na, yy / hh))
		rows.append(row)
		rows_in.append(row_in)
		uvs.append(uvr)
		centers.append(xf * Vector3(0, y, 0))
	E.surface(rows, uvs, c, EGG, centers, true)
	if open:
		E.surface(rows_in, uvs, C.shell_in, SHELL_IN, centers, true, Callable(), true)
		E.surface([rows[nv], rows_in[nv]], [uvs[nv], uvs[nv]], C.shell_in, SHELL_IN, [xf * Vector3(0, -50, 0), xf * Vector3(0, -50, 0)], true)


static func _egg_r(y: float, hh: float, rr: float) -> float:
	var t := y / hh
	var k := (t - 0.42) / (0.42 if t < 0.42 else 0.58)
	return rr * sqrt(maxf(0.0, 1.0 - k * k))


# Pezzi di guscio sparsi a terra
func _shards(E: Builder, lx: float, lz: float, n: int) -> void:
	for k in n:
		var a := rng.next() * TAU
		var r := _r(1.5, 4.5)
		var b := Basis(Vector3.UP, rng.next() * TAU) * Basis(Vector3.RIGHT, _r(-0.5, 0.5))
		E.add(Prims.get_prim("box"), _at(lx + cos(a) * r, lz + sin(a) * r, 0.0, 0.25) * Transform3D(b * Basis.from_scale(Vector3(_r(0.4, 0.9), 0.07, _r(0.3, 0.7))), Vector3.ZERO), C.eggs[k % 5], EGG)


# ---------------- COSTRUTTORE DI MESH ----------------
class Builder:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var cus := PackedFloat32Array()
	var inside := 1.0

	# Primitiva di Prims (facce in senso antiorario, come in Three.js: si scambiano due vertici)
	func add(prim: Dictionary, xf: Transform3D, c: Color, mat: int, extra := 0.0) -> void:
		var nb := xf.basis.inverse().transposed()
		var P: PackedVector3Array = prim.pos
		var Nn: PackedVector3Array = prim.nrm
		for t in range(0, P.size(), 3):
			for o in 3:
				var k: int = t + (0 if o == 0 else 3 - o)
				pos.append(xf * P[k])
				nrm.append((nb * Nn[k]).normalized())
				col.append(c)
				uv.append(Vector2.ZERO)
				cus.append_array([mat, inside, extra, 0.0])

	# Superficie da una griglia di punti (righe della stessa lunghezza): normali lisce dalle differenze tra
	# vicini, rivolte lontano da centers[riga] (o verso, con flip). closed: la prima e l'ultima colonna coincidono.
	# skip(riga, colonna) -> true salta quel quadrilatero.
	func surface(rows: Array, uvs: Array, c: Color, mat: int, centers: Array, closed := false, skip := Callable(), flip := false) -> void:
		var nr := rows.size()
		var nc: int = rows[0].size()
		var norms := []
		for r in nr:
			var nrow := []
			for k in nc:
				var kl := k - 1 if k > 0 else (nc - 2 if closed else 0)
				var kr := k + 1 if k < nc - 1 else (1 if closed else nc - 1)
				var du: Vector3 = rows[r][kr] - rows[r][kl]
				var dv: Vector3 = rows[mini(r + 1, nr - 1)][k] - rows[maxi(r - 1, 0)][k]
				var n := du.cross(dv)
				var p: Vector3 = rows[r][k]
				var away: Vector3 = p - centers[r] if centers.size() > 0 else Vector3.UP
				if n.length_squared() < 1e-10:
					n = away
				n = n.normalized()
				if (n.dot(away) < 0.0) != flip:
					n = -n
				nrow.append(n)
			norms.append(nrow)
		for r in nr - 1:
			for k in nc - 1:
				if skip.is_valid() and skip.call(r, k):
					continue
				var q := [[r, k], [r, k + 1], [r + 1, k + 1], [r + 1, k]]
				for t in [[0, 1, 2], [0, 2, 3]]:
					var a: Array = q[t[0]]
					var b: Array = q[t[1]]
					var e: Array = q[t[2]]
					var pa: Vector3 = rows[a[0]][a[1]]
					var pb: Vector3 = rows[b[0]][b[1]]
					var pe: Vector3 = rows[e[0]][e[1]]
					var na: Vector3 = norms[a[0]][a[1]]
					# faccia in senso orario vista dal lato della normale
					if (pb - pa).cross(pe - pa).dot(na + norms[b[0]][b[1]] + norms[e[0]][e[1]]) > 0.0:
						var tmp := b
						b = e
						e = tmp
					for v in [a, b, e]:
						pos.append(rows[v[0]][v[1]])
						nrm.append(norms[v[0]][v[1]])
						col.append(c)
						uv.append(uvs[v[0]][v[1]] if uvs.size() > 0 else Vector2.ZERO)
						cus.append_array([mat, inside, 0.0, 0.0])

	func build() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_CUSTOM0] = cus
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		return m
