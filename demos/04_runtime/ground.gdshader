// Prairie : herbe en nappes de couleur douces, quelques zones plus sèches, et une
// légère ondulation de lumière comme le vent qui passe sur l'herbe. Aucune texture.
shader_type spatial;
render_mode diffuse_burley, specular_disabled;

#include "res://addons/bastide/shaders/bastide_meadow.gdshaderinc"

// Style peint (donné par BastideGrass) : même prairie que l'herbe, ombres de nuages.
uniform float painted = 0.0;

uniform vec3 grass_a : source_color = vec3(0.4, 0.55, 0.26);
uniform vec3 grass_b : source_color = vec3(0.56, 0.64, 0.31);
uniform vec3 dry : source_color = vec3(0.66, 0.64, 0.4);
uniform vec3 path_color : source_color = vec3(0.7, 0.63, 0.5);
uniform float wind_speed = 0.35;
// Ancien sentier peint dans l'herbe (remplacé par les vrais chemins de l'étape 5).
uniform float painted_path = 0.0;
// Sous l'herbe haute (près du centre suivi), le sol est l'ombre entre les brins.
uniform vec3 grass_center = vec3(0.0, -1000.0, 0.0);
uniform float grass_far = 70.0;
uniform vec3 under_grass : source_color = vec3(0.3, 0.45, 0.16);
uniform vec3 far_tint : source_color = vec3(0.55, 0.62, 0.27);

// Berges et fonds d'étang (couleur des sommets du relief : r = berge, g = lit).
uniform vec3 bank_color : source_color = vec3(0.36, 0.33, 0.24);
uniform vec3 bed_color : source_color = vec3(0.34, 0.31, 0.22);
uniform vec3 pebble_color : source_color = vec3(0.62, 0.6, 0.55);

varying vec3 wp;
varying vec2 water_paint;
// COLOR.b = 1 : gazon sans touffes d'herbe dessus (buttes des terriers) : pas d'ombre
// de sous-herbe, il prend la teinte du pré vu de loin.
varying float lawn;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	water_paint = COLOR.rg;
	lawn = COLOR.b;
}

void fragment() {
	vec2 p = wp.xz;
	float big = fbm(p * 0.035);
	float mid = fbm(p * 0.18 + 3.1);
	float fine = noise(p * 3.5) * 0.5 + noise(p * 9.0) * 0.5;
	vec3 col = mix(grass_a, grass_b, smoothstep(0.35, 0.7, big));
	col = mix(col, dry, smoothstep(0.62, 0.8, fbm(p * 0.06 + 11.0)) * 0.55);
	col *= 0.9 + mid * 0.18 + (fine - 0.5) * 0.08;
	vec3 tone = meadow_tone(p);
	if (painted > 0.5) {
		col = tone * (0.92 + mid * 0.12 + (fine - 0.5) * 0.06);
	}
	// Petites fleurs des champs : quelques points blancs, jaunes et roses.
	vec2 cell = floor(p * 2.2);
	vec2 fp = fract(p * 2.2) - 0.5;
	float h = hash(cell);
	float flower = (1.0 - smoothstep(0.05, 0.11, length(fp - (vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5) * 0.6)))
			* step(0.93, h) * smoothstep(0.45, 0.6, fbm(p * 0.09 + 5.0));
	vec3 petal = h > 0.98 ? vec3(0.98, 0.78, 0.85) : (h > 0.955 ? vec3(0.98, 0.9, 0.45) : vec3(0.97, 0.96, 0.92));
	col = mix(col, petal, flower);
	// Vent sur l'herbe : de longues vagues de lumière qui traversent la prairie.
	float wave = sin(dot(p, vec2(0.08, 0.05)) - TIME * wind_speed * 2.0 + fbm(p * 0.05) * 4.0);
	if (painted > 0.5) {
		// Au loin, le sol peint joue l'herbe : il porte les mêmes vagues claires.
		float mw = meadow_wave(p, TIME);
		col = mix(col, col * 1.25 + vec3(0.03, 0.04, 0.0), mw * 0.45);
		if (grass_center.y > -999.0) {
			float gd = length(wp.xz - grass_center.xz);
			// Sous l'herbe peinte, le sol fait l'ombre entre les touffes.
			col = mix(tone * vec3(0.44, 0.54, 0.52) * (0.9 + mid * 0.2), col, max(smoothstep(grass_far * 0.55, grass_far, gd), lawn));
		}
	} else {
		col *= 1.0 + wave * 0.035;
		// Au loin, la prairie prend la teinte moyenne de l'herbe dorée ; sous les brins, elle s'assombrit.
		col = mix(col, far_tint * (0.85 + big * 0.3), 0.45);
		if (grass_center.y > -999.0) {
			float gd = length(wp.xz - grass_center.xz);
			col = mix(under_grass * (0.85 + mid * 0.3), col, max(smoothstep(grass_far * 0.55, grass_far, gd), lawn));
		}
	}
	// Sentier de terre qui serpente vers le hameau.
	float path_x = sin(wp.z * 0.045) * 7.0 + 3.0;
	float d = abs(wp.x - path_x);
	float on_path = (1.0 - smoothstep(0.9, 1.6 + mid * 0.6, d)) * smoothstep(14.0, 24.0, wp.z) * painted_path;
	col = mix(col, path_color * (0.92 + fine * 0.12), on_path);
	// Étangs : la berge mouillée et le lit (vase, petits galets) remplacent l'herbe.
	float bank = smoothstep(0.05, 0.9, water_paint.r) * (0.75 + mid * 0.4);
	float bed = smoothstep(0.05, 0.8, water_paint.g);
	vec2 pc = floor(p * 6.0);
	vec2 pf = fract(p * 6.0) - 0.5;
	float pebble = (1.0 - smoothstep(0.18, 0.34, length(pf - (vec2(hash(pc + 1.7), hash(pc + 9.2)) - 0.5) * 0.4)))
			* step(0.45, hash(pc));
	vec3 earth = mix(bank_color, bank_color * 0.75, fine);
	earth = mix(earth, pebble_color * (0.85 + hash(pc + 4.0) * 0.3), pebble * 0.55);
	col = mix(col, earth, clamp(bank, 0.0, 1.0) * (1.0 - bed));
	vec3 mud = mix(bed_color, bed_color * 1.25, mid);
	mud = mix(mud, pebble_color * 0.8, pebble * 0.6);
	col = mix(col, mud, bed);
	if (painted > 0.5) {
		col *= meadow_clouds(p, TIME);
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.6, max(bank * 0.6, bed));
}
