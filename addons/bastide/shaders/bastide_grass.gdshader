// Herbe haute : brins fins, foncés au pied et dorés aux pointes, éclairés comme une
// nappe douce (normales vers le ciel), couchés par de longues vagues de vent.
// Chaque sommet porte dans UV : x = côté du brin (-1..1), y = hauteur relative (0..1),
// et dans UV2 : la position du pied du brin dans la tuile (xz), pour que le vent et
// le masque soient lus au même point pour tout le brin.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled, depth_draw_opaque;

uniform vec3 base_color : source_color = vec3(0.17, 0.31, 0.1);
uniform vec3 mid_color : source_color = vec3(0.46, 0.63, 0.22);
uniform vec3 tip_color : source_color = vec3(0.88, 0.9, 0.5);
uniform vec3 dry_color : source_color = vec3(0.88, 0.78, 0.44);
uniform float blade_height = 0.55;
uniform float height_jitter = 0.45;
uniform float wind_strength = 0.32;
uniform float wind_speed = 1.1;
uniform vec2 wind_dir = vec2(0.8, 0.6);
// Centre et rayons de fondu (en xz) : l'herbe s'efface doucement au bord.
uniform vec3 center = vec3(0.0);
uniform float fade_in = 0.0;      // en deçà, la nappe est encore rase (anneau lointain)
uniform float fade_in_width = 4.0;
uniform float fade_out = 30.0;
uniform float fade_out_width = 8.0;
// Masque des constructions : 1 = sol occupé (chemin, maison…), l'herbe s'y couche.
uniform sampler2D mask : filter_linear, repeat_disable, hint_default_black;
uniform vec4 mask_rect = vec4(-80.0, -80.0, 160.0, 160.0);

varying float v_t;
varying float v_tone;
varying float v_wave;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(UV2.x, 0.0, UV2.y, 1.0)).xyz;
	float t = UV.y;
	// Hauteur : grandes plages plus hautes ou plus rases, et chaque brin un peu différent.
	float patch = noise(root.xz * 0.08) * 0.7 + noise(root.xz * 0.31) * 0.3;
	float h = blade_height * (0.55 + patch * 0.9) * (1.0 - height_jitter * hash(root.xz));
	// Masque : couché sur les chemins, raccourci à leurs abords.
	vec2 muv = (root.xz - mask_rect.xy) / mask_rect.zw;
	float occ = 0.0;
	if (muv.x > 0.0 && muv.y > 0.0 && muv.x < 1.0 && muv.y < 1.0) {
		occ = texture(mask, muv).r;
	}
	h *= 1.0 - smoothstep(0.2, 0.75, occ);
	// Fondu de l'anneau (distance au centre suivi).
	float d = length(root.xz - center.xz);
	h *= smoothstep(fade_in, fade_in + fade_in_width, d) * (1.0 - smoothstep(fade_out - fade_out_width, fade_out, d));
	// Vent : longues vagues qui traversent la prairie, et un frémissement propre au brin.
	vec2 wd = normalize(wind_dir);
	float phase = dot(root.xz, wd) * 0.22 - TIME * wind_speed + noise(root.xz * 0.05) * 3.0;
	float wave = 0.5 + 0.5 * sin(phase);
	wave = wave * wave;
	float gust = noise(root.xz * 0.12 - wd * TIME * 0.6);
	float bend = wind_strength * (0.35 + wave * 0.9 + gust * 0.4) + sin(TIME * 2.3 + hash(root.xz) * 6.28) * 0.04;
	vec3 local = VERTEX;
	local.y *= h / max(blade_height, 0.001);
	vec3 world = (MODEL_MATRIX * vec4(local, 1.0)).xyz;
	float bt = t * t;
	world.xz += wd * bend * bt * h * 1.4;
	world.y -= bend * bend * bt * h * 0.35;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	// Éclairage doux : la nappe reçoit la lumière comme un tapis, pas comme des lames.
	NORMAL = normalize(mix(NORMAL, (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.85));
	v_t = t;
	v_tone = noise(root.xz * 0.045 + 7.0) * 0.6 + hash(root.xz + 1.3) * 0.4;
	v_wave = wave;
}

void fragment() {
	vec3 col = mix(base_color, mid_color, smoothstep(0.0, 0.55, v_t));
	vec3 tip = mix(tip_color, dry_color, smoothstep(0.45, 0.85, v_tone));
	col = mix(col, tip, smoothstep(0.45, 1.0, v_t));
	// La vague de vent éclaircit les pointes qu'elle couche (reflet du ciel).
	col *= 1.0 + v_wave * 0.18 * v_t;
	col *= 0.9 + v_tone * 0.2;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.35, 0.33, 0.15) * v_t;
	AO = mix(0.75, 1.0, v_t);
	AO_LIGHT_AFFECT = 0.4;
}
