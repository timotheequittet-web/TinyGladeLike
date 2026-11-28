// Herbe peinte (style « cozy », façon dessin animé) : beaucoup de petites cartes
// tournées vers la caméra, sur lesquelles le shader dessine 6 brins fins au
// pinceau (pointes effilées, en éventail, un bord clair et un bord sombre). Le
// fond de la carte est découpé net (discard : pas de tri, pas de flou).
// Les brins prennent la teinte de la prairie au pied de la carte (même teinte que
// le sol, voir bastide_meadow.gdshaderinc) : foncés à la racine, clairs aux pointes.
// Le vent souffle en repère monde : toute la prairie ploie dans la même direction,
// en longues vagues qui éclaircissent l'herbe.
//
// Chaque sommet porte : UV.x = côté de la carte (-1..1), UV.y = hauteur (0..1),
// UV2 = pied de la carte dans la tuile (xz), COLOR = (rang LOD, trois tirages 0..1).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled, depth_draw_opaque;

#include "res://addons/bastide/shaders/bastide_meadow.gdshaderinc"

uniform float blade_height = 0.42;     // hauteur moyenne d'une carte (m)
uniform float blade_width = 0.34;      // largeur moyenne d'une carte (m)
uniform float wind_strength = 0.3;
// Centre et rayons de fondu (en xz) : l'herbe s'efface doucement au bord.
uniform vec3 center = vec3(0.0);
uniform float fade_in = 0.0;
uniform float fade_in_width = 4.0;
uniform float fade_out = 30.0;
uniform float fade_out_width = 8.0;
// Masque des constructions : 1 = sol occupé (chemin, maison…), l'herbe s'y couche.
uniform sampler2D mask : filter_linear, repeat_disable, hint_default_black;
uniform vec4 mask_rect = vec4(-80.0, -80.0, 160.0, 160.0);
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec4 height_rect = vec4(0.0, 0.0, 0.0, 0.0);
// Niveaux de détail (même calcul que BastideGrass.keep_at).
uniform float lod_d0 = 18.0;
uniform float lod_min = 0.06;
uniform float max_widen = 2.0;
// Près de l'œil (promenade), les cartes s'effacent pour ne pas boucher la vue.
uniform float eye_clear = 0.9;
// 1 : pieds des cartes donnés par le maillage, en repère local (UV2 = xz, VERTEX.y =
// hauteur) : herbe posée sur une forme qui n'est pas le relief (buttes des terriers).
uniform float local_roots = 0.0;

varying vec2 v_root;
varying vec3 v_rnd;
varying float v_wave;
varying float v_side;    // côté vers lequel le vent couche les brins, vu de la caméra (-1..1)

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 root = origin + vec3(UV2.x, 0.0, UV2.y);
	if (local_roots > 0.5) {
		root = (MODEL_MATRIX * vec4(UV2.x, VERTEX.y, UV2.y, 1.0)).xyz;
	}
	float t = UV.y;
	float ground = 0.0;
	if (height_rect.z > 0.0 && local_roots < 0.5) {
		// Même découpe en triangles que le maillage du relief (diagonale a+1 / a+w) :
		// les pieds des cartes ne s'enfoncent pas dans le sol sur les bosses.
		ivec2 ts = textureSize(height_tex, 0);
		vec2 g = clamp((root.xz - height_rect.xy) / height_rect.zw, vec2(0.0), vec2(1.0)) * vec2(ts - 1);
		ivec2 i0 = min(ivec2(g), ts - 2);
		vec2 f = g - vec2(i0);
		float ha = texelFetch(height_tex, i0, 0).r;
		float hb = texelFetch(height_tex, i0 + ivec2(1, 0), 0).r;
		float hc = texelFetch(height_tex, i0 + ivec2(0, 1), 0).r;
		float hd = texelFetch(height_tex, i0 + ivec2(1, 1), 0).r;
		ground = f.x + f.y <= 1.0 ? ha + (hb - ha) * f.x + (hc - ha) * f.y
				: hd + (hc - hd) * (1.0 - f.x) + (hb - hd) * (1.0 - f.y);
	}
	root.y += ground - 0.04;
	vec3 to_cam = CAMERA_POSITION_WORLD - root;
	float dcam = length(to_cam);
	float keep = clamp(pow(lod_d0 / max(dcam, 0.01), 1.5), lod_min, 1.0);
	float lod_h = 1.0 - smoothstep(keep * 0.75, keep, COLOR.r);
	float widen = min(inversesqrt(keep), max_widen);
	// Hauteur : grandes plages plus hautes ou plus rases, chaque carte un peu différente.
	float patch = noise(root.xz * 0.09) * 0.7 + noise(root.xz * 0.37) * 0.3;
	float h = blade_height * (0.72 + patch * 0.45) * (0.85 + 0.3 * COLOR.b);
	vec2 muv = (root.xz - mask_rect.xy) / mask_rect.zw;
	float occ = 0.0;
	if (muv.x > 0.0 && muv.y > 0.0 && muv.x < 1.0 && muv.y < 1.0) {
		occ = texture(mask, muv).r;
	}
	h *= 1.0 - smoothstep(0.2, 0.75, occ);
	float d = length(root.xz - center.xz);
	h *= smoothstep(fade_in, fade_in + fade_in_width, d) * (1.0 - smoothstep(fade_out - fade_out_width, fade_out, d));
	h *= lod_h;
	// Promenade : pas de cartes collées à l'œil.
	h *= smoothstep(eye_clear * 0.5, eye_clear, length(to_cam.xz));
	float w = blade_width * (0.8 + 0.4 * COLOR.g) * widen;
	// Carte tournée vers la caméra (autour de la verticale), un peu de biais.
	vec2 f = normalize(to_cam.xz + vec2(1e-4, 0.0));
	float a = (COLOR.a - 0.5) * 0.8;
	f = vec2(f.x * cos(a) - f.y * sin(a), f.x * sin(a) + f.y * cos(a));
	vec2 right = vec2(-f.y, f.x);
	// Vue d'en haut : le haut de la carte se penche vers la caméra pour rester visible.
	float pitch = clamp(to_cam.y / max(dcam, 0.01), 0.0, 1.0);
	vec3 p = root;
	p.xz += right * UV.x * w * 0.5;
	p.y += t * h;
	p.xz += f * t * h * pitch * 0.35;
	// Vent en repère monde : longues vagues, rafales, et un léger frémissement.
	vec2 wd = normalize(meadow_wind_dir);
	float wave = meadow_wave(root.xz, TIME);
	float gust = noise(root.xz * 0.12 - wd * TIME * 0.6);
	float bend = wind_strength * (0.3 + wave * 0.9 + gust * 0.35) + sin(TIME * 2.1 + COLOR.g * 6.28) * 0.02;
	float tt = t * t;
	p.xz += wd * bend * tt * h * 1.3;
	p.y -= bend * bend * tt * h * 0.3;
	VERTEX = local_roots > 0.5 ? (inverse(MODEL_MATRIX) * vec4(p, 1.0)).xyz : p - origin;
	// Éclairée comme le sol : l'herbe et la prairie ne font qu'un.
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_root = root.xz;
	v_rnd = COLOR.gba;
	v_wave = wave;
	v_side = clamp(dot(wd, right) * (0.6 + bend * 1.5), -1.0, 1.0);
}

void fragment() {
	vec2 uv = vec2(UV.x * 0.5 + 0.5, UV.y);
	// Un pixel, en unités de carte : les brins ne deviennent jamais plus fins que ça.
	float px = max(fwidth(uv.x), 1e-4);
	float hit = -1.0;
	float hit_edge = 0.0;
	float hit_h = 1.0;
	float hit_s = 0.5;
	// Carte petite à l'écran : moins de brins, plus larges (moins de calcul et pas
	// de brins plus fins qu'un pixel qui scintillent quand le vent les bouge).
	float n = px > 0.018 ? 4.0 : 7.0;
	float wscale = 7.0 / n;
	// Tirages par brin : suites à pas irrationnel (bien moins chères que des sinus).
	// Du brin de devant (le dernier) vers le fond : on s'arrête au premier touché.
	for (float fk = n - 1.0; fk >= 0.0; fk -= 1.0) {
		float s1 = fract(v_rnd.x + fk * 0.6180340);
		float s2 = fract(v_rnd.y + fk * 0.7548777);
		float s3 = fract(v_rnd.z + fk * 0.5698403);
		// Hauteurs bien variées : pas de dessus plat.
		float hk = 0.35 + 0.65 * s1 * s1 * (2.0 - s1);
		if (uv.y >= hk) {
			continue;
		}
		float xk = 0.16 + 0.68 * ((fk + 0.5) / n) + (s2 - 0.5) * 0.14;
		// En éventail, et tous couchés du côté où souffle le vent.
		float lean = (xk - 0.5) * 0.5 + (s3 - 0.5) * 0.25 + v_side * (0.35 + 0.3 * s1);
		float yn = uv.y / hk;
		float cx = xk + lean * yn * yn * 0.42;
		float wk = (0.055 + 0.05 * s3) * wscale;
		// Pointe effilée ; jamais moins d'un pixel de large (sauf tout au bout).
		float half_w = max(wk * (1.0 - yn) * (1.25 - 0.25 * (1.0 - yn)), px * 0.75 * step(yn, 0.95));
		float e = (uv.x - cx) / half_w;
		if (abs(e) < 1.0) {
			hit = fk;
			hit_edge = e * sign(lean + 1e-3);
			hit_h = yn;
			hit_s = s2;
			break;
		}
	}
	// Découpe nette hors des brins (comme un alpha scissor, mais sûre dans toutes
	// les passes, y compris la pré-passe de profondeur).
	if (hit < 0.0) {
		discard;
	}
	vec3 tone = meadow_tone(v_root);
	vec3 root_c = tone * vec3(0.5, 0.6, 0.58);
	vec3 tip_c = mix(tone * 1.45, meadow_sun * 1.25, 0.35 + v_rnd.x * 0.3);
	// Foncé au pied de la carte (comme le sol assombri sous l'herbe), clair en haut.
	vec3 col = mix(root_c, tone * 1.1, smoothstep(0.0, 0.45, uv.y));
	col = mix(col, tip_c, smoothstep(0.45, 1.0, uv.y) * (0.6 + 0.4 * hit_h));
	// Valeur propre au brin : ceux de devant un peu plus clairs (profondeur peinte).
	col *= 0.8 + 0.12 * (hit / (n - 1.0)) + 0.24 * hit_s;
	// Coup de pinceau : un bord éclairé, l'autre dans l'ombre.
	col *= hit_edge > 0.15 ? 1.09 : (hit_edge < -0.45 ? 0.9 : 1.0);
	// La vague couche l'herbe et montre le dessus clair des brins.
	col = mix(col, col * 1.3 + vec3(0.03, 0.045, 0.0), v_wave * smoothstep(0.2, 1.0, uv.y) * 0.75);
	// Touffe plus ou moins éclairée : le tapis garde du relief, comme peint à la main.
	col *= 0.86 + 0.28 * v_rnd.y;
	col *= meadow_clouds(v_root, TIME);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	BACKLIGHT = vec3(0.18, 0.2, 0.08) * uv.y;
	AO = mix(0.9, 1.0, uv.y);
	AO_LIGHT_AFFECT = 0.4;
}
