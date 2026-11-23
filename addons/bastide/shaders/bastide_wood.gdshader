// Bois procédural : la couleur vient des couleurs de sommets (générées par l'addon),
// ce shader ajoute un fil du bois (bruit étiré) et de légères taches. Aucune texture.
// Le fil suit la verticale sur les faces verticales et l'axe X/Z dominant ailleurs :
// approximation suffisante pour des poteaux, des poutres et des planches.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float grain_scale = 9.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.22;
uniform float stretch = 14.0;
uniform float blotch_strength : hint_range(0.0, 1.0) = 0.1;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.75;

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = COLOR.rgb;
	vec3 base = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	// Fil vertical sur les faces verticales, horizontal sur le dessus et le dessous.
	vec3 s = abs(world_nrm.y) > 0.6 ? vec3(1.0, 1.0, 1.0 / stretch) : vec3(1.0, 1.0 / stretch, 1.0);
	vec3 p = world_pos * grain_scale * s;
	float grain = vnoise(p) * 0.65 + vnoise(p * 2.7) * 0.35;
	float rings = sin(grain * 18.0) * 0.5 + 0.5;
	float blotch = vnoise(world_pos * 1.1 + vec3(7.3));
	vec3 col = base * (1.0 + (rings - 0.5) * grain_strength);
	col *= 1.0 + (blotch - 0.5) * blotch_strength * 2.0;
	ALBEDO = col;
	ROUGHNESS = roughness_value + (rings - 0.5) * 0.1;
	SPECULAR = 0.35;
}
