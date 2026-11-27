// Prairie peinte (style « cozy ») : couleurs et lumières partagées par l'herbe et
// le sol, pour que les brins sortent du sol sans couture et que, au loin, le sol
// peint prenne le relais de l'herbe avec la même teinte.
//  - meadow_tone : grandes taches vert profond, vert frais et vert-jaune, lues en
//    coordonnées monde (même valeur pour un brin et le sol sous lui) ;
//  - meadow_clouds : ombres de nuages qui défilent lentement ;
//  - meadow_wave : vagues de vent qui traversent la prairie (0..1).

uniform vec3 meadow_deep : source_color = vec3(0.2, 0.47, 0.17);
uniform vec3 meadow_fresh : source_color = vec3(0.36, 0.67, 0.21);
uniform vec3 meadow_sun : source_color = vec3(0.7, 0.83, 0.3);
uniform float meadow_clouds_strength = 0.28;
uniform vec2 meadow_wind_dir = vec2(0.8, 0.6);
uniform float meadow_wind_speed = 1.1;

float m_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float m_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(m_hash(i), m_hash(i + vec2(1, 0)), f.x), mix(m_hash(i + vec2(0, 1)), m_hash(i + vec2(1, 1)), f.x), f.y);
}

vec3 meadow_tone(vec2 p) {
	float big = m_noise(p * 0.025) * 0.65 + m_noise(p * 0.07 + 3.7) * 0.35;
	float sun = smoothstep(0.55, 0.8, m_noise(p * 0.045 + 11.3) * 0.7 + m_noise(p * 0.21) * 0.3);
	vec3 col = mix(meadow_deep, meadow_fresh, smoothstep(0.25, 0.7, big));
	return mix(col, meadow_sun, sun * 0.75);
}

float meadow_clouds(vec2 p, float time) {
	vec2 q = p * 0.012 - meadow_wind_dir * time * 0.012;
	float c = m_noise(q) * 0.6 + m_noise(q * 2.3 + 5.1) * 0.4;
	return 1.0 - meadow_clouds_strength * smoothstep(0.45, 0.7, c);
}

float meadow_wave(vec2 p, float time) {
	vec2 wd = normalize(meadow_wind_dir);
	float phase = dot(p, wd) * 0.22 - time * meadow_wind_speed + m_noise(p * 0.05) * 3.0;
	float w = 0.5 + 0.5 * sin(phase);
	return w * w;
}
