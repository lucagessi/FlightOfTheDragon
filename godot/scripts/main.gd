# Il Volo del Drago — ciclo di gioco, ambiente, camera in terza persona (porting di src/main.js)
extends Node3D

# sole: elevazione 17°, azimut 210° (come sky.js)
const SUN_DIR := Vector3(-0.47815, 0.29237, -0.82818)
const FOG_DENSITY := 0.0009 # foschia volumetrica a terra (in alto si dirada, vedi _process)
const DEAD_CTRL := {"steer": 0.0, "climb": 0.0, "throttle": 0.0, "fire": false, "look_x": 0.0, "look_y": 0.15, "zoom": 0.0, "actions": []}

var world: World
var grass: Grass
var water: Water
var dragon: Dragon
var fx: FX
var enemies: Enemies
var audio: GameAudio
var input: GameInput
var hud: HUD
var camera := Camera3D.new()
var sun := DirectionalLight3D.new()
var env: Environment

var started := false
var paused := false
var time := 0.0
var energy := 100.0
var storm_cd := 0.0
var fireball_cd := 0.0
var wake_t := 0.0
var flap_shake := 0.0
var player_hp := 100.0
var player_alive := true
var dead_t := 0.0
var last_hit_t := -10.0
var invuln := 0.0
var crashed := false
var hurt := 0.0
var cam_offset := Vector3(0, 10, -35)
var cam_up := Vector3.UP
var cam_fov := 62.0
var cam_dist := 34.0
var current_village = null
var was_in_fortress := false
var announced := {}
var screenshot_path := ""
var screenshot_t := -1.0
var test_breathe := false
var test_closeup := false
var closeup_pos := Vector3.ZERO
var closeup_target := Vector3.ZERO
var closeup_angle := 0.0
var closeup_dist := 11.0
var test_burn_house := false # --burnhouse: con --closeup incendia la casa inquadrata
var test_lookup := false # --lookup: con --closeup guarda in alto, sopra la casa (per il cielo)
var test_backlit := false # --backlit: con --closeup sceglie una casa con la facciata in controluce


func _ready() -> void:
	_setup_environment()
	world = World.new()
	world.name = "World"
	add_child(world)
	world.generate()
	grass = Grass.new()
	grass.setup(world)
	add_child(grass)
	water = Water.new()
	add_child(water)
	water.setup(world.data_tex)
	audio = GameAudio.new()
	add_child(audio)
	fx = FX.new()
	fx.audio = audio
	add_child(fx)
	fx.setup(world, water)
	world.fx = fx
	fx.on_explode = _on_explode
	dragon = Dragon.new()
	dragon.position = Vector3(-300, 70, -2750)
	dragon.yaw = 0.15
	add_child(dragon)
	input = GameInput.new()
	add_child(input)
	camera.fov = 62
	camera.near = 1.5
	camera.far = 60000
	add_child(camera)
	camera.make_current()
	hud = HUD.new()
	add_child(hud)
	hud.setup(world)
	enemies = Enemies.new()
	add_child(enemies)
	enemies.setup(world, fx, hud, audio)
	enemies.on_kill = func(e): hud.show_msg("%s abbattuto!" % e.type.name)
	enemies.on_hostile = _on_hostile
	enemies.on_calm = func(e): hud.show_msg("%s torna a sorvegliare %s" % [e.type.name, e.home.name], "small")
	# le palle di fuoco esplodono quando raggiungono un drago avversario
	fx.hit_test = _hit_test
	fx.on_ignite = _on_ignite
	world.fortress.setup(fx, hud, audio)
	world.fortress.on_player_damage = _damage_player
	# --screenshot=<file> [--shot-time=<s>]: salva un'immagine e chiude (per le verifiche)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			screenshot_path = arg.split("=")[1]
			screenshot_t = 4.0
		elif arg.begins_with("--shot-time="):
			screenshot_t = float(arg.split("=")[1])
		elif arg == "--start":
			_start_game.call_deferred()
		elif arg == "--burn":
			_burn_nearest.call_deferred()
		elif arg == "--breathe":
			test_breathe = true
		elif arg == "--novsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		elif arg == "--land":
			_test_land.call_deferred()
		elif arg == "--peak":
			_test_peak.call_deferred()
		elif arg.begins_with("--fortress"):
			_test_fortress.call_deferred(arg.split("=")[1] if "=" in arg else "")
		elif arg == "--guardian":
			_test_guardian.call_deferred()
		elif arg == "--nohud":
			hud.visible = false
		elif arg == "--burnhouse":
			test_burn_house = true
		elif arg == "--lookup":
			test_lookup = true
		elif arg == "--backlit":
			test_backlit = true
		elif arg == "--house":
			_test_house.call_deferred()
		elif arg.begins_with("--closeup"):
			test_closeup = true
			# --closeup=<angolo>[:<distanza>]
			var cv := arg.split("=")[1].split(":") if "=" in arg else PackedStringArray(["0"])
			closeup_angle = float(cv[0])
			if cv.size() > 1:
				closeup_dist = float(cv[1])
			_test_house.call_deferred()
	print("Mondo: %d villaggi, %d edifici, %d alberi" % [world.villages.size(), world.stats.total, world.trees.size()])


func _setup_environment() -> void:
	# cielo con i cumuli (shaders/sky.gdshader)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 1.3
	# luce ambiente in parte dal cielo e in parte grigio calda (rimbalzo del suolo): ombre meno blu
	env.ambient_light_sky_contribution = 0.7
	env.ambient_light_color = Color(0.66, 0.62, 0.55)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.4
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.95
	# foschia: le distanze sfumano in un velo chiaro e caldo, più fitto in basso, con il bagliore verso il sole
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.78, 0.84)
	env.fog_density = 0.0002
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.2
	env.fog_sun_scatter = 0.3
	env.fog_height = 40.0
	env.fog_height_density = 0.004
	# foschia volumetrica vicina: raggi di sole tra i monti e bagliore degli incendi nel fumo
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = FOG_DENSITY
	env.volumetric_fog_albedo = Color(0.85, 0.9, 1.0)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 1200
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.4
	env.volumetric_fog_sky_affect = 0.0
	# occlusione ambientale, luce indiretta e riflessi in spazio schermo (il mare riflette isole e drago)
	env.ssao_enabled = true
	env.ssao_radius = 3.0
	env.ssao_intensity = 2.0
	env.ssao_power = 1.5
	env.ssil_enabled = true
	env.ssil_radius = 8.0
	env.ssil_intensity = 0.6
	env.ssr_enabled = true
	env.ssr_max_steps = 96
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# luce del sole con ombre
	sun.light_color = Color(1.0, 0.91, 0.78)
	sun.light_energy = 1.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1500
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.basis = Basis.looking_at(-SUN_DIR, Vector3.UP)
	add_child(sun)


func _start_game() -> void:
	if started:
		return
	started = true
	audio.start()
	hud.show_game()
	dragon.throttle = 0.35
	hud.show_msg("Spicca il volo!")
	get_tree().create_timer(1.4).timeout.connect(func(): hud.show_msg("Premi H per comandi e combinazioni", "small"))


# Per le verifiche: incendia il villaggio più vicino al drago
func _burn_nearest() -> void:
	var best = null
	for v in world.villages:
		if best == null or Vector2(v.x - dragon.position.x, v.z - dragon.position.z).length() < Vector2(best.x - dragon.position.x, best.z - dragon.position.z).length():
			best = v
	for id in best.ids.slice(0, 12):
		world.ignite(world.buildings[id])
	dragon.position = Vector3(best.x - 150, best.h + 70, best.z - 200)
	dragon.yaw = atan2(best.x - dragon.position.x, best.z - dragon.position.z)


# Per le verifiche: davanti alla vetta più alta, controsole
func _test_peak() -> void:
	var best := 0
	for k in world.hgrid.size():
		if world.hgrid[k] > world.hgrid[best]:
			best = k
	var px := -World.HALF + (best % World.N) * World.STEP
	var pz := -World.HALF + (best / World.N) * World.STEP
	var ph := world.hgrid[best]
	dragon.position = Vector3(px + 520, ph * 0.75, pz + 380)
	dragon.yaw = atan2(px - dragon.position.x, pz - dragon.position.z)
	dragon.throttle = 0.0
	dragon.speed = 30


# Per le verifiche: a terra davanti alle case del villaggio più vicino
func _test_house() -> void:
	_burn_nearest()
	world.burning.clear()
	var v = current_village_of(dragon.position)
	var b: World.Building = world.buildings[v.ids[v.ids.size() / 2]]
	# meglio una casa signorile, la più vicina tra le più ricche (terzo piano, ballatoio, bovindo)
	var best := INF
	var show = null
	for h in world.showcase:
		var dd: float = Vector2(h.b.x - dragon.position.x, h.b.z - dragon.position.z).length() - h.score * 5000.0
		if test_backlit:
			# facciata rivolta dalla parte opposta al sole: in ombra, con il cielo luminoso dietro
			dd += Vector2(sin(h.rot), cos(h.rot)).dot(Vector2(SUN_DIR.x, SUN_DIR.z).normalized()) * 20000.0
		if dd < best:
			best = dd
			show = h
	if show != null:
		b = show.b
	var a := 2.2
	if show != null:
		a = atan2(-cos(show.rot), -sin(show.rot)) # il drago di lato, fuori dall'inquadratura
	dragon.position = Vector3(b.x + cos(a) * 38, 0, b.z + sin(a) * 38)
	dragon.position.y = world.ground_height(dragon.position.x, dragon.position.z) + Dragon.STAND
	dragon.yaw = atan2(b.x - dragon.position.x, b.z - dragon.position.z)
	dragon.mode = "ground"
	dragon.ground_blend = 1
	dragon.speed = 0
	cam_offset = -dragon.forward * 30 + Vector3(0, 12, 0)
	# inquadratura ravvicinata della casa (--closeup)
	var to := Vector3(SUN_DIR.x, 0, SUN_DIR.z).normalized().rotated(Vector3.UP, closeup_angle)
	closeup_target = Vector3(b.x, b.base + 4, b.z)
	closeup_pos = closeup_target + to.rotated(Vector3.UP, 0.5) * 17 + Vector3(0, 3, 0)
	if show != null:
		# ad altezza d'uomo davanti alla facciata con il portale, un po' di sbieco (closeup_angle lo ruota)
		var front := Vector3(sin(show.rot), 0, cos(show.rot))
		var side := Vector3(cos(show.rot), 0, -sin(show.rot))
		var door: Vector3 = Vector3(b.x, show.floor, b.z) + front * show.d / 2
		# il primo punto di vista libero (fuori dalle altre case, con la porta in vista) ruotando e avvicinandosi
		var eye := Vector3.ZERO
		for k in 40:
			var ang := closeup_angle + (k % 8) * 0.22 * (1 if k % 2 == 0 else -1)
			var dist := closeup_dist * (1.0 - (k / 8) * 0.12)
			var e: Vector3 = door + (front * dist + side * dist * 0.4).rotated(Vector3.UP, ang)
			e.y = world.ground_height(e.x, e.z) + 1.7
			var clear := true
			for t in 12:
				var q := e.lerp(door + Vector3(0, 1.5, 0), t / 12.0)
				var hit := world.building_at(q.x, q.y, q.z)
				if hit != null and hit != b:
					clear = false
					break
			if clear:
				eye = e
				break
		closeup_pos = eye if eye != Vector3.ZERO else door + front * closeup_dist + Vector3(0, 1.7, 0)
		closeup_target = door + Vector3(0, 3.8, 0) - side * 0.8
	if test_burn_house:
		world.ignite(b)
	if test_lookup:
		closeup_target += Vector3(0, 16, 0)


# Per le verifiche: di fronte al guardiano più vicino, già ostile
func _test_guardian() -> void:
	_start_game()
	enemies.started = true
	enemies.spawn_initial(dragon)
	var e = enemies.target(dragon, 1e9, PI)
	var d: Dragon = e.dragon
	dragon.position = d.position + Vector3(sin(d.yaw), 0, cos(d.yaw)) * 260
	dragon.yaw = d.yaw + PI
	enemies.provoke(e, "attack")


# Per le verifiche: davanti alla fortezza, già risvegliata (view: camera ferma che la inquadra tutta)
func _test_fortress(view := "") -> void:
	_start_game()
	var f := world.fortress
	var a := float(view) if view.is_valid_float() else 2.4
	dragon.position = f.center + Vector3(cos(a) * 750, -f.center.y * 0.2, sin(a) * 750)
	dragon.yaw = atan2(f.center.x - dragon.position.x, f.center.z - dragon.position.z)
	dragon.throttle = 0.1
	if view == "post":
		# da vicino sulle armi del mastio
		test_closeup = true
		var w: Dictionary = f.weapons[0]
		closeup_target = w.pos + Vector3(0, 2, 0)
		closeup_pos = w.pos + (w.pos - f.center).normalized() * 28 + Vector3(0, 14, 0)
		f.awaken("attack")
	elif view != "":
		test_closeup = true
		closeup_target = f.center + Vector3(0, -f.center.y * 0.4, 0)
		closeup_pos = f.center + Vector3(cos(a) * 950, 40, sin(a) * 950)
	else:
		f.awaken("attack")


func current_village_of(p: Vector3):
	var best = null
	for v in world.villages:
		if v.kind == "village" and (best == null or Vector2(v.x - p.x, v.z - p.z).length() < Vector2(best.x - p.x, best.z - p.z).length()):
			best = v
	return best


# Per le verifiche: atterra vicino al villaggio più vicino
func _test_land() -> void:
	_burn_nearest()
	var g := world.ground_height(dragon.position.x, dragon.position.z)
	dragon.position.y = g + 25
	dragon.land(world)


func _on_explode(pos: Vector3, size: float, owner: String) -> void:
	var d := pos.distance_to(camera.position)
	audio.explosion(d)
	fx.shake = maxf(fx.shake, clampf(1.2 - d / 400, 0, 1) * size)
	if owner == "player":
		enemies.splash(pos, 45 * size, 45)
		world.fortress.splash(pos, 45 * size, 45)
	elif owner == "enemy" and player_alive:
		var pd := pos.distance_to(dragon.position)
		if pd < 30:
			_damage_player(20 * (1 - pd / 30) + 4)


func _hit_test(f: Dictionary) -> bool:
	var pos: Vector3 = f.mesh.position
	if f.owner == "player":
		return enemies.projectile_hit(pos, f.size)
	return f.owner == "enemy" and player_alive and pos.distance_to(dragon.position) < 8 + f.size


# il guardiano di un villaggio si arrabbia solo se è il giocatore ad appiccare il fuoco
func _on_ignite(b: World.Building, owner: String) -> void:
	if owner == "player":
		enemies.village_attacked(b.village)
		if world.fortress.owns(b):
			world.fortress.awaken("fire")


func _on_hostile(e: Dictionary, reason: String) -> void:
	if reason == "village":
		hud.show_msg("%s difende %s!" % [e.type.name, e.home.name], "bad")
	else:
		hud.show_msg("Hai provocato il %s!" % e.type.name, "bad")
	audio.roar(maxf(0.25, 1 - e.dragon.position.distance_to(camera.position) / 2500))
	e.dragon.roaring = 1.5


func _damage_player(amount: float) -> void:
	if not player_alive or invuln > 0 or not started:
		return
	player_hp -= amount
	last_hit_t = time
	hurt = minf(1, hurt + amount / 25)
	fx.shake = maxf(fx.shake, minf(0.8, amount / 30))
	if player_hp <= 0:
		player_hp = 0
		player_alive = false
		dead_t = 0
		crashed = false
		dragon.dying = true
		dragon.breathing = false
		audio.roar(0.8)
		hud.show_msg("Sei stato abbattuto!", "bad")


func _respawn() -> void:
	player_alive = true
	player_hp = 100
	invuln = 3
	dragon.dying = false
	dragon.mode = "air"
	dragon.pitch = 0.3
	dragon.position.y = maxf(dragon.ground_y, 0) + 180
	energy = 100
	hud.show_msg("Di nuovo in volo!", "small")


# Polvere sollevata dalle ali vicino al suolo
func _dust(pos: Vector3, n: int, radius: float) -> void:
	var g := maxf(world.ground_height(pos.x, pos.z), 0)
	for i in n:
		var a := randf() * TAU
		var r := 4 + randf() * radius * 0.5
		var sp := 10 + randf() * radius
		fx.smoke.spawn(Vector3(pos.x + cos(a) * r, g + 1, pos.z + sin(a) * r),
			Vector3(cos(a) * sp, 2 + randf() * 4, sin(a) * sp), 1.5 + randf() * 1.5, 4, 14, 0, 0, 1.5)


func _autopilot() -> Dictionary:
	return {
		"steer": sin(time * 0.13) * 0.35,
		"climb": clampf((75 - dragon.altitude) / 60, -0.5, 0.5),
		"throttle": 0.0, "fire": false, "look_x": sin(time * 0.07) * 0.35, "look_y": 0.05, "zoom": 0.0, "actions": [],
	}


func _handle_actions(actions: Array) -> void:
	for a in actions:
		if a == "help":
			hud.toggle_help()
			continue
		if a == "mute":
			audio.set_muted(not audio.muted)
			hud.show_msg("Audio disattivato" if audio.muted else "Audio attivato", "small")
			continue
		if a == "invert":
			hud.show_msg("Asse verticale invertito" if input.invert_y else "Asse verticale normale", "small")
			continue
		if a == "pad":
			hud.show_msg("Joystick collegato", "small")
			continue
		if not started:
			if a == "start":
				_start_game()
			continue
		if a == "pause":
			paused = not paused
			continue
		if paused or not player_alive:
			continue
		match a:
			"land":
				if dragon.mode == "ground":
					if dragon.take_off():
						audio.whoosh(1.2)
						hud.show_msg("Decollo!", "small")
				elif dragon.mode == "air":
					var r := dragon.land(world)
					if r == "ok":
						hud.show_msg("Atterraggio…", "small")
					elif r == "water":
						hud.show_msg("Non puoi atterrare sull'acqua", "bad")
					elif r == "high":
						hud.show_msg("Scendi più in basso per atterrare", "bad")
			"fireball":
				if energy >= 18 and fireball_cd <= 0:
					energy -= 18
					fireball_cd = 0.35
					var m := dragon.get_mouth()
					var dir: Vector3 = dragon.aim_dir if dragon.mode == "ground" else m[1]
					var vel := dir * 150 + dragon.velocity
					# con un drago nemico nel mirino, la palla di fuoco punta dove si troverà
					var tgt = enemies.target(dragon, 700, 0.45) if dragon.mode == "air" else null
					var post = world.fortress.target(dragon, 700, 0.35) if dragon.mode == "air" and tgt == null else null
					if tgt != null:
						var td: Dragon = tgt.dragon
						dir = (td.position + td.velocity * (td.position.distance_to(m[0]) / 170) - m[0]).normalized()
						vel = dir * 170 + dragon.velocity * 0.2
					elif post != null:
						dir = (post.pos + Vector3(0, 2, 0) - m[0]).normalized()
						vel = dir * 170 + dragon.velocity * 0.2
					fx.launch_fireball(m[0] + dir * 3, vel, 3)
					dragon.roaring = 0.3
					hud.show_msg("Palla di fuoco!")
				else:
					hud.show_msg("Fuoco esaurito", "bad")
			"firestorm":
				if storm_cd > 0:
					hud.show_msg("Tempesta pronta tra %ds" % ceili(storm_cd), "bad")
				elif energy < 50:
					hud.show_msg("Serve più fuoco", "bad")
				else:
					energy -= 50
					storm_cd = 12
					fx.start_firestorm(dragon)
					dragon.roaring = 2.4
					hud.show_msg("TEMPESTA DI FUOCO!")
			"rollLeft", "rollRight":
				if dragon.start_roll(-1 if a == "rollLeft" else 1):
					audio.whoosh(1)
					hud.show_msg("Piroetta!", "small")
			"loop":
				if dragon.start_loop():
					audio.whoosh(1.3)
					hud.show_msg("Giro della morte!", "small")


func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 20.0)
	var ctrl_in := input.update_input(dt)
	_handle_actions(ctrl_in.actions)
	if screenshot_t >= 0:
		screenshot_t -= delta
		if screenshot_t < 0:
			get_viewport().get_texture().get_image().save_png(screenshot_path)
			print("Screenshot: ", screenshot_path, " fps=", Engine.get_frames_per_second())
			get_tree().quit()
	if paused:
		hud.update_hud(dt, _hud_state())
		return
	time += dt
	var c: Dictionary = _autopilot() if not started else (ctrl_in if player_alive else DEAD_CTRL)
	# a terra: W/S cammina, A/D gira, frecce/mouse destro/levetta destra muovono la testa
	var grounded := dragon.mode != "air"
	input.set_pointer_lock(started and player_alive and dragon.mode == "ground")
	if grounded and started and player_alive:
		c = ctrl_in.duplicate()
		c.steer = ctrl_in.walk_steer
		c.climb = ctrl_in.walk
		c.look_x = 0.0
		c.look_y = 0.0
	if test_breathe:
		c = c.duplicate()
		c.fire = true
	# mira assistita sul drago nemico più vicino davanti (solo in volo)
	var aim = enemies.target(dragon) if started and player_alive and not grounded else null
	var post = world.fortress.target(dragon) if started and player_alive and not grounded and aim == null else null
	if not grounded:
		dragon.aim_target = aim.dragon.position if aim != null else (post.pos + Vector3(0, 2, 0) if post != null else null)

	# soffio di fuoco
	var breathing: bool = started and player_alive and c.fire and energy > 1
	dragon.breathing = breathing
	var ev := dragon.update_dragon(dt, c, world)
	if ev.touchdown:
		audio.flap(1.6)
		fx.shake = maxf(fx.shake, 0.5)
		_dust(dragon.position, 70, 26)
		hud.show_msg("A terra", "small")
	if ev.downstroke and grounded:
		_dust(dragon.position, 25, 18)
	var mouth_pos = null
	if breathing:
		energy = maxf(0, energy - dt * 22)
		var m := dragon.get_mouth()
		mouth_pos = m[0]
		# a terra il fuoco va esattamente dove guarda la testa
		var dir: Vector3 = dragon.aim_dir if dragon.mode == "ground" else m[1]
		fx.emit_breath(dt, m[0], dir, dragon.velocity)
		for e in enemies.list:
			if not e.dragon.dying and Enemies.in_breath(m[0], dir, e.dragon.position, 8 * e.type.scale / 0.5):
				enemies.damage(e, 34 * dt)
		world.fortress.breath_hit(m[0], dir, dt)
	else:
		energy = minf(100, energy + dt * (0.0 if c.fire else 14.0))
	storm_cd = maxf(0, storm_cd - dt)
	fireball_cd = maxf(0, fireball_cd - dt)

	# spostamento d'aria sul mare
	var px := dragon.position.x
	var pz := dragon.position.z
	var over_water := world.ground_height(px, pz) < 0.5
	var h := dragon.position.y
	var down := clampf(1 - (h - 8) / 55, 0, 1) * (0.45 + 0.55 * minf(1, dragon.power)) * (1 - dragon.fold * 0.6) if over_water else 0.0
	var dx := px - dragon.forward.x * 5
	var dz := pz - dragon.forward.z * 5
	if ev.downstroke:
		audio.flap(minf(1.2, dragon.power))
		flap_shake = 0.12 * dragon.power
		if down > 0.08:
			water.add_pulse(dx, dz, 0.9 * down)
			for i in int(70 * down):
				var a := randf() * TAU
				var r := 4 + randf() * 10
				var sp := 20 + randf() * 25
				fx.spray.spawn(Vector3(dx + cos(a) * r, 0.5, dz + sin(a) * r), Vector3(cos(a) * sp, 6 + randf() * 12, sin(a) * sp), 1 + randf(), 1.2, 4.5, 1)
	if down > 0.15:
		wake_t += dt
		if wake_t > 0.25:
			wake_t = 0
			water.add_pulse(dx, dz, 0.45 * down)
		var n := int(dt * 220 * down + randf())
		for i in n:
			var a := randf() * TAU
			var r := 5 + randf() * 16
			var sp := 14 + randf() * 22
			fx.spray.spawn(Vector3(dx + cos(a) * r, 0.4, dz + sin(a) * r),
				Vector3(cos(a) * sp + dragon.velocity.x * 0.3, 3 + randf() * 7, sin(a) * sp + dragon.velocity.z * 0.3), 0.8 + randf() * 1.2, 0.8, 3.2, 0)
			if randf() < 0.15:
				fx.smoke.spawn(Vector3(dx + cos(a) * r, 1.5, dz + sin(a) * r), Vector3(cos(a) * sp * 0.4, 2, sin(a) * sp * 0.4), 2.5, 6, 20, 1)
	# combattimento con i draghi guardiani
	if started:
		if fx.storm != null:
			for e in enemies.list:
				if e.dragon.position.distance_to(dragon.position) < 55:
					enemies.damage(e, 45 * dt)
			world.fortress.splash(dragon.position, 55, 45 * dt)
		var ev2 := enemies.update_enemies(dt, dragon, player_alive)
		world.fortress.update_fortress(dt, dragon, player_alive, camera.position)
		if ev2.player_damage > 0:
			_damage_player(ev2.player_damage)
		invuln = maxf(0, invuln - dt)
		if player_alive and time - last_hit_t > 5:
			player_hp = minf(100, player_hp + dt * 4)
		if not player_alive:
			# precipita in fiamme e riparte dopo qualche secondo
			dead_t += dt
			if randf() < dt * 40:
				var p := dragon.position
				fx.fire.spawn(p, Vector3((randf() - 0.5) * 6, 4, (randf() - 0.5) * 6), 0.6, 3, 8, 1)
				fx.smoke.spawn(p, Vector3(0, 3, 0), 4, 5, 20, 0)
			if not crashed and dragon.altitude < 3:
				crashed = true
				fx.explode(dragon.position, 1, "none")
			if dead_t > 4:
				_respawn()
	hurt = maxf(0, hurt - dt * 1.5)
	water.update_water(dt, camera.position, dx, dz, down)
	world.update(dt, time, camera.position)
	world.update_terrain(camera.position)
	var ground_y := world.ground_height(camera.position.x, camera.position.z)
	grass.update_grass(camera.position, ground_y, time)
	# la foschia volumetrica sta in basso: salendo in volo si dirada e il paesaggio resta leggibile
	env.volumetric_fog_density = FOG_DENSITY * lerpf(1.0, 0.3, smoothstep(30.0, 350.0, camera.position.y - maxf(ground_y, 0.0)))
	fx.update_fx(dt, camera.position, mouth_pos)
	fx.shake = maxf(fx.shake, flap_shake)
	flap_shake = maxf(0, flap_shake - dt * 0.8)
	_update_camera(dt, c)
	enemies.update_bars(camera)

	# audio
	var burn_near := 0.0
	for b in world.nearest_fires(camera.position, 4):
		burn_near += b.fire / (1 + Vector2(b.x - camera.position.x, b.z - camera.position.z).length() / 120)
	audio.update_audio(dt, {"speed": dragon.speed, "breathing": breathing,
		"water": clampf(1 - dragon.altitude / 120, 0, 1) if over_water else 0.0, "burn": burn_near})
	if started:
		_update_villages()
	hud.update_hud(dt, _hud_state())


func _hud_state() -> Dictionary:
	var aim = dragon.aim_target if dragon.mode == "air" and dragon.aim_ok and player_alive else null
	var tgt = enemies.target(dragon) if aim != null else null
	var hostile: bool = tgt.hostile if tgt != null else world.fortress.awake
	return {"dragon": dragon, "camera": camera, "hp": player_hp, "energy": energy, "storm_cd": storm_cd,
		"hurt": hurt, "time": time, "paused": paused, "locked": input.pointer_locked(),
		"aim": aim, "aim_hostile": aim != null and hostile, "kills": enemies.kills, "enemies": enemies.list, "fortress": world.fortress}


func _update_villages() -> void:
	var near = null
	for v in world.villages:
		if Vector2(v.x - dragon.position.x, v.z - dragon.position.z).length() < v.r + 160:
			near = v
	var fort := world.fortress
	var in_fort := Vector2(dragon.position.x - fort.center.x, dragon.position.z - fort.center.z).length() < fort.radius
	if in_fort and not was_in_fortress:
		hud.show_banner(Fortress.TITLE, "caduta" if fort.fallen else ("all'attacco" if fort.awake else "dormiente · %d postazioni" % fort.alive_count()))
	was_in_fortress = in_fort
	if near != null and near != current_village:
		var g = enemies.guardian_of(near)
		var sub: String = "Fortezza" if near.kind == "castle" else "Villaggio"
		if g != null:
			sub += " · protetto dal %s" % g.type.name
		hud.show_banner(near.name, sub)
	current_village = near
	for v in world.villages:
		if announced.has(v.name):
			continue
		var done := 0
		for id in v.ids:
			if world.buildings[id].state == 2:
				done += 1
		if v.ids.size() > 0 and float(done) / v.ids.size() > 0.85:
			announced[v.name] = true
			hud.show_msg("%s è in rovina!" % v.name)


# ---------- Camera in terza persona ----------
func _update_camera(dt: float, c: Dictionary) -> void:
	var F := dragon.forward
	var Uv := dragon.up
	var sf := clampf((dragon.speed - 30) / 130, 0, 1)
	cam_dist = U.damp(cam_dist, clampf(34 * pow(1.1, c.zoom), 16, 110), 6, dt)
	var dist := cam_dist * (1 + sf * 0.12)
	var o := F * -dist + Uv * (dist * 0.27)
	# orbita libera (mouse destro / levetta destra)
	var r := F.cross(Uv).normalized()
	o = o.rotated(Uv, c.look_x * PI)
	o = o.rotated(r, c.look_y * 0.9)
	# a terra: camera che ruota attorno alla testa lungo la mira (stile terza persona)
	var gb := dragon.ground_blend
	var head_pos := dragon.head.global_position
	var g_off := Vector3.ZERO
	if gb > 0.001:
		var k := cam_dist / 34
		g_off = head_pos + dragon.aim_dir * (-34 * k) + Vector3(0, 9 * k, 0) - dragon.position
		o = o.lerp(g_off, gb)
	cam_offset = cam_offset.lerp(o, 1 - exp(-dt * (4.5 + gb * 3)))
	var pos := dragon.position + cam_offset
	var g := maxf(world.ground_height(pos.x, pos.z), water.height_at(pos.x, pos.z) + 1)
	if pos.y < g + 3:
		pos.y = g + 3
	cam_up = cam_up.lerp(Vector3.UP if gb > 0.5 else Uv, 1 - exp(-dt * 3)).normalized()
	var target := dragon.position + F * 10 + Uv * 2.5
	if gb > 0.001:
		target = target.lerp(head_pos + dragon.aim_dir * 90, gb)
	if fx.shake > 0:
		var s := fx.shake * 1.6
		pos += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * s
	camera.look_at_from_position(pos, target, cam_up)
	if test_closeup and closeup_pos != Vector3.ZERO:
		camera.look_at_from_position(closeup_pos, closeup_target, Vector3.UP)
	var fov := 60 + sf * 16
	cam_fov = U.damp(cam_fov, fov, 3, dt)
	camera.fov = cam_fov
