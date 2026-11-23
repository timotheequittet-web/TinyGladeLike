// Poignée de retouche : un anneau doux toujours face à la caméra, visible même
// derrière un mur. Aucune texture.
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform vec4 fill_color : source_color = vec4(1.0, 0.98, 0.94, 0.35);
uniform float hover : hint_range(0.0, 1.0) = 0.0;
uniform float pixel_size = 30.0;

void vertex() {
	// Taille constante à l'écran : on compense la distance.
	vec4 view_center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float d = -view_center.z;
	float s = pixel_size * (1.0 + 0.35 * hover) * d / VIEWPORT_SIZE.y * 2.0 / PROJECTION_MATRIX[1][1];
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= s;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float aa = fwidth(r) * 1.5;
	float ring = smoothstep(0.62 - aa, 0.62, r) * (1.0 - smoothstep(0.86 - aa, 0.86, r));
	float inner = 1.0 - smoothstep(0.62 - aa, 0.62, r);
	float shadow = (1.0 - smoothstep(0.86, 1.0, r)) * 0.25;
	vec4 c = vec4(0.0, 0.0, 0.0, shadow);
	c = mix(c, vec4(fill_color.rgb, fill_color.a + hover * 0.4), inner);
	c = mix(c, color, ring);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
