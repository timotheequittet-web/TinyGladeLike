// Herbe soufflée par le vent (MultiMesh, couleur par touffe), reprise de L'Effacement.
// Normales vers le haut : les brins prennent la lumière du sol et le pré se lit comme un tapis qui ondule.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec4 tip_col : source_color = vec4(0.42, 0.58, 0.2, 1.0);   // pointes vert tendre
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;   // même bruit que le sol : plages d'ombre et de soleil
uniform float wind_strength = 0.3;
uniform float blade_h = 0.9;
uniform vec3 translucency = vec3(0.18, 0.24, 0.07);   // lumière qui traverse les brins à contre-jour
uniform float root_dark = 0.42;
// Île du Vent (WindIsle) : front de pousse qui monte. Les touffes plus basses que grow_line (hauteur monde) sont
// levées, les autres rentrées dans le sol ; wither = 1 inverse (l'herbe sèche s'efface au même front).
// Valeurs par défaut : tout est levé, rien ne change pour les autres prés.
const float GROW_BAND = 3.0;   // demi-épaisseur du front (m)
uniform float grow_line = 1000000.0;
uniform float wither : hint_range(0.0, 1.0) = 0.0;
global uniform float autumn;
global uniform float gust;   // rafale de vent (0..1), animée par world.gd

varying vec3 base_col;
varying float h;
varying float patch_light;
varying vec3 blade_n;
varying float sheen;   // passage d'une vague de vent : les brins couchés montrent leur revers clair (prés de Ghibli)

void vertex() {
	h = clamp(VERTEX.y / blade_h, 0.0, 1.0);
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float w = sin(TIME * 1.7 + root.x * 0.15 + root.z * 0.1) * 0.6 + sin(TIME * 3.1 + root.x * 0.4) * 0.25;
	// vagues qui balaient le pré, plus fortes pendant les rafales
	float wave = sin(TIME * 1.1 - root.x * 0.09 - root.z * 0.05);
	w += (wave * 0.5 + 0.5) * (0.5 + gust * 1.6);
	// bandes larges et lentes, cassées par le bruit : on voit le vent courir sur le pré
	float band = sin(TIME * 0.7 - root.x * 0.045 - root.z * 0.03 + texture(noise_tex, root.xz * 0.02).r * 4.0);
	sheen = smoothstep(0.55, 1.0, band) * (0.6 + gust * 0.8);
	VERTEX.x += w * wind_strength * h * h;
	VERTEX.z += w * wind_strength * 0.4 * h * h;
	// au loin, les touffes rentrent dans le sol avant la limite de visibilité (pas de fondu transparent : NaN)
	VERTEX.y *= 1.0 - smoothstep(52.0, 68.0, length(root - CAMERA_POSITION_WORLD));
	float grown = smoothstep(root.y - GROW_BAND, root.y + GROW_BAND, grow_line);
	VERTEX.y *= mix(grown, 1.0 - grown, wither);
	base_col = COLOR.rgb;
	blade_n = NORMAL;   // normale du brin (bombée d'un bord à l'autre), mêlée à la verticale plus bas
	// grandes plages plus sombres ou plus claires, comme l'ombre des nuages sur un pré (même bruit que le sol)
	patch_light = mix(0.62, 1.15, smoothstep(0.3, 0.72, texture(noise_tex, root.xz * 0.012).r));
	NORMAL = vec3(0.0, 1.0, 0.0);
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	// herbe dorée en automne, en plaques : une partie reste verte
	vec3 root_w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// automne en trois tons, par plaques : vert olive qui résiste, blond doré, roux ; jamais un aplat moutarde
	float patch = smoothstep(-0.4, 0.6, sin(root_w.x * 0.11) * sin(root_w.z * 0.13) + sin(root_w.x * 0.031 + root_w.z * 0.027));
	float tuft = fract(sin(dot(root_w.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float lum = dot(base_col, vec3(0.5, 0.8, 0.2));
	vec3 olive = base_col * vec3(1.15, 1.0, 0.55);
	vec3 gold = vec3(0.62, 0.48, 0.16) * lum * 1.6;
	vec3 russet = vec3(0.6, 0.28, 0.1) * lum * 1.6;
	vec3 fall = mix(olive, mix(gold, russet, step(0.72, tuft)), patch);
	vec3 bc = mix(base_col, fall, autumn * mix(0.55, 0.9, patch)) * 1.25;
	vec3 tip = mix(tip_col.rgb, mix(vec3(0.62, 0.66, 0.3), vec3(0.95, 0.72, 0.32), patch), autumn);
	ALBEDO = mix(bc * root_dark, mix(bc, tip, 0.35), smoothstep(0.0, 1.0, h)) * patch_light;
	// vague de vent : le haut des brins s'éclaircit vers un vert doré pâle
	ALBEDO = mix(ALBEDO, mix(tip, vec3(0.72, 0.78, 0.42), 0.5) * patch_light, sheen * h * 0.45);
	// volume : chaque brin garde un peu de sa propre orientation (bords plus sombres, crête plus claire),
	// le reste suit le sol pour que le pré s'éclaire comme un tapis
	vec3 bn = (VIEW_MATRIX * vec4(MODEL_MATRIX[0].xyz * blade_n.x + MODEL_MATRIX[1].xyz * blade_n.y + MODEL_MATRIX[2].xyz * blade_n.z, 0.0)).xyz;
	bn = (dot(bn, bn) > 1e-12 ? normalize(bn) : NORMAL) * (FRONT_FACING ? 1.0 : -1.0);
	NORMAL = normalize(mix(NORMAL, bn, 0.45));
	// rugosité 1 : marque l'herbe pour le trait d'encre (ink_lines.gdshader l'ignore, sinon chaque brin serait cerné) ;
	// les pointes accrochent toujours la lumière par SPECULAR
	ROUGHNESS = 1.0;
	SPECULAR = mix(0.1, 0.4, h);
	BACKLIGHT = translucency * h;
}
