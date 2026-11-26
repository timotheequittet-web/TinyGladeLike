// Terre des cultures (planches, boue des rizières, levées, haies de thé) : la couleur
// vient des sommets, un grain de mottes et de taches en coordonnées monde lui donne de
// la matière. Le même shader, réglé autrement, donne le feuillage serré des théiers.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform float grain_scale = 9.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.3;
uniform float clod_scale = 2.0;
uniform float clod_strength : hint_range(0.0, 1.0) = 0.18;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;
uniform float specular_value : hint_range(0.0, 1.0) = 0.2;
// Petites taches claires (paille sur la terre, jeunes pousses sur les théiers).
uniform vec4 fleck_color : source_color = vec4(0.62, 0.55, 0.38, 1.0);
uniform float fleck_amount : hint_range(0.0, 1.0) = 0.0;
uniform float fleck_scale = 14.0;
// Feuillage serré (haies de thé) : petites grappes de feuilles en relief peint.
uniform float leafy : hint_range(0.0, 1.0) = 0.0;
uniform float leaf_scale = 9.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

// Distance à la grappe la plus proche, et un tirage propre à cette grappe.
vec2 worley(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = hash3(i + g);
				vec3 r = g + o - f;
				float d = dot(r, r);
				if (d < d1) {
					d1 = d;
					id = o.x;
				}
			}
		}
	}
	return vec2(sqrt(d1), id);
}

void fragment() {
	vec3 c = clamp(COLOR.rgb, vec3(0.0), vec3(1.0));
	vec3 base = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	// Sur les faces verticales (talus, flancs des haies), on lit le grain de côté.
	vec2 p = mix(vec2(wpos.x + wpos.z, wpos.y * 1.6), wpos.xz, smoothstep(0.3, 0.7, abs(wnrm.y)));
	float g = noise(p * grain_scale) * 0.6 + noise(p * grain_scale * 2.7 + 7.3) * 0.4;
	float cl = noise(p * clod_scale + 3.1);
	float k = 1.0 + (g - 0.5) * grain_strength * 2.0 + (cl - 0.5) * clod_strength * 2.0;
	vec3 col = base * k;
	if (fleck_amount > 0.0) {
		float f = noise(p * fleck_scale + 11.0);
		vec3 fl = fleck_color.rgb;
		col = mix(col, fl * (0.8 + g * 0.4), smoothstep(1.0 - fleck_amount, 1.0 - fleck_amount * 0.5, f) * 0.85);
	}
	if (leafy > 0.0) {
		vec2 w = worley(wpos * leaf_scale);
		vec2 w2 = worley(wpos * leaf_scale * 2.3 + 5.0);
		float rim = smoothstep(0.2, 0.8, w.x);
		float rim2 = smoothstep(0.25, 0.85, w2.x);
		float k2 = (1.12 - rim * 0.5) * (1.05 - rim2 * 0.2) * (0.88 + w.y * 0.24);
		col = mix(col, base * k2, leafy);
		// Jeunes pousses claires sur le dessus.
		float young = step(0.8, w2.y) * smoothstep(0.3, 0.8, wnrm.y) * (1.0 - rim2);
		col = mix(col, fleck_color.rgb * (0.85 + w.y * 0.3), young * leafy * 0.8);
	}
	ALBEDO = col;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
}
