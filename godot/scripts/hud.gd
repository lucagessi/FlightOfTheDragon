# HUD: velocità, quota, barre, punteggio, messaggi, minimappa, aiuto e schermata iniziale
class_name HUD
extends CanvasLayer

const HELP_TEXT := """COMANDI — tastiera e mouse
W S / ↑ ↓   sali / scendi        A D / ← →   vira
Shift o E   accelera             Q o Z   rallenta
Spazio / clic sinistro   sputa fuoco (tieni premuto)
F   sputa ghiaccio: spegne case, alberi e lanterne
Destro + trascina, rotella   ruota / avvicina la camera
L   atterra / decolla            I   inverti asse verticale
M   attiva / disattiva l'audio

JOYSTICK
Levetta sinistra   vira, sali, scendi     Levetta destra   camera
A / B   accelera / rallenta     RT   fuoco     LT   ghiaccio     X   palla di fuoco
Y   giro della morte     LB RB   piroetta     LT + RT   tempesta di fuoco
Premi la levetta sinistra   atterra / decolla

DRAGHI GUARDIANI
Ogni drago rivale protegge un villaggio: è neutrale (barra dorata) finché non lo
attacchi o incendi il suo villaggio, poi diventa ostile (rosso) e ti insegue.
Se ti allontani dal suo territorio dopo un po' si calma.

LA FORTEZZA DI MONTE NERO
Sulla vetta più alta: dorme finché non la attacchi, poi cannoni, trabucchi,
balestre, arcieri, fuoco greco e la torre arcana ti bersagliano.
Distruggi le postazioni col fuoco: quando cadono tutte, cade la fortezza.

COMBINAZIONI
Spazio Spazio (doppio tocco)   palla di fuoco
↓ ↑ + Spazio   tempesta di fuoco
A A / D D (doppio tocco)   piroetta     W W (doppio tocco)   giro della morte

A TERRA
W S · A D   cammina · gira (Shift corre)
Mouse (clic per catturarlo), frecce, levetta destra   muovi la testa e mira
Esc libera il mouse

Premi H per chiudere"""

var world: World
var root := Control.new()
var speed_lbl := Label.new()
var alt_lbl := Label.new()
var bars := {}
var score_lbl := Label.new()
var score_sub := Label.new()
var msgs := VBoxContainer.new()
var banner := Label.new()
var banner_t := 0.0
var warn := Label.new()
var crosshair := Label.new()
var ground_hint := Label.new()
var hurt := ColorRect.new()
var enemy_layer := Control.new()
var boss := VBoxContainer.new()
var boss_title: Label
var boss_sub: Label
var boss_fill := ColorRect.new()
var help := PanelContainer.new()
var pause_lbl := Label.new()
var start := Control.new()
var minimap := Control.new()
var minimap_tex: ImageTexture
var minimap_markers := []
var stats_box := VBoxContainer.new()


static func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	return l


func setup(w: World) -> void:
	world = w
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	hurt.color = Color(0.6, 0, 0, 0)
	hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hurt)

	# barre della vita dei draghi guardiani, sopra di loro
	enemy_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	enemy_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(enemy_layer)

	# statistiche in alto a sinistra
	stats_box.position = Vector2(24, 20)
	stats_box.add_theme_constant_override("separation", 4)
	root.add_child(stats_box)
	var row := HBoxContainer.new()
	speed_lbl = _label("0", 40)
	row.add_child(speed_lbl)
	row.add_child(_label(" km/h", 18, Color(1, 1, 1, 0.7)))
	stats_box.add_child(row)
	alt_lbl = _label("Quota 0 m", 18)
	stats_box.add_child(alt_lbl)
	for b in [["hp", "Vita", Color(0.85, 0.15, 0.15)], ["thr", "Spinta", Color(0.9, 0.85, 0.4)],
			["fire", "Fuoco", Color(1, 0.45, 0.1)], ["storm", "Tempesta", Color(0.8, 0.3, 1)]]:
		var r := HBoxContainer.new()
		var l := _label(b[1], 15, Color(1, 1, 1, 0.8))
		l.custom_minimum_size = Vector2(80, 0)
		r.add_child(l)
		var track := ColorRect.new()
		track.color = Color(0, 0, 0, 0.45)
		track.custom_minimum_size = Vector2(170, 10)
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := ColorRect.new()
		fill.color = b[2]
		fill.size = Vector2(170, 10)
		track.add_child(fill)
		r.add_child(track)
		stats_box.add_child(r)
		bars[b[0]] = fill

	# punteggio in alto a destra
	var score_box := VBoxContainer.new()
	score_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score_box.position = Vector2(-380, 20)
	score_box.custom_minimum_size = Vector2(360, 0)
	score_lbl = _label("", 22)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_sub = _label("", 16, Color(1, 0.8, 0.6))
	score_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_box.add_child(score_lbl)
	score_box.add_child(score_sub)
	root.add_child(score_box)

	# minimappa in basso a destra
	_build_minimap()

	# barra della fortezza in basso al centro
	boss.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	boss.position = Vector2(-240, -205)
	boss.custom_minimum_size = Vector2(480, 0)
	boss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_title = _label("", 20, Color(1, 0.85, 0.7))
	boss_sub = _label("", 14, Color(1, 1, 1, 0.8))
	var track := ColorRect.new()
	track.color = Color(0, 0, 0, 0.55)
	track.custom_minimum_size = Vector2(480, 10)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_fill.size = Vector2(480, 10)
	boss_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(boss_fill)
	for c in [boss_title, track, boss_sub]:
		if c is Label:
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boss.add_child(c)
	boss.visible = false
	root.add_child(boss)

	msgs.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msgs.position = Vector2(-300, 190)
	msgs.custom_minimum_size = Vector2(600, 0)
	msgs.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(msgs)

	banner = _label("", 40, Color(1, 0.92, 0.75))
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(-400, 60)
	banner.custom_minimum_size = Vector2(800, 0)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.modulate.a = 0
	root.add_child(banner)

	warn = _label("Confine del regno — il drago torna indietro", 20, Color(1, 0.6, 0.4))
	warn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	warn.position = Vector2(-300, -120)
	warn.custom_minimum_size = Vector2(600, 0)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.visible = false
	root.add_child(warn)

	crosshair = _label("◎", 34, Color(1, 0.35, 0.2))
	crosshair.visible = false
	root.add_child(crosshair)

	ground_hint = _label("", 16, Color(1, 1, 1, 0.85))
	ground_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ground_hint.position = Vector2(-400, -70)
	ground_hint.custom_minimum_size = Vector2(800, 0)
	ground_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ground_hint.visible = false
	root.add_child(ground_hint)

	var hint := _label("H aiuto · P pausa · M audio", 14, Color(1, 1, 1, 0.6))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(24, -36)
	root.add_child(hint)

	# aiuto
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.03, 0.85)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(24)
	help.add_theme_stylebox_override("panel", sb)
	help.set_anchors_preset(Control.PRESET_CENTER)
	help.position = Vector2(-330, -330)
	help.add_child(_label(HELP_TEXT, 16))
	help.visible = false
	root.add_child(help)

	pause_lbl = _label("PAUSA\nPremi P per riprendere", 44)
	pause_lbl.set_anchors_preset(Control.PRESET_CENTER)
	pause_lbl.position = Vector2(-300, -60)
	pause_lbl.custom_minimum_size = Vector2(600, 0)
	pause_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_lbl.visible = false
	root.add_child(pause_lbl)

	# schermata iniziale
	start.set_anchors_preset(Control.PRESET_FULL_RECT)
	start.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.25)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start.add_child(shade)
	var title := _label("Il Volo del Drago", 72, Color(1, 0.88, 0.62))
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = Vector2(-500, -140)
	title.custom_minimum_size = Vector2(1000, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start.add_child(title)
	var tag := _label("Sorvola i regni medievali, sfiora il mare, incendia i villaggi.\n\nPremi Invio o fai clic per spiccare il volo", 22)
	tag.set_anchors_preset(Control.PRESET_CENTER)
	tag.position = Vector2(-500, -30)
	tag.custom_minimum_size = Vector2(1000, 0)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start.add_child(tag)
	root.add_child(start)
	stats_box.visible = false


func _build_minimap() -> void:
	var S := 200
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var wx := -World.HALF + (x + 0.5) / S * World.TERRAIN_SIZE
			var wz := -World.HALF + (y + 0.5) / S * World.TERRAIN_SIZE
			var h := world.ground_height(wx, wz)
			var c: Color
			if h < 0:
				var t := clampf(-h / 50, 0, 1)
				c = Color8(int(lerpf(70, 18, t)), int(lerpf(150, 50, t)), int(lerpf(170, 95, t)))
			elif h < 4:
				c = Color8(205, 190, 140)
			elif h < 120:
				var t := h / 120
				c = Color8(int(lerpf(80, 120, t)), int(lerpf(130, 120, t)), int(lerpf(60, 80, t)))
			elif h < 250:
				c = Color8(130, 122, 112)
			else:
				c = Color8(235, 238, 245)
			# bordo circolare
			var d := Vector2(x - S / 2.0 + 0.5, y - S / 2.0 + 0.5).length()
			c.a = clampf(S / 2.0 - d, 0, 1) * 0.92
			img.set_pixel(x, y, c)
	minimap_tex = ImageTexture.create_from_image(img)
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.position = Vector2(-224, -224)
	minimap.size = Vector2(S, S)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	minimap.visible = false
	root.add_child(minimap)


func _to_map(x: float, z: float) -> Vector2:
	var sc := 200.0 / World.TERRAIN_SIZE
	return Vector2((x + World.HALF) * sc, (z + World.HALF) * sc)


func _draw_minimap() -> void:
	minimap.draw_texture(minimap_tex, Vector2.ZERO)
	for m in minimap_markers:
		match m[0]:
			"castle":
				minimap.draw_rect(Rect2(m[1] - Vector2(4, 4), Vector2(8, 8)), m[2])
			"village":
				minimap.draw_circle(m[1], 3.5, m[2])
			"fire":
				minimap.draw_rect(Rect2(m[1] - Vector2(1, 1), Vector2(2, 2)), m[2])
			"post":
				minimap.draw_rect(Rect2(m[1] - Vector2(1, 1), Vector2(2, 2)), m[2])
			"fortress":
				var p: Vector2 = m[1]
				var pts := PackedVector2Array([p + Vector2(0, -7), p + Vector2(6, 4), p + Vector2(-6, 4)])
				minimap.draw_colored_polygon(pts, m[2])
				pts.append(pts[0])
				minimap.draw_polyline(pts, Color.BLACK, 1.5)
			"enemy":
				var p: Vector2 = m[1]
				var pts := PackedVector2Array([p + Vector2(0, -5), p + Vector2(4, 3), p + Vector2(-4, 3)])
				minimap.draw_colored_polygon(pts, m[2])
				pts.append(pts[0])
				minimap.draw_polyline(pts, Color.BLACK, 1)
			"player":
				var p: Vector2 = m[1]
				var a: float = m[2]
				var pts := PackedVector2Array()
				for q in [Vector2(0, 8), Vector2(-5, -5), Vector2(0, -2), Vector2(5, -5)]:
					pts.append(p + q.rotated(a))
				minimap.draw_colored_polygon(pts, Color.WHITE)
				pts.append(pts[0])
				minimap.draw_polyline(pts, Color(0.65, 0, 0), 1.5)
	minimap.draw_arc(Vector2(100, 100), 100, 0, TAU, 64, Color(0, 0, 0, 0.6), 2)


# Barra della vita di un drago guardiano (la posiziona Enemies.update_bars)
func add_enemy_bar(title: String, sub: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(130, 0)
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_lbl := _label(title, 13)
	var sub_lbl := _label(sub, 11, Color(1, 1, 1, 0.75))
	for l in [name_lbl, sub_lbl]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	var track := ColorRect.new()
	track.color = Color(0, 0, 0, 0.55)
	track.custom_minimum_size = Vector2(130, 6)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.size = Vector2(130, 6)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	box.add_child(track)
	box.visible = false
	enemy_layer.add_child(box)
	return {"box": box, "name": name_lbl, "fill": fill, "hostile": null}


# Barra della fortezza: postazioni ancora in piedi, rossa quando è all'attacco
func set_boss(show: bool, title := "", sub := "", frac := 1.0, hostile := false) -> void:
	boss.visible = show
	if not show:
		return
	boss_title.text = title
	boss_sub.text = sub
	boss_fill.size.x = 480 * clampf(frac, 0, 1)
	boss_fill.color = Color(0.9, 0.2, 0.1) if hostile else Color(0.75, 0.7, 0.62)


# dorata se il drago è neutrale, rossa se ostile
func set_enemy_bar(bar: Dictionary, frac: float, hostile: bool) -> void:
	bar.fill.size.x = 130 * clampf(frac, 0, 1)
	if bar.hostile != hostile:
		bar.hostile = hostile
		bar.fill.color = Color(0.95, 0.25, 0.12) if hostile else Color(1, 0.8, 0.3)
		bar.name.add_theme_color_override("font_color", Color(1, 0.54, 0.44) if hostile else Color.WHITE)


func show_game() -> void:
	start.visible = false
	stats_box.visible = true
	minimap.visible = true


func show_msg(text: String, cls := "") -> void:
	var col := Color(1, 0.85, 0.5)
	var size := 26
	if cls == "bad":
		col = Color(1, 0.45, 0.35)
	elif cls == "small":
		col = Color(1, 1, 1, 0.9)
		size = 18
	var l := _label(text, size, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msgs.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func show_banner(title: String, sub: String) -> void:
	banner.text = sub + "\n" + title
	banner_t = 2.6


func toggle_help() -> void:
	help.visible = not help.visible


func update_hud(dt: float, s: Dictionary) -> void:
	var d: Dragon = s.dragon
	banner_t = maxf(0, banner_t - dt)
	banner.modulate.a = clampf(banner_t / 0.4, 0, 1)
	speed_lbl.text = str(roundi(d.speed * 3.6))
	alt_lbl.text = "a terra" if d.mode == "ground" else "Quota %d m" % roundi(d.altitude)
	bars.hp.size.x = 170 * s.hp / 100.0
	bars.hp.color = Color(1, 0.2, 0.2) if s.hp < 30 else Color(0.85, 0.15, 0.15)
	bars.thr.size.x = 170 * d.throttle
	bars.fire.size.x = 170 * s.energy / 100.0
	bars.storm.size.x = 170 * (1 - s.storm_cd / 12.0)
	bars.storm.color = Color(1, 0.5, 1) if s.storm_cd <= 0 and s.energy >= 50 else Color(0.6, 0.25, 0.8)
	hurt.color.a = minf(1, s.hurt * 0.9 + (0.25 + 0.15 * sin(s.time * 6) if s.hp < 30 else 0.0)) * 0.35
	score_lbl.text = "%d / %d edifici distrutti" % [world.stats.destroyed, world.stats.total]
	score_sub.text = "%d in fiamme · %d draghi abbattuti" % [world.stats.burning, s.kills]
	warn.visible = d.out_of_bounds
	pause_lbl.visible = s.paused
	# a terra il mirino mostra dove andrà il fuoco; in volo segue il drago nemico agganciato
	var on_ground := d.mode == "ground"
	var aim = s.aim
	crosshair.visible = on_ground or aim != null
	ground_hint.visible = on_ground
	var fly := "esci dalla grotta per volare" if world.lair.inside(s.dragon.position) else "L: decolla"
	ground_hint.text = ("Mouse: mira · Esc: libera il mouse · " if s.locked else "Clic: mira col mouse · Frecce/levetta destra: testa · ") + fly
	if crosshair.visible:
		var cam: Camera3D = s.camera
		var p: Vector3 = d.get_mouth()[0] + d.aim_dir * 90 if on_ground else aim
		if not cam.is_position_behind(p):
			crosshair.position = cam.unproject_position(p) - crosshair.size / 2
		var col := Color(1, 0.94, 0.86) if on_ground else (Color(1, 0.35, 0.2) if s.aim_hostile else Color(1, 0.76, 0.23))
		crosshair.add_theme_color_override("font_color", col)
	# minimappa
	minimap_markers.clear()
	for v in world.villages:
		var burnt := 0
		for id in v.ids:
			if world.buildings[id].state > 0:
				burnt += 1
		var f := float(burnt) / maxi(1, v.ids.size())
		var c := Color("#222") if f > 0.85 else (Color("#ff5a1f") if f > 0 else Color("#ffe2a8"))
		minimap_markers.append(["castle" if v.kind == "castle" else "village", _to_map(v.x, v.z), c])
	for b in world.burning:
		if b.fire >= 0.2:
			minimap_markers.append(["fire", _to_map(b.x, b.z), Color(1, 0.3 + randf() * 0.25, 0.08, 0.9)])
	var fort: Fortress = s.fortress
	if fort != null and fort.built:
		var post := Color(1, 0.25, 0.15) if fort.awake else Color(0.85, 0.82, 0.75)
		for w in fort.weapons:
			if w.alive:
				minimap_markers.append(["post", _to_map(w.pos.x, w.pos.z), post])
		minimap_markers.append(["fortress", _to_map(fort.center.x, fort.center.z), Color("#333") if fort.fallen else Color("#7a1a14")])
	for e in s.enemies:
		var c := Color("#555") if e.dragon.dying else (Color("#ff2a2a") if e.hostile else Color("#ffc23a"))
		minimap_markers.append(["enemy", _to_map(e.dragon.position.x, e.dragon.position.z), c])
	minimap_markers.append(["player", _to_map(d.position.x, d.position.z), -d.yaw])
	minimap.queue_redraw()
