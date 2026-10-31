// Membrana delle ali: chiazze e venature che partono dal braccio, visibile da entrambi i lati
shader_type spatial;
render_mode cull_disabled;

uniform vec4 color : source_color = vec4(0.42, 0.07, 0.05, 1.0);
uniform vec4 glow : source_color = vec4(0.14, 0.02, 0.01, 1.0);

float mhash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float mnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mhash(i), mhash(i + vec2(1.0, 0.0)), u.x), mix(mhash(i + vec2(0.0, 1.0)), mhash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	float blot = 0.78 + (mnoise(uv * 9.0) - 0.5) * 0.25 + (mnoise(uv * 23.0) - 0.5) * 0.1;
	// venature: linee serpeggianti dal braccio (v = 0) verso il bordo, con ramificazioni
	float u = uv.x * 22.0 + (mnoise(vec2(uv.x * 6.0, uv.y * 3.0)) - 0.5) * 2.4;
	float vein = 1.0 - smoothstep(0.0, 0.07, abs(fract(u) - 0.5) - 0.42);
	float branch = 1.0 - smoothstep(0.0, 0.05, abs(fract(u * 0.5 + uv.y * 3.0) - 0.5) - 0.46);
	vein = max(vein, branch * step(0.6, mnoise(uv * 5.0)));
	float k = blot * (1.0 - vein * 0.45);
	ALBEDO = color.rgb * k;
	ROUGHNESS = 0.65;
	EMISSION = glow.rgb;
	BACKLIGHT = color.rgb * 0.35;
}
