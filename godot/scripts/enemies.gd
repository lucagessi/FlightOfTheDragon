# Draghi guardiani: ognuno protegge un villaggio e gli vola intorno. Diventano ostili se li attacchi o se incendi
# il loro villaggio: inseguono, sputano fuoco e palle di fuoco viola, e si calmano se ti allontani.
# Hanno una barra della vita; quando muoiono precipitano in fiamme ed esplodono (porting di src/enemies.js)
class_name Enemies
extends Node3D

const TYPES := [
	{"name": "Drago di Smeraldo", "hp": 100.0, "scale": 0.5, "speed": 0.55, "fireball_every": 3.2, "palette": {
		"back": Color(0.06, 0.3, 0.1), "ridge": Color(0.02, 0.12, 0.04), "belly": Color(0.75, 0.7, 0.35),
		"skin": 0x0f4a1c, "dark": 0x0a2a10, "membrane": 0x1f5a22, "membrane_glow": 0x041a06, "eye": Color(0.6, 1, 0.2)}},
	{"name": "Drago di Zaffiro", "hp": 120.0, "scale": 0.52, "speed": 0.65, "fireball_every": 2.6, "palette": {
		"back": Color(0.05, 0.15, 0.45), "ridge": Color(0.02, 0.05, 0.2), "belly": Color(0.7, 0.75, 0.85),
		"skin": 0x123070, "dark": 0x0a1840, "membrane": 0x1e3a7a, "membrane_glow": 0x040a24, "eye": Color(0.3, 0.9, 1)}},
	{"name": "Drago d'Ambra", "hp": 140.0, "scale": 0.56, "speed": 0.6, "fireball_every": 3.0, "palette": {
		"back": Color(0.55, 0.35, 0.05), "ridge": Color(0.3, 0.15, 0.02), "belly": Color(0.9, 0.8, 0.5),
		"skin": 0x6a3e0a, "dark": 0x3a2205, "membrane": 0x7a4a10, "membrane_glow": 0x201004, "eye": Color(1, 0.5, 0.1)}},
	{"name": "Drago d'Ombra", "hp": 220.0, "scale": 0.7, "speed": 0.75, "fireball_every": 2.0, "palette": {
		"back": Color(0.08, 0.07, 0.1), "ridge": Color(0.03, 0.03, 0.04), "belly": Color(0.35, 0.3, 0.4),
		"skin": 0x1a1820, "dark": 0x111015, "membrane": 0x2a2233, "membrane_glow": 0x0a0410, "eye": Color(0.8, 0.2, 1)}},
]

const GUARD_RADIUS := 2200.0 # oltre questa distanza dal villaggio il guardiano smette di inseguire
const CALM_TIME := 25.0 # secondi fuori dal territorio prima che si calmi
const BREATH_RANGE := 110.0
const MAX_GUARDIANS := 5

var world: World
var fx: FX
var hud: HUD
var list: Array = []
var kills := 0
var spawn_timer := 0.0
var started := false
var on_kill := Callable() # (nemico)
var on_hostile := Callable() # (nemico, motivo: "village" o "attack")
var on_calm := Callable() # (nemico)


func setup(w: World, f: FX, h: HUD) -> void:
	world = w
	fx = f
	hud = h


# Villaggi senza guardiano
func unguarded() -> Array:
	var guarded := {}
	for e in list:
		guarded[e.home.name] = true
	return world.villages.filter(func(v): return not guarded.has(v.name))


# Ogni drago protegge un villaggio: nasce lì e ci vola intorno
func spawn(home: Dictionary, type: Dictionary) -> void:
	var d := Dragon.new(type.scale, type.palette)
	var ground := maxf(world.ground_height(home.x, home.z), 0)
	var a := randf() * TAU
	var r: float = home.r + 150 + randf() * 120
	d.position = Vector3(home.x + cos(a) * r, ground + 130 + randf() * 60, home.z + sin(a) * r)
	d.yaw = a + PI / 2
	d.throttle = 0.3
	add_child(d)
	list.append({
		"dragon": d, "type": type, "home": home, "hp": type.hp, "max_hp": type.hp,
		"bar": hud.add_enemy_bar(type.name, "guardiano di " + home.name),
		"patrol": {"a": a, "r": r, "alt": ground + 130 + randf() * 60},
		"fire_cd": 2 + randf() * 2, "breath_t": 0.0, "breath_cd": 0.0, "flash": 0.0,
		"hostile": false, "calm_t": 0.0, "dying_t": 0.0, "acc": {}, "smoke_acc": 0.0,
	})


func spawn_initial(player: Dragon) -> void:
	for v in world.villages:
		if v.kind == "castle":
			spawn(v, TYPES[3])
	var pp := Vector2(player.position.x, player.position.z)
	var villages := world.villages.filter(func(v): return v.kind == "village")
	villages.sort_custom(func(a, b): return pp.distance_to(Vector2(a.x, a.z)) < pp.distance_to(Vector2(b.x, b.z)))
	# un guardiano ogni due villaggi, partendo dai più vicini
	var i := 0
	while i < villages.size() and list.size() < MAX_GUARDIANS:
		spawn(villages[i], TYPES[list.size() % 3])
		i += 2


func guardian_of(village):
	if village == null:
		return null
	for e in list:
		if e.home.name == village.name and not e.dragon.dying:
			return e
	return null


func provoke(e, reason: String) -> void:
	if e == null or e.dragon.dying:
		return
	e.calm_t = 0.0
	if e.hostile:
		return
	e.hostile = true
	e.fire_cd = minf(e.fire_cd, 1.5)
	if on_hostile.is_valid():
		on_hostile.call(e, reason)


# Un edificio di un villaggio è stato incendiato dal giocatore
func village_attacked(village) -> void:
	provoke(guardian_of(village), "village")


func alive() -> Array:
	return list.filter(func(e): return not e.dragon.dying)


func damage(e: Dictionary, amount: float) -> void:
	var d: Dragon = e.dragon
	if d.dying:
		return
	e.hp -= amount
	e.flash = 1.0
	provoke(e, "attack")
	if e.hp <= 0:
		e.hp = 0.0
		d.dying = true
		d.breathing = false


# Danno ad area (esplosioni del giocatore)
func splash(pos: Vector3, radius: float, amount: float) -> void:
	for e in list:
		var d: float = e.dragon.position.distance_to(pos)
		if d < radius:
			damage(e, amount * (1 - d / radius * 0.6))


# Una palla di fuoco del giocatore ha colpito un drago?
func projectile_hit(pos: Vector3, size: float) -> bool:
	for e in list:
		if not e.dragon.dying and e.dragon.position.distance_to(pos) < 9 * e.type.scale / 0.5 + size:
			return true
	return false


# Bersaglio per la mira assistita: il nemico più vicino davanti al giocatore
func target(player: Dragon, max_dist := 320.0, cone := 0.55):
	var best = null
	var best_d := INF
	for e in list:
		if e.dragon.dying:
			continue
		var to: Vector3 = e.dragon.position - player.position
		var d := to.length()
		if d > max_dist or d < 1:
			continue
		if (to / d).dot(player.forward) < cos(cone):
			continue
		if d < best_d:
			best = e
			best_d = d
	return best


# Cono del soffio: il bersaglio è dentro le fiamme?
static func in_breath(mouth: Vector3, dir: Vector3, tgt: Vector3, radius: float, rng := BREATH_RANGE) -> bool:
	var dv := tgt - mouth
	var d := dv.length()
	if d > rng:
		return false
	return (dv / maxf(d, 0.01)).angle_to(dir) < atan(radius / maxf(d, 1)) + 0.12


static func _wrap(a: float) -> float:
	return atan2(sin(a), cos(a))


func update_enemies(dt: float, player: Dragon, player_alive: bool) -> Dictionary:
	var events := {"player_damage": 0.0}
	var P := player.position
	if not started:
		started = true
		spawn_initial(player)
		spawn_timer = 45.0
	# un nuovo guardiano arriva in un villaggio scoperto, lontano dal giocatore
	if alive().size() < MAX_GUARDIANS:
		spawn_timer -= dt
		if spawn_timer <= 0:
			var free := unguarded().filter(func(v): return v.kind == "village" and Vector2(v.x - P.x, v.z - P.z).length() > 1200)
			if not free.is_empty():
				spawn(free.pick_random(), TYPES[randi() % 3])
			spawn_timer = 45 + randf() * 20

	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		var d: Dragon = e.dragon
		var to := P - d.position
		var dist := to.length()
		var ctrl := {"steer": 0.0, "climb": 0.0, "throttle": 0.0, "fire": false}

		if not d.dying:
			# ostile solo se provocato; insegue finché il giocatore resta nel suo territorio
			var from_home := Vector2(P.x - e.home.x, P.z - e.home.z).length()
			var engaged: bool = e.hostile and player_alive and from_home < GUARD_RADIUS and dist < 2600
			if e.hostile and not engaged:
				e.calm_t += dt
				if e.calm_t > CALM_TIME:
					e.hostile = false
					e.calm_t = 0.0
					if on_calm.is_valid():
						on_calm.call(e)
			var t: Vector3
			if engaged:
				# insegue con un po' di anticipo, restando leggermente sopra
				t = Vector3(P.x + player.velocity.x * 0.6, P.y + 12, P.z + player.velocity.z * 0.6)
				if dist < 55: # troppo vicino: si allontana
					t = Vector3(d.position.x - to.x, d.position.y + 30, d.position.z - to.z)
			else:
				# ronda attorno al proprio villaggio
				e.patrol.a += dt * 0.16
				t.x = e.home.x + cos(e.patrol.a) * e.patrol.r
				t.z = e.home.z + sin(e.patrol.a) * e.patrol.r
				t.y = maxf(e.patrol.alt, world.ground_height(t.x, t.z) + 60)
			var err := _wrap(atan2(t.x - d.position.x, t.z - d.position.z) - d.yaw)
			ctrl.steer = clampf(-err * 2.2, -1, 1)
			ctrl.climb = clampf((t.y - d.position.y) / 60, -1, 1)
			var sp: float = e.type.speed
			var want: float = (sp + 0.25 if dist > 350 else (sp - 0.25 if dist < 130 else sp)) if engaged else 0.3
			ctrl.throttle = 0.0 if absf(want - d.throttle) < 0.03 else signf(want - d.throttle)

			var facing := to.normalized().dot(d.forward) if engaged else -1.0
			d.aim_target = null
			if engaged and dist < 400:
				d.aim_target = P
			# soffio di fuoco a raffiche quando è vicino
			e.breath_cd -= dt
			if engaged and dist < BREATH_RANGE + 20 and facing > 0.8 and e.breath_cd <= 0:
				e.breath_t = 1.2 + randf()
				e.breath_cd = 3 + randf() * 2
			e.breath_t -= dt
			d.breathing = e.breath_t > 0
			# palle di fuoco a media distanza
			e.fire_cd -= dt
			if engaged and dist > 140 and dist < 650 and facing > 0.85 and e.fire_cd <= 0:
				e.fire_cd = e.type.fireball_every * (0.7 + randf() * 0.6)
				var m: Vector3 = d.get_mouth()[0]
				var speed := 150.0
				var aim := (P + player.velocity * (dist / speed * 0.6) - m).normalized()
				fx.launch_fireball(m + aim * 3, aim * speed + d.velocity * 0.3, 2.2, "enemy")
				d.roaring = 0.3
		else:
			d.breathing = false
			d.aim_target = null
			e.dying_t += dt
			# scia di fuoco e fumo durante la caduta
			e.smoke_acc += dt * 40
			while e.smoke_acc >= 1:
				e.smoke_acc -= 1
				var p := d.position
				fx.fire.spawn(Vector3(p.x + (randf() - 0.5) * 6, p.y, p.z + (randf() - 0.5) * 6),
					Vector3((randf() - 0.5) * 6, 4, (randf() - 0.5) * 6), 0.6, 3, 7, 1)
				if randf() < 0.5:
					fx.smoke.spawn(p, Vector3(0, 3, 0), 4, 4, 18, 0)

		# i draghi lontani non animano corpo e ali (risparmio di calcoli)
		d.visible = dist < 7000
		d.update_dragon(dt, ctrl, world, dist < 2500)
		if d.breathing:
			var mo := d.get_mouth()
			fx.emit_breath(dt, mo[0], mo[1], d.velocity, 0.6, e.acc, 2)
			if player_alive and in_breath(mo[0], mo[1], P, 9):
				events.player_damage += 16 * dt

		# schianto a terra / in mare
		if d.dying and (d.altitude < 3 or e.dying_t > 8):
			fx.explode(d.position, 1.3, "none")
			e.bar.box.queue_free()
			d.queue_free()
			list.remove_at(i)
			kills += 1
			if on_kill.is_valid():
				on_kill.call(e)
			continue

		# lampo quando viene colpito
		e.flash = maxf(0, e.flash - dt * 4)
		d.set_flash(e.flash)
	return events


# Barre della vita sopra i draghi (dopo l'aggiornamento della camera, per non tremolare)
func update_bars(camera: Camera3D) -> void:
	var vs := camera.get_viewport().get_visible_rect().size
	for e in list:
		var d: Dragon = e.dragon
		var box: Control = e.bar.box
		var dist := d.position.distance_to(camera.global_position)
		var p := d.position + Vector3(0, 9 * e.type.scale / 0.5, 0)
		var visible := dist < 1600 and not camera.is_position_behind(p)
		var sp := Vector2.ZERO
		if visible:
			sp = camera.unproject_position(p)
			visible = sp.x > -0.05 * vs.x and sp.x < 1.05 * vs.x and sp.y > -0.05 * vs.y and sp.y < 1.05 * vs.y
		box.visible = visible
		if not visible:
			continue
		box.position = sp - Vector2(box.size.x / 2, box.size.y)
		box.modulate.a = (1.0 if dist < 900 else 1 - (dist - 900) / 700) * (0.4 if d.dying else 1.0)
		hud.set_enemy_bar(e.bar, e.hp / e.max_hp, e.hostile)
