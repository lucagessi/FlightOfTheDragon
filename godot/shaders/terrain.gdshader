// Terreno: altezze dalla griglia esportata (interpolazione Catmull-Rom) con rilievo roccioso fine.
// Le maschere procedurali (porting di colorTerrain e makeTerrainMaterial di src/world.js) decidono dove
// vanno erba, campi, terra, sabbia, roccia e neve; il dettaglio viene da texture fotografiche CC0.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D terrain_data : filter_linear, repeat_disable; // R altezza, G rumore fine, B foresta
uniform vec4 villages[12]; // x, z, raggio, tipo (1 villaggio, 2 castello)
uniform float u_time;
uniform vec3 focus; // posizione della camera: il rilievo fine sfuma con la distanza

uniform sampler2D grass_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

const float HALF = 3800.0;
const float STEP = 7600.0 / 480.0;
const float NN = 481.0;

varying vec3 v_wpos;

vec2 grid_uv(vec2 p) { return ((p + HALF) / STEP + 0.5) / NN; }

// smoothstep che accetta anche gli estremi invertiti, come quello di noise.js
float ss(float e0, float e1, float x) {
	float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }

float th2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float tvn(vec2 p) {
	vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(th2(i), th2(i + vec2(1.0, 0.0)), u.x), mix(th2(i + vec2(0.0, 1.0)), th2(i + vec2(1.0, 1.0)), u.x), u.y);
}
float tfbm(vec2 p) { return tvn(p) * 0.5 + tvn(p * 2.03) * 0.25 + tvn(p * 4.07) * 0.125 + tvn(p * 8.1) * 0.0625; }

vec4 cr_w(float t) {
	float t2 = t * t, t3 = t2 * t;
	return vec4(-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0, -1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2);
}
vec4 cr_d(float t) {
	float t2 = t * t;
	return vec4(-1.5 * t2 + 2.0 * t - 0.5, 4.5 * t2 - 5.0 * t, -4.5 * t2 + 4.0 * t + 0.5, 1.5 * t2 - t);
}

// Altezza e pendenze (dh/dx, dh/dz) della griglia con interpolazione Catmull-Rom
vec3 height_grad(vec2 p) {
	vec2 g = (p + HALF) / STEP;
	vec2 gi = floor(g), t = g - gi;
	vec4 wx = cr_w(t.x), wz = cr_w(t.y), dx = cr_d(t.x), dz = cr_d(t.y);
	ivec2 base = ivec2(gi) - 1;
	float h = 0.0, hx = 0.0, hz = 0.0;
	for (int b = 0; b < 4; b++) {
		float r = 0.0, rd = 0.0;
		for (int a = 0; a < 4; a++) {
			float v = texelFetch(terrain_data, clamp(base + ivec2(a, b), ivec2(0), ivec2(480)), 0).r;
			r += wx[a] * v;
			rd += dx[a] * v;
		}
		h += wz[b] * r;
		hx += wz[b] * rd;
		hz += dz[b] * r;
	}
	return vec3(h, hx / STEP, hz / STEP);
}

// Creste e guglie: rumore "ridged" applicato solo ai pendii rocciosi, sfuma lontano dalla camera
float ridged(vec2 p) {
	float s = 0.0, a = 0.5, f = 1.0;
	for (int i = 0; i < 4; i++) {
		float n = 1.0 - abs(tvn(p * f) * 2.0 - 1.0);
		s += n * n * a;
		a *= 0.5;
		f *= 2.03;
	}
	return s;
}
float rock_detail(vec2 p, vec3 hg) {
	float slope = 1.0 - inversesqrt(1.0 + hg.y * hg.y + hg.z * hg.z);
	float amp = smoothstep(0.12, 0.4, slope) * smoothstep(6.0, 30.0, hg.x) * (1.0 - smoothstep(1100.0, 2200.0, length(p - focus.xz)));
	return amp > 0.001 ? (ridged(p / 42.0) - 0.45) * 9.0 * amp : 0.0;
}
float surface(vec2 p) {
	vec3 hg = height_grad(p);
	return hg.x + rock_detail(p, hg);
}

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec3 hg = height_grad(p);
	float h = hg.x + rock_detail(p, hg);
	VERTEX.y = h - UV2.x * 18.0;
	NORMAL = normalize(vec3(-hg.y, 1.0, -hg.z));
	v_wpos = vec3(p.x, h, p.y);
}

// Tinta di grande scala del suolo (era il colore per vertice di colorTerrain): erba, bosco, campi, sabbia
vec3 ground_tint(vec3 wp, float ny, float n1, float forest_n) {
	vec3 sand = lin(vec3(0.78, 0.71, 0.52)), wet_sand = lin(vec3(0.55, 0.5, 0.38)), seabed = lin(vec3(0.3, 0.33, 0.28));
	vec3 g1 = lin(vec3(0.24, 0.39, 0.13)), g2 = lin(vec3(0.44, 0.52, 0.2)), forest = lin(vec3(0.16, 0.28, 0.1));
	vec3 fields[5] = { lin(vec3(0.66, 0.58, 0.33)), lin(vec3(0.38, 0.48, 0.2)), lin(vec3(0.42, 0.36, 0.25)), lin(vec3(0.5, 0.54, 0.27)), lin(vec3(0.6, 0.53, 0.3)) };
	float y = wp.y;
	vec3 c;
	if (y < 3.2) {
		c = mix(sand, wet_sand, ss(1.5, -1.5, y));
		c = mix(c, seabed, ss(-3.0, -25.0, y));
	} else {
		c = mix(g1, g2, n1);
		c = mix(c, forest, ss(0.0, 0.35, forest_n) * 0.8);
		c = mix(c, sand, ss(6.0, 3.2, y));
		// campi coltivati intorno ai villaggi
		for (int i = 0; i < 12; i++) {
			vec4 v = villages[i];
			if (v.w < 0.5 || v.w > 1.5) continue;
			float d = length(wp.xz - v.xy);
			if (d > v.z + 200.0 || d < v.z * 0.85 || y > 90.0 || ny < 0.93) continue;
			float ang = atan(wp.z - v.y, wp.x - v.x) + 0.3;
			// confini dei campi irregolari, come appezzamenti veri
			float ux = cos(ang) * d + (tvn(wp.xz * 0.03) - 0.5) * 14.0;
			float uz = sin(ang) * d + (tvn(wp.xz * 0.03 + 9.0) - 0.5) * 10.0;
			int cell = (int(floor(ux / 40.0)) * 73856093) ^ (int(floor(uz / 28.0)) * 19349663);
			float edge = min(min(fract(ux / 40.0), 1.0 - fract(ux / 40.0)) * 40.0, min(fract(uz / 28.0), 1.0 - fract(uz / 28.0)) * 28.0);
			float k = 0.55 * ss(v.z + 200.0, v.z + 140.0, d) * ss(0.5, 3.0, edge);
			c = mix(c, fields[abs(cell) % 5] * (0.9 + 0.2 * tvn(wp.xz * 0.08)), k);
		}
	}
	return c * (0.88 + n1 * 0.24);
}

// Campionamento a due scale (dettaglio vicino + scala larga) per nascondere la ripetizione.
// Restituisce colore e scostamento della normale nel piano orizzontale.
void tex2(sampler2D d, sampler2D n, vec2 p, float near, float far, float k, out vec3 col, out vec3 nrm) {
	vec2 a = p / near, b = p / far + 0.37;
	col = mix(texture(d, a).rgb, texture(d, b).rgb, k);
	vec3 na = texture(n, a).xyz * 2.0 - 1.0, nb = texture(n, b).xyz * 2.0 - 1.0;
	vec2 t = mix(na.xy, nb.xy, k);
	nrm = vec3(t.x, 0.0, -t.y);
}

// Colore medio di una texture (ultimo livello di mipmap): serve per applicarle la tinta procedurale
vec3 avg(sampler2D d) { return textureLod(d, vec2(0.5), 12.0).rgb; }

// Roccia in proiezione triplanare: niente stiramenti sulle pareti verticali
void rock_tri(vec3 p, vec3 wn, float k, out vec3 col, out vec3 nrm) {
	vec3 w = pow(abs(wn), vec3(6.0));
	w /= w.x + w.y + w.z;
	vec3 c = vec3(0.0), o = vec3(0.0);
	float sc = 9.0, sf = 47.0;
	if (w.x > 0.01) {
		vec3 c1 = mix(texture(rock_d, p.zy / sc).rgb, texture(rock_d, p.zy / sf + 0.5).rgb, k);
		vec2 t = mix(texture(rock_n, p.zy / sc).xy, texture(rock_n, p.zy / sf + 0.5).xy, k) * 2.0 - 1.0;
		c += c1 * w.x;
		o += vec3(0.0, t.y, t.x) * w.x;
	}
	if (w.y > 0.01) {
		vec3 c1 = mix(texture(rock_d, p.xz / sc).rgb, texture(rock_d, p.xz / sf + 0.5).rgb, k);
		vec2 t = mix(texture(rock_n, p.xz / sc).xy, texture(rock_n, p.xz / sf + 0.5).xy, k) * 2.0 - 1.0;
		c += c1 * w.y;
		o += vec3(t.x, 0.0, -t.y) * w.y;
	}
	if (w.z > 0.01) {
		vec3 c1 = mix(texture(rock_d, p.xy / sc).rgb, texture(rock_d, p.xy / sf + 0.5).rgb, k);
		vec2 t = mix(texture(rock_n, p.xy / sc).xy, texture(rock_n, p.xy / sf + 0.5).xy, k) * 2.0 - 1.0;
		c += c1 * w.z;
		o += vec3(t.x, t.y, 0.0) * w.z;
	}
	col = c;
	nrm = o;
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
	float kfar = mix(0.3, 0.85, smoothstep(20.0, 400.0, tdist));
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float n1 = tfbm(tp * 0.035), n2 = tvn(tp * 0.6);
	vec3 tint = ground_tint(v_wpos, wn.y, td.g, td.b);
	// variazioni dell'erba e del suolo: chiazze secche e zone più rigogliose
	tint *= 0.82 + 0.36 * n1;
	tint = mix(tint, tint * vec3(1.12, 1.0, 0.7), ss(0.55, 0.8, tvn(tp * 0.012)) * 0.45);
	tint = mix(tint, tint * vec3(0.8, 0.95, 0.75), ss(0.5, 0.75, tfbm(tp * 0.005 + 7.0)) * 0.4);
	// chiazze naturali a varie scale (ciuffi, avvallamenti umidi, erba più secca)
	tint *= 0.8 + 0.4 * tfbm(tp * 0.11 + 3.0);
	tint = mix(tint, tint * vec3(1.15, 1.05, 0.75), ss(0.55, 0.75, tvn(tp * 0.035 + 5.0)) * 0.35);

	// erba (con la tinta procedurale di prati, boschi e campi)
	vec3 col, nb, c2, n2v;
	tex2(grass_d, grass_n, tp, 4.0, 29.0, kfar, col, nb);
	col *= clamp(tint / max(avg(grass_d), vec3(0.01)), 0.0, 3.0);
	// sabbia sulla riva e sul fondale
	float sand_w = ss(6.0, 3.2, th);
	if (sand_w > 0.0) {
		tex2(sand_d, sand_n, tp, 5.0, 33.0, kfar, c2, n2v);
		c2 *= clamp(tint / max(avg(sand_d), vec3(0.01)), 0.0, 3.0);
		col = mix(col, c2, sand_w);
		nb = mix(nb, n2v, sand_w);
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
		float inner = ss(vr, vr * 0.7, d) * clamp(0.45 + 0.4 * n1 + paths * 0.5, 0.0, 0.95);
		if (v.w > 1.5) inner = 0.75 * ss(vr * 0.9, vr * 0.3, d);
		if (inner > 0.0) {
			tex2(dirt_d, dirt_n, tp, 3.5, 23.0, kfar, c2, n2v);
			col = mix(col, c2 * 0.8, inner);
			nb = mix(nb, n2v, inner);
		}
		if (v.w > 1.5) continue;
		float dj = d + (tvn(tp * 0.12) - 0.5) * vr * 0.18;
		float plaza = ss(vr * 0.36, vr * 0.28, dj) * (0.75 + 0.25 * n1);
		if (plaza > 0.0) {
			tex2(cobble_d, cobble_n, tp, 3.0, 3.0, 0.0, c2, n2v);
			col = mix(col, c2 * 0.7, plaza * 0.95);
			nb = mix(nb, n2v * 1.5, plaza);
		}
		float ring = ss(vr * 0.8, vr * 0.95, d) * ss(vr + 210.0, vr + 140.0, d) * (1.0 - rock_mask);
		if (ring > 0.0) {
			float ang = atan(tp.y - v.y, tp.x - v.x);
			vec2 dir = vec2(cos(ang * 7.0), sin(ang * 7.0));
			col *= 1.0 - ring * 0.14 * (0.5 + 0.5 * sin(dot(tp, dir) * 1.6)) * tfade;
		}
	}
	// roccia sui pendii ripidi: foto in triplanare, ingrigita, con creste chiare e canaloni scuri
	if (rock_mask > 0.0) {
		rock_tri(v_wpos, wn, kfar, c2, n2v);
		float l = dot(c2, vec3(0.3, 0.59, 0.11));
		c2 = mix(c2, vec3(l) * vec3(1.0, 0.97, 0.92), 0.55);
		float cavity = ss(0.25, 0.75, ridged(tp / 42.0));
		c2 *= mix(0.6, 1.15, cavity) * mix(0.85, 1.12, tfbm(tp * 0.02 + th * 0.01));
		// licheni sulle parti meno ripide
		c2 = mix(c2, c2 * vec3(0.85, 1.05, 0.7), ss(0.6, 0.8, tfbm(tp * 0.05)) * (1.0 - ss(0.5, 0.8, slope)) * 0.6);
		col = mix(col, c2, rock_mask);
		nb = mix(nb, n2v * 1.4, rock_mask);
	}
	// neve solo sulle cime più alte, dove la pendenza la trattiene
	float snow_line = 255.0 + (n1 - 0.5) * 90.0;
	float snow = ss(snow_line, snow_line + 25.0, th) * (1.0 - ss(0.45, 0.68, slope));
	snow = max(snow, ss(snow_line + 60.0, snow_line + 110.0, th) * (1.0 - ss(0.66, 0.9, slope)));
	if (snow > 0.0) {
		tex2(snow_d, snow_n, tp, 6.0, 41.0, kfar, c2, n2v);
		col = mix(col, c2 * vec3(0.9, 0.93, 1.0), snow);
		nb = mix(nb, n2v, snow);
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.75, snow);
	METALLIC = 0.0;
	// il rilievo delle texture sfuma con la distanza (lontano resta solo la forma del terreno)
	float bump = mix(0.55, 0.12, smoothstep(30.0, 900.0, tdist));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn + nb * bump, 0.0)).xyz);
}
