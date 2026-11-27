// Herbe haute : brins fins, foncés au pied et dorés aux pointes, éclairés comme une
// nappe douce (normales vers le ciel), couchés par de longues vagues de vent.
// Chaque sommet porte dans UV : x = côté du brin (-1..1), y = hauteur relative (0..1),
// et dans UV2 : la position du pied du brin dans la tuile (xz), pour que le vent et
// le masque soient lus au même point pour tout le brin.
// Deux styles : « naturelle » (brins dorés de fin de journée) et « peinte » (painted
// = 1 : touffes vert vif colorées par la prairie partagée avec le sol, ombres de
// nuages, vagues de vent qui éclaircissent l'herbe, façon dessin animé).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled, depth_draw_opaque;

#include "res://addons/bastide/shaders/bastide_meadow.gdshaderinc"

uniform float painted = 0.0;

uniform vec3 base_color : source_color = vec3(0.17, 0.31, 0.1);
uniform vec3 mid_color : source_color = vec3(0.46, 0.63, 0.22);
uniform vec3 tip_color : source_color = vec3(0.88, 0.9, 0.5);
uniform vec3 dry_color : source_color = vec3(0.88, 0.78, 0.44);
uniform float blade_height = 0.55;
uniform float height_jitter = 0.45;
uniform float wind_strength = 0.32;
// Centre et rayons de fondu (en xz) : l'herbe s'efface doucement au bord.
uniform vec3 center = vec3(0.0);
uniform float fade_in = 0.0;      // en deçà, la nappe est encore rase (anneau lointain)
uniform float fade_in_width = 4.0;
uniform float fade_out = 30.0;
uniform float fade_out_width = 8.0;
// Masque des constructions : 1 = sol occupé (chemin, maison…), l'herbe s'y couche.
uniform sampler2D mask : filter_linear, repeat_disable, hint_default_black;
uniform vec4 mask_rect = vec4(-80.0, -80.0, 160.0, 160.0);
// Relief (facultatif) : hauteurs du sol en monde, sur height_rect (x, z, largeur, profondeur).
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec4 height_rect = vec4(0.0, 0.0, 0.0, 0.0);
// Niveaux de détail : COLOR.r = rang du brin (0..1). À la distance d de la caméra,
// on garde la part keep = clamp((lod_d0 / d)^1.5, lod_min, 1) des brins ; les autres
// se couchent et les restants s'élargissent pour couvrir le sol (même calcul que
// BastideGrass.keep_at, qui choisit le maillage de chaque tuile).
uniform float lod_d0 = 18.0;
uniform float lod_min = 0.06;
uniform float blade_width = 0.04;
uniform float max_widen = 2.0;

varying float v_t;
varying float v_tone;
varying float v_wave;
varying vec2 v_root;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	// Les tuiles ne sont que déplacées : pas besoin d'inverser leur matrice.
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 root = origin + vec3(UV2.x, 0.0, UV2.y);
	float t = UV.y;
	float ground = 0.0;
	if (height_rect.z > 0.0) {
		vec2 huv = clamp((root.xz - height_rect.xy) / height_rect.zw, vec2(0.0), vec2(1.0));
		// Centre des texels : la grille de hauteurs a un point par sommet.
		vec2 ts = vec2(textureSize(height_tex, 0));
		ground = texture(height_tex, (huv * (ts - 1.0) + 0.5) / ts).r;
	}
	// Niveau de détail : part de brins gardés à cette distance de l'œil.
	float dcam = length(vec3(root.x, root.y + ground, root.z) - CAMERA_POSITION_WORLD);
	float keep = clamp(pow(lod_d0 / max(dcam, 0.01), 1.5), lod_min, 1.0);
	float rank = COLOR.r;
	// Les brins au bord de la part gardée rapetissent au lieu de disparaître d'un coup.
	float lod_h = 1.0 - smoothstep(keep * 0.75, keep, rank);
	float widen = min(inversesqrt(keep), max_widen);
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
	h *= lod_h;
	// Vent : longues vagues qui traversent la prairie, et un frémissement propre au brin.
	vec2 wd = normalize(meadow_wind_dir);
	float wave = meadow_wave(root.xz, TIME);
	float gust = noise(root.xz * 0.12 - wd * TIME * 0.6);
	float bend = wind_strength * (0.35 + wave * 0.9 + gust * 0.4) + sin(TIME * 2.3 + hash(root.xz) * 6.28) * 0.04;
	vec3 local = VERTEX;
	local.y *= h / max(blade_height, 0.001);
	vec3 world = origin + local;
	world.y += ground;
	float bt = t * t;
	world.xz += wd * bend * bt * h * 1.4;
	world.y -= bend * bend * bt * h * 0.35;
	VERTEX = world - origin;
	// Élargit les brins restants (UV.x = côté du brin, -1..1, perpendiculaire à la normale).
	VERTEX.xz += normalize(vec2(-NORMAL.z, NORMAL.x) + 1e-5) * UV.x * blade_width * 0.5 * (widen - 1.0) * (1.0 - t * 0.55);
	// Éclairage doux : la nappe reçoit la lumière comme un tapis, pas comme des lames.
	// En style peint, exactement comme le sol : l'herbe et la prairie ne font qu'un.
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), mix(0.85, 1.0, painted)));
	v_root = root.xz;
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
	if (painted > 0.5) {
		// Teinte de la prairie au pied du brin : foncée à la racine (même teinte que
		// le sol assombri), lumineuse et un peu jaune vers la pointe.
		vec3 tone = meadow_tone(v_root);
		vec3 root_c = tone * 0.72;
		vec3 tip_c = mix(tone * 1.35, meadow_sun * 1.15, 0.3 + v_tone * 0.25);
		col = mix(root_c, tone, smoothstep(0.0, 0.45, v_t));
		col = mix(col, tip_c, smoothstep(0.5, 1.0, v_t));
		col *= 0.93 + v_tone * 0.14;
		// La vague couche l'herbe et montre le dessus clair des brins.
		col = mix(col, col * 1.35 + vec3(0.04, 0.05, 0.0), v_wave * smoothstep(0.2, 1.0, v_t) * 0.8);
		col *= meadow_clouds(v_root, TIME);
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.35, 0.33, 0.15) * v_t * (1.0 - painted * 0.5);
	AO = mix(mix(0.75, 0.9, painted), 1.0, v_t);
	AO_LIGHT_AFFECT = 0.4;
}
