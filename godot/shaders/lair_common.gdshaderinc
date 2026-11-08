// Parti comuni a terreno e tana del drago (scripts/lair.gd): dove sta la grotta e quanta luce del giorno arriva
// dentro. Il buio è dato dall'occlusione ambientale (AO), che spegne cielo e riflessi ma non le lanterne.
uniform vec4 lair_c = vec4(0.0); // centro del pavimento della grotta (x, y, z); w = 1 se c'è la tana
uniform vec4 lair_ax = vec4(1.0, 0.0, 150.0, 100.0); // asse verso l'interno (x, z), semiassi lungo e largo
uniform vec4 lair_pl = vec4(0.0); // centro dello spiazzo (x, z) e raggio

// metri oltre la bocca, lungo l'asse della grotta
float lair_depth(vec3 p) {
	return dot(p.xz - lair_c.xz, lair_ax.xy) + lair_ax.z;
}

// luce del giorno che arriva in un punto della grotta: piena alla bocca, quasi nulla in fondo
float cave_light(vec3 p) {
	return mix(1.0, 0.025, smoothstep(-10.0, 95.0, lair_depth(p)));
}

// 1 sul pavimento della grotta (e sotto le pareti), 0 fuori
float cave_floor(vec2 p) {
	vec2 d = p - lair_c.xz;
	vec2 q = vec2(dot(d, lair_ax.xy) / lair_ax.z, dot(d, vec2(-lair_ax.y, lair_ax.x)) / lair_ax.w);
	return (1.0 - smoothstep(1.02, 1.2, length(q))) * lair_c.w;
}

// spiazzo e grotta: niente neve, roccia e terra battuta
float lair_zone(vec3 p) {
	if (lair_c.w < 0.5) return 0.0;
	float d = length(p.xz - lair_pl.xy);
	float z = max(1.0 - smoothstep(lair_pl.z - 10.0, lair_pl.z + 45.0, d), cave_floor(p.xz));
	return z * smoothstep(lair_c.y - 70.0, lair_c.y - 8.0, p.y);
}

// macchie morbide e irregolari (0..1) su scala di qualche decina di metri
float lair_blob(vec2 p) {
	vec2 q = p * 0.035;
	q += vec2(sin(q.y * 1.7 + 1.3), sin(q.x * 1.3 + 0.7)) * 0.9;
	float a = sin(q.x * 1.1) * sin(q.y * 0.9 + 0.5);
	vec2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * q * 2.1;
	float b = sin(r.x + sin(r.y * 1.4)) * sin(r.y * 1.2 + 2.0);
	return 0.5 + 0.32 * a + 0.18 * b;
}
