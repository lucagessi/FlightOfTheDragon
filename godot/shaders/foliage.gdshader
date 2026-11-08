// Foglie e aghi degli alberi: ciuffi ritagliati dall'atlante disegnato in Foliage.atlas(), mossi dal vento,
// con le normali della chioma (luce morbida e volumetrica) e la luce del sole che le attraversa.
// COLOR: ombreggiatura del ciuffo (vertice) per la tinta dell'albero (istanza, nera se bruciato).
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float t = TIME * 1.2 + o.x * 0.05 + o.z * 0.07;
	// la chioma oscilla tutta insieme, i ciuffi tremano ognuno per conto suo
	float bend = max(VERTEX.y - 2.0, 0.0) * 0.014;
	VERTEX.x += sin(t) * bend + sin(TIME * 4.3 + VERTEX.y * 1.7 + VERTEX.x) * 0.035;
	VERTEX.z += cos(t * 0.8) * bend * 0.7 + sin(TIME * 3.9 + VERTEX.z * 1.3 + VERTEX.y) * 0.035;
}

void fragment() {
	vec4 tx = texture(atlas, UV);
	// le mipmap lontane assottigliano il ritaglio: si compensa con la distanza
	ALPHA = tx.a * (1.0 + length(VERTEX) * 0.003);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(512.0, 256.0);
	ALBEDO = tx.rgb * COLOR.rgb;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	BACKLIGHT = ALBEDO * 0.8;
	// la normale è quella della chioma su entrambe le facce del ciuffo
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
