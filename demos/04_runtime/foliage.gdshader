// Feuillage stylisé qui respire dans le vent. La couleur vient des sommets.
shader_type spatial;
render_mode diffuse_burley, cull_back;

uniform float sway = 0.12;
uniform float speed = 0.9;

varying float shade;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float t = TIME * speed + wp.x * 0.15 + wp.z * 0.11;
	VERTEX.x += sin(t) * sway * h * 0.25;
	VERTEX.z += cos(t * 0.8) * sway * h * 0.18;
	shade = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
}

void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = c * (0.78 + shade * 0.3);
	ROUGHNESS = 0.9;
	BACKLIGHT = c * 0.35;
}
