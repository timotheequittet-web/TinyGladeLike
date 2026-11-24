class_name Blossom
## Arbre « peint » : le tronc du modèle Blender, et sa couronne refaite en cartes face caméra
## (shaders/blossom.gdshader). Les cartes suivent la surface des boules du modèle et en gardent les normales.
## Cerisiers (touffes de fleurs, palette rose), érables (feuilles à cinq pointes) et chênes (feuilles ovales)
## gardent les couleurs de sommets de leur modèle.

const SHADER := preload("res://shaders/blossom.gdshader")
const COVER := 5.0           # recouvrement : cartes ≈ COVER × surface de la boîte / taille² (~750 pour un cerisier)
const INNER := 0.33          # part de cartes plus sombres en retrait : bouchent les trous, donnent de la profondeur
const SIZE := Vector2(0.9, 1.4)   # demi-taille d'une carte (m) pour une couronne de cerisier : de grosses touffes lisibles
const REF_REACH := 16.0      # diagonale de la couronne de cerisier : les petits buissons ont des cartes plus petites
const BARK_MAX := 0.12       # écorce : aucune composante au-dessus (bruns très sombres des modèles Blender)
const PAINTED := "res://assets/textures/foliage/%s.png"   # touffe peinte par type de carte, si elle existe
const SAKURA := [Color(0.9, 0.6, 0.66), Color(1.0, 0.84, 0.86)]   # cœur, bord au soleil (sRGB)

static var _tex := {}
static var _cache := {}


static func leaf_color(c: Color) -> bool:
	## Feuillage plutôt qu'écorce : assez clair, ou vert même très sombre (le dessous de la couronne du chêne oak_2,
	## ~0.07/0.10/0.01, restait en grosses facettes vertes pleines au milieu des cartes). L'écorce brune a r > g.
	return maxf(c.r, maxf(c.g, c.b)) > BARK_MAX or (c.g > c.r and c.g > c.b * 1.1)


static func build(key: String, arrays: Array, opts := {}) -> Dictionary:
	## {trunk (null sans écorce), crown, mat, box}, mis en cache par clé. Options :
	##   kind = flower | maple | leaf | needle (forme des cartes, flower par défaut) ;
	##   autumn = 0 pour un feuillage qui ne change pas en automne (érables déjà rouges, persistants) ;
	##   palette = [cœur, bord] (sRGB) à la place des couleurs du modèle ;
	##   green_only : seul le vert est feuillage (feuillage sombre, ou corde et papier clairs sur le tronc) ;
	##   card = échelle des cartes, depth = profondeur des cartes en retrait (plateaux plats du pin : petites, peu profondes) ;
	##   cover = recouvrement (COVER par défaut ; moins de cartes, plus grandes, pour une version lointaine) ;
	##   min_y = hauteur sous laquelle rien n'est feuillage (la mousse verte d'un tronc ne fait pas de feuilles) ;
	##   all_leafy : tout le modèle devient cartes (massifs : leurs feuilles sombres restaient en facettes) ;
	##   holes = [[centre, rayon]] (repère du modèle) : creux sans cartes, pour une cabane dans la couronne.
	if _cache.has(key):
		return _cache[key]
	var kind: String = opts.get("kind", "flower")
	var palette: Array = opts.get("palette", [])
	var green_only: bool = opts.get("green_only", false)
	var min_y: float = opts.get("min_y", -1e9)   # sous cette hauteur, pas de feuillage (mousse du tronc)
	var all_leafy: bool = opts.get("all_leafy", false)   # buisson : tout est feuillage, même les feuilles sombres
	var depth: float = opts.get("depth", 1.0)
	var pull: float = opts.get("pull", 0.0)   # rapproche les cartes du centre (0 à 1)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var leafy := func(i: int) -> bool:
		if v[i].y < min_y:
			return false
		if all_leafy:
			return true
		if green_only:
			return col[i].g > col[i].r and col[i].g > col[i].b * 1.1
		return leaf_color(col[i])
	# tronc : les triangles sans sommet de feuillage
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
	var keep := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if not (leafy.call(idx[t]) or leafy.call(idx[t + 1]) or leafy.call(idx[t + 2])):
			keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
	var crown_ids := PackedInt32Array()
	var box := AABB()
	var holes: Array = opts.get("holes", [])   # [[centre, rayon]] : pas de cartes là (une cabane nichée dans les branches)
	for i in v.size():
		var in_hole := false
		for hl: Array in holes:
			in_hole = in_hole or v[i].distance_to(hl[0]) < float(hl[1])
		if leafy.call(i) and not in_hole:
			box = AABB(v[i], Vector3.ZERO) if crown_ids.is_empty() else box.expand(v[i])
			crown_ids.append(i)
	var ta := arrays.duplicate()
	ta[Mesh.ARRAY_INDEX] = keep
	var trunk: ArrayMesh = null
	if not keep.is_empty():
		trunk = ArrayMesh.new()
		trunk.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)
	# couronne : cartes posées sur des sommets de feuillage tirés au hasard
	var r := RandomNumberGenerator.new()
	r.seed = key.hash()
	var c := box.get_center()
	var reach := box.size.length() * 0.5
	var area := box.size.x * box.size.z + box.size.y * (box.size.x + box.size.z)
	var size: Vector2 = SIZE * clampf(reach * 2.0 / REF_REACH, 0.25, 1.0) * float(opts.get("card", 1.0))
	var count := maxi(60, int(float(opts.get("cover", COVER)) * area / (size.x * size.y)))
	var pal := [(palette[0] as Color).srgb_to_linear(), (palette[1] as Color).srgb_to_linear()] if not palette.is_empty() else []
	if not pal.is_empty() and painted(kind):   # la touffe peinte porte déjà ses couleurs : la palette ne fait plus que l'ombre
		pal = [Color(0.76, 0.66, 0.64), Color(1.04, 0.98, 0.95)]   # ombre chaude : le ciel bleu tirait le rose au lilas
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in int(count * (1.0 + INNER)):
		var i := crown_ids[r.randi() % crown_ids.size()]
		var inner := k >= count
		var out := (v[i] - c).normalized()
		var n := (nrm[i] + out * 0.6).normalized()   # normale de la boule, arrondie vers l'extérieur de l'arbre
		var p := v[i] - nrm[i] * (r.randf_range(0.5, 1.1) if inner else r.randf_range(-0.1, 0.25)) * depth
		p = c + (p - c) * (1.0 - pull)   # massif resserré : pas de cartes isolées qui flottent autour
		# ombre interne : sombre au cœur et dessous, clair au bord et au sommet
		var shade := clampf(0.25 + 0.55 * (p - c).length() / reach + 0.3 * n.y, 0.0, 1.0) * (0.7 if inner else 1.0)
		var base: Color = (pal[0] as Color).lerp(pal[1], shade) if not pal.is_empty() else col[i] * (0.75 + 0.4 * shade)
		# les couleurs de sommets sont stockées sur 8 bits : au-delà de 1, un canal repasse à 0 (rouge éclairci -> cyan)
		base = Color(minf(base.r, 1.0), minf(base.g, 1.0), minf(base.b, 1.0))
		# touffe peinte : elle garde son haut en haut (sa lumière est peinte), à peine inclinée ; sinon tournée au hasard
		var ang := r.randf_range(-0.35, 0.35) if painted(kind) else r.randf() * TAU
		_card(st, p, n, r.randf_range(size.x, size.y), ang, Color(base.r, base.g, base.b, shade))
	st.index()   # coins partagés : 4 sommets par carte au lieu de 6
	var crown := st.commit()
	crown.custom_aabb = box.grow(size.y * 1.5)   # les cartes s'ouvrent dans le shader, hors de la boîte des centres
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("clump_tex", clump_tex(kind))
	m.set_shader_parameter("autumn_k", float(opts.get("autumn", 1.0)))
	_cache[key] = {trunk = trunk, crown = crown, mat = m, box = Geo.arrays_aabb(arrays)}   # box : l'arbre entier (collisions)
	return _cache[key]


static func tuft(kind: String, tint := Color.WHITE) -> Dictionary:
	## Touffe peinte au sol (fleurs des champs) : trois cartes debout, un peu décalées, pied posé à l'origine.
	## {mesh, mat} ; null-safe : {} si la touffe peinte n'existe pas.
	if not painted(kind):
		return {}
	var key := "tuft_" + kind + str(tint)
	if _cache.has(key):
		return _cache[key]
	var r := RandomNumberGenerator.new()
	r.seed = key.hash()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var s := r.randf_range(0.3, 0.42)
		var p := Vector3(r.randf_range(-0.25, 0.25), s * 0.82, r.randf_range(-0.25, 0.25))   # le bas de la peinture touche le sol
		var c := tint * r.randf_range(0.9, 1.05)
		_card(st, p, Vector3.UP, s, 0.0, Color(c.r, c.g, c.b, 1.0))
	st.index()
	var mesh := st.commit()
	mesh.custom_aabb = AABB(Vector3(-0.8, -0.1, -0.8), Vector3(1.6, 1.2, 1.6))
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("clump_tex", clump_tex(kind))
	m.set_shader_parameter("upright", true)
	m.set_shader_parameter("wind", 0.06)
	m.set_shader_parameter("translucency", 0.15)
	_cache[key] = {mesh = mesh, mat = m}
	return _cache[key]


static func _card(st: SurfaceTool, p: Vector3, n: Vector3, s: float, ang: float, color: Color) -> void:
	## Quatre coins au même centre p : le shader les écarte face caméra (UV2). L'UV tourne pour varier la touffe.
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var rot := Transform2D(ang, Vector2.ZERO)
	for j in [0, 1, 2, 0, 2, 3]:
		var cn: Vector2 = corners[j]
		st.set_color(color)
		st.set_normal(n)
		st.set_uv((rot * cn) * 0.5 + Vector2(0.5, 0.5))
		st.set_uv2(Vector2(cn.x, -cn.y) * s)
		st.add_vertex(p)


static func painted(kind: String) -> bool:
	return ResourceLoader.exists(PAINTED % kind)


static func clump_tex(kind: String) -> ImageTexture:
	## Touffe (128 px) : une grosse masse au centre (elle se lit en aplat), des formes plus petites qui festonnent
	## le bord. flower : fleurs à cinq lobes ronds, blanc à rose ; maple : feuilles à cinq pointes ; leaf : ovales ;
	## needle : pinceaux d'aiguilles de pin ; bloom : petites fleurs blanches serrées (massifs : la couleur vient du modèle).
	if _tex.has(kind):
		return _tex[kind]
	if painted(kind):   # touffe peinte (Gemini, détourée par tools/foliage_key.gd), mipmaps pour le découpage alpha
		var pimg := (load(PAINTED % kind) as Texture2D).get_image()
		pimg.decompress()
		pimg.generate_mipmaps()
		_tex[kind] = ImageTexture.create_from_image(pimg)
		return _tex[kind]
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var n := 34 if kind == "flower" else (90 if kind == "bloom" else 60)
	for f in n:
		var d := 0.0 if f == 0 else sqrt(r.randf()) * 44.0
		var a := r.randf() * TAU
		var fc := Vector2(64, 64) + Vector2(cos(a), sin(a)) * d
		var fr := (20.0 if kind == "bloom" else 30.0) if f == 0 else r.randf_range(6.0, 10.0) * (1.0 - d / 90.0) if kind == "bloom" else r.randf_range(9.0, 16.0) * (1.0 - d / 80.0)
		var spin := r.randf() * TAU
		var tone := Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.82, 0.88), r.randf()) if kind == "flower" else Color.WHITE * r.randf_range(0.78, 1.0)
		for y in range(maxi(0, int(fc.y - fr - 1)), mini(sz, int(fc.y + fr + 2))):
			for x in range(maxi(0, int(fc.x - fr - 1)), mini(sz, int(fc.x + fr + 2))):
				var q := Vector2(x, y) - fc
				var inside := false
				match kind:
					"flower", "bloom":   # cinq lobes : un contour de fleur plutôt qu'un rond
						inside = q.length() < fr * (0.82 + 0.18 * cos(5.0 * q.angle() + f))
					"maple":    # cinq pointes marquées
						inside = q.length() < fr * (0.55 + 0.45 * absf(cos(2.5 * (q.angle() + spin))))
					"needle":   # pinceau d'aiguilles : un cœur dense hérissé de pointes fines
						inside = q.length() < fr * (0.4 + 0.6 * absf(cos(4.5 * (q.angle() + spin))) ** 6)
					_:          # feuille ovale tournée au hasard
						var qr := q.rotated(spin)
						inside = f == 0 and q.length() < fr or (qr.x / fr) ** 2 + (qr.y / (fr * 0.5)) ** 2 < 1.0
				if inside:
					var k := q.length() / fr
					img.set_pixel(x, y, Color(tone.r, tone.g * (0.92 + 0.08 * k), tone.b * (0.94 + 0.06 * k), 1.0))
	img.generate_mipmaps()
	_tex[kind] = ImageTexture.create_from_image(img)
	return _tex[kind]
