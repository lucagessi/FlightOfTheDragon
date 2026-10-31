// Edifici: texture procedurali (tegole, pietra, legno, intonaco) e incendio
// letto da burn_tex (R carbonizzato, G fuoco, B crollo) — porting di makeBuildingMaterial
shader_type spatial;

uniform sampler2D burn_tex : filter_nearest, repeat_disable;
uniform float burn_size = 1024.0;
uniform float u_time;

varying float v_char;
varying float v_fire;
varying float v_glow;
varying float v_seed;
varying float v_heat;
varying vec3 v_bpos;
varying vec3 v_bnrm;
varying float v_mat;

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
}

void fragment() {
	vec3 bn = normalize(v_bnrm);
	vec3 bp = v_bpos;
	float bu = abs(bn.x) > abs(bn.z) ? bp.z : bp.x;
	float bfade = 1.0 / (1.0 + length(bp - CAMERA_POSITION_WORLD) * 0.006);
	float k = 1.0;
	if (v_mat > 0.5 && v_mat < 1.5) {
		// tegole: file sfalsate, ombra sotto ogni fila, colore che varia da tegola a tegola
		float rc = bp.y * 2.3;
		float row = floor(rc), fr = fract(rc);
		float cc = bu * 1.7 + row * 0.5;
		float fc = fract(cc);
		float gap = smoothstep(0.0, 0.1, fc) * (1.0 - smoothstep(0.9, 1.0, fc));
		float lip = 0.55 + 0.45 * smoothstep(0.0, 0.35, fr);
		float var = bh2(vec2(floor(cc), row));
		k = mix(1.0, lip * (0.72 + 0.28 * gap), bfade) * (0.82 + 0.36 * var) * (0.9 + 0.2 * bvn(bp.xz * 0.3));
	} else if (v_mat > 1.5 && v_mat < 2.5) {
		// blocchi di pietra con malta
		float rc = bp.y * 1.5;
		float rowi = floor(rc);
		float cu = (abs(bn.y) > 0.7 ? bp.x : bu) * 0.75 + mod(rowi, 2.0) * 0.5;
		vec2 f = vec2(fract(cu), abs(bn.y) > 0.7 ? fract(bp.z * 0.75) : fract(rc));
		float mortar = smoothstep(0.0, 0.07, f.x) * (1.0 - smoothstep(0.93, 1.0, f.x)) * smoothstep(0.0, 0.1, f.y) * (1.0 - smoothstep(0.9, 1.0, f.y));
		float var = bh2(vec2(floor(cu), rowi));
		k = mix(1.0, 0.55 + 0.45 * mortar, bfade) * (0.75 + 0.45 * var) * (0.85 + 0.3 * bvn(vec2(bu, bp.y) * 2.0));
	} else if (v_mat > 2.5 && v_mat < 3.5) {
		// venature del legno
		float g = sin((bu * 0.4 + bp.y * 5.0) * 5.0 + bvn(vec2(bu, bp.y) * 3.0) * 5.0);
		k = 0.82 + 0.18 * g;
	} else if (v_mat < 0.5) {
		// intonaco con macchie
		float st = bvn(vec2(bu, bp.y) * 0.7) * 0.6 + bvn(vec2(bu, bp.y) * 3.1) * 0.4;
		k = 0.86 + 0.2 * st;
	}
	ALBEDO = mix(COLOR.rgb * k, vec3(0.022, 0.018, 0.016), v_char * 0.93);
	ROUGHNESS = 0.88;
	float flick = 0.7 + 0.3 * sin(u_time * 11.0 + v_seed * 3.7) * sin(u_time * 7.3 + v_seed * 1.3);
	float ember = v_char * (0.35 + 0.65 * v_heat) * (0.6 + 0.4 * sin(u_time * 2.3 + v_seed));
	EMISSION = vec3(1.0, 0.36, 0.07) * v_fire * flick * (v_glow * 9.0 + ember * 1.6);
}
