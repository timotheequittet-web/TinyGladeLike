// Pierre procédurale : la couleur de chaque pierre vient des couleurs de sommets
// (générées par l'addon), ce shader ajoute du grain, des taches et un peu de mousse
// sur les surfaces tournées vers le ciel. Aucune texture requise.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float grain_scale = 7.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.22;
uniform float blotch_scale = 1.3;
uniform float blotch_strength : hint_range(0.0, 1.0) = 0.12;
uniform vec4 moss_color : source_color = vec4(0.36, 0.45, 0.22, 1.0);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
// Soubassement sur la pente (sommets marqués alpha 0 par BastideDrape) : pierres
// sèches appareillées, façon ishigaki.
uniform float socle_stone_size = 0.5;
// Enduit (couleurs claires) : nuages de chaux, traces de taloche, coulures fines
// sous les poutres et pied un peu sali. 0 = pierre seule.
uniform float plaster_amount : hint_range(0.0, 1.0) = 0.0;
uniform float plaster_threshold : hint_range(0.0, 1.0) = 0.62;

varying vec3 world_pos;
varying vec3 world_nrm;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
				   mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
				   mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Voronoï 2D : x = distance au centre le plus proche, y = écart au second (joint),
// z = identifiant de la pierre.
vec3 voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash3(vec3(i + g, 1.3)), hash3(vec3(i + g, 7.9))) * 0.8 + 0.1;
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = hash3(vec3(i + g, 4.4));
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d1, d2 - d1, id);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz + vec3(0.0, 1e-5, 0.0));
}

void fragment() {
	// Les couleurs de sommets sont données en sRGB : conversion en linéaire.
	vec3 c = clamp(COLOR.rgb, vec3(0.0), vec3(1.0));   // jamais négatif : pow() donnerait NaN
	vec3 base = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	float grain = fbm(world_pos * grain_scale);
	float blotch = fbm(world_pos * blotch_scale + vec3(13.1));
	vec3 col = base * (1.0 + (grain - 0.5) * grain_strength * 2.0);
	col *= 1.0 + (blotch - 0.5) * blotch_strength * 2.0;
	// Mousse : sur les faces orientées vers le haut, par plaques.
	float up = smoothstep(0.55, 0.95, world_nrm.y);
	float patches = smoothstep(0.45, 0.7, fbm(world_pos * 0.9 + vec3(4.2)));
	col = mix(col, moss_color.rgb * (0.8 + grain * 0.4), up * patches * moss_amount);
	// Soubassement : pierres appareillées, joints sombres, teinte par pierre.
	float socle = (1.0 - step(0.985, COLOR.a)) * (1.0 - smoothstep(0.5, 0.8, abs(world_nrm.y)));
	if (socle > 0.0) {
		vec3 t = normalize(vec3(-world_nrm.z, 0.0, world_nrm.x) + vec3(1e-4, 0.0, 0.0));
		vec2 q = vec2(dot(world_pos, t) / (socle_stone_size * 1.35), world_pos.y / socle_stone_size);
		vec3 vo = voronoi(q);
		float joint = 1.0 - smoothstep(0.025, 0.09, vo.y);
		float bump = smoothstep(0.0, 0.5, vo.x);
		vec3 stone = base * (0.78 + vo.z * 0.38) * (1.0 + (grain - 0.5) * 0.3);
		stone = mix(stone, stone * vec3(1.05, 1.0, 0.9), step(0.7, vo.z));
		stone *= 1.0 - bump * 0.18;
		stone = mix(stone, base * 0.3, joint * 0.75);
		col = mix(col, stone, socle);
		float sm = smoothstep(0.5, 0.75, fbm(world_pos * 0.9 + vec3(2.7)));
		col = mix(col, moss_color.rgb * 0.8, sm * socle * moss_amount * 0.6 * (1.0 - joint));
	}
	// Enduit : repéré à sa clarté (les pierres et le bois sont plus sombres).
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	float pl = smoothstep(plaster_threshold, plaster_threshold + 0.1, lum) * plaster_amount
			* (1.0 - smoothstep(0.6, 0.9, abs(world_nrm.y)));
	if (pl > 0.0) {
		// Nuages de chaux chauds et froids.
		float cloud = fbm(world_pos * 0.45 + vec3(3.3));
		vec3 tint = mix(vec3(1.05, 1.0, 0.9), vec3(0.93, 0.96, 1.0), smoothstep(0.3, 0.7, cloud));
		// Traces de taloche : arcs larges, à peine visibles.
		float trowel = vnoise(vec3(world_pos.x * 2.2 + world_pos.z * 2.2, world_pos.y * 5.0, 0.7) + vec3(cloud * 2.0));
		// Coulures fines, verticales.
		vec3 sp = vec3(world_pos.x * 7.0 + world_pos.z * 7.0, world_pos.y * 0.5, 4.1);
		float drip = smoothstep(0.55, 0.85, fbm(sp)) * (0.6 + 0.4 * vnoise(world_pos * 0.7));
		vec3 pcol = base * tint * (0.97 + (trowel - 0.5) * 0.12);
		pcol *= 1.0 - drip * 0.22;
		pcol *= 0.97 + (grain - 0.5) * 0.05;
		col = mix(col, pcol, pl);
	}
	ALBEDO = col;
	ROUGHNESS = roughness_value - grain * 0.1;
	SPECULAR = 0.3;
}
