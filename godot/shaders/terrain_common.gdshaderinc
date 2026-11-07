// Parti comuni a terreno ed erba: altezza Catmull-Rom dalla griglia (terrain_data), rilievo roccioso,
// rumori e tinta di grande scala del suolo. Chi lo include dichiara gli uniform terrain_data e focus.
const float HALF = 3800.0;
const float STEP = 7600.0 / 480.0;
const float NN = 481.0;

vec2 grid_uv(vec2 p) { return ((p + HALF) / STEP + 0.5) / NN; }

// smoothstep che accetta anche gli estremi invertiti, come quello di noise.js
float ss(float e0, float e1, float x) {
	float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }

float th2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float tvn(vec2 p) {
	vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(th2(i), th2(i + vec2(1.0, 0.0)), u.x), mix(th2(i + vec2(0.0, 1.0)), th2(i + vec2(1.0, 1.0)), u.x), u.y);
}
float tfbm(vec2 p) { return tvn(p) * 0.5 + tvn(p * 2.03) * 0.25 + tvn(p * 4.07) * 0.125 + tvn(p * 8.1) * 0.0625; }

vec4 cr_w(float t) {
	float t2 = t * t, t3 = t2 * t;
	return vec4(-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0, -1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2);
}
vec4 cr_d(float t) {
	float t2 = t * t;
	return vec4(-1.5 * t2 + 2.0 * t - 0.5, 4.5 * t2 - 5.0 * t, -4.5 * t2 + 4.0 * t + 0.5, 1.5 * t2 - t);
}

// Altezza e pendenze (dh/dx, dh/dz) della griglia con interpolazione Catmull-Rom
vec3 height_grad(vec2 p) {
	vec2 g = (p + HALF) / STEP;
	vec2 gi = floor(g), t = g - gi;
	vec4 wx = cr_w(t.x), wz = cr_w(t.y), dx = cr_d(t.x), dz = cr_d(t.y);
	ivec2 base = ivec2(gi) - 1;
	float h = 0.0, hx = 0.0, hz = 0.0;
	for (int b = 0; b < 4; b++) {
		float r = 0.0, rd = 0.0;
		for (int a = 0; a < 4; a++) {
			float v = texelFetch(terrain_data, clamp(base + ivec2(a, b), ivec2(0), ivec2(480)), 0).r;
			r += wx[a] * v;
			rd += dx[a] * v;
		}
		h += wz[b] * r;
		hx += wz[b] * rd;
		hz += dz[b] * r;
	}
	return vec3(h, hx / STEP, hz / STEP);
}

// Creste e guglie: rumore "ridged" applicato solo ai pendii rocciosi, sfuma lontano dalla camera
float ridged(vec2 p) {
	float s = 0.0, a = 0.5, f = 1.0;
	for (int i = 0; i < 4; i++) {
		float n = 1.0 - abs(tvn(p * f) * 2.0 - 1.0);
		s += n * n * a;
		a *= 0.5;
		f *= 2.03;
	}
	return s;
}
// Letto del ruscello della tana (maschera da scripts/lair.gd): 1 al centro, 0 oltre le sponde
uniform sampler2D stream_tex : filter_linear, repeat_disable;
uniform vec4 stream_box = vec4(0.0, 0.0, 1.0, 0.0); // origine (x, z), lato, 1 se c'è il ruscello
float stream_mask(vec2 p) {
	if (stream_box.w < 0.5) return 0.0;
	vec2 uv = (p - stream_box.xy) / stream_box.z;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return 0.0;
	return textureLod(stream_tex, uv, 0.0).r;
}

float rock_detail(vec2 p, vec3 hg) {
	float slope = 1.0 - inversesqrt(1.0 + hg.y * hg.y + hg.z * hg.z);
	float amp = smoothstep(0.12, 0.4, slope) * smoothstep(6.0, 30.0, hg.x) * (1.0 - smoothstep(1100.0, 2200.0, length(p - focus.xz)));
	amp *= 1.0 - stream_mask(p);
	return amp > 0.001 ? (ridged(p / 42.0) - 0.45) * 9.0 * amp : 0.0;
}
float surface(vec2 p) {
	vec3 hg = height_grad(p);
	return hg.x + rock_detail(p, hg);
}

// Tinta di grande scala del suolo (era il colore per vertice di colorTerrain): erba, bosco, sabbia
vec3 ground_tint(vec3 wp, float n1, float forest_n) {
	vec3 sand = lin(vec3(0.78, 0.71, 0.52)), wet_sand = lin(vec3(0.55, 0.5, 0.38)), seabed = lin(vec3(0.3, 0.33, 0.28));
	vec3 g1 = lin(vec3(0.27, 0.37, 0.17)), g2 = lin(vec3(0.44, 0.49, 0.27)), forest = lin(vec3(0.18, 0.26, 0.13));
	float y = wp.y;
	vec3 c;
	if (y < 3.2) {
		c = mix(sand, wet_sand, ss(1.5, -1.5, y));
		c = mix(c, seabed, ss(-3.0, -25.0, y));
	} else {
		c = mix(g1, g2, n1);
		c = mix(c, forest, ss(0.0, 0.35, forest_n) * 0.8);
		c = mix(c, sand, ss(6.0, 3.2, y));
	}
	return c * (0.88 + n1 * 0.24);
}
