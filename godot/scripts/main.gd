# Il Volo del Drago — ciclo di gioco, ambiente, camera in terza persona (porting di src/main.js)
extends Node3D

# sole: elevazione 17°, azimut 210° (come sky.js)
const SUN_DIR := Vector3(-0.47815, 0.29237, -0.82818)

var world: World
var water: Water
var dragon: Dragon
var fx: FX
var input: GameInput
var hud: HUD
var camera := Camera3D.new()
var sun := DirectionalLight3D.new()

var started := false
var paused := false
var time := 0.0
var energy := 100.0
var storm_cd := 0.0
var fireball_cd := 0.0
var wake_t := 0.0
var flap_shake := 0.0
var player_hp := 100.0
var hurt := 0.0
var cam_offset := Vector3(0, 10, -35)
var cam_up := Vector3.UP
var cam_fov := 62.0
var cam_dist := 34.0
var current_village = null
var announced := {}
var screenshot_path := ""
var screenshot_t := -1.0
var test_breathe := false


func _ready() -> void:
	_setup_environment()
	world = World.new()
	world.name = "World"
	add_child(world)
	world.generate()
	water = Water.new()
	add_child(water)
	water.setup(world.data_tex)
	fx = FX.new()
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
	print("Mondo: %d villaggi, %d edifici, %d alberi" % [world.villages.size(), world.stats.total, world.trees.size()])


func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.42, 0.78)
	sky_mat.sky_horizon_color = Color(0.68, 0.77, 0.88)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.1, 0.16, 0.22)
	sky_mat.ground_horizon_color = Color(0.68, 0.77, 0.88)
	sky_mat.sun_angle_max = 18
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.4
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.72, 0.84)
	env.fog_density = 0.00008
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.15
	# foschia volumetrica vicina: raggi di sole tra i monti e bagliore degli incendi nel fumo
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0003
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
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1500
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.basis = Basis.looking_at(-SUN_DIR, Vector3.UP)
	add_child(sun)


func _start_game() -> void:
	if started:
		return
	started = true
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


# Per le verifiche: atterra vicino al villaggio più vicino
func _test_land() -> void:
	_burn_nearest()
	var g := world.ground_height(dragon.position.x, dragon.position.z)
	dragon.position.y = g + 25
	dragon.land(world)


func _on_explode(pos: Vector3, size: float) -> void:
	var d := pos.distance_to(camera.position)
	fx.shake = maxf(fx.shake, clampf(1.2 - d / 400, 0, 1) * size)


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
		if paused:
			continue
		match a:
			"land":
				if dragon.mode == "ground":
					if dragon.take_off():
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
					fx.launch_fireball(m[0] + dir * 3, dir * 150 + dragon.velocity, 3)
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
					hud.show_msg("Piroetta!", "small")
			"loop":
				if dragon.start_loop():
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
	var c: Dictionary = _autopilot() if not started else ctrl_in
	# a terra: W/S cammina, A/D gira, frecce/mouse destro/levetta destra muovono la testa
	var grounded := dragon.mode != "air"
	input.set_pointer_lock(started and dragon.mode == "ground")
	if grounded and started:
		c = ctrl_in.duplicate()
		c.steer = ctrl_in.walk_steer
		c.climb = ctrl_in.walk
		c.look_x = 0.0
		c.look_y = 0.0
	if test_breathe:
		c = c.duplicate()
		c.fire = true
	if not grounded:
		dragon.aim_target = null

	# soffio di fuoco
	var breathing: bool = started and c.fire and energy > 1
	dragon.breathing = breathing
	var ev := dragon.update_dragon(dt, c, world)
	if ev.touchdown:
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
	hurt = maxf(0, hurt - dt * 1.5)
	water.update_water(dt, camera.position, dx, dz, down)
	world.update(dt, time, camera.position)
	world.update_terrain(camera.position)
	fx.update_fx(dt, camera.position, mouth_pos)
	fx.shake = maxf(fx.shake, flap_shake)
	flap_shake = maxf(0, flap_shake - dt * 0.8)
	_update_camera(dt, c)
	if started:
		_update_villages()
	hud.update_hud(dt, _hud_state())


func _hud_state() -> Dictionary:
	return {"dragon": dragon, "camera": camera, "hp": player_hp, "energy": energy, "storm_cd": storm_cd,
		"hurt": hurt, "time": time, "paused": paused, "locked": input.pointer_locked()}


func _update_villages() -> void:
	var near = null
	for v in world.villages:
		if Vector2(v.x - dragon.position.x, v.z - dragon.position.z).length() < v.r + 160:
			near = v
	if near != null and near != current_village:
		hud.show_banner(near.name, "Fortezza" if near.kind == "castle" else "Villaggio")
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
	var fov := 60 + sf * 16
	cam_fov = U.damp(cam_fov, fov, 3, dt)
	camera.fov = cam_fov
