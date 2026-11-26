// Oiseaux et papillons (MultiMesh) : les ailes battent dans le shader.
// Le maillage est symétrique autour de l'axe du corps (z) ; plus un sommet est loin
// du corps (|x|), plus il monte et descend. INSTANCE_CUSTOM : x = phase, y = vitesse
// de battement, z = amplitude (radians), w = plané (0..1, ailes immobiles).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

uniform float backlight = 0.35;

void vertex() {
	float side = sign(VERTEX.x);
	float span = abs(VERTEX.x);
	float beat = sin(TIME * INSTANCE_CUSTOM.y + INSTANCE_CUSTOM.x * 6.2831);
	// En plané, les ailes restent un peu relevées.
	float a = mix(beat * INSTANCE_CUSTOM.z, 0.12, INSTANCE_CUSTOM.w);
	VERTEX.x = side * span * cos(a);
	VERTEX.y += span * sin(a);
	NORMAL = normalize(vec3(-side * sin(a), cos(a), 0.0));
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(backlight) * COLOR.rgb;
}
