// Scaglie embricate procedurali (8 colonne x 10 file per tessera, senza cuciture):
// stessa disposizione della texture su canvas di src/dragon.js.
// Restituisce la luminosità della scaglia (fa da colore e da rilievo).

float scale_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float scale_pattern(vec2 uv) {
	float X = fract(uv.x) * 8.0;
	float Y = (1.0 - fract(uv.y)) * 10.0;
	float r = floor(Y);
	float off = mod(r, 2.0) * 0.5;
	float dy = Y - r;
	// nella stessa fila vince la scaglia disegnata per ultima (colonna più alta)
	float found = -1.0;
	float best_dx = 0.0;
	float best_e = 0.0;
	for (int k = -1; k <= 1; k++) {
		float cx = floor(X - off) + float(k) + off;
		float dx = X - cx;
		float e = (dx / 0.62) * (dx / 0.62) + (dy / 0.814) * (dy / 0.814);
		if (e <= 1.0) {
			found = cx;
			best_dx = dx;
			best_e = e;
		}
	}
	if (found < -0.5) return 0.23; // fessura scura tra le file
	float tone = (200.0 + floor(scale_hash(mod(vec2(floor(found + 8.0), r), vec2(8.0, 10.0))) * 40.0)) / 255.0;
	float t = clamp(length(vec2((best_dx + 0.093) / 0.62, (dy - 0.16) / 0.814)), 0.0, 1.0);
	float c;
	if (t < 0.55) c = mix(tone + 15.0 / 255.0, tone - 30.0 / 255.0, t / 0.55);
	else if (t < 0.85) c = mix(tone - 30.0 / 255.0, 110.0 / 255.0, (t - 0.55) / 0.3);
	else c = mix(110.0 / 255.0, 40.0 / 255.0, (t - 0.85) / 0.15);
	// cresta centrale di ogni scaglia
	if (abs(best_dx) < 0.03 && dy > 0.04 && dy < 0.65) c += 0.18;
	return c;
}

// Rilievo senza tangenti (gradiente in spazio schermo): n e pos in spazio vista
vec3 bump_normal(vec3 n, vec3 pos, float h, float strength) {
	vec3 dpdx = dFdx(pos), dpdy = dFdy(pos);
	float dhdx = dFdx(h), dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, n), r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * n - grad * strength);
}
