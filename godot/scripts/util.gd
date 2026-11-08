# Utilità numeriche condivise (equivalenti di src/noise.js)
class_name U


static func smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# Smorzamento indipendente dal frame
static func damp(a: float, b: float, rate: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-rate * dt))


static func damp_v(a: Vector3, b: Vector3, rate: float, dt: float) -> Vector3:
	return a.lerp(b, 1.0 - exp(-rate * dt))


static func ease_in_out(p: float) -> float:
	return p * p * p * (p * (p * 6.0 - 15.0) + 10.0)


# Conversione sRGB -> lineare per i colori dei vertici
static func lin(r: float, g: float, b: float) -> Color:
	return Color(pow(r, 2.2), pow(g, 2.2), pow(b, 2.2))
