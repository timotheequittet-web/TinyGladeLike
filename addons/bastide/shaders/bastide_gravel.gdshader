// Sols du décor : gravier ratissé des chemins, galets au pied des maisons.
// Couleur de base = couleur des sommets. Le grain (petits cailloux) est calculé en
// coordonnées monde : deux chemins qui se croisent se fondent sans couture.
// L'alpha des sommets donne la position en travers du chemin (0 d'un bord à 1 de
// l'autre) : les sillons du râteau suivent ainsi le chemin. Alpha 0 partout (galets
// au pied des maisons) : pas de sillons. Aucune texture.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform float pebble_scale = 9.0;
uniform float rake_lines = 7.0;
uniform float rake_strength : hint_range(0.0, 1.0) = 0.16;

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Cailloux : distance au centre de la cellule la plus proche (Voronoï simple).
float pebbles(vec2 p, out float id) {
	vec2 i = floor(p), f = fract(p);
	float best = 8.0;
	id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 17.3));
			float d = length(g + o - f);
			if (d < best) { best = d; id = hash(i + g + 5.1); }
		}
	}
	return best;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = clamp(COLOR.rgb, vec3(0.0), vec3(1.0));   // jamais négatif : pow() donnerait NaN
	vec3 base = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	vec2 p = world_pos.xz;
	float id;
	float d = pebbles(p * pebble_scale, id);
	float stone = 1.0 - smoothstep(0.25, 0.55, d);
	vec3 col = base * (0.86 + id * 0.26) * (0.82 + stone * 0.22);
	col *= 0.94 + noise(p * 0.7) * 0.12;
	// Sillons du râteau, parallèles au chemin.
	float rake = sin(COLOR.a * rake_lines * 3.14159);
	col *= 1.0 + rake * rake_strength;
	ALBEDO = col;
	ROUGHNESS = 0.96;
}
