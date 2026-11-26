// Carpe koï : chaque instance tourne sur son cercle (INSTANCE_CUSTOM : rayon,
// vitesse en m/s, phase, échelle), ondule de la queue et dérive doucement en
// profondeur. Tout se passe ici : aucune mise à jour depuis le script.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

void vertex() {
	float radius = max(INSTANCE_CUSTOM.x, 0.2);
	float speed = INSTANCE_CUSTOM.y;
	float phase = INSTANCE_CUSTOM.z;
	float s = max(INSTANCE_CUSTOM.w, 0.01);
	// Vitesse qui varie un peu : un coup de queue, une glissade.
	float t = TIME + phase * 3.0;
	float a = phase + (t * speed + sin(t * 0.37) * 0.25) / radius;
	vec2 pos = vec2(cos(a), sin(a)) * radius;
	vec2 tangent = normalize(vec2(-sin(a), cos(a)) * sign(speed));
	// Ondulation : la queue bat, la tête reste presque droite.
	float tail = smoothstep(0.12, -0.3, VERTEX.z);
	VERTEX.x += sin(TIME * 5.0 + phase * 7.0 + VERTEX.z * 14.0) * 0.035 * tail;
	// Le poisson regarde le long de son cercle (+z = tête).
	vec3 fwd = vec3(tangent.x, 0.0, tangent.y);
	vec3 right = vec3(fwd.z, 0.0, -fwd.x);
	mat3 rot = mat3(right, vec3(0.0, 1.0, 0.0), fwd);
	VERTEX = rot * VERTEX + vec3(pos.x, sin(t * 0.5) * 0.03, pos.y) / s;
	NORMAL = rot * NORMAL;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
}
