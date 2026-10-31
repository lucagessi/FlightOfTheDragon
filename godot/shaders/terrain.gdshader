// Terreno: altezze dalla griglia esportata, colori e dettagli calcolati per pixel
// (porting di colorTerrain e makeTerrainMaterial di src/world.js)
shader_type spatial;
render_mode cull_back;

uniform sampler2D terrain_data : filter_linear, repeat_disable; // R altezza, G rumore fine, B foresta
uniform vec4 villages[12]; // x, z, raggio, tipo (1 villaggio, 2 castello)
uniform float u_time;

const float HALF = 3800.0;
const float STEP = 7600.0 / 480.0;
const float NN = 481.0;

varying vec3 v_wpos;
varying vec3 v_wnrm;

vec2 grid_uv(vec2 p) { return ((p + HALF) / STEP + 0.5) / NN; }
float hgt(vec2 uv) { return textureLod(terrain_data, uv, 0.0).r; }

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
// ciottoli: distanza dal centro della cella di Voronoi più vicina
float cobble(vec2 p) {
	vec2 i = floor(p), f = fract(p); float d = 1.0;
	for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y));
		vec2 o = vec2(th2(i + g), th2(i + g + 17.3)) * 0.8 + 0.1;
		d = min(d, length(g + o - f));
	}
	return d;
}

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec2 uv = grid_uv(p);
	float e = 1.0 / NN;
	VERTEX.y = hgt(uv);
	float hl = hgt(uv - vec2(e, 0.0)), hr = hgt(uv + vec2(e, 0.0));
	float hd = hgt(uv - vec2(0.0, e)), hu = hgt(uv + vec2(0.0, e));
	NORMAL = normalize(vec3(hl - hr, 2.0 * STEP, hd - hu));
	v_wpos = vec3(p.x, VERTEX.y, p.y);
	v_wnrm = NORMAL;
}

// Colore di base (era calcolato per vertice in colorTerrain)
vec3 base_color(vec3 wp, float ny, float n1, float forest_n) {
	vec3 sand = lin(vec3(0.78, 0.71, 0.52)), wet_sand = lin(vec3(0.55, 0.5, 0.38)), seabed = lin(vec3(0.3, 0.33, 0.28));
	vec3 g1 = lin(vec3(0.24, 0.39, 0.13)), g2 = lin(vec3(0.44, 0.52, 0.2)), forest = lin(vec3(0.16, 0.28, 0.1));
	vec3 rock = lin(vec3(0.46, 0.43, 0.39)), rock2 = lin(vec3(0.36, 0.33, 0.3)), snow = lin(vec3(0.94, 0.95, 0.98));
	vec3 dirt = lin(vec3(0.5, 0.41, 0.28));
	vec3 fields[5] = { lin(vec3(0.78, 0.65, 0.3)), lin(vec3(0.36, 0.52, 0.17)), lin(vec3(0.45, 0.34, 0.21)), lin(vec3(0.55, 0.6, 0.24)), lin(vec3(0.7, 0.58, 0.25)) };
	float y = wp.y;
	vec3 c;
	if (y < 3.2) {
		c = mix(sand, wet_sand, ss(1.5, -1.5, y));
		c = mix(c, seabed, ss(-3.0, -25.0, y));
	} else {
		c = mix(g1, g2, n1);
		c = mix(c, forest, ss(0.0, 0.35, forest_n) * 0.8);
		c = mix(c, sand, ss(6.0, 3.2, y));
		// campi coltivati e terra battuta intorno ai villaggi
		for (int i = 0; i < 12; i++) {
			vec4 v = villages[i];
			if (v.w < 0.5) continue;
			float d = length(wp.xz - v.xy);
			if (d > v.z + 200.0) continue;
			if (v.w < 1.5 && d > v.z * 0.85 && y < 90.0 && ny > 0.93) {
				float ang = atan(wp.z - v.y, wp.x - v.x) + 0.3;
				float ux = cos(ang) * d, uz = sin(ang) * d;
				int cell = (int(floor(ux / 40.0)) * 73856093) ^ (int(floor(uz / 28.0)) * 19349663);
				c = mix(c, fields[abs(cell) % 5], 0.85 * ss(v.z + 200.0, v.z + 140.0, d));
			}
			c = mix(c, dirt, 0.75 * ss(v.z * 0.9, v.z * 0.3, d));
		}
		c = mix(c, rock, ss(110.0, 175.0, y + n1 * 30.0));
		c = mix(c, rock2, ss(0.86, 0.66, ny));
		c = mix(c, snow, ss(260.0, 310.0, y + n1 * 40.0) * ss(0.55, 0.8, ny));
	}
	return c * (0.88 + n1 * 0.24);
}

void fragment() {
	vec3 wn = normalize(v_wnrm);
	vec4 td = texture(terrain_data, grid_uv(v_wpos.xz));
	vec2 tp = v_wpos.xz;
	float th = v_wpos.y;
	float tdist = length(v_wpos - CAMERA_POSITION_WORLD);
	float tfade = 1.0 / (1.0 + tdist * 0.004);
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float n1 = tfbm(tp * 0.035), n2 = tvn(tp * 0.6), n3 = tvn(tp * 2.7);
	vec3 tcol = base_color(v_wpos, wn.y, td.g, td.b);
	// variazioni dell'erba e del suolo
	tcol *= (0.82 + 0.36 * n1) * (0.9 + 0.2 * mix(0.5, n2, tfade));
	tcol = mix(tcol, tcol * vec3(1.08, 1.0, 0.82), ss(0.55, 0.8, tvn(tp * 0.012)) * 0.5);
	// roccia stratificata sui pendii ripidi
	float rock_mask = ss(0.32, 0.5, slope + (n1 - 0.5) * 0.2) * step(2.0, th);
	float strata = 0.5 + 0.5 * sin(th * 0.32 + n1 * 9.0 + tvn(tp * 0.025) * 7.0);
	strata = mix(0.5, strata, 0.45 * tvn(tp * 0.01 + 3.0) + 0.2);
	vec3 rock = mix(vec3(0.085, 0.078, 0.066), vec3(0.17, 0.158, 0.138), strata) * (0.75 + 0.5 * mix(0.5, n3, tfade)) * (0.85 + 0.3 * n1);
	tcol = mix(tcol, rock, rock_mask);
	// neve solo sulle cime più alte, dove la pendenza la trattiene
	float snow_line = 255.0 + (n1 - 0.5) * 90.0;
	float snow = ss(snow_line, snow_line + 25.0, th) * (1.0 - ss(0.45, 0.68, slope));
	snow = max(snow, ss(snow_line + 60.0, snow_line + 110.0, th) * (1.0 - ss(0.66, 0.9, slope)));
	tcol = mix(tcol, vec3(0.78, 0.82, 0.9) * (0.9 + 0.12 * mix(0.5, n3, tfade)), snow);
	// sabbia increspata vicino alla riva
	float beach = ss(4.5, 1.5, th) * (1.0 - rock_mask);
	tcol *= 1.0 - beach * 0.1 * (0.5 + 0.5 * sin(dot(tp, vec2(0.7, 0.45)) * 2.5 + n2 * 5.0)) * tfade;
	// paesi: terra battuta, piazza acciottolata, solchi nei campi
	for (int i = 0; i < 12; i++) {
		vec4 v = villages[i];
		if (v.w < 0.5 || v.w > 1.5) continue;
		float vr = v.z + 10.0;
		float d = length(tp - v.xy);
		if (d > vr + 210.0) continue;
		float inner = ss(vr, vr * 0.7, d);
		vec3 dirt = vec3(0.13, 0.085, 0.05) * (0.75 + 0.5 * n2) * (0.85 + 0.3 * n3);
		float paths = ss(0.62, 0.7, tvn(tp * 0.05 + v.xy));
		tcol = mix(tcol, dirt, inner * clamp(0.45 + 0.4 * n1 + paths * 0.5, 0.0, 0.95));
		float dj = d + (tvn(tp * 0.12) - 0.5) * vr * 0.18;
		float plaza = ss(vr * 0.36, vr * 0.28, dj) * (0.75 + 0.25 * n1);
		if (plaza > 0.0) {
			float cb = cobble(tp * 0.8);
			vec3 stone = vec3(0.2, 0.185, 0.165) * (0.7 + 0.6 * th2(floor(tp * 0.8))) * mix(0.35, 1.0, ss(0.05, 0.3, cb));
			tcol = mix(tcol, stone, plaza * 0.9 * tfade + plaza * 0.5 * (1.0 - tfade));
		}
		float ring = ss(vr * 0.8, vr * 0.95, d) * ss(vr + 210.0, vr + 140.0, d) * (1.0 - rock_mask);
		if (ring > 0.0) {
			float ang = atan(tp.y - v.y, tp.x - v.x);
			vec2 dir = vec2(cos(ang * 7.0), sin(ang * 7.0));
			tcol *= 1.0 - ring * 0.14 * (0.5 + 0.5 * sin(dot(tp, dir) * 1.6)) * tfade;
		}
	}
	ALBEDO = tcol;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
	// rilievo fine: più marcato sulla roccia
	vec2 q = tp * 0.45;
	float e = 0.3;
	float b0 = tfbm(q), bx = tfbm(q + vec2(e, 0.0)), bz = tfbm(q + vec2(0.0, e));
	vec3 bw = vec3(-(bx - b0), 0.0, -(bz - b0)) / e * (0.25 + rock_mask * 1.3 + snow * 0.15) * tfade;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bw, 0.0)).xyz);
}
