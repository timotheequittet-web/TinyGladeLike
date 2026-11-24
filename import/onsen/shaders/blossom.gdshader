// Couronnes « peintes » (cerisiers, érables, chênes) : des cartes face caméra posées sur la surface des boules
// de feuillage. Chaque carte garde la normale de la boule sous elle : la couronne s'éclaire comme une masse,
// en deux tons francs comme dans un décor peint (light() : aplat d'ombre sous chaque touffe, bord net mais doux),
// et le bord découpé des cartes donne la silhouette floconneuse des arbres de Ghibli.
// Sommets : VERTEX = centre de la carte, UV2 = coin (-1..1) × taille, COLOR.rgb = couleur (linéaire, ombre comprise),
// COLOR.a = ombre interne (0 dedans, 1 dehors). Forward+, une texture lue par pixel.
shader_type spatial;
// shadows_disabled : la couronne ne reçoit pas d'ombre (celle de sa silhouette simplifiée y dessinait des plaques
// anguleuses) ; son volume vient des normales des boules
render_mode cull_disabled, skip_vertex_transform, shadows_disabled;   // sommet placé en espace vue

group_uniforms couleurs;
uniform float translucency = 0.35;   // lumière qui traverse le bord des couronnes à contre-jour
uniform float autumn_k = 1.0;        // 0 : feuillage qui ne change pas en automne (érables déjà rouges)
group_uniforms peinture;
uniform float cel_edge = 0.08;       // où passe la limite ombre / lumière (cosinus soleil-normale)
uniform float cel_soft = 0.12;       // largeur du bord : net mais pas crénelé
uniform float cel_shadow = 0.08;     // part du soleil qui reste dans l'aplat d'ombre (il reste le ciel)
uniform vec3 shade_tint = vec3(0.78, 0.86, 1.0);   // l'ombre des feuillages tire vers le bleu (lumière du ciel)
group_uniforms forme;
uniform sampler2D clump_tex : source_color, filter_linear_mipmap;   // touffe de fleurs ou de feuilles, alpha découpé
uniform float alpha_cut = 0.5;
uniform float wind = 0.04;           // balancement, en mètres
uniform vec2 near_fade = vec2(1.5, 12.0);   // de près (m), les cartes rapetissent : on lit des feuilles, pas des plans
uniform float near_scale = 0.3;      // taille relative d'une carte collée à la caméra
uniform bool upright = false;        // touffe au sol : tourne seulement autour de la verticale, le pied reste posé
global uniform float autumn;

varying float tree_pick;   // un tirage par arbre (sa position) : chaque arbre a sa couleur d'automne

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 root = MODEL_MATRIX[3].xyz;
	tree_pick = fract(sin(dot(floor(root.xz * 0.7), vec2(12.9898, 78.233))) * 43758.5453);
	float ph = dot(center, vec3(0.37, 0.21, 0.29));
	// au sol, seul le haut de la touffe ondule (le pied, UV2.y < 0, reste planté)
	float sway = upright ? max(UV2.y, 0.0) / max(abs(UV2.x), 0.001) : 1.0;
	vec3 gust = vec3(sin(TIME * 1.3 + ph), 0.0, cos(TIME * 1.1 + ph * 1.3)) * wind * sway;
	// la carte s'ouvre face à la caméra autour de son centre (à la verticale pour une touffe au sol)
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	if (upright) {
		right = normalize(vec3(right.x, 0.0, right.z) + vec3(1e-4, 0.0, 0.0));
		up = vec3(0.0, 1.0, 0.0);
	}
	float k = upright ? 1.0 : mix(near_scale, 1.0, smoothstep(near_fade.x, near_fade.y, length(center - CAMERA_POSITION_WORLD)));
	vec3 world = center + gust + (right * UV2.x + up * UV2.y) * k;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 t = texture(clump_tex, UV);
	ALBEDO = COLOR.rgb * t.rgb;
	// automne : roux, orange ou doré selon l'arbre (un par arbre, pas de mouchetis), même ombre interne
	vec3 red = vec3(0.55, 0.1, 0.04);
	vec3 orange = vec3(0.85, 0.32, 0.06);
	vec3 gold = vec3(0.9, 0.6, 0.12);
	vec3 deep = tree_pick < 0.33 ? red : (tree_pick < 0.7 ? orange : gold * 0.8);
	vec3 bright = tree_pick < 0.33 ? orange : (tree_pick < 0.7 ? gold : vec3(1.0, 0.82, 0.35));
	vec3 fall = mix(deep, bright, COLOR.a) * t.rgb;
	ALBEDO = mix(ALBEDO, fall, autumn * autumn_k);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	// bord découpé adouci (alpha to coverage avec le MSAA) : moins de scintillement en mouvement
	ALPHA_ANTIALIASING_EDGE = 0.35;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(clump_tex, 0));
	BACKLIGHT = ALBEDO * translucency * COLOR.a;
	ROUGHNESS = 0.9;
	SPECULAR = 0.0;
}

void light() {
	// deux tons : la face au soleil reçoit tout, l'autre garde un peu de soleil (l'aplat d'ombre) ; le ciel
	// (lumière ambiante) éclaire les deux pareil, ce qui donne le vert-bleu profond des dessous de touffes
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(cel_edge - cel_soft, cel_edge + cel_soft, ndl);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * mix(cel_shadow * shade_tint, vec3(1.0), lit) / PI;
	// contre-jour : le bord des touffes face au soleil s'allume
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * BACKLIGHT * clamp(-ndl, 0.0, 1.0) / PI;
}
