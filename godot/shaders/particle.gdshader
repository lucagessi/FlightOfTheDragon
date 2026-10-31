// Particelle billboard: colore e opacità in INSTANCE_CUSTOM, dimensione nella scala dell'istanza
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform int kind = 0; // 0 fuoco, 1 scintilla

varying vec4 v_col;
varying float v_rot;

void vertex() {
	v_col = INSTANCE_CUSTOM;
	v_rot = float(INSTANCE_ID) * 2.399;
	float c = cos(v_rot), s = sin(v_rot);
	VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
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
	float d = length(UV - 0.5) * 2.0;
	float a;
	if (kind == 1) {
		a = 1.0 - smoothstep(0.0, 0.3, d) * 0.85 - smoothstep(0.3, 1.0, d) * 0.15;
		a *= 1.0 - smoothstep(0.8, 1.0, d);
	} else {
		float lumps = vnoise(UV * 5.0 + v_rot) * 0.6 + 0.4;
		a = clamp((1.0 - d) * (0.8 + 0.6 * lumps), 0.0, 1.0);
		a *= a;
	}
	ALBEDO = v_col.rgb;
	ALPHA = clamp(v_col.a * a, 0.0, 1.0);
}
