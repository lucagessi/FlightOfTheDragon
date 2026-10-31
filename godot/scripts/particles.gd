# Sistema di particelle su CPU disegnato con un MultiMesh di billboard
# (porting di ParticleSystem in src/fx.js). Colore in INSTANCE_CUSTOM, dimensione nella scala.
class_name ParticleSystem
extends MultiMeshInstance3D

enum Ramp { FIRE, EMBER, SMOKE, SPRAY }

var max_n := 0
var gravity := 0.0
var drag := 0.0
var ramp := Ramp.FIRE
var n := 0
var head := 0
var p := PackedVector3Array()
var v := PackedVector3Array()
var age := PackedFloat32Array()
var life := PackedFloat32Array()
var s0 := PackedFloat32Array()
var s1 := PackedFloat32Array()
var pdrag := PackedFloat32Array()
var ramp_id := PackedByteArray()
var flags := PackedByteArray()
var buf := PackedFloat32Array()
var on_collide := Callable() # (posizione, flag) -> true se la particella va eliminata


func setup(max_count: int, mat: Material, grav: float, drg: float, rmp: Ramp) -> void:
	max_n = max_count
	gravity = grav
	drag = drg
	ramp = rmp
	p.resize(max_n)
	v.resize(max_n)
	age.resize(max_n)
	life.resize(max_n)
	s0.resize(max_n)
	s1.resize(max_n)
	pdrag.resize(max_n)
	ramp_id.resize(max_n)
	flags.resize(max_n)
	buf.resize(max_n * 16)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()
	mm.instance_count = max_n
	mm.visible_instance_count = 0
	multimesh = mm
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))


func spawn(pos: Vector3, vel: Vector3, lifetime: float, size0: float, size1: float, rid := 0, flag := 0, drg := -1.0) -> void:
	var i := n
	if n < max_n:
		n += 1
	else:
		i = head
		head = (head + 1) % max_n
	p[i] = pos
	v[i] = vel
	age[i] = 0
	life[i] = lifetime
	s0[i] = size0
	s1[i] = size1
	ramp_id[i] = rid
	flags[i] = flag
	pdrag[i] = drag if drg < 0 else drg


# Elimina la particella i spostando l'ultima al suo posto
func _kill(i: int) -> void:
	n -= 1
	if i == n:
		return
	p[i] = p[n]
	v[i] = v[n]
	age[i] = age[n]
	life[i] = life[n]
	s0[i] = s0[n]
	s1[i] = s1[n]
	pdrag[i] = pdrag[n]
	ramp_id[i] = ramp_id[n]
	flags[i] = flags[n]


func update_particles(dt: float) -> void:
	var g := gravity * dt
	var i := 0
	while i < n:
		var a := age[i] + dt
		if a >= life[i]:
			_kill(i)
			continue
		age[i] = a
		var k := exp(-pdrag[i] * dt)
		var vel := v[i] * k
		vel.y += g
		v[i] = vel
		var pos := p[i] + vel * dt
		p[i] = pos
		if flags[i] != 0 and on_collide.is_valid() and on_collide.call(pos, flags[i]):
			_kill(i)
			continue
		var t := a / life[i]
		var c := _ramp(t, ramp_id[i], i)
		var size := s0[i] + (s1[i] - s0[i]) * sqrt(t)
		var o := i * 16
		buf[o] = size
		buf[o + 3] = pos.x
		buf[o + 5] = size
		buf[o + 7] = pos.y
		buf[o + 10] = size
		buf[o + 11] = pos.z
		buf[o + 12] = c.r
		buf[o + 13] = c.g
		buf[o + 14] = c.b
		buf[o + 15] = c.a
		i += 1
	multimesh.buffer = buf
	multimesh.visible_instance_count = n


static func _ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)


func _ramp(t: float, id: int, i: int) -> Color:
	match ramp:
		Ramp.FIRE:
			var a := _ss(0, 0.06, t) * (1 - _ss(0.55, 1, t))
			if id == 0: # soffio del drago: nucleo bianco-giallo -> arancio -> rosso scuro
				var o := 0.35 + 0.5 * minf(1, t * 4)
				if t < 0.12:
					var k := t / 0.12
					return Color(3.2, 2.6 - 1.0 * k, 1.2 - 1.0 * k, a * o)
				elif t < 0.5:
					var k := (t - 0.12) / 0.38
					return Color(3.2 - 1.2 * k, 1.6 - 1.0 * k, 0.2 - 0.15 * k, a * o)
				var k2 := (t - 0.5) / 0.5
				return Color(2.0 - 1.5 * k2, 0.6 - 0.5 * k2, 0.05 - 0.04 * k2, a * o)
			elif id == 1: # fiamme degli edifici
				return Color(4.2 - 2.2 * t, 1.9 - 1.5 * t, 0.35 - 0.3 * t, a * 0.8)
			return Color(4 - 2.6 * t, 2.3 - 2 * t, 0.6 - 0.55 * t, a * 0.7) # esplosioni e palle di fuoco
		Ramp.EMBER:
			var f := 0.6 + 0.4 * sin(i * 1.7 + t * 40)
			return Color(9 * f, 3.5 * f, 0.6 * f, 1 - _ss(0.6, 1, t))
		Ramp.SMOKE:
			if id == 1: # vapore / nebbia marina
				return Color(0.85, 0.88, 0.92, _ss(0, 0.1, t) * (1 - _ss(0.3, 1, t)) * 0.4)
			var k := _ss(0, 0.5, t)
			return Color(0.09 + 0.16 * k, 0.085 + 0.15 * k, 0.08 + 0.15 * k, _ss(0, 0.12, t) * (1 - _ss(0.4, 1, t)) * 0.55)
	# spruzzi
	return Color(0.9, 0.94, 0.98, _ss(0, 0.08, t) * (1 - _ss(0.4, 1, t)) * (0.75 if id == 1 else 0.5))
