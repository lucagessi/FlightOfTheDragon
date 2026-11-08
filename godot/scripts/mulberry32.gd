# Generatore pseudo-casuale con seme, identico a mulberry32 di src/noise.js:
# stessa sequenza => stessi villaggi, case e alberi della versione Three.js.
class_name Mulberry32
extends RefCounted

const MASK := 0xFFFFFFFF
var _a: int


func _init(seed_value: int) -> void:
	_a = seed_value & MASK


# Moltiplicazione a 32 bit (Math.imul) senza overflow degli interi a 64 bit
static func _imul(a: int, b: int) -> int:
	var al := a & 0xFFFF
	var ah := (a >> 16) & 0xFFFF
	var bl := b & 0xFFFF
	var bh := (b >> 16) & 0xFFFF
	return (al * bl + (((ah * bl + al * bh) & 0xFFFF) << 16)) & MASK


func next() -> float:
	_a = (_a + 0x6D2B79F5) & MASK
	var t := _imul(_a ^ (_a >> 15), 1 | _a)
	t = ((t + _imul(t ^ (t >> 7), 61 | t)) & MASK) ^ t
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0
