// Petit étang : eau calme, reflets du ciel en bord de vue, rides douces.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform vec3 deep : source_color = vec3(0.12, 0.27, 0.3);
uniform vec3 shallow : source_color = vec3(0.32, 0.5, 0.48);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wp.xz * 1.3;
	float n1 = noise(p + vec2(TIME * 0.25, TIME * 0.1));
	float n2 = noise(p * 1.7 - vec2(TIME * 0.18, -TIME * 0.22));
	vec3 n = normalize(vec3((n1 - 0.5) * 0.18, 1.0, (n2 - 0.5) * 0.18));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = mix(deep, shallow, smoothstep(0.55, 1.0, r));
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = 1.0 - smoothstep(0.92, 1.0, r);
}
