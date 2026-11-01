# Effetti: particelle (fuoco, fumo, scintille, spruzzi), palle di fuoco, tempesta di fuoco,
# esplosioni e luci dinamiche (porting di src/fx.js)
class_name FX
extends Node3D

var world: World
var water: Water
var audio: GameAudio
var fire := ParticleSystem.new()
var embers := ParticleSystem.new()
var smoke := ParticleSystem.new()
var spray := ParticleSystem.new()
var systems: Array[ParticleSystem] = []
var lights: Array[OmniLight3D] = []
var light_i := 0
var fireballs: Array = []
var flashes: Array = []
var blasts: Array = []
var blast_idx := 0
var shake := 0.0
var storm = null
var breath_acc := 0.0
var breath_light := 0.0
var fb_mesh := SphereMesh.new()
var fb_mat := StandardMaterial3D.new()
var fb_enemy_mat := StandardMaterial3D.new()
var on_explode := Callable() # (posizione, dimensione, proprietario)
var on_ignite := Callable() # (edificio, proprietario): chi ha appiccato il fuoco
var hit_test := Callable() # (palla di fuoco) -> true se ha colpito un drago avversario


func setup(w: World, wt: Water) -> void:
	world = w
	water = wt
	var add_mat := ShaderMaterial.new()
	add_mat.shader = load("res://shaders/particle.gdshader")
	var spark_mat := ShaderMaterial.new()
	spark_mat.shader = add_mat.shader
	spark_mat.set_shader_parameter("kind", 1)
	var smoke_mat := ShaderMaterial.new()
	smoke_mat.shader = load("res://shaders/smoke.gdshader")
	fire.setup(5000, add_mat, 7, 1.2, ParticleSystem.Ramp.FIRE)
	embers.setup(1000, spark_mat, -6, 0.6, ParticleSystem.Ramp.EMBER)
	smoke.setup(2500, smoke_mat, 1.2, 0.35, ParticleSystem.Ramp.SMOKE)
	spray.setup(2000, smoke_mat, -14, 0.8, ParticleSystem.Ramp.SPRAY)
	systems = [smoke, spray, fire, embers]
	for s in systems:
		add_child(s)
	fire.on_collide = _particle_hit
	for i in 6:
		var l := OmniLight3D.new()
		l.light_color = Color(1, 0.48, 0.16)
		l.omni_range = 220
		l.omni_attenuation = 1.6
		l.light_energy = 0
		l.shadow_enabled = false
		add_child(l)
		lights.append(l)
	fb_mesh.radius = 1
	fb_mesh.height = 2
	fb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fb_mat.albedo_color = Color(1, 0.6, 0.25)
	fb_mat.emission_enabled = true
	fb_mat.emission = Color(1, 0.55, 0.2)
	fb_mat.emission_energy_multiplier = 4
	# palle di fuoco viola dei draghi nemici
	fb_enemy_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fb_enemy_mat.albedo_color = Color(0.85, 0.35, 1)
	fb_enemy_mat.emission_enabled = true
	fb_enemy_mat.emission = Color(0.7, 0.2, 1)
	fb_enemy_mat.emission_energy_multiplier = 4
	# lampo sferico e onda d'urto delle esplosioni
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.albedo_color = Color(1, 0.55, 0.2)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.9
	ring.outer_radius = 1.0
	ring.rings = 64
	for i in 8:
		var flash := MeshInstance3D.new()
		flash.mesh = fb_mesh
		flash.material_override = flash_mat.duplicate()
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flash.visible = false
		var wave := MeshInstance3D.new()
		wave.mesh = ring
		wave.material_override = flash_mat.duplicate()
		wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wave.visible = false
		add_child(flash)
		add_child(wave)
		blasts.append({"flash": flash, "wave": wave, "t": 99.0, "r": 1.0})


static func owner_of(flag: int) -> String:
	return "enemy" if flag == 2 else "player"


func _ignite(b: World.Building, owner: String, delay := 0.0) -> void:
	if world.ignite(b, delay) and on_ignite.is_valid():
		on_ignite.call(b, owner)


# Collisione delle fiamme del soffio con terreno, acqua ed edifici
# (flag delle particelle: 1 = fuoco del giocatore, 2 = fuoco di un drago nemico)
func _particle_hit(pos: Vector3, flag: int) -> bool:
	var g := world.ground_height(pos.x, pos.z)
	if pos.y < g + 0.6 or pos.y < 0.4:
		var r := randf()
		if g < 0.5:
			if r < 0.25:
				smoke.spawn(Vector3(pos.x, 0.6, pos.z), Vector3((randf() - 0.5) * 4, 4 + randf() * 4, (randf() - 0.5) * 4), 2.5, 3, 14, 1)
		else:
			if r < 0.04 and not world.char_trees(pos.x, pos.z, 9, 3).is_empty():
				audio.crackle()
			if r < 0.12:
				fire.spawn(Vector3(pos.x, g + 1, pos.z), Vector3((randf() - 0.5) * 6, 5 + randf() * 5, (randf() - 0.5) * 6), 0.7, 3, 6, 1)
			elif r < 0.16:
				smoke.spawn(Vector3(pos.x, g + 2, pos.z), Vector3(0, 5, 0), 4, 4, 18, 0)
		return true
	var b := world.building_at(pos.x, pos.y, pos.z)
	if b != null:
		_ignite(b, owner_of(flag))
		return true
	return false


# acc: accumulatore del drago che soffia (null = il giocatore, che accende anche la luce della bocca)
func emit_breath(dt: float, mouth: Vector3, dir: Vector3, dragon_vel: Vector3, intensity := 1.0, acc = null, flag := 1) -> void:
	var n: float = (breath_acc if acc == null else acc.get("breath", 0.0)) + dt * 560 * intensity
	var upv := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var right := dir.cross(upv).normalized()
	var up2 := right.cross(dir).normalized()
	while n >= 1:
		n -= 1
		var a := randf() * TAU
		var s := sqrt(randf()) * 0.11
		var d := dir + (right * cos(a) + up2 * sin(a)) * s
		var sp := 95 + randf() * 35
		var j := randf() * 2.5
		fire.spawn(mouth + dir * j, d * sp + dragon_vel, 0.75 + randf() * 0.35, 0.8 + randf() * 0.8, 7 + randf() * 5, 0, flag, 0.8)
		if randf() < 0.05:
			embers.spawn(mouth, d * sp * 0.8 + dragon_vel, 1.2, 0.5, 0.3, 0)
	if acc == null:
		breath_acc = n
		breath_light = 1
	else:
		acc.breath = n


# owner: "player" o "enemy" (decide chi viene danneggiato)
func launch_fireball(pos: Vector3, vel: Vector3, size := 2.6, owner := "player") -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = fb_mesh
	mi.material_override = fb_enemy_mat if owner == "enemy" else fb_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * size
	mi.position = pos
	add_child(mi)
	fireballs.append({"mesh": mi, "vel": vel, "t": 0.0, "size": size, "acc": 0.0, "owner": owner})
	if owner == "player":
		audio.whoosh(0.8)


func start_firestorm(dragon: Dragon) -> void:
	storm = {"t": 0.0, "next": 0.25, "n": 0, "dragon": dragon, "acc": 0.0}
	audio.roar()
	shake = maxf(shake, 0.6)


func _spawn_blast(pos: Vector3, radius: float, ground_y: float, on_water: bool) -> void:
	var b: Dictionary = blasts[blast_idx]
	blast_idx = (blast_idx + 1) % blasts.size()
	b.t = 0.0
	b.r = radius
	b.flash.position = pos
	b.flash.visible = true
	b.wave.position = Vector3(pos.x, maxf(ground_y, 0) + 0.8, pos.z)
	b.wave.visible = pos.y - ground_y < radius * 1.2 # l'onda d'urto solo vicino al suolo
	b.wave.material_override.albedo_color = Color(0.6, 0.75, 0.9) if on_water else Color(1, 0.55, 0.2)


# burn = false: l'esplosione non incendia edifici e alberi (colpi della fortezza sulle sue stesse mura)
func explode(pos: Vector3, size := 1.0, owner := "player", burn := true) -> void:
	var g := world.ground_height(pos.x, pos.z)
	var on_water := g < 0.5 and pos.y < 3
	var R := 36 * size
	for i in int(170 * size):
		var d := Vector3(randf() - 0.5, randf() * 0.8 - 0.1, randf() - 0.5).normalized()
		fire.spawn(pos + Vector3(0, 1, 0), d * (15 + randf() * 55), 0.6 + randf() * 0.9, 4 + randf() * 3, 12 + randf() * 10, 2, 0, 2.5)
	for i in int(90 * size):
		var d := Vector3(randf() - 0.5, randf() * 0.9, randf() - 0.5).normalized()
		embers.spawn(pos + Vector3(0, 1, 0), d * (25 + randf() * 60), 1.5 + randf() * 2, 0.7, 0.4, 0)
	for i in int(35 * size):
		smoke.spawn(pos + Vector3((randf() - 0.5) * 20, 4, (randf() - 0.5) * 20),
			Vector3((randf() - 0.5) * 14, 6 + randf() * 10, (randf() - 0.5) * 14), 5 + randf() * 4, 10, 45, 1 if on_water else 0)
	if on_water:
		water.add_pulse(pos.x, pos.z, 3.2 * size)
		for i in int(220 * size):
			var a := randf() * TAU
			var r := randf() * 10
			var sp := 10 + randf() * 30
			spray.spawn(Vector3(pos.x + cos(a) * r, 0.5, pos.z + sin(a) * r),
				Vector3(cos(a) * sp * 0.5, 15 + randf() * 40, sin(a) * sp * 0.5), 1.5 + randf() * 1.5, 2.5, 9, 1)
	elif pos.y - g < R: # le esplosioni in volo non incendiano il suolo
		if burn:
			for b in world.buildings_near(pos.x, pos.z, R):
				var d := Vector2(b.x - pos.x, b.z - pos.z).length()
				if d < R + b.size * 0.5:
					_ignite(b, owner, d * 0.012)
			world.char_trees(pos.x, pos.z, R * 0.85, 40)
		# colonna di fumo
		for i in int(18 * size):
			smoke.spawn(pos + Vector3((randf() - 0.5) * 8, 2, (randf() - 0.5) * 8),
				Vector3((randf() - 0.5) * 5, 22 + randf() * 22, (randf() - 0.5) * 5), 6 + randf() * 3, 8, 38, 0, 0, 0.45)
	_spawn_blast(pos, R * 0.45, g, on_water)
	flashes.append({"pos": pos + Vector3(0, 6, 0), "t": 0.0})
	if on_explode.is_valid():
		on_explode.call(pos, size, owner)


func _update_blasts(dt: float) -> void:
	for b in blasts:
		if b.t > 3:
			continue
		b.t += dt
		var ft: float = b.t / 0.55
		if ft < 1:
			b.flash.scale = Vector3.ONE * b.r * (0.25 + 0.75 * sqrt(ft))
			b.flash.material_override.albedo_color.a = (1 - ft) * (1 - ft)
		else:
			b.flash.visible = false
		var wt: float = b.t / 0.9
		if wt < 1 and b.wave.visible:
			var s: float = b.r * (0.3 + 2.6 * sqrt(wt))
			b.wave.scale = Vector3(s, 0.3, s)
			b.wave.material_override.albedo_color.a = (1 - wt) * (1 - wt) * 0.6
		else:
			b.wave.visible = false


func _light(pos: Vector3, energy: float, color: Color) -> void:
	if light_i >= lights.size():
		return
	var l := lights[light_i]
	light_i += 1
	l.position = pos
	l.light_energy = energy
	l.light_color = color


func update_fx(dt: float, cam_pos: Vector3, mouth_pos) -> void:
	# palle di fuoco
	for i in range(fireballs.size() - 1, -1, -1):
		var f: Dictionary = fireballs[i]
		var mi: MeshInstance3D = f.mesh
		f.t += dt
		f.vel.y -= 14 * dt
		mi.position += f.vel * dt
		var pos := mi.position
		var size: float = f.size
		mi.scale = Vector3.ONE * size * (0.9 + randf() * 0.25)
		f.acc += dt * 90
		while f.acc >= 1:
			f.acc -= 1
			fire.spawn(pos + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * size,
				f.vel * 0.25 + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 6, 0.3 + randf() * 0.3, size * 1.1, size * 2.4, 2)
			if randf() < 0.15:
				smoke.spawn(pos, Vector3(0, 2, 0), 2.5, size * 2, size * 7, 0)
		var g := world.ground_height(pos.x, pos.z)
		if pos.y < maxf(g, 0.3) + size * 0.5 or world.building_at(pos.x, pos.y, pos.z) != null or f.t > 7 				or (hit_test.is_valid() and hit_test.call(f)):
			explode(pos, size / 2.6, f.owner)
			mi.queue_free()
			fireballs.remove_at(i)

	# tempesta di fuoco
	if storm != null:
		var s: Dictionary = storm
		var d: Dragon = s.dragon
		s.t += dt
		var dp := d.position
		while s.next <= s.t and s.n < 30:
			var a: float = s.n * 2.39996 + randf() * 0.3
			var out := 0.45 + randf() * 0.5
			var v := Vector3(cos(a) * out, -0.35 - randf() * 0.5, sin(a) * out).normalized() * (60 + randf() * 40)
			v += d.velocity * 0.6
			launch_fireball(v.normalized() * 8 + dp, v, 2.2 + randf() * 1.2)
			s.n += 1
			s.next += 0.075
		# vortice di fiamme attorno al drago
		s.acc += dt * 300
		while s.acc >= 1:
			s.acc -= 1
			var a := randf() * TAU
			var r: float = 9 + s.t * 5 + randf() * 5
			var tang := 40.0
			fire.spawn(Vector3(dp.x + cos(a) * r, dp.y + (randf() - 0.6) * 14, dp.z + sin(a) * r),
				Vector3(-sin(a) * tang + cos(a) * 18, (randf() - 0.3) * 10, cos(a) * tang + sin(a) * 18) + d.velocity,
				0.4 + randf() * 0.4, 2, 6, 0, 0, 2.5)
		if s.t > 2.6:
			storm = null

	for ps in systems:
		ps.update_particles(dt)
	_update_blasts(dt)

	# luci dinamiche
	light_i = 0
	for i in range(flashes.size() - 1, -1, -1):
		var f: Dictionary = flashes[i]
		f.t += dt
		if f.t > 0.9:
			flashes.remove_at(i)
			continue
		_light(f.pos, 40.0 * pow(1 - f.t / 0.9, 2), Color(1, 0.63, 0.25))
	if breath_light > 0 and mouth_pos != null:
		_light(mouth_pos - Vector3(0, 6, 0), 6.0 * breath_light * (0.8 + randf() * 0.4), Color(1, 0.54, 0.19))
		breath_light = maxf(0, breath_light - dt * 6)
	var fbs := fireballs.duplicate()
	fbs.sort_custom(func(a, b): return a.mesh.position.distance_squared_to(cam_pos) < b.mesh.position.distance_squared_to(cam_pos))
	for k in mini(2, fbs.size()):
		_light(fbs[k].mesh.position, 20.0, Color(1, 0.56, 0.25))
	for b in world.nearest_fires(cam_pos, 6):
		_light(Vector3(b.x, lerpf(b.base, b.top, 0.6) + 4, b.z), 14.0 * b.fire * (0.75 + randf() * 0.25) * (0.6 + b.size * 0.05), Color(1, 0.44, 0.12))
	for k in range(light_i, lights.size()):
		lights[k].light_energy = 0

	shake = maxf(0, shake - dt * 1.5)
