// Erba vicino alla camera: ciuffi di fili su un reticolo fisso nel mondo (la MultiMesh segue la camera a passi
// interi, così i ciuffi non scivolano), appoggiati sul terreno con la stessa altezza dello shader del suolo.
// Il reticolo è diradato dove il suolo non è prato (terra battuta, piazza, campi arati, sabbia, roccia, neve);
// nei campi di grano i fili diventano spighe alte e dorate. Il vento li piega.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

uniform sampler2D terrain_data : filter_linear, repeat_disable;
uniform vec4 villages[12];
uniform float u_time;
uniform vec3 focus;
uniform float spacing = 0.4; // passo del reticolo (m)
uniform float radius = 32.0; // oltre questo raggio i ciuffi spariscono
uniform float inner = 0.0; // sotto questo raggio li disegna l'anello più fitto
uniform float clump = 1.0; // larghezza del ciuffo

varying vec3 v_tint;
varying float v_dry;

#include "res://shaders/terrain_common.gdshaderinc"

uint hash_u(uvec2 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v ^= v >> 16u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v ^= v >> 16u;
	return v.x ^ v.y;
}
float rnd(ivec2 c, uint k) { return float(hash_u(uvec2(c) + uvec2(k * 7919u, k * 104729u)) & 0xffffffu) / 16777216.0; }

// Quanta erba c'è (w), di che colore e quanto è alta, con le stesse maschere dello shader del terreno
vec4 meadow(vec2 tp, float th, float slope, vec3 tint, out float tall) {
	tall = 1.0;
	float n1 = tfbm(tp * 0.035);
	float w = ss(3.8, 6.5, th) * (1.0 - ss(0.26, 0.4, slope + (n1 - 0.5) * 0.2));
	float snow_line = 255.0 + (n1 - 0.5) * 90.0;
	w *= 1.0 - ss(snow_line - 30.0, snow_line, th);
	vec3 col = tint;
	for (int i = 0; i < 12; i++) {
		vec4 v = villages[i];
		if (v.w < 0.5 || w <= 0.0) continue;
		float vr = v.z + 10.0;
		float d = length(tp - v.xy);
		if (d > vr + 210.0) continue;
		float paths = ss(0.62, 0.7, tvn(tp * 0.05 + v.xy));
		float dirt = ss(vr, vr * 0.7, d) * clamp(0.22 + 0.3 * tfbm(tp * 0.02 + v.xy) + paths * 0.55, 0.0, 0.95);
		if (v.w > 1.5) dirt = 0.75 * ss(vr * 0.9, vr * 0.3, d);
		w *= 1.0 - ss(0.25, 0.55, dirt);
		if (v.w > 1.5) continue;
		float dj = d + (tvn(tp * 0.12) - 0.5) * vr * 0.18;
		w *= 1.0 - ss(vr * 0.36, vr * 0.28, dj); // piazza acciottolata
		float ring = ss(v.z * 0.85, v.z * 0.95, d) * ss(v.z + 200.0, v.z + 140.0, d) * step(th, 90.0);
		if (ring > 0.0) {
			float ang = atan(tp.y - v.y, tp.x - v.x) + 0.3;
			float ux = cos(ang) * d + (tvn(tp * 0.03) - 0.5) * 14.0;
			float uz = sin(ang) * d + (tvn(tp * 0.03 + 9.0) - 0.5) * 10.0;
			vec2 cell = floor(vec2(ux / 40.0, uz / 28.0));
			float hs = th2(cell + v.xy * 0.01);
			float edge = min(min(fract(ux / 40.0), 1.0 - fract(ux / 40.0)) * 40.0, min(fract(uz / 28.0), 1.0 - fract(uz / 28.0)) * 28.0);
			float inside = ring * ss(1.2, 3.2, edge + (tvn(tp * 0.4) - 0.5) * 1.2);
			float kind = fract(hs * 13.7);
			if (kind < 0.3) {
				// grano maturo: spighe alte e dorate
				col = mix(col, lin(vec3(0.72, 0.6, 0.3)) * mix(0.85, 1.1, tvn(tp * 0.15)), inside);
				tall = mix(tall, 1.7, inside);
				w = mix(w, 1.0, inside);
			} else if (kind < 0.5) {
				w *= 1.0 - inside; // terra arata
			} else if (kind < 0.7) {
				col = mix(col, col * vec3(0.75, 0.95, 0.65), inside * 0.8);
				tall = mix(tall, 0.6, inside);
			} else {
				col = mix(col, col * vec3(1.12, 1.05, 0.8), inside * 0.5);
				tall = mix(tall, 1.25, inside);
			}
		}
	}
	return vec4(col, w);
}

void vertex() {
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	ivec2 c = ivec2(round(o.xz / spacing));
	vec2 p = vec2(c) * spacing + (vec2(rnd(c, 1u), rnd(c, 2u)) - 0.5) * spacing * 0.9;
	float dist = length(p - CAMERA_POSITION_WORLD.xz);
	float fade = (1.0 - smoothstep(radius * 0.72, radius, dist)) * smoothstep(inner * 0.8, inner, dist);
	if (fade <= 0.0) {
		// fuori dall'anello: ciuffo degenere, senza calcolare terreno e maschere
		VERTEX = vec3(p.x, -1000.0, p.y);
		v_tint = vec3(0.0);
		v_dry = 0.0;
	} else {
		vec3 hg = height_grad(p);
		float h = hg.x + rock_detail(p, hg);
		vec3 tn = normalize(vec3(-hg.y, 1.0, -hg.z));
		float slope = 1.0 - tn.y;
		vec4 td = texture(terrain_data, grid_uv(p));
		vec3 tint = ground_tint(vec3(p.x, h, p.y), td.g, td.b);
		tint *= 0.92 + 0.16 * tfbm(p * 0.004);
		float dry = ss(0.45, 0.75, tfbm(p * 0.0022 + 7.0)) * 0.4;
		tint = mix(tint, tint * vec3(1.1, 1.03, 0.8), dry);
		float tall;
		vec4 m = meadow(p, h, slope, tint, tall);
		// ciuffi sparsi dove il prato si dirada, nessuno oltre il raggio o dentro l'anello più fitto
		float keep = step(rnd(c, 3u), m.w * 1.15);
		float sz = keep * fade * mix(0.55, 1.0, m.w) * (0.75 + 0.5 * rnd(c, 4u));
		vec3 lv = VERTEX - o;
		float a = rnd(c, 5u) * TAU;
		lv.xz = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * lv.xz * clump * mix(0.6, 1.0, sz);
		float height = (0.32 + 0.22 * rnd(c, 6u)) * tall * sz;
		lv.y *= height;
		// vento: raffiche lente che attraversano il prato e un tremolio più rapido, più forti in punta
		float t = UV.y * UV.y;
		float gust = sin(u_time * 1.3 - dot(p, vec2(0.21, 0.13))) * 0.5 + 0.5;
		vec2 wind = vec2(0.8, 0.6) * (0.06 + 0.22 * gust) + vec2(sin(u_time * 4.1 + p.x * 2.3), cos(u_time * 3.7 + p.y * 2.1)) * 0.04;
		lv.xz += wind * t * height * 1.6;
		lv.y -= length(wind) * t * height * 0.35;
		VERTEX = vec3(p.x, h - 0.04, p.y) + lv;
		vec3 bn = NORMAL;
		bn.xz = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * bn.xz;
		NORMAL = normalize(mix(bn, tn, 0.55));
		v_tint = m.rgb * vec3(1.35, 1.4, 1.1) * (0.85 + 0.3 * rnd(c, 7u)) * (0.9 + 0.2 * COLOR.r);
		v_dry = dry + COLOR.g * 0.3;
	}
}

void fragment() {
	float t = UV.y;
	vec3 col = v_tint * mix(0.45, 1.1, t);
	// punte più chiare e secche
	col = mix(col, col * vec3(1.25, 1.15, 0.75), smoothstep(0.65, 1.0, t) * (0.3 + v_dry));
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.55;
	AO = mix(0.55, 1.0, t);
	AO_LIGHT_AFFECT = 0.5;
}
