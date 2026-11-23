// Prairie : herbe en nappes de couleur douces, quelques zones plus sèches, et une
// légère ondulation de lumière comme le vent qui passe sur l'herbe. Aucune texture.
shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform vec3 grass_a : source_color = vec3(0.4, 0.55, 0.26);
uniform vec3 grass_b : source_color = vec3(0.56, 0.64, 0.31);
uniform vec3 dry : source_color = vec3(0.66, 0.64, 0.4);
uniform vec3 path_color : source_color = vec3(0.7, 0.63, 0.5);
uniform float wind_speed = 0.35;

varying vec3 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float big = fbm(p * 0.035);
	float mid = fbm(p * 0.18 + 3.1);
	float fine = noise(p * 3.5) * 0.5 + noise(p * 9.0) * 0.5;
	vec3 col = mix(grass_a, grass_b, smoothstep(0.35, 0.7, big));
	col = mix(col, dry, smoothstep(0.62, 0.8, fbm(p * 0.06 + 11.0)) * 0.55);
	col *= 0.9 + mid * 0.18 + (fine - 0.5) * 0.08;
	// Petites fleurs des champs : quelques points blancs, jaunes et roses.
	vec2 cell = floor(p * 2.2);
	vec2 fp = fract(p * 2.2) - 0.5;
	float h = hash(cell);
	float flower = (1.0 - smoothstep(0.05, 0.11, length(fp - (vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5) * 0.6)))
			* step(0.93, h) * smoothstep(0.45, 0.6, fbm(p * 0.09 + 5.0));
	vec3 petal = h > 0.98 ? vec3(0.98, 0.78, 0.85) : (h > 0.955 ? vec3(0.98, 0.9, 0.45) : vec3(0.97, 0.96, 0.92));
	col = mix(col, petal, flower);
	// Vent sur l'herbe : de longues vagues de lumière qui traversent la prairie.
	float wave = sin(dot(p, vec2(0.08, 0.05)) - TIME * wind_speed * 2.0 + fbm(p * 0.05) * 4.0);
	col *= 1.0 + wave * 0.035;
	// Sentier de terre qui serpente vers le hameau.
	float path_x = sin(wp.z * 0.045) * 7.0 + 3.0;
	float d = abs(wp.x - path_x);
	float on_path = (1.0 - smoothstep(0.9, 1.6 + mid * 0.6, d)) * smoothstep(14.0, 24.0, wp.z);
	col = mix(col, path_color * (0.92 + fine * 0.12), on_path);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
