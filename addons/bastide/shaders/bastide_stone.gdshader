// Pierre procédurale : la couleur de chaque pierre vient des couleurs de sommets
// (générées par l'addon), ce shader ajoute du grain, des taches et un peu de mousse
// sur les surfaces tournées vers le ciel. Aucune texture requise.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float grain_scale = 7.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.22;
uniform float blotch_scale = 1.3;
uniform float blotch_strength : hint_range(0.0, 1.0) = 0.12;
uniform vec4 moss_color : source_color = vec4(0.36, 0.45, 0.22, 1.0);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;

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

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Les couleurs de sommets sont données en sRGB : conversion en linéaire.
	vec3 c = COLOR.rgb;
	vec3 base = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	float grain = fbm(world_pos * grain_scale);
	float blotch = fbm(world_pos * blotch_scale + vec3(13.1));
	vec3 col = base * (1.0 + (grain - 0.5) * grain_strength * 2.0);
	col *= 1.0 + (blotch - 0.5) * blotch_strength * 2.0;
	// Mousse : sur les faces orientées vers le haut, par plaques.
	float up = smoothstep(0.55, 0.95, world_nrm.y);
	float patches = smoothstep(0.45, 0.7, fbm(world_pos * 0.9 + vec3(4.2)));
	col = mix(col, moss_color.rgb * (0.8 + grain * 0.4), up * patches * moss_amount);
	ALBEDO = col;
	ROUGHNESS = roughness_value - grain * 0.1;
	SPECULAR = 0.3;
}
