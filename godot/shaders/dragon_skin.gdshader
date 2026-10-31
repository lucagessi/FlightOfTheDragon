// Pelle del drago (testa, ossa delle ali, zampe): colore uniforme con scaglie in rilievo
shader_type spatial;

#include "res://shaders/scales.gdshaderinc"

uniform vec4 color : source_color = vec4(0.35, 0.04, 0.03, 1.0);
uniform bool use_map = true;
uniform float uv_scale = 2.0;
uniform float bump = 0.35;
uniform float roughness = 0.4;
uniform float metallic = 0.25;

void fragment() {
	float h = scale_pattern(UV * uv_scale);
	ALBEDO = color.rgb * (use_map ? h : 1.0);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	NORMAL = bump_normal(NORMAL, VERTEX, h, bump);
}
