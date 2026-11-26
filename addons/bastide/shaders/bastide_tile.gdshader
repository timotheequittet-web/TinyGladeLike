// Tuiles procédurales (kawara émaillées ou terre cuite) : la couleur vient des
// couleurs de sommets (rangs déjà nuancés par l'addon). Ce shader ajoute, sans
// texture :
// - des écarts de teinte d'une tuile à l'autre (cuisson inégale) ;
// - un émail satiné qui accroche la lumière rasante, plus mat là où il est usé ;
// - la patine : coulures sombres dans le sens de la pente, poussière claire sur les
//   rangs, et quelques lichens jaunis par plaques sur les faces tournées vers le ciel.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float tile_size = 0.3;
uniform float tint_variation : hint_range(0.0, 0.5) = 0.14;
uniform float glaze : hint_range(0.0, 1.0) = 0.55;
uniform float streaks : hint_range(0.0, 1.0) = 0.35;
uniform float dust : hint_range(0.0, 1.0) = 0.25;
uniform vec4 dust_color : source_color = vec4(0.62, 0.58, 0.5, 1.0);
uniform vec4 lichen_color : source_color = vec4(0.66, 0.64, 0.38, 1.0);
uniform float lichen_amount : hint_range(0.0, 1.0) = 0.25;
uniform vec4 moss_color : source_color = vec4(0.32, 0.4, 0.2, 1.0);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.1;

varying vec3 world_pos;
varying vec3 world_nrm;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
				   mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
				   mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz + vec3(0.0, 1e-5, 0.0));
}

void fragment() {
	vec3 c = clamp(COLOR.rgb, vec3(0.0), vec3(1.0));   // jamais négatif : pow() donnerait NaN
	vec3 base = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));

	// Repère de la pente : « travers » le long des rangs, « pente » vers le bas.
	vec2 down2 = world_nrm.xz;
	float sl = length(down2);
	down2 = sl > 1e-3 ? down2 / sl : vec2(0.0, 1.0);
	vec2 across2 = vec2(-down2.y, down2.x);
	float u = dot(world_pos.xz, across2);
	float v = dot(world_pos.xz, down2) - world_pos.y * 0.6;

	// Une teinte par tuile (cellules alignées sur la pente) + nuances douces.
	vec2 cell = floor(vec2(u, v) / tile_size);
	float h = hash3(vec3(cell, 3.7));
	float soft = fbm(world_pos * 0.8 + vec3(2.1));
	vec3 col = base * (1.0 + (h - 0.5) * tint_variation * 2.0);
	col *= 0.92 + soft * 0.16;
	// Légère dérive de teinte (bleuté / brun) d'une tuile à l'autre.
	col *= mix(vec3(0.97, 0.99, 1.04), vec3(1.04, 1.0, 0.95), hash3(vec3(cell, 9.1)));

	// Coulures : bruit très étiré dans le sens de la pente.
	float streak = fbm(vec3(u * 9.0, v * 0.35, 1.3));
	float run = smoothstep(0.45, 0.8, streak) * streaks;
	col *= 1.0 - run * 0.5;

	// Poussière claire sur les rangs (faces qui regardent le ciel).
	float up = smoothstep(0.3, 0.9, world_nrm.y);
	float d = smoothstep(0.35, 0.75, fbm(world_pos * 1.7 + vec3(5.3))) * dust * up;
	col = mix(col, dust_color.rgb * (0.85 + soft * 0.3), d * 0.55);

	// Lichens jaunis, en petites taches groupées par plaques.
	float plaque = smoothstep(0.5, 0.72, fbm(world_pos * 0.55 + vec3(8.8)));
	float dots = smoothstep(0.55, 0.75, vnoise(world_pos * 9.0));
	float lich = plaque * dots * lichen_amount * up;
	col = mix(col, lichen_color.rgb * (0.8 + h * 0.3), lich);
	// Mousse dans les creux, très discrète.
	float moss = smoothstep(0.6, 0.8, fbm(world_pos * 1.1 + vec3(1.7))) * moss_amount * up;
	col = mix(col, moss_color.rgb, moss * 0.6);

	ALBEDO = col;
	// Émail : brillant là où il est intact, mat sous la poussière et les lichens.
	float wear = clamp(d + lich + run * 0.5 + moss, 0.0, 1.0);
	ROUGHNESS = mix(mix(0.85, 0.32, glaze) + (h - 0.5) * 0.12, 0.9, wear);
	SPECULAR = mix(0.3, 0.55, glaze * (1.0 - wear));
}
