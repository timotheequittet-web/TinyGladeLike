shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Matériau commun, repris de L'Effacement : lumière douce (pas de bandes), éclairage « peint » venu du haut,
// légère marbrure dans l'espace du monde et liseré lumineux. Couleurs de sommets en linéaire (comme les GLB).
// Alpha de sommet : 0 = s'allume la nuit ; 0,6 = chaume ; 0,7 = tuiles ; 0,85 = planches ; 1 = uni.

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform bool use_tex = false;   // modèles faits par IA : texture peinte au lieu des couleurs de sommets
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float tex_glow = 0.0;   // modèle IA : les zones claires et chaudes de la texture (papier de lanterne) s'allument
uniform vec4 leaf_color : source_color = vec4(1.0);   // modèle IA : feuillage repeint dans cette teinte (leaf_mix > 0)
uniform float leaf_mix = 0.0;
uniform float flutter = 0.0;        // feuilles qui frémissent (m), seulement au-dessus de flutter_from (la couronne)
uniform float flutter_from = 0.0;
uniform float rim_strength = 0.25;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float wind = 0.0;       // feuillage : amplitude du balancement, proportionnelle à la hauteur du sommet
uniform float roughness = 0.8;
uniform float detail_noise = 0.1;
uniform float bands = 0.5;      // conservé pour compatibilité (inutilisé)
global uniform float night;
global uniform float autumn;    // 0 = printemps, 1 = automne
global uniform float gust;      // rafale de vent (0..1)
uniform bool foliage = false;   // feuillage caduc : prend les couleurs d'automne (pas les pins ni les bambous)
// Grain de matière (texture CC0 de roche, projetée sur les trois axes) : fort sur la pierre, léger sur le reste.
uniform sampler2D detail_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_nor : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_amount = 0.0;
// Corps souple (le dragon du vent) : le modèle, allongé le long de +Z de spine_z0 à spine_z1, suit la courbe
// spine_p (repère local), « haut » donné par spine_u. spine_n = 0 : pas de déformation.
const int SPINE_MAX = 48;
uniform int spine_n = 0;
uniform vec3 spine_p[SPINE_MAX];
uniform vec3 spine_u[SPINE_MAX];
uniform float spine_z0 = 0.0;
uniform float spine_z1 = 1.0;
uniform float spine_paddle = 0.0;    // m : battement des pattes le long du corps
uniform float spine_flutter = 0.0;   // m : frémissement de la crinière et des nageoires
uniform float spine_swell = 0.0;     // respiration (part du rayon)

varying vec3 wpos;
varying vec3 wnorm;
varying vec3 root;

float m_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float m_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(m_hash(i), m_hash(i + vec3(1, 0, 0)), f.x), mix(m_hash(i + vec3(0, 1, 0)), m_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(m_hash(i + vec3(0, 0, 1)), m_hash(i + vec3(1, 0, 1)), f.x), mix(m_hash(i + vec3(0, 1, 1)), m_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	if (spine_n > 1) {
		// vie propre du maillage (poids dans COLOR, posés par WindDragon) : r = patte, g = avant / arrière, b = crinière et nageoires
		vec3 v = VERTEX;
		v.z += COLOR.r * sin(TIME * 2.6 + COLOR.g * 3.14159) * spine_paddle;                    // les pattes pagaient
		v.x += COLOR.b * sin(TIME * 5.0 - v.z * 0.9) * spine_flutter;                             // la crinière frémit dans le vent
		v.y += COLOR.b * cos(TIME * 4.1 - v.z * 0.7) * spine_flutter * 0.5;
		v.xy *= 1.0 + spine_swell * sin(TIME * 1.1 - v.z * 0.25);                                 // endormi : il respire
		float s = clamp((v.z - spine_z0) / (spine_z1 - spine_z0), 0.0, 1.0) * float(spine_n - 1);
		int i = min(int(floor(s)), spine_n - 2);
		float f = s - float(i);
		// Catmull-Rom : une courbe lisse entre les points (des segments droits faisaient des facettes)
		vec3 a = spine_p[max(i - 1, 0)];
		vec3 b = spine_p[i];
		vec3 c = spine_p[i + 1];
		vec3 d = spine_p[min(i + 2, spine_n - 1)];
		vec3 k1 = c - a;
		vec3 k2 = 2.0 * a - 5.0 * b + 4.0 * c - d;
		vec3 k3 = -a + 3.0 * b - 3.0 * c + d;
		vec3 p = 0.5 * (2.0 * b + k1 * f + k2 * f * f + k3 * f * f * f);
		vec3 t = normalize(k1 + 2.0 * k2 * f + 3.0 * k3 * f * f);
		vec3 x = normalize(cross(mix(spine_u[i], spine_u[i + 1], f), t));
		vec3 u = cross(t, x);
		VERTEX = p + x * v.x + u * v.y;
		NORMAL = mat3(x, u, t) * NORMAL;
	}
	if (wind > 0.0) {
		float sway = sin(TIME * 1.3 + root.x * 0.13 + root.z * 0.09) + 0.45 * sin(TIME * 2.9 + root.x * 0.37 + VERTEX.y);
		float k = wind * max(VERTEX.y, 0.0) * (1.0 + gust * 1.2);
		VERTEX.x += sway * k;
		VERTEX.z += sway * k * 0.6;
	}
	if (flutter > 0.0) {
		// chaque bouquet de feuilles vibre à son rythme ; les rafales les agitent
		float ph = dot(VERTEX, vec3(1.3, 0.9, 1.1)) + root.x * 0.3 + root.z * 0.2;   // basse fréquence : la touffe bouge d'un bloc
		float up = clamp((VERTEX.y - flutter_from) / max(flutter_from, 0.5), 0.0, 1.0);
		// direction tirée de la position (pas de la normale) : deux triangles voisins bougent ensemble, sans fente
		vec3 dir = vec3(sin(ph * 1.3), 0.5 * cos(ph * 0.9), cos(ph * 0.7));
		VERTEX += dir * (sin(TIME * 5.5 + ph) * 0.6 + sin(TIME * 9.0 + ph * 1.7) * 0.4) * flutter * up * (0.5 + gust * 1.2);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// triangles dégénérés (normale nulle) : on évite un NaN, qui ressortait en pixel noir étalé par le halo
	vec3 wn0 = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	wnorm = dot(wn0, wn0) > 1e-12 ? normalize(wn0) : vec3(0.0, 1.0, 0.0);
}

void fragment() {
	// normale nulle ou NaN (triangle dégénéré des modèles IA, objet réduit à zéro) : sans ce garde-fou, le pixel
	// sort en NaN, noir, et le halo l'étale en carré noir
	NORMAL = dot(NORMAL, NORMAL) > 1e-12 ? NORMAL : (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	vec4 vc = use_vertex_color ? COLOR : vec4(1.0);
	vec3 c = albedo.rgb * vc.rgb;
	if (use_tex) {
		c *= texture(albedo_tex, UV).rgb;
		if (leaf_mix > 0.0) {
			// feuilles = couleurs vives et claires ; l'écorce, sombre, ne change pas. On garde le modelé peint (luminance).
			float mx = max(c.r, max(c.g, c.b));
			float sat = (mx - min(c.r, min(c.g, c.b))) / max(mx, 0.001);
			float leaf = smoothstep(0.35, 0.55, sat) * smoothstep(0.18, 0.4, mx);
			float lum = dot(c, vec3(0.3, 0.59, 0.11));
			c = mix(c, leaf_color.rgb * clamp(0.3 + lum * 1.15, 0.0, 1.1), leaf * leaf_mix);
		}
	}
	if (use_vertex_color && vc.a > 0.55 && vc.a < 0.95) {
		float along = abs(wnorm.x) > abs(wnorm.z) ? wpos.z : wpos.x;
		if (vc.a < 0.65) {          // chaume (kayabuki) peint
			// rangs de paille superposés : chaque rang ondule un peu, son bas fait une lèvre ombrée
			float wav = (m_noise(vec3(along * 0.9, 0.0, 3.0)) - 0.5) * 0.18;
			float r = fract(wpos.y * 2.6 + wav);
			float course = 0.7 + 0.3 * smoothstep(0.0, 0.4, r) - 0.15 * (1.0 - smoothstep(0.82, 1.0, r));
			// brins : stries franches dans le sens de la pente (une botte tous les ~15 cm), de longueurs inégales
			float strand = m_noise(vec3(along * 6.5, wpos.y * 0.9, 0.0)) * 0.65 + m_noise(vec3(along * 17.0, wpos.y * 2.2, 7.0)) * 0.35;
			float s = 0.66 + 0.55 * smoothstep(0.32, 0.7, strand);
			// âge : la paille dorée grisonne doucement par grandes plaques, des coussins de mousse s'y accrochent
			float age = smoothstep(0.45, 0.85, m_noise(wpos * 0.22 + vec3(2.0, 0.0, 5.0)));
			vec3 straw = c * course * s;
			// (vieille paille plus sombre et plus terne : un gris pâle sur fond doré faisait des ronds clairs)
			straw = mix(straw, straw * vec3(0.74, 0.72, 0.68), age * 0.7);
			// mousse : coussins morcelés (grand bruit × petit bruit), vert sombre en linéaire (≈ 0,3 / 0,38 / 0,2 à l'écran)
			// (larges plaques bordées d'éclats : un vert sombre au fond, un vert-jaune vif là où la mousse est épaisse)
			float mn = m_noise(wpos * 0.32 + vec3(9.0, 1.0, 4.0)) * 0.55 + m_noise(wpos * 1.6 + vec3(1.0, 5.0, 2.0)) * 0.3 + m_noise(wpos * 6.0 + vec3(4.0, 2.0, 8.0)) * 0.15;
			// bord net (style peint), touffes claires en éclats dedans, liseré sombre autour
			float mv = mn + age * 0.12 - strand * 0.06;
			float moss = smoothstep(0.49, 0.515, mv) * smoothstep(0.2, 0.9, wnorm.y);
			float rim_m = smoothstep(0.46, 0.49, mv) * (1.0 - moss) * smoothstep(0.2, 0.9, wnorm.y);
			float clump = step(0.52, m_noise(wpos * 5.0 + vec3(3.0, 7.0, 1.0)) + (mv - 0.55) * 1.5);
			vec3 moss_c = mix(vec3(0.07, 0.13, 0.03), vec3(0.21, 0.31, 0.05), clump);
			c = mix(straw * (1.0 - rim_m * 0.35), moss_c, moss);
		} else if (vc.a < 0.8) {    // tuiles : rangées et joints décalés
			float row = fract(wpos.y * 3.0);
			float rid = floor(wpos.y * 3.0);
			float seam = fract(along * 1.6 + rid * 0.5);
			float line = max(1.0 - smoothstep(0.0, 0.1, row), 1.0 - smoothstep(0.0, 0.07, seam));
			c *= (0.84 + 0.16 * row) * mix(1.0, 0.7, line);
		} else {                    // planches
			float coord = abs(wnorm.y) > 0.7 ? wpos.x : along;
			float plank = fract(coord * 2.2);
			float id = floor(coord * 2.2);
			c *= (0.9 + 0.1 * fract(sin(id * 12.9898) * 43758.5)) * mix(1.0, 0.72, 1.0 - smoothstep(0.0, 0.06, plank));
		}
	}
	if (foliage && autumn > 0.001) {
		// Feuilles (vertes, ou roses/bleues : le bleu domine le vert) -> rouge, orange ou or selon l'arbre ;
		// l'écorce (brune : rouge > vert > bleu) ne change pas. On garde l'ombre peinte via la luminance.
		// écorce = brun sombre (rouge > vert > bleu et peu saturé en clair) ; tout le reste du feuillage change
		float bark = step(c.b, c.g) * step(c.g, c.r) * step(max(c.r, max(c.g, c.b)), 0.32);
		float leaf = 1.0 - bark;
		float lum = dot(c, vec3(0.3, 0.59, 0.11));
		// une teinte par arbre (pas de mouchetis), avec un léger dégradé dans la couronne
		float pick = fract(sin(dot(floor(root.xz * 0.5), vec2(12.9898, 78.233))) * 43758.5);
		pick = clamp(pick + (wpos.y - root.y) * 0.015, 0.0, 0.98);   // sommet un peu plus doré
		vec3 red = vec3(0.5, 0.06, 0.04);
		vec3 orange = vec3(0.78, 0.24, 0.04);
		vec3 gold = vec3(0.82, 0.52, 0.06);
		vec3 ac = pick < 0.33 ? mix(red, orange, pick * 3.0) : (pick < 0.66 ? mix(orange, gold, (pick - 0.33) * 3.0) : mix(gold, orange, (pick - 0.66) * 1.5));
		c = mix(c, ac * clamp(0.45 + lum * 2.2, 0.5, 1.35), autumn * leaf);
	}
	vec3 dn = vec3(0.0);
	if (detail_amount > 0.0) {
		vec3 tw = pow(abs(wnorm), vec3(4.0));
		tw /= (tw.x + tw.y + tw.z + 1e-5);
		vec3 p = wpos * 0.9;
		vec3 dt = texture(detail_tex, p.zy).rgb * tw.x + texture(detail_tex, p.xz).rgb * tw.y + texture(detail_tex, p.xy).rgb * tw.z;
		float avg = dot(textureLod(detail_tex, vec2(0.5), 11.0).rgb, vec3(0.3, 0.59, 0.11));
		float lum = dot(dt, vec3(0.3, 0.59, 0.11)) / avg;
		float mx = max(c.r, max(c.g, c.b));
		float sat = (mx - min(c.r, min(c.g, c.b))) / max(mx, 0.001);
		float stone = 1.0 - smoothstep(0.12, 0.4, sat);   // gris et pierre : grain fort ; couleurs franches : léger
		stone *= 1.0 - smoothstep(0.55, 0.8, mx);          // blancs (tissu, enduit, papier) : pas de marbrure de rocher
		float k = detail_amount * mix(0.22, 0.8, stone) * (foliage ? 0.3 : 1.0);
		c *= mix(1.0, clamp(lum, 0.45, 1.7), k);
		vec2 nx = texture(detail_nor, p.zy).xy * 2.0 - 1.0;
		vec2 ny = texture(detail_nor, p.xz).xy * 2.0 - 1.0;
		vec2 nz = texture(detail_nor, p.xy).xy * 2.0 - 1.0;
		dn = (vec3(0.0, nx.y, nx.x) * tw.x + vec3(ny.x, 0.0, ny.y) * tw.y + vec3(nz.x, nz.y, 0.0) * tw.z) * k * 1.4;
	}
	// Touche peinte : lumière douce venue du haut et légère marbrure.
	c *= mix(0.78, 1.12, wnorm.y * 0.5 + 0.5);
	c *= 1.0 + (m_noise(wpos * 2.3) - 0.5) * detail_noise;
	ALBEDO = clamp(c, vec3(0.0), vec3(4.0));
	if (detail_amount > 0.0) {
		vec3 nn = NORMAL + (VIEW_MATRIX * vec4(dn, 0.0)).xyz;
		NORMAL = dot(nn, nn) > 1e-12 ? normalize(nn) : NORMAL;
	}
	ROUGHNESS = roughness;
	if (foliage) {
		// feuilles et pétales : la lumière les traverse à contre-jour (comme sur le concept)
		BACKLIGHT = clamp(c * 0.55, vec3(0.0), vec3(4.0));
	}
	SPECULAR = 0.3;
	// liseré : pow(0, 3) sortait en NaN sur certains pixels de feuillage (carrés noirs étalés par le halo, vus en vol) ;
	// on multiplie à la main, et une normale invalide ne donne pas de liseré
	float ndv = dot(NORMAL, VIEW);
	float rim_x = ndv == ndv ? 1.0 - clamp(ndv, 0.0, 1.0) : 0.0;
	float fres = clamp(rim_x * rim_x * rim_x, 0.0, 1.0);
	fres *= foliage ? 1.8 : 1.0;   // bords des couronnes plus lumineux
	vec3 emis = emission.rgb * emission_energy + c * fres * rim_strength;
	if (use_vertex_color && vc.a < 0.5) {
		emis += c * (0.5 + night * 3.3);   // lanternes et papier : déjà tièdes le jour, éclatants la nuit
	}
	if (use_tex && tex_glow > 0.0) {
		float lum = dot(c, vec3(0.3, 0.59, 0.11));
		float warm = smoothstep(0.02, 0.12, c.r - c.b);
		emis += c * smoothstep(0.45, 0.7, lum) * warm * (0.4 + night * 3.0) * tex_glow;
	}
	// min/max rendent la valeur non-NaN sur GPU (isnan peut être retiré par l'optimiseur)
	EMISSION = clamp(emis, vec3(0.0), vec3(64.0));
}
