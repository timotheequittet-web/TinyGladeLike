// Eau d'étang : couleur selon la profondeur réelle (on voit le fond et les galets
// dans les hauts-fonds, l'eau devient sombre et verte au milieu), réfraction douce,
// reflets du ciel au ras de l'eau, petites rides poussées par le vent, éclats de
// soleil, rive fondue et liseré clair, reflets dansants (caustiques) sur le fond.
//
// Le fond est relu dans les textures d'écran et de profondeur : rien à préparer.
// Sans elles (UV.x = distance à la rive en secours), l'eau reste correcte.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap, repeat_disable;

// Couleurs (sRGB) : eau fine au-dessus du fond, eau profonde, teinte de diffusion.
uniform vec3 shallow_tint : source_color = vec3(0.62, 0.78, 0.66);
uniform vec3 deep_color : source_color = vec3(0.05, 0.17, 0.16);
uniform vec3 scatter_color : source_color = vec3(0.16, 0.34, 0.28);
// Absorption par mètre : plus fort = eau plus trouble.
uniform float absorption = 1.6;
// Laiteux (eau d'onsen) : 0 = limpide, 1 = opaque et pâle.
uniform float milky = 0.0;
uniform vec3 milky_color : source_color = vec3(0.6, 0.8, 0.82);
uniform float refraction = 0.035;
uniform float ripple_scale = 1.0;
uniform float ripple_strength = 0.22;
uniform vec2 wind = vec2(0.35, 0.18);
uniform float shore_foam = 0.35;
uniform vec3 foam_color : source_color = vec3(0.92, 0.93, 0.86);
uniform float caustics = 0.55;
uniform float sky_reflection = 1.0;
uniform vec3 sky_tint : source_color = vec3(0.8, 0.84, 0.82);
// Fondu de rive : largeur (m) de l'eau qui s'efface sur la berge.
uniform float edge_fade = 0.12;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Hauteur des rides : trois couches de bruit qui dérivent à des vitesses
// différentes (pas de motif qui se répète), plus de longues ondes de vent.
float ripples(vec2 p, float t) {
	p *= ripple_scale;
	float h = vnoise(p * 1.1 + wind * t * 1.0) * 0.5;
	h += vnoise(p * 2.3 - wind.yx * t * 1.4 + 7.3) * 0.3;
	h += vnoise(p * 5.1 + vec2(-wind.x, wind.y) * t * 2.1 + 3.1) * 0.15;
	h += sin(dot(p, normalize(wind + 1e-4)) * 1.7 - t * 1.3) * 0.05;
	return h;
}

// Caustiques : réseau de lignes claires qui ondulent, lu sur le fond.
float caustic(vec2 p, float t) {
	vec2 q = p * 1.6;
	float c = 0.0;
	for (int i = 0; i < 2; i++) {
		vec2 g = q + vec2(sin(t * 0.6 + q.y * 1.3), cos(t * 0.5 + q.x * 1.1)) * 0.35;
		vec2 f = fract(g) - 0.5;
		vec2 cell = floor(g);
		float m = 1.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 o = vec2(float(x), float(y));
				vec2 r = o + vec2(hash(cell + o), hash(cell + o + 17.1)) * 0.8 + 0.1 * sin(t + 6.2831 * hash(cell + o + 3.3)) - 0.5 - f;
				m = min(m, dot(r, r));
			}
		}
		c += pow(smoothstep(0.0, 0.32, m), 3.0);
		q = q * 1.7 + 4.1;
	}
	return clamp(1.0 - c * 0.5, 0.0, 1.0);
}

float scene_depth(vec2 uv, mat4 inv_proj) {
	float raw = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, raw) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 p = wpos.xz;
	// Normale des rides (différences finies sur la hauteur).
	float e = 0.06;
	float h0 = ripples(p, t);
	float hx = ripples(p + vec2(e, 0.0), t);
	float hz = ripples(p + vec2(0.0, e), t);
	// Les rides s'adoucissent au loin (pas de scintillement) et près de la rive.
	float dist = length(VERTEX);
	float calm = mix(1.0, 0.35, smoothstep(25.0, 90.0, dist));
	vec3 n_w = normalize(vec3(-(hx - h0) / e * ripple_strength * calm, 1.0, -(hz - h0) / e * ripple_strength * calm));
	vec3 n_v = normalize((VIEW_MATRIX * vec4(n_w, 0.0)).xyz);

	// Épaisseur d'eau entre la surface et le fond, le long du regard.
	float surf_d = -VERTEX.z;
	float floor_d = scene_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float thick = max(floor_d - surf_d, 0.0);
	// Réfraction : on décale la lecture du fond selon les rides, sans aller lire un
	// objet posé devant l'eau.
	vec2 off = n_w.xz * refraction * clamp(thick, 0.0, 1.5) / max(1.0, surf_d * 0.05);
	vec2 ruv = SCREEN_UV + off;
	float floor_r = scene_depth(ruv, INV_PROJECTION_MATRIX);
	if (floor_r < surf_d) {
		ruv = SCREEN_UV;
		floor_r = floor_d;
	}
	float thick_r = max(floor_r - surf_d, 0.0);
	// Épaisseur verticale (plus juste pour la couleur que celle du regard).
	vec3 view_dir = normalize(-VERTEX);
	float cos_v = max(abs(dot(view_dir, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz)), 0.12);
	float depth_v = thick_r * cos_v;

	vec3 bottom = textureLod(screen_tex, ruv, 0.0).rgb;
	// Reflets dansants sur le fond des hauts-fonds.
	vec3 floor_w = wpos + normalize(wpos - CAMERA_POSITION_WORLD) * thick_r;
	float ca = caustic(floor_w.xz, t) * caustics * (1.0 - smoothstep(0.1, 1.2, depth_v)) * smoothstep(0.0, 0.08, depth_v);
	bottom *= shallow_tint * (1.0 + ca * 0.9);
	// Ce qu'on voit à travers l'eau est déjà éclairé (émission) ; ce que l'eau
	// ajoute elle-même (sa couleur, son voile, l'écume) reçoit la lumière et l'ombre.
	// Absorption (Beer-Lambert) : l'eau se teinte puis se ferme vers le fond.
	float absorb = 1.0 - exp(-depth_v * absorption);
	vec3 lit = mix(scatter_color, deep_color, smoothstep(0.2, 1.0, absorb));
	float w = absorb;
	// Eau laiteuse : un voile pâle qui cache le fond, plus dense en profondeur.
	float milk = milky * (1.0 - exp(-depth_v * 6.0));
	lit = mix(lit, milky_color, milk);
	w = mix(w, 1.0, milk);

	// Ciel au ras de l'eau (Fresnel), en plus du reflet spéculaire du moteur.
	float fres = pow(1.0 - clamp(dot(view_dir, n_v), 0.0, 1.0), 5.0) * sky_reflection;
	lit = mix(lit, sky_tint, fres * 0.6);
	w = mix(w, 1.0, fres * 0.6);

	// Liseré clair contre la rive, qui respire doucement.
	float edge = 1.0 - smoothstep(0.0, 0.28, depth_v);
	float foam_n = vnoise(p * 6.0 + t * 0.4) * vnoise(p * 2.0 - t * 0.2);
	float foam = edge * smoothstep(0.25, 0.6, foam_n + edge * 0.4) * shore_foam * (0.75 + 0.25 * sin(t * 1.3 + p.x * 0.7));
	lit = mix(lit, foam_color, foam / max(w + foam, 1e-3));
	w = mix(w, 1.0, foam);

	EMISSION = bottom * (1.0 - w);
	vec3 water = lit * w;
	ALBEDO = water;
	NORMAL = n_v;
	ROUGHNESS = mix(0.03, 0.12, milky);
	METALLIC = 0.0;
	SPECULAR = 0.55;
	// La rive : l'eau s'efface sur les derniers centimètres, sans trait dur.
	float fade = smoothstep(0.0, edge_fade, thick * cos_v);
	ALPHA = fade;
}
