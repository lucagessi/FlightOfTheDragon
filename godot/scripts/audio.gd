# Audio procedurale: vento, battito d'ali, fiamme, mare, esplosioni e ruggito (porting di src/audio.js).
# I suoni continui sono rumore in loop filtrato dagli effetti dei bus (frequenza e volume cambiano ogni frame);
# quelli brevi sono sintetizzati una volta all'avvio, in un thread, con filtri e inviluppi come in Web Audio.
class_name GameAudio
extends Node

const RATE := 22050
const MASTER_GAIN := 0.85
const BUS := "Gioco"
enum { LOW, HIGH, BAND }

var muted := false
var active := false
var synth_done := false
var task := -1
var rendered := {}
var sounds := {} # nome -> varianti [{"stream", "gain"}]
var loops := {} # nome -> {"player", "bus", "gain", "freq"}
var pool: Array[AudioStreamPlayer] = []
var pool_i := 0


# Filtro biquad (formule RBJ, come BiquadFilterNode di Web Audio); la frequenza può cambiare nel tempo
class Biquad:
	var type: int
	var q: float
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func _init(t: int, qq: float) -> void:
		type = t
		q = maxf(qq, 0.3)

	func set_freq(f: float) -> void:
		var w := TAU * clampf(f, 10, RATE * 0.45) / RATE
		var c := cos(w)
		var al := sin(w) / (2 * q)
		var a0 := 1 + al
		if type == LOW:
			b0 = (1 - c) / 2 / a0
			b1 = (1 - c) / a0
			b2 = b0
		elif type == HIGH:
			b0 = (1 + c) / 2 / a0
			b1 = -(1 + c) / a0
			b2 = b0
		else:
			b0 = al / a0
			b1 = 0
			b2 = -al / a0
		a1 = -2 * c / a0
		a2 = (1 - al) / a0

	func process(x: float) -> float:
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y


func _ready() -> void:
	# bus del gioco con compressore, come la catena master di Web Audio
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, BUS)
	AudioServer.set_bus_volume_db(idx, linear_to_db(MASTER_GAIN))
	var comp := AudioEffectCompressor.new()
	comp.threshold = -14
	comp.ratio = 4
	AudioServer.add_bus_effect(idx, comp)
	for i in 24:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		pool.append(p)
	task = WorkerThreadPool.add_task(_render_all, false, "Sintesi dei suoni")


# Avviato con la partita (come il contesto Web Audio, che parte al primo comando)
func start() -> void:
	active = true
	if synth_done:
		_start_loops()


func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS), m)


func _process(_dt: float) -> void:
	if task >= 0 and WorkerThreadPool.is_task_completed(task):
		WorkerThreadPool.wait_for_task_completion(task)
		task = -1
		_build_streams()
		synth_done = true
		if active:
			_start_loops()


func _exit_tree() -> void:
	if task >= 0:
		WorkerThreadPool.wait_for_task_completion(task)


# ---------------- SINTESI (thread) ----------------
static func _white(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n + RATE / 10)
	for i in a.size():
		a[i] = randf() * 2 - 1
	return _seamless(a, n)


static func _brown(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n + RATE / 10)
	var last := 0.0
	for i in a.size():
		last = (last + 0.02 * (randf() * 2 - 1)) / 1.02
		a[i] = last * 3.5
	return _seamless(a, n)


# sfuma la coda nell'inizio, così il loop riparte senza scatti
static func _seamless(a: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var fade := a.size() - n
	for i in fade:
		var k := float(i) / fade
		a[i] = a[i] * k + a[n + i] * (1 - k)
	a.resize(n)
	return a


# inviluppo esponenziale da quasi zero al picco e ritorno (exponentialRampToValueAtTime)
static func _env(t: float, peak: float, attack: float, decay: float) -> float:
	peak = maxf(peak, 0.0002)
	if t < attack:
		return 0.0001 * pow(peak / 0.0001, t / attack)
	return peak * pow(0.0001 / peak, minf((t - attack) / decay, 1))


# Raffica di rumore filtrato con frequenza che scivola da f0 a f1, sommata in out
static func _burst(out: PackedFloat32Array, noise: PackedFloat32Array, type: int, f0: float, f1: float,
		peak: float, attack: float, decay: float, q := 0.7) -> void:
	var total := attack + decay
	var n := mini(out.size(), int(total * RATE))
	var f := Biquad.new(type, q)
	var off := randi() % (noise.size() - n)
	for i in n:
		var t := float(i) / RATE
		if i % 16 == 0:
			f.set_freq(f0 * pow(f1 / f0, t / total))
		out[i] += f.process(noise[off + i]) * _env(t, peak, attack, decay)


static func _buf(seconds: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(seconds * RATE))
	return a


# Normalizza e converte in PCM a 16 bit; gain riporta il volume relativo originale
static func _pcm(buf: PackedFloat32Array, normalize := true) -> Dictionary:
	var m := 0.0
	for v in buf:
		m = maxf(m, absf(v))
	var k := 0.95 / maxf(m, 1e-6) if normalize else 1.0
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i] * k, -1, 1) * 32767))
	return {"data": bytes, "gain": 1.0 / k}


func _render_all() -> void:
	var white := _white(RATE * 3)
	var brown := _brown(RATE * 4)
	var r := {"white": [_pcm(white, false)], "brown": [_pcm(brown, false)],
		"flap": [], "whoosh": [], "crackle": [], "explosion": [], "roar": []}
	# più varianti per i suoni ripetuti spesso
	for v in 3:
		var b := _buf(0.45)
		_burst(b, brown, LOW, 500, 120, 0.5, 0.06, 0.35)
		_burst(b, white, BAND, 300, 120, 0.12, 0.05, 0.25, 0.5)
		r.flap.append(_pcm(b))
		b = _buf(0.62)
		_burst(b, white, BAND, 300, 2200, 0.35, 0.15, 0.45, 1.2)
		r.whoosh.append(_pcm(b))
		b = _buf(0.1)
		_burst(b, white, HIGH, 2500, 1500, 0.15, 0.002, 0.08)
		r.crackle.append(_pcm(b))
	# esplosione: boato, schiocco e colpo sordo che scende di tono
	var e := _buf(1.85)
	_burst(e, brown, LOW, 1400, 80, 1.6, 0.01, 1.8)
	_burst(e, white, LOW, 4000, 300, 0.4, 0.005, 0.6)
	var ph := 0.0
	for i in int(0.91 * RATE):
		var t := float(i) / RATE
		ph += 70 * pow(28.0 / 70, t / 0.9) / RATE
		e[i] += sin(ph * TAU) * _env(t, 0.8, 0.01, 0.9)
	r.explosion.append(_pcm(e))
	r.roar.append(_pcm(_roar(white)))
	# colpo di cannone: boato secco e corto con un tonfo profondo
	var c := _buf(1.3)
	_burst(c, brown, LOW, 900, 90, 1.2, 0.005, 1.2)
	_burst(c, white, LOW, 3000, 400, 0.5, 0.002, 0.3)
	ph = 0.0
	for i in int(0.71 * RATE):
		var t := float(i) / RATE
		ph += 55 * pow(32.0 / 55, t / 0.7) / RATE
		c[i] += sin(ph * TAU) * _env(t, 0.9, 0.005, 0.7)
	r.cannon = [_pcm(c)]
	# scatto della corda di balestre e trabucchi
	var tw := _buf(0.4)
	_burst(tw, white, BAND, 700, 250, 0.5, 0.002, 0.3, 4)
	ph = 0.0
	for i in int(0.31 * RATE):
		var t := float(i) / RATE
		ph += lerpf(120, 70, t / 0.3) / RATE
		tw[i] += (2 * fmod(ph, 1.0) - 1) * _env(t, 0.35, 0.003, 0.3)
	r.twang = [_pcm(tw)]
	r.horn = [_pcm(_horn(white))]
	r.magic = [_pcm(_magic())]
	rendered = r


# Ruggito: quattro dente di sega con vibrato, filtro passa-basso che si apre e si chiude, e un soffio rauco
static func _roar(white: PackedFloat32Array) -> PackedFloat32Array:
	var out := _buf(2.2)
	var f := Biquad.new(LOW, 3)
	var freqs := [88.0, 91.0, 133.0, 176.0]
	var phase := [0.0, 0.0, 0.0, 0.0]
	for i in out.size():
		var t := float(i) / RATE
		var vib := sin(TAU * 23 * t) * 9
		var k := lerpf(1.2, 1.0, t / 0.5) if t < 0.5 else lerpf(1.0, 0.75, minf((t - 0.5) / 1.6, 1))
		var s := 0.0
		for j in 4:
			phase[j] = fmod(phase[j] + (freqs[j] * k + vib) / RATE, 1.0)
			s += 2 * phase[j] - 1
		if i % 16 == 0:
			f.set_freq(lerpf(400, 1300, t / 0.4) if t < 0.4 else lerpf(1300, 300, minf((t - 0.4) / 1.6, 1)))
		out[i] = f.process(s) * _env(t, 0.55, 0.15, 1.9)
	_burst(out, white, BAND, 900, 400, 0.25, 0.1, 1.8, 2)
	return out


# Corno di guerra: tre dente di sega in quinta con vibrato lento, filtro chiuso e un po' di fiato
static func _horn(white: PackedFloat32Array) -> PackedFloat32Array:
	var out := _buf(2.6)
	var f := Biquad.new(LOW, 1.2)
	f.set_freq(650)
	var voices := [[98.0, 1.0], [147.0, 0.7], [196.0, 0.4]]
	var phase := [0.0, 0.0, 0.0]
	for i in out.size():
		var t := float(i) / RATE
		var bend := lerpf(0.94, 1.0, minf(t / 0.3, 1))
		var vib := sin(TAU * 5 * t) * 1.2
		var s := 0.0
		for j in 3:
			phase[j] = fmod(phase[j] + (voices[j][0] * bend + vib) / RATE, 1.0)
			s += (2 * phase[j] - 1) * voices[j][1]
		var e := minf(t / 0.35, 1) * (1.0 if t < 1.9 else pow(0.002, (t - 1.9) / 0.7))
		out[i] = f.process(s) * 0.5 * e
	_burst(out, white, BAND, 420, 380, 0.05, 0.3, 2.2, 1)
	return out


# Sfera arcana: due sinusoidi in quinta che scendono, con tremolo e un luccichio acuto
static func _magic() -> PackedFloat32Array:
	var out := _buf(1.0)
	var ph := [0.0, 0.0, 0.0]
	var fr := [523.0, 784.0, 1568.0]
	var amp := [1.0, 0.7, 0.15]
	for i in out.size():
		var t := float(i) / RATE
		var glide := lerpf(1.0, 0.85, t)
		var s := 0.0
		for j in 3:
			ph[j] = fmod(ph[j] + fr[j] * glide / RATE, 1.0)
			s += sin(ph[j] * TAU) * amp[j]
		out[i] = s * (0.7 + 0.3 * sin(TAU * 9 * t)) * _env(t, 0.35, 0.02, 0.95)
	return out


# ---------------- RIPRODUZIONE ----------------
static func _stream(d: Dictionary, loop := false) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = d.data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = d.data.size() / 2
	return s


func _build_streams() -> void:
	for key in rendered:
		sounds[key] = []
		for d in rendered[key]:
			sounds[key].append({"stream": _stream(d, key == "white" or key == "brown"), "gain": d.gain})
	rendered = {}


# Un suono continuo: rumore in loop su un bus con il suo filtro
func _loop(key: String, noise: String, type: int, freq: float, q: float) -> void:
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, "Gioco_" + key)
	AudioServer.set_bus_send(idx, BUS)
	var fx: AudioEffectFilter = AudioEffectLowPassFilter.new() if type == LOW else AudioEffectBandPassFilter.new()
	fx.cutoff_hz = freq
	fx.resonance = clampf(q * 0.6, 0.3, 0.8)
	fx.db = AudioEffectFilter.FILTER_12DB # pendenza dei biquad di Web Audio
	AudioServer.add_bus_effect(idx, fx)
	var p := AudioStreamPlayer.new()
	p.stream = sounds[noise][0].stream
	p.bus = "Gioco_" + key
	p.volume_db = -80
	p.pitch_scale = 0.9 + randf() * 0.2
	add_child(p)
	p.play(randf() * p.stream.get_length())
	loops[key] = {"player": p, "filter": fx, "gain": 0.0, "freq": freq}


func _start_loops() -> void:
	if not loops.is_empty():
		return
	_loop("wind", "brown", LOW, 400, 0.7)
	_loop("wind2", "white", BAND, 1200, 0.6)
	_loop("fire", "white", BAND, 900, 0.7)
	_loop("fire_low", "brown", LOW, 350, 0.7)
	_loop("sea", "brown", LOW, 700, 0.5)
	_loop("blaze", "white", BAND, 2200, 0.8)


# avvicina gradualmente volume (lineare) e frequenza del filtro, come setTargetAtTime
func _approach(key: String, gain: float, dt: float, tc := 0.1, freq := -1.0) -> void:
	var l: Dictionary = loops[key]
	var k := 1 - exp(-dt / tc)
	l.gain += (gain - l.gain) * k
	l.player.volume_db = linear_to_db(maxf(l.gain, 1e-5))
	if freq > 0:
		l.freq += (freq - l.freq) * k
		l.filter.cutoff_hz = l.freq


# s: speed, breathing, water (0-1), burn (incendi vicini), in_cloud (0-1)
func update_audio(dt: float, s: Dictionary) -> void:
	if loops.is_empty():
		return
	var sp := minf(1, s.speed / 170.0)
	var cloud: float = s.get("in_cloud", 0.0)
	var br: bool = s.breathing
	_approach("wind", 0.12 + sp * 0.55 + cloud * 0.15, dt, 0.1, 250 + sp * 900)
	_approach("wind2", sp * sp * 0.12, dt, 0.1, 800 + sp * 1800)
	_approach("fire", 0.55 if br else 0.0, dt, 0.05 if br else 0.15, 700 + randf() * 500)
	_approach("fire_low", 0.7 if br else 0.0, dt, 0.05 if br else 0.2)
	_approach("sea", 0.03 + s.water * 0.45, dt)
	_approach("blaze", minf(0.45, s.burn) * (0.5 + randf() * 0.5), dt, 0.04)


func _play(key: String, vol: float, pitch := 1.0) -> void:
	if not synth_done or not active or vol < 0.002:
		return
	var v: Dictionary = sounds[key].pick_random()
	var p := pool[pool_i]
	pool_i = (pool_i + 1) % pool.size()
	p.stream = v.stream
	p.volume_db = linear_to_db(vol * v.gain)
	p.pitch_scale = pitch
	p.play()


func flap(power: float) -> void:
	_play("flap", power, 0.92 + randf() * 0.16)


func whoosh(amount := 1.0) -> void:
	_play("whoosh", amount, 0.95 + randf() * 0.1)


func explosion(dist: float) -> void:
	var v := 1 / (1 + dist / 250)
	if v >= 0.03:
		_play("explosion", v, 0.9 + randf() * 0.2)


func roar(vol := 1.0) -> void:
	_play("roar", vol, 0.95 + randf() * 0.1)


# Suono di un'arma della fortezza (cannon, twang, horn, magic, whoosh), attenuato con la distanza
func shot(key: String, dist: float, vol := 1.0, pitch := 1.0) -> void:
	_play(key, vol / (1 + dist / 300), pitch * (0.95 + randf() * 0.1))


func crackle() -> void:
	_play("crackle", 1.0, 0.9 + randf() * 0.2)
