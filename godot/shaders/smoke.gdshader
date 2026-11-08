// Fumo, vapore e spruzzi: billboard in trasparenza normale, più chiari in alto
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

varying vec4 v_col;
varying float v_rot;

void vertex() {
	v_col = INSTANCE_CUSTOM;
	v_rot = float(INSTANCE_ID) * 2.399;
	float c = cos(v_rot), s = sin(v_rot);
	VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_col.a *= 1.0 - smoothstep(4000.0, 7000.0, length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz));
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 q = UV - 0.5;
	float d = length(q) * 2.0;
	float lumps = vnoise(UV * 4.0 + v_rot) * 0.5 + vnoise(UV * 9.0 - v_rot) * 0.25 + 0.35;
	float a = clamp((1.0 - d) * lumps * 1.4, 0.0, 1.0);
	// il lato rivolto verso l'alto è più chiaro
	float light = 0.75 + 0.5 * (0.5 - UV.y);
	ALBEDO = v_col.rgb * light;
	ALPHA = clamp(v_col.a * a, 0.0, 1.0);
}
