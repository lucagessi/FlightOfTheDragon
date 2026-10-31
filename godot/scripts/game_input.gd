# Input da tastiera, mouse e joystick con riconoscimento delle combo (porting di src/input.js)
class_name GameInput
extends Node

const DOUBLE_TAP := 0.3
const SEQ_WINDOW := 0.9

var actions: Array[String] = []
var history: Array = []
var time := 0.0
var invert_y := false
var mouse_fire := false
var look := Vector2.ZERO
var zoom := 0.0
var dragging := false
var mouse_d := Vector2.ZERO
var pad_prev := {}
var pad_axes_prev := {"left": false, "right": false, "up": false, "down": false}
var any_press := false
var want_lock := false


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection)


func _on_joy_connection(_device: int, connected: bool) -> void:
	if connected:
		actions.append("pad")


static func _logical(key: Key) -> String:
	match key:
		KEY_SPACE: return "fire"
		KEY_A, KEY_LEFT: return "left"
		KEY_D, KEY_RIGHT: return "right"
		KEY_W, KEY_UP: return "up"
		KEY_S, KEY_DOWN: return "down"
	return ""


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		any_press = true
		if event.echo:
			return
		var key: Key = event.physical_keycode
		var l := _logical(key)
		if l != "":
			press(_adjust(l))
		match key:
			KEY_H, KEY_F1: actions.append("help")
			KEY_P: actions.append("pause")
			KEY_M: actions.append("mute")
			KEY_I:
				invert_y = not invert_y
				actions.append("invert")
			KEY_C: actions.append("camera")
			KEY_L: actions.append("land")
			KEY_ENTER, KEY_KP_ENTER: actions.append("start")
			KEY_ESCAPE:
				# Esc che libera il mouse catturato non deve anche mettere in pausa
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					actions.append("pause")
	elif event is InputEventMouseButton:
		if event.pressed:
			any_press = true
			# a terra un clic cattura il mouse per mirare liberamente (Esc lo rilascia)
			if want_lock and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				mouse_fire = event.pressed
				if event.pressed:
					press("fire")
					actions.append("start")
			MOUSE_BUTTON_RIGHT:
				dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom -= 1
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom += 1
	elif event is InputEventMouseMotion:
		var rel: Vector2 = event.relative
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			mouse_d += rel
			return
		if not dragging:
			return
		mouse_d += rel
		look.x = clampf(look.x - rel.x * 0.004, -1, 1)
		look.y = clampf(look.y + rel.y * 0.003, -0.6, 0.8)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		mouse_fire = false
		dragging = false


# Il puntatore resta catturato solo mentre il drago è a terra
func set_pointer_lock(want: bool) -> void:
	want_lock = want
	if not want and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func pointer_locked() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _adjust(l: String) -> String:
	if invert_y and (l == "up" or l == "down"):
		return "down" if l == "up" else "up"
	return l


# Registra una pressione e controlla le combinazioni speciali
func press(l: String) -> void:
	var t := time
	var h := history
	var last = h[h.size() - 1] if h.size() > 0 else null
	if l == "fire":
		# ↓ ↑ + Fuoco  =>  Tempesta di fuoco
		var n := h.size()
		if n >= 2 and h[n - 1].l == "up" and h[n - 2].l == "down" and t - h[n - 2].t < SEQ_WINDOW:
			actions.append("firestorm")
			history = []
			return
		if last != null and last.l == "fire" and t - last.t < DOUBLE_TAP:
			actions.append("fireball")
			history = []
			return
	if last != null and last.l == l and t - last.t < DOUBLE_TAP:
		var combo := {"left": "rollLeft", "right": "rollRight", "up": "loop"}
		if combo.has(l):
			actions.append(combo[l])
			history = []
			return
	h.append({"l": l, "t": t})
	if h.size() > 6:
		h.pop_front()


static func _dz(v: float) -> float:
	return 0.0 if absf(v) < 0.15 else (v - signf(v) * 0.15) / 0.85


func _poll_pad():
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return null
	var id: int = pads[0]
	var btn := func(b: JoyButton) -> bool: return Input.is_joy_button_pressed(id, b)
	var state := {
		"lx": _dz(Input.get_joy_axis(id, JOY_AXIS_LEFT_X)), "ly": _dz(Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)),
		"rx": _dz(Input.get_joy_axis(id, JOY_AXIS_RIGHT_X)), "ry": _dz(Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y)),
		"a": btn.call(JOY_BUTTON_A), "b": btn.call(JOY_BUTTON_B), "x": btn.call(JOY_BUTTON_X), "y": btn.call(JOY_BUTTON_Y),
		"lb": btn.call(JOY_BUTTON_LEFT_SHOULDER), "rb": btn.call(JOY_BUTTON_RIGHT_SHOULDER),
		"lt": Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT), "rt": Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT),
		"back": btn.call(JOY_BUTTON_BACK), "start": btn.call(JOY_BUTTON_START), "l3": btn.call(JOY_BUTTON_LEFT_STICK),
		"dl": btn.call(JOY_BUTTON_DPAD_LEFT), "dr": btn.call(JOY_BUTTON_DPAD_RIGHT), "du": btn.call(JOY_BUTTON_DPAD_UP), "dd": btn.call(JOY_BUTTON_DPAD_DOWN),
	}
	var prev := pad_prev
	var edge := func(k: String) -> bool: return state[k] and not prev.get(k, false)
	for k in state:
		if state[k] is bool and edge.call(k):
			any_press = true
	# grilletto destro = fuoco (doppio tocco = palla di fuoco)
	if state.rt > 0.5 and prev.get("rt", 0.0) <= 0.5:
		if state.lt > 0.5:
			actions.append("firestorm")
		else:
			press("fire")
	if edge.call("x"):
		actions.append("fireball")
	if edge.call("y"):
		actions.append("loop")
	if edge.call("lb"):
		actions.append("rollLeft")
	if edge.call("rb"):
		actions.append("rollRight")
	if edge.call("l3"):
		actions.append("land") # pressione della levetta sinistra
	if edge.call("start"):
		actions.append("pause")
		actions.append("start")
	if edge.call("back"):
		actions.append("help")
	# levetta: anche i "colpetti" contano per le combo (doppio colpetto = piroetta)
	var dirs := {
		"left": state.lx < -0.75 or state.dl, "right": state.lx > 0.75 or state.dr,
		"up": state.ly < -0.75 or state.du, "down": state.ly > 0.75 or state.dd,
	}
	for k in ["left", "right", "up", "down"]:
		if dirs[k] and not pad_axes_prev[k]:
			press(_adjust(k))
		pad_axes_prev[k] = dirs[k]
	pad_prev = state
	return state


func _key(k: Key) -> bool:
	return Input.is_physical_key_pressed(k)


func update_input(dt: float) -> Dictionary:
	time += dt
	var steer := (1.0 if _key(KEY_D) or _key(KEY_RIGHT) else 0.0) - (1.0 if _key(KEY_A) or _key(KEY_LEFT) else 0.0)
	var climb := (1.0 if _key(KEY_W) or _key(KEY_UP) else 0.0) - (1.0 if _key(KEY_S) or _key(KEY_DOWN) else 0.0)
	if invert_y:
		climb = -climb
	var throttle := (1.0 if _key(KEY_SHIFT) or _key(KEY_E) else 0.0) - (1.0 if _key(KEY_Q) or _key(KEY_Z) else 0.0)
	var fire := _key(KEY_SPACE) or mouse_fire
	var look_x := 0.0
	var look_y := 0.0
	# a terra: lettere per camminare, frecce per muovere la testa
	var walk_steer := (1.0 if _key(KEY_D) else 0.0) - (1.0 if _key(KEY_A) else 0.0)
	var walk := (1.0 if _key(KEY_W) else 0.0) - (1.0 if _key(KEY_S) else 0.0)
	var aim_x := (1.0 if _key(KEY_RIGHT) else 0.0) - (1.0 if _key(KEY_LEFT) else 0.0)
	var aim_y := (1.0 if _key(KEY_UP) else 0.0) - (1.0 if _key(KEY_DOWN) else 0.0)

	var pad = _poll_pad()
	if pad != null:
		if absf(pad.lx) > 0:
			steer = pad.lx
			walk_steer = pad.lx
		if absf(pad.ly) > 0:
			climb = pad.ly if invert_y else -pad.ly
			walk = -pad.ly
		if pad.dl:
			steer = -1
			walk_steer = -1
		if pad.dr:
			steer = 1
			walk_steer = 1
		if pad.du:
			climb = -1.0 if invert_y else 1.0
			walk = 1
		if pad.dd:
			climb = 1.0 if invert_y else -1.0
			walk = -1
		if pad.a:
			throttle = 1
		if pad.b:
			throttle = -1
		if pad.rt > 0.3:
			fire = true
		look_x = -pad.rx
		look_y = pad.ry
		if absf(pad.rx) > 0:
			aim_x = pad.rx
		if absf(pad.ry) > 0:
			aim_y = pad.ry if invert_y else -pad.ry
	var md := mouse_d
	mouse_d = Vector2.ZERO
	if not dragging:
		look *= exp(-dt * 1.5)
	var acts := actions
	actions = []
	return {
		"steer": clampf(steer, -1, 1), "climb": clampf(climb, -1, 1),
		"throttle": throttle, "fire": fire,
		"look_x": look.x + look_x, "look_y": look.y + look_y * 0.6,
		"zoom": zoom,
		"walk_steer": walk_steer, "walk": walk, "aim_x": aim_x, "aim_y": aim_y, "mouse_dx": md.x, "mouse_dy": md.y,
		"actions": acts,
	}
