// Corpo del drago: ogni vertice è (anello, angolo) in UV2; la posizione la calcola
// lo shader dagli anelli della spina dorsale aggiornati ogni frame dallo script
shader_type spatial;

#include "res://shaders/scales.gdshaderinc"

uniform vec3 centers[64];
uniform vec3 sides[64];
uniform vec3 ups[64];
uniform float radii[64];
uniform vec3 flash = vec3(0.0); // lampo quando il drago viene colpito
uniform float bump = 0.5;

void vertex() {
	int i = int(UV2.x + 0.5);
	float a = UV2.y;
	float hr = (float(i) / 63.0 > 0.4 && float(i) / 63.0 < 0.72) ? 1.12 : 1.0;
	float r = radii[i];
	vec3 S = sides[i], Uu = ups[i];
	VERTEX = centers[i] + S * cos(a) * r + Uu * sin(a) * r * hr;
	NORMAL = normalize(S * cos(a) * hr + Uu * sin(a));
}

void fragment() {
	float h = scale_pattern(UV);
	ALBEDO = COLOR.rgb * h;
	ROUGHNESS = 0.38;
	METALLIC = 0.3;
	EMISSION = flash;
	NORMAL = bump_normal(NORMAL, VERTEX, h, bump);
}
