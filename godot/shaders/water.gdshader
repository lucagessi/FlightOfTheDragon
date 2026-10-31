// Mare: onde lunghe di Gerstner, increspature, schiuma su costa e creste,
// deformazione per lo spostamento d'aria del drago (porting di src/water.js).
// Riflessi del cielo e scintillio del sole li calcola l'illuminazione PBR di Godot.
shader_type spatial;
render_mode cull_disabled;

#define NP 24
uniform float u_time;
uniform vec4 u_down; // x, z, intensità
uniform vec4 u_pulses[NP]; // x, z, istante, ampiezza
uniform sampler2D terrain_data : filter_linear, repeat_disable;

const float HALF = 3800.0;
const float STEP = 7600.0 / 480.0;
const float NN = 481.0;

varying vec3 v_world;
varying float v_swell;

float terrain_h(vec2 p) {
	vec2 g = (p + HALF) / STEP;
	if (g.x <= 0.0 || g.y <= 0.0 || g.x >= NN - 1.0 || g.y >= NN - 1.0) return -55.0;
	return clamp(textureLod(terrain_data, (g + 0.5) / NN, 0.0).r, -30.0, 30.0);
}

// direzione, lunghezza d'onda, ampiezza, velocità
const vec4 WAVES[6] = {
	vec4(1.0, 0.3, 170.0, 1.5), vec4(0.6, 1.0, 104.0, 0.95), vec4(-0.4, 0.9, 63.0, 0.55),
	vec4(0.9, -0.6, 37.0, 0.3), vec4(-0.8, -0.3, 21.0, 0.14), vec4(0.2, -1.0, 13.0, 0.07)
};
const float SPEEDS[6] = { 11.0, 9.0, 7.0, 5.2, 3.9, 3.1 };

float swell(vec2 p, out vec2 g) {
	float h = 0.0; g = vec2(0.0);
	for (int i = 0; i < 6; i++) {
		vec2 d = normalize(WAVES[i].xy);
		float k = 6.2831853 / WAVES[i].z;
		float ph = dot(d, p) * k + u_time * SPEEDS[i] * k;
		h += WAVES[i].w * sin(ph);
		g += WAVES[i].w * k * cos(ph) * d;
	}
	return h;
}
// spostamento orizzontale che appuntisce le creste
vec2 swell_shift(vec2 p) {
	vec2 s = vec2(0.0);
	for (int i = 0; i < 6; i++) {
		vec2 d = normalize(WAVES[i].xy);
		float k = 6.2831853 / WAVES[i].z;
		float ph = dot(d, p) * k + u_time * SPEEDS[i] * k;
		s -= 0.75 * WAVES[i].w * cos(ph) * d;
	}
	return s;
}

float local_h(vec2 p) {
	float h = 0.0;
	vec2 dd = p - u_down.xy;
	float r2 = dot(dd, dd);
	float s = u_down.z;
	if (s > 0.001 && r2 < 40000.0) {
		float r = sqrt(r2);
		h -= s * 2.8 * exp(-r2 / 420.0);
		h += s * 0.75 * exp(-r2 / 2600.0) * sin(r * 0.55 - u_time * 10.0);
	}
	for (int i = 0; i < NP; i++) {
		vec4 P = u_pulses[i];
		float age = u_time - P.z;
		if (P.w <= 0.0 || age < 0.0 || age > 7.0) continue;
		float d = length(p - P.xy);
		float x = d - (3.0 + age * 17.0);
		float w = 3.0 + age * 2.5;
		if (abs(x) > w * 3.0) continue;
		h += P.w * exp(-x * x / (w * w)) * sin(x * 0.75) * exp(-age * 0.55) / (1.0 + d * 0.025);
	}
	return h;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float detail(vec2 p) {
	float t = u_time;
	return vnoise(p * 0.32 + vec2(t * 0.55, t * 0.3)) * 0.5
		+ vnoise(p * 0.85 - vec2(t * 0.45, -t * 0.8)) * 0.25
		+ vnoise(p * 2.2 + vec2(t * 1.1, t * 0.7)) * 0.12;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 wp = VERTEX + origin;
	vec2 g;
	float depth = max(0.0, -terrain_h(wp.xz));
	float amp = 0.25 + 0.75 * smoothstep(0.0, 14.0, depth);
	float hs = swell(wp.xz, g) * amp;
	vec2 sh = swell_shift(wp.xz) * amp * (1.0 - smoothstep(2000.0, 9000.0, length(wp.xz - CAMERA_POSITION_WORLD.xz)));
	wp.y += hs + local_h(wp.xz);
	wp.xz += sh;
	v_swell = hs;
	v_world = wp;
	VERTEX = wp - origin;
}

void fragment() {
	vec2 p = v_world.xz;
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	float depth = max(0.0, -terrain_h(p));
	float amp = 0.25 + 0.75 * smoothstep(0.0, 14.0, depth);

	vec2 gs; float hs = swell(p, gs);
	gs *= amp;
	float e = 0.7;
	float hl = local_h(p);
	vec2 gl = vec2(local_h(p + vec2(e, 0.0)) - hl, local_h(p + vec2(0.0, e)) - hl) / e;
	float dfade = 1.0 / (1.0 + dist * 0.02);
	float d0 = detail(p);
	vec2 gd = vec2(detail(p + vec2(0.35, 0.0)) - d0, detail(p + vec2(0.0, 0.35)) - d0) / 0.35;
	// l'aria spinta dal drago increspa la superficie
	vec2 dd = p - u_down.xy;
	float down = u_down.z * exp(-dot(dd, dd) / 1800.0);
	vec2 grad = gs + gl + gd * (0.55 + down * 2.5) * dfade;
	vec3 N = normalize(vec3(-grad.x, 1.0, -grad.y));

	vec3 deep = vec3(0.003, 0.025, 0.05);
	vec3 mid = vec3(0.008, 0.07, 0.1);
	vec3 shallow = vec3(0.04, 0.26, 0.27);
	vec3 body = mix(deep, mid, smoothstep(30.0, 10.0, depth));
	body = mix(body, shallow, smoothstep(12.0, 0.0, depth));

	// schiuma: riva, creste, spostamento d'aria, anelli d'onda
	float foam = (1.0 - smoothstep(0.0, 1.8, depth)) * (0.55 + 0.45 * sin(depth * 4.0 - u_time * 1.8 + d0 * 6.0));
	float crest = smoothstep(1.7, 2.9, hs * amp) * smoothstep(0.35, 0.75, detail(p * 0.6 + vec2(u_time * 0.3, 0.0)));
	foam += crest * 0.45 + smoothstep(1.2, 2.2, hs * amp) * 0.12 * d0;
	foam += down * smoothstep(0.3, 0.65, detail(p * 2.3 + u_time));
	foam += clamp(abs(hl) * 0.35, 0.0, 0.6) * smoothstep(0.35, 0.6, d0);
	foam = clamp(foam, 0.0, 1.0) * 0.85;

	ALBEDO = mix(body, vec3(0.82, 0.88, 0.92), foam);
	ROUGHNESS = mix(0.04, 0.8, foam);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	// luce che attraversa le creste
	EMISSION = vec3(0.05, 0.25, 0.22) * max(hs + hl, 0.0) * 0.02 * (1.0 - foam);
	NORMAL = normalize((VIEW_MATRIX * vec4(N, 0.0)).xyz);
}
