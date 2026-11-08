// Tana del drago: guscio di roccia della grotta, ossa, carri, navi, tesoro, lanterne e uova (scripts/lair.gd).
// CUSTOM0: x materiale, y 1 se dentro la grotta (buia), z indice della lanterna. Le texture (roccia, travi,
// assi, neve) sono quelle del terreno e degli edifici, proiettate in triplanare o lungo l'UV.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2DArray tex_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lit_tex : filter_nearest, repeat_disable; // R: lanterna accesa
uniform float u_time;

#include "res://shaders/lair_common.gdshaderinc"

const int ROCK = 0;
const int WOOD = 1;
const int PLANKS = 2;
const int BONE = 3;
const int GOLD = 4;
const int IRON = 5;
const int GEM = 6;
const int EGG = 7;
const int STRAW = 8;
const int CLOTH = 9;
const int SILVER = 10;
const int GLASS = 11;
const int SHELL_IN = 12;
const int HOARD = 13;

varying vec3 v_wpos;
varying vec3 v_wnrm;
varying vec4 v_cus;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_cus = CUSTOM0;
}

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float h31(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vn3(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), u.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), u.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}
float fbm3(vec3 p) { return vn3(p) * 0.5 + vn3(p * 2.03) * 0.25 + vn3(p * 4.1) * 0.125 + vn3(p * 8.2) * 0.0625; }

// Campione triplanare di uno strato: colore, normale (mondo), occlusione e rugosità
struct Tri {
	vec3 col;
	vec3 n;
	float ao;
	float rough;
};
Tri tri(float l, vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec3 ax = vec3(p.zy / scale, l), ay = vec3(p.xz / scale, l), az = vec3(p.xy / scale, l);
	Tri t;
	t.col = texture(tex_d, ax).rgb * w.x + texture(tex_d, ay).rgb * w.y + texture(tex_d, az).rgb * w.z;
	vec2 nx = texture(tex_n, ax).xy * 2.0 - 1.0, ny = texture(tex_n, ay).xy * 2.0 - 1.0, nz = texture(tex_n, az).xy * 2.0 - 1.0;
	t.n = normalize(n + (vec3(0.0, nx.y, nx.x) * w.x + vec3(ny.x, 0.0, -ny.y) * w.y + vec3(nz.x, nz.y, 0.0) * w.z) * 1.2);
	vec3 ra = texture(tex_arm, ax).rgb * w.x + texture(tex_arm, ay).rgb * w.y + texture(tex_arm, az).rgb * w.z;
	t.ao = ra.r;
	t.rough = ra.g;
	return t;
}

void fragment() {
	int m = int(v_cus.x + 0.5);
	float inside = v_cus.y;
	vec3 wn = normalize(v_wnrm) * (FRONT_FACING ? 1.0 : -1.0);
	vec3 col = COLOR.rgb;
	vec3 n = wn;
	float rough = 0.8;
	float metal = 0.0;
	float spec = 0.4;
	float ao = 1.0;
	vec3 emit = vec3(0.0);
	float noise = fbm3(v_wpos * 0.8);

	if (m == ROCK) {
		Tri t = tri(0.0, v_wpos, wn, 9.0);
		Tri t2 = tri(0.0, v_wpos * 0.21 + 3.7, wn, 9.0);
		float l = dot(mix(t.col, t2.col, 0.45), vec3(0.3, 0.59, 0.11));
		col = vec3(l) * vec3(1.0, 0.96, 0.9) * col * 2.2;
		col *= mix(0.65, 1.15, fbm3(v_wpos * 0.03));
		n = normalize(mix(t.n, t2.n, 0.4));
		ao = t.ao;
		rough = clamp(t.rough, 0.7, 1.0);
		spec = 0.3;
		// fuori: neve sulle facce rivolte in alto, come sulle pendici del monte
		float snow = (1.0 - inside) * smoothstep(0.42, 0.7, wn.y + (fbm3(v_wpos * 0.08) - 0.5) * 0.5);
		if (snow > 0.0) {
			Tri s = tri(3.0, v_wpos, wn, 6.0);
			col = mix(col, s.col * vec3(0.9, 0.93, 1.0), snow);
			n = normalize(mix(n, s.n, snow));
			rough = mix(rough, 0.85, snow);
		}
		// dentro: pareti umide e annerite dal fumo verso l'alto
		col *= mix(1.0, 0.7 - 0.25 * smoothstep(10.0, 70.0, v_wpos.y - lair_c.y), inside);
	} else if (m == WOOD || m == PLANKS) {
		if (m == PLANKS) {
			// fasciame: assi lungo l'UV con le commessure scure
			vec2 uv = UV * vec2(0.3, 1.0 / 0.42);
			float row = floor(uv.y);
			vec3 tc = vec3(uv.x + h21(vec2(row, 1.0)) * 7.0, fract(uv.y) * 0.3, 2.0);
			col *= texture(tex_d, tc).rgb * 2.0 * (0.8 + 0.4 * h21(vec2(row, 3.0)));
			float seam = smoothstep(0.0, 0.07, fract(uv.y)) * smoothstep(1.0, 0.93, fract(uv.y));
			col *= mix(0.35, 1.0, seam);
			rough = 0.85;
		} else {
			Tri t = tri(1.0, v_wpos, wn, 2.2);
			col *= t.col * 2.0;
			n = t.n;
			ao = t.ao;
			rough = clamp(t.rough, 0.6, 1.0);
		}
		// legno vecchio, ingrigito e marcio a chiazze
		col = mix(col, vec3(dot(col, vec3(0.33))) * vec3(0.9, 0.85, 0.8), 0.3 + 0.3 * noise);
	} else if (m == BONE) {
		float c = fbm3(v_wpos * 3.0);
		col *= 0.75 + 0.4 * c;
		col = mix(col, col * vec3(0.7, 0.62, 0.5), smoothstep(0.55, 0.75, fbm3(v_wpos * 0.7)));
		rough = 0.65;
		spec = 0.45;
	} else if (m == GOLD || m == SILVER || m == HOARD) {
		// monete ammucchiate: celle tonde con il bordo in rilievo, e scintille che cambiano con lo sguardo
		vec3 q = v_wpos * 3.2;
		vec3 cell = floor(q);
		float dmin = 9.0;
		vec3 best = vec3(0.0);
		for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
			vec3 c = cell + vec3(float(x), float(y), float(z));
			vec3 o = c + vec3(h31(c), h31(c + 7.1), h31(c + 3.3));
			float d = length(q - o);
			if (d < dmin) { dmin = d; best = c; }
		}
		float rim = smoothstep(0.42, 0.5, dmin) * (1.0 - smoothstep(0.5, 0.62, dmin));
		col *= 0.9 + 0.4 * h31(best) - rim * 0.3;
		n = normalize(wn + (vec3(h31(best + 1.0), h31(best + 2.0), h31(best + 3.0)) - 0.5) * 0.6);
		metal = m == HOARD ? 0.3 : 0.6;
		rough = (m == HOARD ? 0.5 : 0.3) + 0.15 * noise;
		if (m == HOARD) n = normalize(wn + (n - wn) * 2.2);
		spec = 0.5;
		vec3 vd = normalize(v_wpos - CAMERA_POSITION_WORLD);
		float glint = step(0.985, h31(best + floor(vd * 28.0)));
		// al buio della grotta il tesoro manda appena un riflesso, le scintille restano
		emit = col * (glint * 3.0 * mix(1.0, 0.5, inside) + 0.006 * inside);
	} else if (m == IRON) {
		col *= mix(vec3(1.0), vec3(1.5, 0.85, 0.5), smoothstep(0.5, 0.75, fbm3(v_wpos * 2.0)));
		metal = 0.75;
		rough = 0.55 + 0.25 * noise;
	} else if (m == GEM) {
		rough = 0.05;
		spec = 1.0;
		vec3 vd = normalize(CAMERA_POSITION_WORLD - v_wpos);
		emit = col * (0.25 + 1.5 * pow(1.0 - abs(dot(vd, wn)), 3.0)) * inside;
	} else if (m == EGG || m == SHELL_IN) {
		if (m == EGG) {
			// squame in file sfalsate, con il bordo scuro e un riflesso cangiante
			vec2 g = vec2(UV.x * 26.0, UV.y * 15.0);
			float row = floor(g.y);
			g.x += mod(row, 2.0) * 0.5;
			vec2 f = fract(g) - vec2(0.5, 0.75);
			float sc = length(f * vec2(1.0, 0.8));
			float edge = smoothstep(0.38, 0.55, sc);
			col *= mix(1.15, 0.45, edge) * (0.85 + 0.3 * h21(floor(g)));
			vec3 vd = normalize(CAMERA_POSITION_WORLD - v_wpos);
			float fr = pow(1.0 - abs(dot(vd, wn)), 2.0);
			col += vec3(0.25, 0.1, 0.35) * fr * 0.5;
			rough = 0.35 + edge * 0.3;
			spec = 0.6;
		} else {
			col *= 0.85 + 0.3 * noise;
			rough = 0.5;
		}
	} else if (m == STRAW) {
		col *= 0.6 + 0.6 * fbm3(v_wpos * vec3(6.0, 1.5, 6.0));
		rough = 0.95;
		spec = 0.2;
	} else if (m == CLOTH) {
		col *= 0.7 + 0.4 * noise;
		rough = 0.95;
	} else if (m == GLASS) {
		// vetro della lanterna: spento è scuro, acceso brilla della fiamma che tremola
		float lit = texelFetch(lit_tex, ivec2(int(v_cus.z + 0.5), 0), 0).r;
		float fl = 0.85 + 0.1 * sin(u_time * 9.0 + v_cus.z * 1.7) + 0.05 * sin(u_time * 23.0 + v_cus.z);
		col = vec3(0.05, 0.04, 0.03);
		rough = 0.15;
		spec = 0.6;
		emit = vec3(1.0, 0.5, 0.16) * lit * fl * 9.0;
	}

	// buio della grotta: niente luce del cielo dentro, salvo vicino alla bocca
	ao *= mix(1.0, cave_light(v_wpos), inside);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	AO = ao;
	AO_LIGHT_AFFECT = 0.0;
	EMISSION = emit;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
