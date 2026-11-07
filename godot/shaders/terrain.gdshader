// Terreno: altezze dalla griglia esportata (interpolazione Catmull-Rom) con rilievo roccioso fine.
// Le maschere procedurali (porting di colorTerrain e makeTerrainMaterial di src/world.js) decidono dove
// vanno erba, campi, terra, sabbia, roccia e neve; il dettaglio viene da texture fotografiche CC0.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D terrain_data : filter_linear, repeat_disable; // R altezza, G rumore fine, B foresta
uniform vec4 villages[12]; // x, z, raggio, tipo (1 villaggio, 2 castello)
uniform float u_time;
uniform vec3 focus; // posizione della camera: il rilievo fine sfuma con la distanza

// strati nell'ordine di World.TERRAIN_LAYERS: erba, terra, roccia, sabbia, neve, ciottoli
uniform sampler2DArray tex_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_h : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 v_wpos;

#include "res://shaders/terrain_common.gdshaderinc"
#include "res://shaders/lair_common.gdshaderinc"

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec3 hg = height_grad(p);
	float h = hg.x + rock_detail(p, hg);
	VERTEX.y = h - UV2.x * 18.0;
	NORMAL = normalize(vec3(-hg.y, 1.0, -hg.z));
	v_wpos = vec3(p.x, h, p.y);
}

// Campione di un materiale: colore, scostamento della normale (in coordinate mondo), occlusione, rugosità, rilievo
struct Mat {
	vec3 col;
	vec3 off;
	float ao;
	float rough;
	float h;
};

// Colore medio di uno strato (ultimo livello di mipmap): serve per applicargli la tinta procedurale
vec3 avg(int i) { return textureLod(tex_d, vec3(0.5, 0.5, float(i)), 12.0).rgb; }

// Campionamento a due scale (dettaglio vicino + scala larga ruotata) per nascondere la ripetizione.
// proj: piano di proiezione (0 orizzontale, 1 parete verso X, 2 parete verso Z).
Mat layer2(int i, vec2 p, float near, float k, int proj) {
	float l = float(i);
	mat2 R = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec3 a = vec3(p / near, l), b = vec3(R * p / (near * 6.5) + 0.37, l);
	Mat m;
	m.col = mix(texture(tex_d, a).rgb, texture(tex_d, b).rgb, k);
	vec2 t = mix(texture(tex_n, a).xy * 2.0 - 1.0, transpose(R) * (texture(tex_n, b).xy * 2.0 - 1.0), k);
	m.off = proj == 0 ? vec3(t.x, 0.0, -t.y) : (proj == 1 ? vec3(0.0, t.y, t.x) : vec3(t.x, t.y, 0.0));
	vec3 ra = texture(tex_arm, a).rgb, rb = texture(tex_arm, b).rgb;
	m.ao = mix(ra.r, rb.r, k);
	m.rough = mix(ra.g, rb.g, k);
	m.h = mix(texture(tex_h, a).r, texture(tex_h, b).r, k);
	return m;
}

// Roccia in proiezione triplanare: niente stiramenti sulle pareti verticali
Mat rock_tri(vec3 p, vec3 wn, float k) {
	vec3 w = pow(abs(wn), vec3(6.0));
	w /= w.x + w.y + w.z;
	Mat r = Mat(vec3(0.0), vec3(0.0), 0.0, 0.0, 0.0);
	for (int j = 0; j < 3; j++) {
		float wj = w[j];
		if (wj < 0.01) continue;
		Mat s = layer2(2, j == 0 ? p.zy : (j == 1 ? p.xz : p.xy), 9.0, k, j == 0 ? 1 : (j == 1 ? 0 : 2));
		r.col += s.col * wj;
		r.off += s.off * wj;
		r.ao += s.ao * wj;
		r.rough += s.rough * wj;
		r.h += s.h * wj;
	}
	return r;
}

// Peso di un nuovo strato steso sopra quello attuale: dove il peso è parziale emerge prima dove il suo
// rilievo supera quello dell'altro (ciuffi d'erba tra la terra, sassi nella sabbia). soft allarga la
// transizione da lontano, dove il rilievo delle mipmap è ormai uniforme.
float hblend(float w, float hn, float hc, float soft) {
	if (w <= 0.0) return 0.0;
	if (w >= 1.0) return 1.0;
	return smoothstep(-soft, soft, (w * 2.0 - 1.0) * 1.2 + (hn - hc) * 0.8);
}
void mix_in(inout Mat cur, Mat n, float w) {
	cur.col = mix(cur.col, n.col, w);
	cur.off = mix(cur.off, n.off, w);
	cur.ao = mix(cur.ao, n.ao, w);
	cur.rough = mix(cur.rough, n.rough, w);
	cur.h = mix(cur.h, n.h, w);
}

void fragment() {
	vec2 tp = v_wpos.xz;
	// normale per pixel dalla superficie completa: le pendici restano nitide anche sui blocchi radi
	float e = 0.9;
	float h0 = surface(tp);
	vec3 wn = normalize(vec3(h0 - surface(tp + vec2(e, 0.0)), e, h0 - surface(tp + vec2(0.0, e))));
	vec4 td = texture(terrain_data, grid_uv(tp));
	float th = v_wpos.y;
	float tdist = length(v_wpos - CAMERA_POSITION_WORLD);
	float tfade = 1.0 / (1.0 + tdist * 0.004);
	// lontano conta di più la scala larga, così la ripetizione del dettaglio non si vede
	float kfar = mix(0.25, 0.85, smoothstep(20.0, 400.0, tdist));
	float soft = mix(0.12, 0.9, smoothstep(40.0, 700.0, tdist));
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float n1 = tfbm(tp * 0.035);
	vec3 tint = ground_tint(v_wpos, td.g, td.b);
	// variazioni ampie e graduali: prati più secchi o più verdi, senza macchie
	tint *= 0.92 + 0.16 * tfbm(tp * 0.004);
	tint = mix(tint, tint * vec3(1.1, 1.03, 0.8), ss(0.45, 0.75, tfbm(tp * 0.0022 + 7.0)) * 0.4);

	// erba (con la tinta procedurale di prati, boschi e campi)
	Mat cur = layer2(0, tp, 4.0, kfar, 0);
	cur.col *= clamp(tint / max(avg(0), vec3(0.01)), 0.0, 3.0);
	// sabbia sulla riva e sul fondale
	float sand_w = ss(6.0, 3.2, th);
	if (sand_w > 0.0) {
		Mat s = layer2(3, tp, 5.0, kfar, 0);
		s.col *= clamp(tint / max(avg(3), vec3(0.01)), 0.0, 3.0);
		mix_in(cur, s, hblend(sand_w, s.h, cur.h, soft));
	}
	// paesi: terra battuta, piazza acciottolata, solchi nei campi
	float rock_mask = ss(0.3, 0.48, slope + (n1 - 0.5) * 0.2) * step(2.0, th);
	for (int i = 0; i < 12; i++) {
		vec4 v = villages[i];
		if (v.w < 0.5) continue;
		float vr = v.z + 10.0;
		float d = length(tp - v.xy);
		if (d > vr + 210.0) continue;
		float paths = ss(0.62, 0.7, tvn(tp * 0.05 + v.xy));
		float inner = ss(vr, vr * 0.7, d) * clamp(0.22 + 0.3 * tfbm(tp * 0.02 + v.xy) + paths * 0.55, 0.0, 0.95);
		if (v.w > 1.5) inner = 0.75 * ss(vr * 0.9, vr * 0.3, d);
		if (inner > 0.0) {
			Mat s = layer2(1, tp, 3.5, kfar, 0);
			s.col *= 0.8;
			mix_in(cur, s, hblend(inner, s.h, cur.h, soft));
		}
		if (v.w > 1.5) continue;
		float dj = d + (tvn(tp * 0.12) - 0.5) * vr * 0.18;
		float plaza = ss(vr * 0.36, vr * 0.28, dj);
		if (plaza > 0.0) {
			Mat s = layer2(5, tp, 3.0, 0.0, 0);
			s.col *= 0.7;
			s.off *= 1.5;
			mix_in(cur, s, hblend(plaza, s.h, cur.h, soft));
		}
		// campi coltivati intorno al paese: appezzamenti irregolari di grano, terra arata, ortaggi e prato,
		// con le file della coltura e siepi sui confini
		float ring = ss(v.z * 0.85, v.z * 0.95, d) * ss(v.z + 200.0, v.z + 140.0, d) * (1.0 - rock_mask) * step(th, 90.0) * ss(0.9, 0.95, wn.y);
		if (ring > 0.0) {
			float ang = atan(tp.y - v.y, tp.x - v.x) + 0.3;
			float ux = cos(ang) * d + (tvn(tp * 0.03) - 0.5) * 14.0;
			float uz = sin(ang) * d + (tvn(tp * 0.03 + 9.0) - 0.5) * 10.0;
			vec2 cell = floor(vec2(ux / 40.0, uz / 28.0));
			float hs = th2(cell + v.xy * 0.01);
			float edge = min(min(fract(ux / 40.0), 1.0 - fract(ux / 40.0)) * 40.0, min(fract(uz / 28.0), 1.0 - fract(uz / 28.0)) * 28.0);
			float inside = ring * ss(1.2, 3.2, edge + (tvn(tp * 0.4) - 0.5) * 1.2);
			// file della coltura (sfumano da lontano per non sfarfallare)
			float rows = (0.5 + 0.5 * sin((fract(hs * 7.3) > 0.5 ? ux : uz) * 2.6)) * (1.0 - ss(120.0, 500.0, tdist));
			float kind = fract(hs * 13.7);
			if (kind < 0.3) {
				// grano maturo
				vec3 wheat = lin(vec3(0.7, 0.6, 0.31)) * (0.7 + 0.5 * cur.h) * mix(0.9, 1.1, tvn(tp * 0.15));
				cur.col = mix(cur.col, wheat * (0.85 + 0.2 * rows), inside * 0.8);
			} else if (kind < 0.5) {
				// terra arata con i solchi
				Mat s = layer2(1, tp, 3.5, kfar, 0);
				s.col *= lin(vec3(0.5, 0.37, 0.23)) / max(avg(1), vec3(0.01)) * (0.75 + 0.35 * rows);
				mix_in(cur, s, hblend(inside * 0.9, s.h, cur.h, soft));
			} else if (kind < 0.7) {
				// ortaggi in file verde scuro
				cur.col = mix(cur.col, cur.col * vec3(0.75, 0.95, 0.65) * (0.7 + 0.4 * rows), inside * 0.8);
			} else {
				// prato da fieno, un po' più secco
				cur.col = mix(cur.col, cur.col * vec3(1.12, 1.05, 0.8), inside * 0.5);
			}
			// siepi e filari sui confini
			float hedge = ring * (1.0 - ss(0.4, 1.6, edge)) * step(0.35, th2(cell.yx + 3.1));
			cur.col = mix(cur.col, cur.col * vec3(0.45, 0.6, 0.4), hedge * 0.8);
		}
	}
	// roccia sui pendii ripidi: foto in triplanare, ingrigita, con creste chiare e canaloni scuri
	if (rock_mask > 0.0) {
		Mat r = rock_tri(v_wpos, wn, kfar);
		float l = dot(r.col, vec3(0.3, 0.59, 0.11));
		r.col = mix(r.col, vec3(l) * vec3(1.0, 0.97, 0.92), 0.55);
		float cavity = ss(0.25, 0.75, ridged(tp / 42.0));
		r.col *= mix(0.6, 1.15, cavity) * mix(0.85, 1.12, tfbm(tp * 0.02 + th * 0.01));
		// licheni sulle parti meno ripide
		r.col = mix(r.col, r.col * vec3(0.85, 1.05, 0.7), ss(0.6, 0.8, tfbm(tp * 0.05)) * (1.0 - ss(0.5, 0.8, slope)) * 0.6);
		r.off *= 1.4;
		mix_in(cur, r, hblend(rock_mask, r.h, cur.h, soft));
	}
	// neve solo sulle cime più alte, dove la pendenza la trattiene
	float snow_line = 255.0 + (n1 - 0.5) * 90.0;
	float snow = ss(snow_line, snow_line + 25.0, th) * (1.0 - ss(0.45, 0.68, slope));
	snow = max(snow, ss(snow_line + 60.0, snow_line + 110.0, th) * (1.0 - ss(0.66, 0.9, slope)));
	// tana del drago: spiazzo e pavimento della grotta di terra battuta e roccia, anneriti dal fuoco, senza neve
	float lz = lair_zone(v_wpos);
	if (lz > 0.0) {
		snow *= 1.0 - lz;
		Mat d = layer2(1, tp, 3.5, kfar, 0);
		d.col *= vec3(0.6, 0.56, 0.52);
		mix_in(cur, d, lz);
		// lastroni di roccia affioranti, bruciature e muschio a chiazze morbide (onde intrecciate: il rumore a
		// griglia, tagliato a soglia, darebbe bordi squadrati)
		Mat r = rock_tri(v_wpos, wn, kfar);
		r.col = mix(r.col, vec3(dot(r.col, vec3(0.3, 0.59, 0.11))), 0.6) * 0.8;
		mix_in(cur, r, lz * ss(0.6, 0.85, lair_blob(tp * 1.3 + 17.0)));
		cur.col *= mix(1.0, 0.45, ss(0.62, 0.9, lair_blob(tp * 0.8 + 40.0)) * lz);
		float moss = ss(0.6, 0.8, lair_blob(tp)) * lz * (1.0 - cave_floor(tp));
		if (moss > 0.0) {
			Mat g = layer2(0, tp, 4.0, kfar, 0);
			g.col *= clamp(lin(vec3(0.4, 0.43, 0.24)) / max(avg(0), vec3(0.01)), 0.0, 3.0);
			mix_in(cur, g, moss);
		}
	}
	// letto del ruscello: sassi bagnati e scuri, niente neve
	float sm = stream_mask(tp);
	if (sm > 0.0) {
		snow *= 1.0 - sm;
		Mat r = rock_tri(v_wpos, wn, kfar);
		r.col *= 0.55;
		mix_in(cur, r, sm * 0.85);
		cur.rough *= 1.0 - 0.5 * sm;
	}
	if (snow > 0.0) {
		Mat s = layer2(4, tp, 6.0, kfar, 0);
		s.col *= vec3(0.9, 0.93, 1.0);
		mix_in(cur, s, hblend(snow, s.h, cur.h, soft));
	}
	ALBEDO = cur.col;
	// prato e terra sono opachi: col sole basso davanti non devono luccicare come un pavimento
	ROUGHNESS = clamp(cur.rough, 0.75, 1.0);
	SPECULAR = 0.3;
	// dentro la grotta arriva solo la luce della bocca
	AO = cur.ao * mix(1.0, cave_light(v_wpos), cave_floor(v_wpos.xz) * step(v_wpos.y, lair_c.y + 4.0));
	AO_LIGHT_AFFECT = 0.15;
	METALLIC = 0.0;
	// il rilievo delle texture sfuma con la distanza (lontano resta solo la forma del terreno)
	float bump = mix(0.7, 0.12, smoothstep(30.0, 900.0, tdist));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn + cur.off * bump, 0.0)).xyz);
}
