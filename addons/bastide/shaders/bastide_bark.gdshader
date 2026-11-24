// Troncs et branches des arbres du kit nature (couleurs par sommet des modèles Blender
// d'Onsen) : un peu éclaircis, lumière douce venue du haut, légère marbrure d'écorce,
// liseré clair sur les bords et balancement lent proportionnel à la hauteur.
shader_type spatial;
render_mode diffuse_burley;

uniform float gain = 2.3;            // les bruns des modèles sont très sombres
uniform float rim_strength = 0.22;
uniform float wind = 0.004;          // balancement par mètre de hauteur
uniform float marble = 0.18;

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y, 0.0);
	float ph = dot(root, vec3(0.37, 0.0, 0.29));
	VERTEX.x += sin(TIME * 0.9 + ph) * wind * h * h * 0.1;
	VERTEX.z += cos(TIME * 0.7 + ph * 1.3) * wind * h * h * 0.07;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = COLOR.rgb * gain;
	c *= mix(0.78, 1.12, wnorm.y * 0.5 + 0.5);
	// écorce : stries verticales et marbrure
	float strie = vnoise(vec3(wpos.x * 5.0, wpos.y * 0.6, wpos.z * 5.0));
	c *= 1.0 + (vnoise(wpos * 1.7) - 0.5) * marble + (strie - 0.5) * marble * 0.8;
	ALBEDO = clamp(c, vec3(0.0), vec3(2.0));
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = (1.0 - ndv) * (1.0 - ndv) * (1.0 - ndv);
	EMISSION = c * rim * rim_strength;
}
