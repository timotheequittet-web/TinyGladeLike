shader_type spatial;
// Herbe rase des buttes des maisons-terriers. Mêmes taches de prairie que le sol
// peint (bastide_meadow.gdshaderinc, lues en coordonnées monde) : la butte sort de
// la prairie sans couture. Repli quand aucun relief ne fournit son matériau de sol
// (voir BastideTerrain.shared_material).

#include "res://addons/bastide/shaders/bastide_meadow.gdshaderinc"

uniform vec3 soil_color : source_color = vec3(0.36, 0.27, 0.18);
uniform float flowers = 1.0;

varying vec3 wp;

float t_hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743); }

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	vec3 col = meadow_tone(p);
	// Petites touches de pinceau : herbe rase, un peu tachetée.
	float fine = m_noise(p * 3.3) * 0.55 + m_noise(p * 11.0 + 1.7) * 0.45;
	col *= 0.84 + fine * 0.26;
	// Le haut de la butte prend plus de soleil, les flancs restent plus profonds.
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	col = mix(col * 0.88, col * 1.06 + vec3(0.02, 0.025, 0.0), smoothstep(0.55, 0.95, wn.y));
	// Fleurs des prés semées sur la butte.
	vec2 cell = floor(p * 2.6);
	vec2 fp = fract(p * 2.6) - 0.5;
	float h = t_hash(cell);
	float flower = (1.0 - smoothstep(0.05, 0.12, length(fp - (vec2(t_hash(cell + 3.1), t_hash(cell + 7.7)) - 0.5) * 0.6)))
			* step(0.9, h) * smoothstep(0.35, 0.55, m_noise(p * 0.3 + 5.0)) * flowers;
	vec3 petal = h > 0.975 ? vec3(0.98, 0.78, 0.85) : (h > 0.945 ? vec3(0.98, 0.88, 0.42) : vec3(0.97, 0.96, 0.92));
	col = mix(col, petal, flower);
	// Terre nue (dessous de l'avancée d'herbe, racines).
	col *= meadow_clouds(p, TIME);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
