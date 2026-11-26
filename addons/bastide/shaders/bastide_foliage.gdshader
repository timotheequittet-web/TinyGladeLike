// Feuillage du décor (buissons, fougères, herbes, arbres) : la couleur vient des
// sommets, le vent fait respirer les plantes. L'alpha des sommets règle la souplesse
// (1 = feuilles et brins, 0 = tronc rigide). Aucune texture.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform float sway = 0.11;
uniform float speed = 0.9;
uniform float flutter = 0.025;

varying float shade;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float soft = 0.35 + 0.65 * COLOR.a;
	float t = TIME * speed + wp.x * 0.15 + wp.z * 0.11;
	VERTEX.x += sin(t) * sway * h * 0.2 * soft;
	VERTEX.z += cos(t * 0.8) * sway * h * 0.15 * soft;
	// Petit frémissement des feuilles.
	float f = sin(TIME * 3.1 + wp.x * 2.3 + wp.z * 1.7) * flutter * COLOR.a;
	VERTEX.y += f;
	shade = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
}

void fragment() {
	vec3 c = clamp(COLOR.rgb, vec3(0.0), vec3(1.0));   // jamais négatif : pow() donnerait NaN
	vec3 base = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	ALBEDO = base * (0.8 + shade * 0.28);
	ROUGHNESS = 0.88;
	SPECULAR = 0.3;
	BACKLIGHT = base * 0.4;
}
