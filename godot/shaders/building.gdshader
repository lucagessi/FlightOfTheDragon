// Edifici: texture fotografiche CC0 (intonaco, tegole, ardesia, pietra, travi, assi) tinte con il colore
// di ogni parte, e incendio letto da burn_tex (R carbonizzato, G fuoco, B crollo) — porting di makeBuildingMaterial
shader_type spatial;

uniform sampler2D burn_tex : filter_nearest, repeat_disable;
uniform float burn_size = 1024.0;
uniform float u_time;

uniform sampler2D plaster_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_tiles_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_tiles_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_slate_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_slate_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_wall_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_wall_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D timber_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D timber_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shutter_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shutter_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

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

// Campiona colore (tinto: foto / colore medio * colore della parte) e normale nel piano della faccia
void face_tex(sampler2D d, sampler2D n, vec2 uv, vec3 tint, out vec3 col, out vec2 nt) {
	vec3 a = textureLod(d, vec2(0.5), 12.0).rgb;
	col = texture(d, uv).rgb / max(a, vec3(0.02)) * tint;
	nt = texture(n, uv).xy * 2.0 - 1.0;
}

void fragment() {
	vec3 bn = normalize(v_bnrm);
	vec3 bp = v_bpos;
	// assi della faccia: t orizzontale lungo la parete (o il colmo), b verso l'alto lungo la pendenza
	vec3 t = cross(vec3(0.0, 1.0, 0.0), bn);
	t = length(t) < 0.1 ? vec3(1.0, 0.0, 0.0) : normalize(t);
	vec3 b = normalize(cross(bn, t));
	vec2 uv = vec2(dot(bp, t), dot(bp, b));
	vec3 tint = COLOR.rgb;
	vec3 col = tint;
	vec2 nt = vec2(0.0);
	float rough = 0.88;
	float bump = 1.0;
	int m = int(v_mat + 0.5);
	// i timpani (facce verticali del tetto) sono muro intonacato, non tegole
	if ((m == 1 || m == 5) && abs(bn.y) < 0.2) {
		m = 0;
		tint = vec3(0.62, 0.56, 0.45);
	}
	if (m == 0) {
		face_tex(plaster_d, plaster_n, uv / 2.5, tint, col, nt);
		// sporco che risale dal basso e macchie d'umidità
		col *= mix(0.7, 1.0, smoothstep(0.3, 2.4, bp.y - v_base)) * (0.9 + 0.15 * bvn(uv * 0.6 + v_seed));
	} else if (m == 1) {
		face_tex(roof_tiles_d, roof_tiles_n, uv / 3.6, tint, col, nt);
		col *= 0.85 + 0.25 * bvn(uv * 0.35 + v_seed);
		rough = 0.75;
		bump = 1.4;
	} else if (m == 5) {
		face_tex(roof_slate_d, roof_slate_n, uv / 3.0, tint, col, nt);
		rough = 0.7;
		bump = 1.3;
	} else if (m == 2) {
		face_tex(stone_wall_d, stone_wall_n, uv / 2.6, tint, col, nt);
		bump = 1.5;
	} else if (m == 3) {
		// le travi hanno le venature lungo l'asse più lungo: si usano le coordinate così come sono
		face_tex(timber_d, timber_n, uv.yx / 1.6, tint, col, nt);
		rough = 0.8;
	} else if (m == 6) {
		face_tex(shutter_d, shutter_n, uv / 1.4, tint, col, nt);
		rough = 0.7;
	} else {
		// vetro scuro: riflette il cielo
		col = tint;
		rough = 0.12;
	}
	ALBEDO = mix(col, vec3(0.022, 0.018, 0.016), v_char * 0.93);
	ROUGHNESS = mix(rough, 0.95, v_char);
	vec3 wn = normalize(bn + (t * nt.x + b * nt.y) * 0.6 * bump * (1.0 - v_char * 0.5));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float flick = 0.7 + 0.3 * sin(u_time * 11.0 + v_seed * 3.7) * sin(u_time * 7.3 + v_seed * 1.3);
	float ember = v_char * (0.35 + 0.65 * v_heat) * (0.6 + 0.4 * sin(u_time * 2.3 + v_seed));
	EMISSION = vec3(1.0, 0.36, 0.07) * v_fire * flick * (v_glow * 9.0 + ember * 1.6);
}
