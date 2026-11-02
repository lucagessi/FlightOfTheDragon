// Cielo: gradiente dallo zenit all'orizzonte, disco e alone del sole e cumuli procedurali con volume: uno strato
// spesso attraversato a passi (base piatta e grigia, cime gonfie e illuminate dal lato del sole, bordo argentato
// controluce) che sfuma verso l'orizzonte, con meno passi per la mappa della luce ambiente. Niente TIME: quella
// mappa si calcola una volta.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.17, 0.39, 0.8);
uniform vec3 horizon_color : source_color = vec3(0.7, 0.78, 0.88);
// sotto l'orizzonte: la luce che il terreno al sole rimanda sui muri (nella mappa della luce ambiente)
uniform vec3 ground_color : source_color = vec3(0.42, 0.42, 0.33);
uniform float coverage = 0.6; // quota di cielo coperta dai cumuli
uniform vec2 cloud_offset = vec2(0.0);

// hash intero (quello col seno perde precisione lontano dall'origine e disegna schegge dritte)
float hash(vec2 p) {
	uvec2 v = uvec2(ivec2(p)) * uvec2(1597334673u, 3812015801u);
	uint n = (v.x ^ v.y) * 1597334673u;
	return float(n >> 8u) / 16777216.0;
}
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
// cumuli: forma ampia deformata e sbuffi sempre più piccoli che la gonfiano; px è la dimensione di un pixel
// sullo strato: gli sbuffi più fini dei pixel (verso l'orizzonte) si spengono invece di sfarfallare
float clouds(vec2 p, float px) {
	vec2 q = p + vec2(vnoise(p * 0.3 + 3.1), vnoise(p * 0.3 + 8.7)) * 0.6;
	float base = vnoise(q * 0.45) * 0.55 + vnoise(q * 0.9 + 4.3) * 0.3 + vnoise(q * 1.9 + 1.7) * 0.15;
	// sbuffi tondeggianti (rumore "billow")
	float puff = 0.0, a = 0.5, f = 2.3;
	for (int i = 0; i < 5; i++) {
		float k = 1.0 - smoothstep(0.12, 0.45, px * f);
		puff += mix(0.5, abs(vnoise(q * f) * 2.0 - 1.0), k) * a;
		a *= 0.5;
		f *= 2.07;
	}
	return base * 0.85 + puff * 0.3;
}


// Cumuli lungo la direzione d: rgb già moltiplicato per la copertura, a = copertura
vec4 cloud_layer(vec3 d, vec3 sun_dir, vec3 sun_col, float sun_e, int steps) {
	float y = d.y;
	vec2 proj = d.xz / (y + 0.3) * 1.8;
	float px = length(fwidth(proj));
	vec2 sd = normalize(sun_dir.xz + 1e-4) * 0.25;
	float cs = dot(d, sun_dir);
	vec3 shade = mix(vec3(0.5, 0.55, 0.64), horizon_color * 0.9, 0.3);
	vec3 bright = vec3(1.0, 0.97, 0.93) * (0.75 + 0.35 * sun_col.r / max(sun_e, 0.01));
	vec3 acc = vec3(0.0);
	float tr = 1.0;
	for (int i = 0; i < steps; i++) {
		// quota nello strato (0 base, 1 cima): più in alto il raggio è più lontano e serve più densità
		float h = (float(i) + 0.5) / float(steps);
		vec2 p = proj * (1.0 + h * 0.45) + cloud_offset;
		float dn = clouds(p, px);
		float th = 1.0 - coverage + h * 0.2;
		float s = smoothstep(th, th + 0.07 + px * 2.0, dn);
		if (s > 0.002) {
			// luce: quanto la nuvola si assottiglia verso il sole, le parti alte più chiare della base
			float toward = clouds(p + sd, px);
			float lit = clamp(0.5 + (dn - toward) * 3.0, 0.0, 1.0) * mix(0.55, 1.08, h);
			// dove la nuvola è spessa la base resta in ombra
			lit *= 1.0 - 0.5 * smoothstep(0.0, 0.25, dn - th) * (1.0 - h);
			vec3 c = mix(shade, bright, clamp(lit, 0.0, 1.0));
			c += sun_col * pow(max(cs, 0.0), 6.0) * (1.0 - s) * 0.5;
			float a = s * (steps > 3 ? 0.55 : 0.75);
			acc += tr * a * c;
			tr *= 1.0 - a;
			if (tr < 0.02) break;
		}
	}
	return vec4(acc, 1.0 - tr);
}


void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 sun_dir = LIGHT0_DIRECTION;
	vec3 sun_col = LIGHT0_COLOR * LIGHT0_ENERGY;
	vec3 col;
	if (y >= 0.0) {
		col = mix(horizon_color, top_color, pow(y, 0.45));
		// foschia chiara appena sopra l'orizzonte
		col = mix(col, horizon_color * 1.08, exp(-y * 18.0) * 0.5);
	} else {
		col = mix(horizon_color, ground_color, 1.0 - exp(y * 6.0));
	}
	float cs = dot(d, sun_dir);
	// alone del sole (in foschia più ampio) e disco
	col += sun_col * (pow(max(cs, 0.0), 24.0) * 0.07 + pow(max(cs, 0.0), 400.0) * 0.5);
	col += sun_col * smoothstep(0.99985, 0.99995, cs) * 8.0;
	if (y > 0.012) {
		vec4 cl = cloud_layer(d, sun_dir, sun_col, LIGHT0_ENERGY, AT_CUBEMAP_PASS ? 3 : 5);
		// i cumuli lontani si perdono nella foschia dell'orizzonte
		float far = smoothstep(0.0, 0.22, y);
		float c = cl.a * smoothstep(0.015, 0.09, y);
		vec3 cc = cl.rgb / max(cl.a, 1e-4);
		col = mix(col, mix(horizon_color * 1.05, cc, far), c);
	}
	COLOR = col;
}
