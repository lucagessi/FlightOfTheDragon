// Ruscello della tana del drago (scripts/lair.gd): nastro d'acqua sul letto scavato. UV.x attraverso, UV.y lungo
// la corrente; COLOR.r è la pendenza: dove scende ripido l'acqua corre più veloce e diventa schiuma (cascate).
shader_type spatial;
render_mode cull_disabled;

uniform float u_time;

varying float v_slope;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_slope = COLOR.r * 2.0;
}

void fragment() {
	float speed = 0.6 + v_slope * 5.0;
	vec2 uv = vec2(UV.x * 2.0, UV.y - u_time * speed);
	float n1 = vn(uv * vec2(3.0, 1.4));
	float n2 = vn(uv * vec2(8.0, 3.5) + 13.0);
	float edge = abs(UV.x * 2.0 - 1.0);
	float foam = smoothstep(0.3, 0.8, v_slope) * (0.55 + 0.45 * n2);
	foam += smoothstep(0.7, 1.0, edge) * 0.45 * n1 + smoothstep(0.78, 0.95, n2) * 0.2;
	foam = clamp(foam, 0.0, 1.0);
	ALBEDO = mix(vec3(0.02, 0.07, 0.07), vec3(0.82, 0.88, 0.9), foam);
	ALPHA = mix(0.55, 0.95, foam) * smoothstep(0.0, 0.3, 1.0 - edge);
	ROUGHNESS = mix(0.12, 0.6, foam);
	SPECULAR = 0.5;
	vec3 wn = normalize(vec3((n1 - 0.5) * 0.5, 1.0, (n2 - 0.5) * 0.5));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
