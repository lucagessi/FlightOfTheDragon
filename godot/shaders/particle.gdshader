// Particelle billboard: colore e opacità in INSTANCE_CUSTOM, dimensione nella scala dell'istanza.
// Le fiamme sono lingue di fuoco rivolte verso l'alto, erose da un rumore che sale nel tempo.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform int kind = 0; // 0 fuoco, 1 scintilla

varying vec4 v_col;
varying float v_seed;

void vertex() {
	v_col = INSTANCE_CUSTOM;
	v_seed = float(INSTANCE_ID) * 2.399;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	// dissolvenza lontana
	v_col.a *= 1.0 - smoothstep(4000.0, 7000.0, length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz));
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 q = UV - 0.5;
	q.y = -q.y; // verso l'alto
	float a;
	vec3 col = v_col.rgb;
	if (kind == 1) {
		float d = length(q) * 2.0;
		a = 1.0 - smoothstep(0.0, 0.3, d) * 0.85 - smoothstep(0.3, 1.0, d) * 0.15;
		a *= 1.0 - smoothstep(0.8, 1.0, d);
	} else {
		float t = TIME * 2.2 + v_seed;
		// la fiamma si stringe salendo e ondeggia ai lati
		float sway = (vnoise(vec2(q.y * 3.0 - t, v_seed)) - 0.5) * 0.18 * (q.y + 0.5);
		float width = mix(0.5, 0.12, clamp(q.y + 0.5, 0.0, 1.0));
		float body = 1.0 - length(vec2((q.x - sway) / width, (q.y + 0.08) * 1.7));
		float n = vnoise(vec2(q.x * 5.0 + v_seed, q.y * 4.0 - t * 1.6)) * 0.65 + vnoise(vec2(q.x * 11.0, q.y * 9.0 - t * 2.4) + v_seed) * 0.35;
		a = clamp(body * 1.6 - (1.0 - n) * 0.55, 0.0, 1.0);
		a = a * a * (3.0 - 2.0 * a);
		// il cuore della fiamma è più caldo e chiaro
		col *= 1.0 + smoothstep(0.35, 0.9, a) * 0.6;
	}
	ALBEDO = col;
	ALPHA = clamp(v_col.a * a, 0.0, 1.0);
}
