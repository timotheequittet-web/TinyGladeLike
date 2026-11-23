// Surbrillance douce posée par-dessus une structure (survol, sélection) :
// un liseré lumineux sur les contours, comme une lueur de fin de journée.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.82, 0.55, 1.0);
uniform float strength : hint_range(0.0, 2.0) = 0.35;
uniform float power = 4.0;

void fragment() {
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), power);
	float pulse = 0.8 + 0.2 * sin(TIME * 2.2);
	ALBEDO = color.rgb * rim * strength * pulse;
}
