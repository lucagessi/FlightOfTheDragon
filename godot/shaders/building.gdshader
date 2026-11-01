// Edifici: materiali PBR da texture fotografiche CC0 (colore, normali, occlusione/rugosità, rilievo) tinte con il
// colore di ogni parte, parallasse sui materiali in rilievo (tegole, ardesia, pietra) e incendio letto da burn_tex
// (R carbonizzato, G fuoco, B crollo) — porting di makeBuildingMaterial
shader_type spatial;

uniform sampler2D burn_tex : filter_nearest, repeat_disable;
uniform float burn_size = 1024.0;
uniform float u_time;

// strati nell'ordine di World.BUILDING_LAYERS: intonaco, tegole, pietra, travi, assi, ardesia
uniform sampler2DArray tex_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_h : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

// metri coperti da una ripetizione della texture, profondità del rilievo (m) e forza delle normali per strato
const float SCALE[6] = { 2.5, 3.2, 2.6, 1.6, 1.4, 2.8 };
const float RELIEF[6] = { 0.0, 0.1, 0.07, 0.0, 0.015, 0.05 };
const float BUMP[6] = { 0.8, 1.3, 1.4, 0.9, 0.9, 1.2 };

varying float v_char;
varying float v_fire;
varying float v_glow;
varying float v_seed;
varying float v_heat;
varying vec3 v_bpos;
varying vec3 v_bnrm;
varying float v_mat;
varying float v_base;

float bh2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float bvn(vec2 p) {
	vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(bh2(i), bh2(i + vec2(1.0, 0.0)), u.x), mix(bh2(i + vec2(0.0, 1.0)), bh2(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	// CUSTOM0: id edificio, quota della base, bagliore delle finestre, materiale
	vec4 st = textureLod(burn_tex, vec2((CUSTOM0.x + 0.5) / burn_size, 0.5), 0.0);
	v_bpos = VERTEX;
	v_bnrm = NORMAL;
	float rel = VERTEX.y - CUSTOM0.y;
	VERTEX.y = CUSTOM0.y + rel * (1.0 - 0.62 * st.b);
	VERTEX.x += sin(CUSTOM0.x * 13.0 + VERTEX.y) * st.b * 0.6;
	v_char = st.r;
	v_fire = st.g;
	v_glow = CUSTOM0.z;
	v_seed = CUSTOM0.x;
	v_heat = clamp(1.0 - rel / 16.0, 0.0, 1.0);
	v_mat = CUSTOM0.w;
	v_base = CUSTOM0.y;
}

// Parallasse a strati con rifinitura lineare: sposta le coordinate dove il rilievo nasconde la superficie.
// vt: direzione verso la camera negli assi della faccia; depth in unità di texture.
vec2 pom(float layer, vec2 uv, vec3 vt, float depth, vec2 dx, vec2 dy) {
	const int STEPS = 14;
	float ls = 1.0 / float(STEPS);
	vec2 duv = vt.xy / max(vt.z, 0.25) * depth * ls;
	float ld = 0.0;
	float hd = 1.0 - textureGrad(tex_h, vec3(uv, layer), dx, dy).r;
	for (int i = 0; i < STEPS; i++) {
		if (ld >= hd) break;
		uv -= duv;
		ld += ls;
		hd = 1.0 - textureGrad(tex_h, vec3(uv, layer), dx, dy).r;
	}
	vec2 prev = uv + duv;
	float after = hd - ld;
	float before = 1.0 - textureGrad(tex_h, vec3(prev, layer), dx, dy).r - (ld - ls);
	return mix(uv, prev, clamp(after / (after - before + 1e-5), 0.0, 1.0));
}

void fragment() {
	vec3 bn = normalize(v_bnrm);
	vec3 bp = v_bpos;
	vec3 tint = COLOR.rgb;
	int m = int(v_mat + 0.5);
	vec3 col;
	float rough;
	float ao = 1.0;
	vec3 wn = bn;
	if (m == 6) {
		// vetro scuro: riflette il cielo
		col = tint;
		rough = 0.1;
	} else {
		// sotto le falde: tavolato di legno scuro
		if ((m == 1 || m == 5) && bn.y < -0.2) {
			m = 4;
			tint = vec3(0.05, 0.035, 0.025);
		}
		// assi della faccia: t orizzontale lungo la parete (o il colmo), b verso l'alto lungo la pendenza;
		// le travi hanno le venature lungo l'asse più lungo
		vec3 t = cross(vec3(0.0, 1.0, 0.0), bn);
		t = length(t) < 0.1 ? vec3(1.0, 0.0, 0.0) : normalize(t);
		vec3 b = normalize(cross(bn, t));
		if (m == 3) {
			vec3 k = t;
			t = b;
			b = k;
		}
		float layer = float(m);
		float sc = SCALE[m];
		vec2 uv = vec2(dot(bp, t), dot(bp, b)) / sc;
		vec2 dx = dFdx(uv), dy = dFdy(uv);
		vec3 to_cam = CAMERA_POSITION_WORLD - bp;
		float dist = length(to_cam);
		float depth = RELIEF[m] / sc * (1.0 - smoothstep(25.0, 50.0, dist));
		if (depth > 0.0) {
			vec3 v = to_cam / dist;
			uv = pom(layer, uv, vec3(dot(v, t), dot(v, b), dot(v, bn)), depth, dx, dy);
		}
		vec3 avg = textureLod(tex_d, vec3(0.5, 0.5, layer), 12.0).rgb;
		col = textureGrad(tex_d, vec3(uv, layer), dx, dy).rgb / max(avg, vec3(0.02)) * tint;
		vec3 arm = textureGrad(tex_arm, vec3(uv, layer), dx, dy).rgb;
		vec2 nt = textureGrad(tex_n, vec3(uv, layer), dx, dy).xy * 2.0 - 1.0;
		ao = arm.r;
		rough = clamp(arm.g * 1.1, 0.35, 1.0);
		float wy = bp.y - v_base;
		if (m == 0) {
			// sporco che risale dal basso, macchie d'umidità e colature
			col *= mix(0.68, 1.0, smoothstep(0.3, 2.4, wy)) * (0.88 + 0.16 * bvn(bp.xz * 0.4 + bp.y * 0.3 + v_seed));
			col *= 1.0 - 0.12 * smoothstep(0.55, 0.9, bvn(vec2(dot(bp, t) * 2.5, bp.y * 0.15) + v_seed));
		} else if (m == 1 || m == 5) {
			// tegole diverse una dall'altra, muschio sulle falde e bordi anneriti
			float lum = dot(col, vec3(0.3, 0.59, 0.11));
			col = mix(vec3(lum), col, m == 1 ? 0.78 : 0.9);
			col *= (m == 1 ? 1.25 : 1.0) * (0.82 + 0.3 * bvn(uv * vec2(9.0, 7.0) + v_seed));
			float moss = smoothstep(0.5, 0.85, bvn(bp.xz * 0.45 + v_seed * 3.1) * 0.7 + bvn(bp.xz * 2.1) * 0.3);
			moss *= smoothstep(0.2, 0.6, bn.y) * smoothstep(0.35, 0.7, arm.r);
			col = mix(col, vec3(0.07, 0.085, 0.03), moss * 0.55);
			rough = mix(rough, 0.95, moss);
		} else if (m == 2) {
			// pietra più scura e umida alla base
			col *= mix(0.72, 1.0, smoothstep(0.0, 1.8, wy));
		}
		float bump = BUMP[m] * (1.0 - v_char * 0.5) * mix(1.0, 0.5, smoothstep(40.0, 200.0, dist));
		wn = normalize(bn + (t * nt.x + b * nt.y) * 0.6 * bump);
	}
	ALBEDO = mix(col, vec3(0.022, 0.018, 0.016), v_char * 0.93);
	ROUGHNESS = mix(rough, 0.95, v_char);
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float flick = 0.7 + 0.3 * sin(u_time * 11.0 + v_seed * 3.7) * sin(u_time * 7.3 + v_seed * 1.3);
	float ember = v_char * (0.35 + 0.65 * v_heat) * (0.6 + 0.4 * sin(u_time * 2.3 + v_seed));
	EMISSION = vec3(1.0, 0.36, 0.07) * v_fire * flick * (v_glow * 9.0 + ember * 1.6);
}
