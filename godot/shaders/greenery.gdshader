// Edera e cespugli delle case: ciuffi ritagliati dall'atlante delle foglie (come foliage.gdshader) che il fuoco
// della casa (burn_tex, id dell'edificio in UV2.x) annerisce e poi consuma. COLOR.a: quanto li muove il vento.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D burn_tex : filter_nearest, repeat_disable;
uniform float burn_size = 1024.0;

varying float v_char;

void vertex() {
	vec4 st = textureLod(burn_tex, vec2((UV2.x + 0.5) / burn_size, 0.5), 0.0);
	v_char = st.r;
	// le foglie si accartocciano e spariscono quando la casa è quasi del tutto bruciata
	if (st.r > 0.85 || st.b > 0.02) {
		VERTEX = vec3(0.0, -1000.0, 0.0);
	}
	float sway = COLOR.a;
	float t = TIME * 1.1 + VERTEX.x * 0.3 + VERTEX.z * 0.4;
	VERTEX.x += (sin(t) * 0.04 + sin(TIME * 4.1 + VERTEX.y * 2.3 + VERTEX.x) * 0.025) * sway;
	VERTEX.z += (cos(t * 0.8) * 0.03 + sin(TIME * 3.7 + VERTEX.z * 1.9 + VERTEX.y) * 0.025) * sway;
}

void fragment() {
	vec4 tx = texture(atlas, UV);
	ALPHA = tx.a * (1.0 + length(VERTEX) * 0.003);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(512.0, 256.0);
	vec3 c = tx.rgb * COLOR.rgb;
	// col calore le foglie ingialliscono, poi diventano brune e nere
	c = mix(c, vec3(0.2, 0.13, 0.04) * dot(c, vec3(1.0)), smoothstep(0.0, 0.3, v_char));
	c = mix(c, vec3(0.015), smoothstep(0.3, 0.7, v_char));
	ALBEDO = c;
	ROUGHNESS = 0.7;
	SPECULAR = 0.35;
	BACKLIGHT = c * 0.7;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
