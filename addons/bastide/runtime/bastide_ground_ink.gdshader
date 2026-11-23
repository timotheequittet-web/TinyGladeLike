// Trait lumineux posé au sol (tracé en cours, contour d'une maison, curseur).
// UV.x : position le long du trait (en mètres), UV.y : 0 → 1 en travers.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.97, 0.88, 0.85);

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float soft = 1.0 - smoothstep(0.35, 1.0, across);
	float dash = 0.75 + 0.25 * sin(UV.x * 6.0 - TIME * 3.0);
	ALBEDO = color.rgb;
	ALPHA = color.a * soft * dash * COLOR.a;
}
