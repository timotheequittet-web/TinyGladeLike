class_name Nature
extends Node3D
## Végétation, rochers, rivière, cascade, cumulus et montagnes lointaines (les îles flottantes : Islands).

const CHUNK := 80.0
const GRASS_LAYER := 2   # calque de rendu de l'herbe
const TREE_CELL := 6.0   # taille des cases de la grille d'espacement des arbres (tree_room)
const PINE_DARK := Color(0.20, 0.36, 0.25)
const PINE_MID := Color(0.27, 0.45, 0.28)
const SAKURA := Color(0.98, 0.72, 0.80)
const SAKURA_LIGHT := Color(1.0, 0.86, 0.90)
const BARK := Color(0.40, 0.29, 0.22)
const WOOD := {kind = "leaf", cover = 2.6, card = 1.25}   # feuillus des forêts : peu de grandes cartes (des milliers d'arbres)
const SHRUB := {kind = "bloom", autumn = 0.0, all_leafy = true, card = 0.5, cover = 12.0, pull = 0.18}   # massifs fleuris : petites cartes serrées
const MOMI := {kind = "needle", autumn = 0.0, green_only = true, card = 1.15, depth = 0.6}   # cartes du sapin des versants
const MATSU := {kind = "needle", autumn = 0.0, green_only = true, card = 0.45, depth = 0.35}   # cartes du pin taillé

var t: Terrain
var rng := RandomNumberGenerator.new()
var _trunks: Array = []   # [nom du modèle, transformation] des arbres qui reçoivent un tronc et une couronne solides
var _last := []           # dernier arbre posé par _add
var _crowns := {}         # case de TREE_CELL m -> [Vector3(x, z, rayon de couronne)] (tree_room)
var _tree_bodies: Array[RID] = []   # corps physiques des arbres (serveur), libérés à la sortie
var _tree_shapes := []
var _rocks := []
var grass_count := 0   # [clé, tableau de surface, transform] : collisions à la forme exacte
var reed_count := 0    # touffes de roseaux plantées le long de la rivière (vérification)
var _pending := {}   # nom -> {mesh, mat, vis, chunks}


func build(terrain: Terrain) -> void:
	t = terrain
	rng.seed = 2026
	# feuillage caduc (prend les couleurs d'automne) ou persistant (pins, bambous, érables déjà rouges)
	var leafy := func(w: float) -> ShaderMaterial: return Mats.toon(Color.WHITE, {vertex_color = true, wind = w, rim = 0.2, foliage = true})
	var evergreen := func(w: float) -> ShaderMaterial: return Mats.toon(Color.WHITE, {vertex_color = true, wind = w, rim = 0.2})
	# sapins des versants (6 500 sur la carte) : le sapin à étages (momi_1, tools/blender/japan.py) habillé de cartes
	# d'aiguilles peintes comme les autres arbres ; au loin, le même arbre en moins de cartes, plus grandes
	if "--oldtrees" in OS.get_cmdline_user_args() or not Blossom.painted("needle"):   # --oldtrees : comparaison (debug)
		_register("pine", _glb("pine_1"), evergreen.call(0.006), 0.0)
	else:
		var near := Blossom.build("momi_1", Geo.glb("momi_1"), MOMI)
		var far_opts := MOMI.duplicate()
		far_opts.merge({cover = 0.7, card = 2.6}, true)   # loin : peu de grandes cartes, même silhouette
		var far := Blossom.build("momi_1_far", Geo.glb("momi_1"), far_opts)
		var trunk_mat: ShaderMaterial = evergreen.call(0.006)
		_register("pine", near.trunk, trunk_mat, 0.0, _glb("momi_1_shadow"))   # ombre : fût et trois cônes (légère)
		_pending.pine.lod = {mesh = near.trunk, mat = trunk_mat, dist = 60.0}
		_pending.pine.crown = {mesh = near.crown, mat = near.mat, far = {mesh = far.crown, mat = far.mat}}
		_pending.pine.box = near.box
	# arbres « peints » : tronc Blender et couronne en cartes face caméra (Blossom), ombre par la silhouette légère
	var cards := func(nm: String, arrays: Array, opts: Dictionary, shadow: Mesh, vis := 260.0) -> void:
		var bl := Blossom.build(nm, arrays, opts)
		if bl.trunk == null:   # buisson sans écorce : les cartes seules, sans ombre (l'occlusion ambiante suffit)
			_register(nm, bl.crown, bl.mat, vis, shadow)
			_pending[nm].cast = false
		else:
			_register(nm, bl.trunk, evergreen.call(0.006), vis, shadow)
			_pending[nm].crown = {mesh = bl.crown, mat = bl.mat}
		_pending[nm].box = bl.box   # collisions : l'arbre entier, pas le seul tronc
	# feuillus des forêts : les chênes ronds en deux verts, version proche en cartes, au loin moins de cartes plus grandes
	for k in 2:
		var wood := _recolor(_glb("oak_%d" % (k + 2)), [[Color(0.32, 0.5, 0.18), Color(0.44, 0.6, 0.22), Color(0.58, 0.7, 0.28)],
			[Color(0.26, 0.44, 0.2), Color(0.36, 0.54, 0.24), Color(0.5, 0.64, 0.3)]][k])
		var wa := wood.surface_get_arrays(0)
		var wn := Blossom.build("wood%d" % k, wa, WOOD)   # proche : moins de cartes que les chênes isolés (forêt nombreuse)
		var wf_opts := WOOD.duplicate()
		wf_opts.merge({cover = 0.9, card = 2.2}, true)   # loin : une trentaine de grandes cartes, même silhouette
		var wf := Blossom.build("wood%d_far" % k, wa, wf_opts)
		var wmat: ShaderMaterial = evergreen.call(0.004)
		_register("wood%d" % k, wn.trunk, wmat, 0.0, _glb("oak_%d_shadow" % (k + 2)))
		_pending["wood%d" % k].shadow_vis = 50.0   # ombre portée seulement de près : la forêt lointaine s'en passe
		_pending["wood%d" % k].lod = {mesh = wn.trunk, mesh_far = null, mat = wmat, dist = 70.0}   # loin : pas de tronc
		_pending["wood%d" % k].crown = {mesh = wn.crown, mat = wn.mat, far = {mesh = wf.crown, mat = wf.mat}}
		_pending["wood%d" % k].box = wn.box
	for k in 3:
		var oak := _recolor(_glb("oak_%d" % (k + 1)), [Color(0.36, 0.55, 0.2), Color(0.48, 0.64, 0.24), Color(0.62, 0.72, 0.3)])
		cards.call("oak%d" % k, oak.surface_get_arrays(0), {kind = "leaf"}, _glb("oak_%d_shadow" % (k + 1)))
		cards.call("sakura%d" % k, Geo.glb("sakura_%d" % (k + 1)), {palette = Blossom.SAKURA}, _glb("sakura_%d_shadow" % (k + 1)))
	cards.call("bush", Geo.glb("bush_1"), {kind = "leaf"}, null, 160.0)
	_register("rock1", _glb("rock_1"), Mats.toon(Color.WHITE, {vertex_color = true, rim = 0.1}), 260.0)
	_register("rock2", _glb("rock_2"), Mats.toon(Color.WHITE, {vertex_color = true, rim = 0.1}), 260.0)
	for k in 4:   # rocher fait par IA s'il existe, ajusté à chaque variante (sinon rocher Blender)
		var fit := Geo.ia_fit("rocher", Geo.arrays_aabb(Geo.boulder(k)))
		if fit.is_empty():
			_register("boulder%d" % k, Geo.boulder_mesh(k), Mats.toon(Color.WHITE, {vertex_color = true, rim = 0.15}), 200.0)
		else:
			_register("boulder%d" % k, fit.mesh, fit.mat, 200.0)
	_register("flower", _glb("flowers"), leafy.call(0.08), 70.0)
	_register("pebbles", Geo.boulder_mesh(2), Mats.toon(Color.WHITE, {vertex_color = true, rim = 0.1}), 70.0)   # petits galets moussus
	# végétation de jardin (tools/blender/japan.py)
	for n in ["hydrangea_blue", "hydrangea_pink", "azalea_pink", "azalea_red"]:   # massifs fleuris : petites fleurs sur feuillage
		# petites cartes serrées : un massif se lit en fleurs et en feuilles, pas en grosses boules espacées
		cards.call(n, Geo.glb(n), SHRUB, null, 150.0)
	var fern_tf := Blossom.tuft("fern")   # fougère peinte debout (Gemini) ; à défaut, la fougère Blender
	if fern_tf.is_empty():
		_register("fern", _glb("fern"), leafy.call(0.06), 90.0)
	else:
		_register("fern", fern_tf.mesh, fern_tf.mat, 90.0)
		_pending.fern.cast = false
	var reed_tf := Blossom.tuft("reed")   # roseaux et massettes peints (Gemini), plantés à la ligne d'eau (_river_stones)
	if not reed_tf.is_empty():
		_register("reed", reed_tf.mesh, reed_tf.mat, 110.0)
		_pending.reed.cast = false
	_register("iris", _glb("iris"), leafy.call(0.08), 90.0)
	# fleurs des champs : touffes peintes debout (Blossom.tuft) ; à défaut, les fleurs Blender
	for it in [["flowers_meadow", Color.WHITE], ["flowers_warm", Color(1.0, 0.86, 0.74)]]:
		var tf := Blossom.tuft("meadow", it[1])
		if tf.is_empty():
			_register(it[0], _glb(it[0]), leafy.call(0.1), 80.0)
		else:
			_register(it[0], tf.mesh, tf.mat, 80.0)
			_pending[it[0]].cast = false
	_register("bamboo", _glb("bamboo"), evergreen.call(0.004), 260.0)
	for k in 4:   # rouge, cramoisi, orange, jaune doré (couleurs des modèles) ; deux ombres légères suffisent
		cards.call("momiji%d" % k, Geo.glb("momiji_%d" % (k + 1)), {kind = "maple", autumn = 0.0}, _glb("momiji_%d_shadow" % (k % 2 + 1)))
	for k in 2:   # pins noirs taillés en nuages (niwaki) : plateaux d'aiguilles plats, persistants
		cards.call("matsu%d" % k, Geo.glb("matsu_%d" % (k + 1)), MATSU, _glb("matsu_%d" % (k + 1)))
	_register("petal", _petal_mesh(), Mats.toon(Color.WHITE, {vertex_color = true, rim = 0.0, foliage = true}), 70.0)   # pétales -> feuilles mortes
	_accent_trees()    # d'abord les arbres posés à la main : la forêt se range autour d'eux
	_scatter_trees()
	_scatter_ground()
	_river_stones()
	_flora()
	for nm in _pending:
		_emit(nm)
	_trunk_collision()
	_rock_collision()
	_grass()
	_river(Layout.RIVER)
	_river(Layout.RIVER_LOW)
	_pool()
	_waterfall()
	_cumulus()
	_far_mountains()


# ---------------------------------------------------------------- modèles

func _ia_tree(nm: String, proxy: ArrayMesh, wind: float, tint := Color.WHITE, extra := {}) -> Dictionary:
	## Arbre peint fait par IA, à la taille de l'arbre Blender qu'il remplace. Son socle de terre (le bas du concept,
	## ~12 % de la hauteur) est retiré : il pousse dans notre sol. Vent et teinte par arbre comme les autres. {} si absent.
	var box := Geo.arrays_aabb(proxy.surface_get_arrays(0))
	var base := box.size.y * 0.13
	var fit := Geo.ia_fit(nm, AABB(box.position - Vector3(0, base, 0), box.size + Vector3(0, base, 0)))
	if fit.is_empty():
		return {}
	var y0 := box.position.y
	var mesh := Geo.cut_tris(fit.arrays, func(a: Vector3, b: Vector3, c: Vector3) -> bool: return maxf(a.y, maxf(b.y, c.y)) > y0 + 0.02)
	var tex: Texture2D = (fit.mat as ShaderMaterial).get_shader_parameter("albedo_tex")
	var opts := {tex = tex, vertex_color = true, wind = wind, rim = 0.2, flutter = box.size.y * 0.004, flutter_from = box.position.y + box.size.y * 0.4}
	opts.merge(extra, true)
	return {mesh = mesh, mat = Mats.toon(tint, opts)}


func _glb(nm: String) -> ArrayMesh:
	return Geo.glb_mesh(nm)


func _recolor(oak: ArrayMesh, tones: Array) -> ArrayMesh:
	## Les chênes de L'Effacement sont dorés (un soir d'automne). On repeint leur couronne (sommets hauts et clairs)
	## dans d'autres tons, en gardant le dégradé peint : sombre dessous, lumineux au sommet.
	var arr := oak.surface_get_arrays(0)
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var lin := []
	for c in tones:
		lin.append((c as Color).srgb_to_linear())
	for i in cols.size():
		var c := cols[i]
		var v := verts[i]
		if v.y > 2.6 and Blossom.leaf_color(c):   # le feuillage de la couronne, pas les branches
			var shade := clampf(0.55 + c.r / 0.9, 0.75, 1.3)
			var k := fposmod(sin(v.x * 3.1 + v.y * 1.7 + v.z * 2.3) * 43758.5, 1.0)
			var base: Color = lin[0].lerp(lin[1], k) if k < 0.75 else lin[2]
			cols[i] = Color(base.r * shade, base.g * shade, base.b * shade, 1.0)
	arr[Mesh.ARRAY_COLOR] = cols
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out

func _petal_mesh() -> ArrayMesh:
	return Geo.merge([[Geo.cyl(0.07, 0.07, 0.01, 5), Geo.at(Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1, 1, 0.65)), Color.WHITE]])


func _grass_mesh(lite := false) -> ArrayMesh:
	## Touffe de 20 brins fins en trois segments qui se courbent vers l'extérieur : un pré doux et serré,
	## plutôt que de grands triangles. Chaque brin a sa nuance (le pré se lit en brins, pas en moquette).
	## lite : les mêmes brins en un seul triangle (herbe lointaine, réglage Qualité) — 20 triangles au lieu de 100.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in 20:
		var a := r.randf() * TAU
		var out := Vector3(cos(a), 0, sin(a))
		var off := out * sqrt(r.randf()) * 0.32
		var h := r.randf_range(0.18, 0.42)
		var w := r.randf_range(0.03, 0.05)   # brins larges : le pré couvre le sol sans un triangle de plus
		var ba := a + PI * 0.5 + r.randf_range(-0.4, 0.4)
		var side := Vector3(cos(ba), 0, sin(ba)) * w
		var bend := r.randf_range(0.12, 0.35)
		var p1 := off + out * h * bend * 0.15 + Vector3.UP * h * 0.45
		var p2 := off + out * h * bend * 0.55 + Vector3.UP * h * 0.8
		var tip := off + out * h * bend + Vector3.UP * h
		var shade := r.randf_range(0.7, 1.0)
		st.set_color(Color(shade, shade, shade))
		# normale bombée : face du brin, inclinée vers chaque bord (le brin paraît arrondi)
		var face := side.cross(tip - off).normalized()
		if face.y < 0.0:
			face = -face
		var sd := side.normalized()
		var verts := [off - side, off + side, p1 + side * 0.75, off - side, p1 + side * 0.75, p1 - side * 0.75,
				p1 - side * 0.75, p1 + side * 0.75, p2 + side * 0.4, p1 - side * 0.75, p2 + side * 0.4, p2 - side * 0.4,
				p2 - side * 0.4, p2 + side * 0.4, tip]
		if lite:
			verts = [off - side, off + side, tip]
		for vtx: Vector3 in verts:
			var across: float = (vtx - off).dot(sd) / w
			st.set_normal((face + sd * clampf(across, -1.0, 1.0) * 0.8).normalized())
			st.add_vertex(vtx)
	return st.commit()

# ---------------------------------------------------------------- dispersion

func _register(nm: String, mesh: Mesh, mat: Material, vis: float, shadow: Mesh = null) -> void:
	_pending[nm] = {mesh = mesh, mat = mat, vis = vis, shadow = shadow, chunks = {}, colors = {}}


func _add(nm: String, xf: Transform3D, color := Color.WHITE) -> void:
	var key := Vector2i(floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK))
	var e: Dictionary = _pending[nm]
	if not e.chunks.has(key):
		e.chunks[key] = []
		e.colors[key] = []
	e.chunks[key].append(xf)
	e.colors[key].append(color)
	_last = [nm, xf]


func plant(list: Array) -> Node3D:
	## Végétation ajoutée en cours de partie (embellissement de l'onsen) : [[nom, xf], …] -> un nœud de MultiMesh.
	var root := Node3D.new()
	add_child(root)
	for e: Dictionary in _pending.values():
		e.chunks = {}
		e.colors = {}
	for it: Array in list:
		_add(it[0], it[1])
	for nm: String in _pending:
		if not _pending[nm].chunks.is_empty():
			_emit(nm, root)
	return root


func _emit(nm: String, parent: Node = null) -> void:
	## Un MultiMesh par bloc, placé au centre du bloc : la portée de visibilité se mesure depuis là.
	var e: Dictionary = _pending[nm]
	for key in e.chunks:
		var list: Array = e.chunks[key]
		var origin := Vector3((key.x + 0.5) * CHUNK, 0, (key.y + 0.5) * CHUNK)
		# passes : [maillage, matériau, ombre, début et fin de la portée, groupe de bascule] ; « lod » = version légère
		# au-delà de lod.dist (groupes lod_near / lod_far, réglés par set_quality)
		var shade := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if e.shadow or not e.get("cast", true) or nm in ["flower", "petal", "pebbles"] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var split: float = e.lod.dist if e.has("lod") else e.vis
		var passes := [[e.mesh, e.mat, shade, 0.0, split, "lod_near" if e.has("lod") else ""]]
		if e.shadow:
			passes.append([e.shadow, e.mat, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, 0.0, e.get("shadow_vis", e.vis), ""])   # ombre légère des gros arbres
		if e.has("lod"):
			if e.lod.get("mesh_far", e.lod.mesh) != null:   # (un tronc caché par sa couronne au loin : on ne le dessine pas)
				passes.append([e.lod.get("mesh_far", e.lod.mesh), e.lod.mat, shade, split, e.vis, "lod_far"])
		if e.has("crown"):   # cartes face caméra : sans ombre propre (elles se tourneraient vers le soleil)
			var off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if e.crown.has("far"):   # même arbre, moins de cartes plus grandes au loin : la bascule ne se voit pas
				passes.append([e.crown.mesh, e.crown.mat, off, 0.0, split, "lod_near"])
				passes.append([e.crown.far.mesh, e.crown.far.mat, off, split, e.vis, "lod_far"])
			else:
				passes.append([e.crown.mesh, e.crown.mat, off, 0.0, e.vis, ""])
		for ps in passes:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = ps[0]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i].translated(-origin))
				mm.set_instance_color(i, e.colors[key][i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.position = origin
			mmi.material_override = ps[1]
			mmi.cast_shadow = ps[2]
			mmi.visibility_range_begin = ps[3]
			if ps[4] > 0.0:
				mmi.visibility_range_end = ps[4]
				# marge seulement en fin de portée : à une bascule, elle gardait l'ancienne version 20 m de trop
				# par-dessus la nouvelle (deux sapins l'un dans l'autre)
				mmi.visibility_range_end_margin = 20.0 if ps[5] != "lod_near" else 0.0
			# pas de fondu : en fondu, Godot passe nos matériaux en transparent et sort des pixels NaN (carrés noirs
			# étalés par le halo, partout quand on survole le village en balai) ; la brume de distance masque l'apparition
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			if ps[5] != "":
				mmi.add_to_group(ps[5])   # bascule réglée par set_quality
			(parent if parent else self).add_child(mmi)


func set_quality(grass_split: float, grass_end: float, tree_lod: float) -> void:
	## Réglage Qualité : où l'herbe passe en touffes légères, où elle s'arrête, où les sapins passent au modèle léger.
	## Haute : grass_split = grass_end (pas d'herbe légère).
	for m: GeometryInstance3D in get_tree().get_nodes_in_group("grass_near"):
		m.visibility_range_end = grass_split
		m.visibility_range_end_margin = 0.0 if grass_split < grass_end else 10.0
	for m: GeometryInstance3D in get_tree().get_nodes_in_group("grass_far"):
		m.visible = grass_split < grass_end
		m.visibility_range_begin = grass_split
		m.visibility_range_end = grass_end
	for m: GeometryInstance3D in get_tree().get_nodes_in_group("lod_near"):
		m.visibility_range_end = tree_lod
	for m: GeometryInstance3D in get_tree().get_nodes_in_group("lod_far"):
		m.visibility_range_begin = tree_lod
	for e: Dictionary in _pending.values():
		if e.has("lod"):
			e.lod.dist = tree_lod   # pour la végétation plantée plus tard (plant)


func ground(x: float, z: float) -> Vector3:
	return Vector3(x, t.height_at(x, z), z)


func tree_room(p: Vector2, crown: float) -> bool:
	## Place pour un arbre de rayon de couronne « crown » (m) : sa couronne ne touche aucun bâtiment ni la couronne
	## d'un arbre déjà planté (elles se traversaient). Si oui, la place est retenue.
	if near_slot(p, crown + 1.0) or t.build_at(p.x, p.y) > 0.3:
		return false
	var cell := Vector2i(floori(p.x / TREE_CELL), floori(p.y / TREE_CELL))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for o: Vector3 in _crowns.get(cell + Vector2i(dx, dz), []):
				if p.distance_to(Vector2(o.x, o.y)) < (crown + o.z) * 0.8:   # un peu de chevauchement : une forêt dense
					return false
	if not _crowns.has(cell):
		_crowns[cell] = []
	_crowns[cell].append(Vector3(p.x, p.y, crown))
	return true


func near_slot(p: Vector2, margin: float) -> bool:
	for s in Layout.slots():
		var r := 16.0 if s.kind in ["onsen", "bath"] else (13.0 if s.kind == "treehouse" else 8.0)   # la couronne du cerisier géant fait 25 m
		if p.distance_to(s.p) < r + margin:
			return true
	return p.distance_to(Layout.VILLAGE_BOARD) < 6.0 + margin or p.distance_to(Layout.SHOP.p) < 5.0 + margin


func shade(p: Vector2) -> float:
	## 1 sous le cœur d'une couronne, 0 à découvert (sous-bois : herbe plus rase et plus clairsemée).
	var cell := Vector2i(floori(p.x / TREE_CELL), floori(p.y / TREE_CELL))
	var best := 0.0
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for o: Vector3 in _crowns.get(cell + Vector2i(dx, dz), []):
				best = maxf(best, 1.0 - smoothstep(o.z * 0.5, o.z * 1.1, p.distance_to(Vector2(o.x, o.y))))
	return best


func _forest_density(p: Vector2, h: float, ny: float) -> float:
	var d := 0.55 + t.noise.get_noise_2dv(p * 2.2) * 0.6
	d -= (1.0 - smoothstep(55.0, 85.0, p.distance_to(Vector2(62, 88)))) * 0.55   # village : clairsemé
	d -= (1.0 - smoothstep(18.0, 30.0, p.distance_to(Vector2(-6, 74)))) * 0.8      # place
	d += smoothstep(0.95, 0.7, ny) * 0.2                                            # pentes boisées comme sur le concept
	d *= 1.0 - smoothstep(70.0, 95.0, h)                                            # limite des arbres
	return d


func _tree(kind: String, pos: Vector3, sz: float) -> void:
	var xf := Geo.at(pos, Vector3(0, rng.randf() * TAU, 0), Vector3.ONE * sz)
	match kind:
		"pine":
			_add("pine", xf, Color(1, 1, 1).lerp(Color(0.85, 0.95, 0.9), rng.randf()))
		"oak":
			_add("oak%d" % (rng.randi() % 3), xf, Color(1, 1, 1).lerp(Color(0.92, 1.0, 0.85), rng.randf()))
		"wood":
			_add("wood%d" % (rng.randi() % 2), xf, Color(1, 1, 1).lerp(Color(0.9, 1.0, 0.82), rng.randf()))
		"sakura":
			_add("sakura%d" % (rng.randi() % 3), xf, Color(1, 1, 1).lerp(Color(1.0, 0.94, 0.97), rng.randf()))
			var tree := _last
			_petal_carpet(pos, 4.5 * sz)
			_last = tree   # le tapis de pétales ne compte pas comme arbre


func _scatter_trees() -> void:
	var step := 4.8
	var x := -Layout.HALF
	while x < Layout.HALF:
		var z := -Layout.HALF
		while z < Layout.HALF:
			var p := Vector2(x + rng.randf() * step, z + rng.randf() * step)
			z += step
			var h := t.height_at(p.x, p.y)
			var ny := t.normal_at(p.x, p.y).y
			if h < 1.0 or ny < 0.42 or t.clear_at(p.x, p.y) > 0.2 or t.path_at(p.x, p.y) > 0.05:
				continue
			if t.river_at(p.x, p.y) < Layout.RIVER_HALF_WIDTH + 3.5 or near_slot(p, 2.0):
				continue
			if p.x < Terrain.shore_x(p.y) + 12.0:
				continue
			if rng.randf() > _forest_density(p, h, ny):
				continue
			var pos := Vector3(p.x, h - 0.2, p.y)
			var sk := Terrain.in_sakura(p)
			var r := rng.randf()
			_last = []
			# taille d'abord, puis la place de sa couronne (ni dans une maison, ni à travers un voisin)
			if r < sk * 0.6:
				var s := rng.randf_range(0.75, 1.0)
				if rng.randf() < 0.5 and tree_room(p, 4.8 * s):   # les cerisiers sont larges : on en garde un sur deux
					_tree("sakura", pos, s)
			elif r < sk * 0.6 + 0.1 and h < 30.0 and ny > 0.8:
				var s := rng.randf_range(0.4, 0.55)
				if tree_room(p, 5.5 * s):
					_tree("oak", pos, s)
			elif h > 55.0 or rng.randf() < 0.12:
				# sapins : en altitude, et quelques-uns fins parmi les feuillus (pas des masses sombres en rangées)
				var s := rng.randf_range(0.7, 1.0)
				if tree_room(p, 2.7 * s):
					_tree("pine", pos, s)
			else:
				# forêt des versants : feuillus ronds en bosquets (vert au printemps, roux et dorés en automne),
				# comme les collines des décors de Ghibli ; une grande clairière de temps en temps
				if t.noise.get_noise_2dv(p * 1.7 + Vector2(40, 10)) < -0.45:
					continue
				# grands feuillus (~10 m) : la couronne passe au-dessus de la tête, on se balade entre les troncs
				var s := rng.randf_range(0.85, 1.15)
				if tree_room(p, 4.6 * s):   # couronnes qui se touchent : une voûte, pas un mur
					_tree("wood", pos, s)
			if ny > 0.7 and not _last.is_empty():   # (un cerisier sur deux est sauté)
				_trunks.append(_last)
		x += step


func _accent_trees() -> void:
	## Cerisiers posés à la main : ils encadrent les vues importantes (comme sur les concepts).
	for p in [Vector2(-30, -52), Vector2(30, -40), Vector2(-24, -6), Vector2(22, -10), Vector2(-33, -28),
			Vector2(7, 30), Vector2(-14, 40), Vector2(10, 82), Vector2(-22, 62), Vector2(48, 110), Vector2(78, 72),
			Vector2(102, 104), Vector2(56, 140), Vector2(-46, 90), Vector2(112, -88), Vector2(-188, -124)]:
		if t.river_at(p.x, p.y) < Layout.RIVER_HALF_WIDTH + 2.5 or t.height_at(p.x, p.y) < Layout.SEA_Y + 1.0:
			continue   # jamais les pieds dans l'eau
		var s := rng.randf_range(0.95, 1.12)
		if not tree_room(p, 4.8 * s):
			continue
		var pos := ground(p.x, p.y) - Vector3(0, 0.2, 0)
		_tree("sakura", pos, s)
		_trunks.append(_last)
	## Pins taillés en nuages aux seuils : arrivée de l'onsen, haut et bas de l'escalier, place, Grand-rue,
	## chemin du camphrier, belvédère — penchés vers le passage, comme dans les jardins de temple.
	for p in [Vector2(-8, -3), Vector2(8.5, -12), Vector2(6, 8), Vector2(-13, 52), Vector2(3.5, 57), Vector2(-19, 79),
			Vector2(12, 79), Vector2(22, 68), Vector2(-29, 115), Vector2(-96, -142), Vector2(-60, 70)]:
		var s := rng.randf_range(0.9, 1.1)
		if t.path_at(p.x, p.y) > 0.05 or t.river_at(p.x, p.y) < Layout.RIVER_HALF_WIDTH + 2.5 or not tree_room(p, 3.5 * s):
			continue
		var xf := Geo.at(ground(p.x, p.y) - Vector3(0, 0.2, 0), Vector3(0, rng.randf() * TAU, 0), Vector3.ONE * s)
		_add("matsu%d" % (rng.randi() % 2), xf)
		_trunks.append(_last)


func _scatter_ground() -> void:
	## Rochers, buissons, fleurs ; cailloux le long des chemins. L'herbe a son propre système (_grass).
	var step := 2.2
	var x := -Layout.HALF
	while x < Layout.HALF:
		var z := -Layout.HALF
		while z < Layout.HALF:
			var p := Vector2(x + rng.randf() * step, z + rng.randf() * step)
			z += step
			var h := t.height_at(p.x, p.y)
			var ny := t.normal_at(p.x, p.y).y
			if h < 0.8 or h > 90.0 or t.river_at(p.x, p.y) < Layout.RIVER_HALF_WIDTH:
				continue
			var path := t.path_at(p.x, p.y)
			var pos := Vector3(p.x, h, p.y)
			var yaw := Vector3(0, rng.randf() * TAU, 0)
			var rock_p := 0.004 + smoothstep(0.8, 0.6, ny) * 0.01 + (0.04 if t.river_at(p.x, p.y) < Layout.RIVER_HALF_WIDTH + 3.0 else 0.0)
			if rng.randf() < rock_p and not near_slot(p, 1.0):
				if ny > 0.8:   # dans les prés : rochers ronds moussus ; dans les pentes : roche anguleuse
					var v := rng.randi() % 4
					var xf := Geo.at(pos - Vector3(0, 0.15, 0), yaw, Vector3.ONE * rng.randf_range(0.6, 1.8))
					_add("boulder%d" % v, xf)
					_rocks.append(["boulder%d" % v, Geo.boulder(v), xf])
				else:
					var nm := "rock_1" if rng.randf() < 0.5 else "rock_2"
					var xf := Geo.at(pos - Vector3(0, 0.2, 0), yaw, Vector3.ONE * rng.randf_range(0.5, 1.6))
					_add(nm.replace("_", ""), xf)
					_rocks.append([nm, Geo.glb(nm), xf])
				continue
			if ny < 0.8 or near_slot(p, -4.0):
				continue
			if path > 0.15 and path < 0.6 and rng.randf() < 0.18:   # cailloux en bord de chemin
				_add("pebbles", Geo.at(pos - Vector3(0, 0.05, 0), yaw, Vector3.ONE * rng.randf_range(0.18, 0.4)))
				continue
			if path > 0.05:
				continue
			if rng.randf() < 0.014 and t.clear_at(p.x, p.y) < 0.5:
				_add("bush", Geo.at(pos, yaw, Vector3.ONE * rng.randf_range(0.7, 1.3)))
			elif rng.randf() < 0.035 + Terrain.in_sakura(p) * 0.06:
				_add("flower", Geo.at(pos, yaw, Vector3.ONE * rng.randf_range(0.8, 1.4)))
		x += step


## Bosquets de bambous : centre (x, z), rayon.
const BAMBOO_GROVES := [[Vector2(96, 28), 12.0], [Vector2(110, -62), 10.0], [Vector2(-62, 128), 13.0], [Vector2(48, -112), 9.0], [Vector2(130, 120), 12.0]]
## Érables rouges posés à la main : ils réchauffent les vues (entrée de l'onsen, village, berges).
const MOMIJI := [Vector2(-46, -28), Vector2(44, -48), Vector2(13, 6), Vector2(-17, 9), Vector2(-40, -58), Vector2(20, 96),
	Vector2(70, 100), Vector2(46, 58), Vector2(-28, 84), Vector2(100, 70), Vector2(60, 165), Vector2(120, -78)]


func _flora() -> void:
	## Fleurs, fougères, iris, bambous, érables et massifs de jardin. Générateur à part : les arbres et rochers
	## déjà posés ne bougent pas.
	var vr := RandomNumberGenerator.new()
	vr.seed = 77
	var step := 2.6
	var x := -Layout.HALF
	while x < Layout.HALF:
		var z := -Layout.HALF
		while z < Layout.HALF:
			var p := Vector2(x + vr.randf() * step, z + vr.randf() * step)
			z += step
			var h := t.height_at(p.x, p.y)
			var ny := t.normal_at(p.x, p.y).y
			var rd := t.river_at(p.x, p.y)
			if h < 0.8 or h > 85.0 or rd < Layout.RIVER_HALF_WIDTH + 0.3 or t.path_at(p.x, p.y) > 0.1 or t.build_at(p.x, p.y) > 0.3 or near_slot(p, 0.5):
				continue
			if p.x < Terrain.shore_x(p.y) + 8.0:
				continue
			var pos := Vector3(p.x, h - 0.05, p.y)
			var yaw := Vector3(0, vr.randf() * TAU, 0)
			var grove := false
			for g in BAMBOO_GROVES:
				grove = grove or p.distance_to(g[0]) < g[1]
			if grove and ny > 0.75:
				if vr.randf() < 0.28:
					_add("bamboo", Geo.at(pos - Vector3(0, 0.1, 0), yaw, Vector3.ONE * vr.randf_range(0.8, 1.15)))
					_trunks.append(_last)
				elif vr.randf() < 0.3:
					_add("fern", Geo.at(pos, yaw, Vector3.ONE * vr.randf_range(0.8, 1.3)))
				continue
			if rd < Layout.RIVER_HALF_WIDTH + 3.0 and ny > 0.7:   # berges : iris et fougères
				if vr.randf() < 0.4:
					_add("iris" if vr.randf() < 0.7 else "fern", Geo.at(pos, yaw, Vector3.ONE * vr.randf_range(0.8, 1.3)))
				continue
			if ny > 0.55 and ny < 0.9 and h < 70.0:   # sous-bois et pentes : fougères
				if vr.randf() < 0.09:
					_add("fern", Geo.at(pos, yaw, Vector3.ONE * vr.randf_range(0.8, 1.5)))
				continue
			if ny > 0.85:   # pétales et feuilles tombés, posés sur l'herbe (plus nombreux près des cerisiers et de l'onsen)
				var near_onsen := 1.0 - smoothstep(30.0, 50.0, p.distance_to(Vector2(0, -40)))
				var fall_k := 0.35 + Terrain.in_sakura(p) * 0.8 + near_onsen * 0.8
				for k in 3:
					if vr.randf() < fall_k * 0.5:
						var q := p + Vector2(vr.randf_range(-1.3, 1.3), vr.randf_range(-1.3, 1.3))
						var r := vr.randf()
						var c: Color = (SAKURA_LIGHT if r < 0.45 else (SAKURA if r < 0.7 else (Color(1, 0.98, 0.94) if r < 0.82 else Color(0.78, 0.5, 0.26)))).srgb_to_linear()
						var tilt := Vector3(vr.randf_range(-0.5, 0.5), vr.randf() * TAU, vr.randf_range(-0.5, 0.5))
						_add("petal", Geo.at(Vector3(q.x, t.height_at(q.x, q.y) + vr.randf_range(0.06, 0.2), q.y), tilt, Vector3.ONE * vr.randf_range(1.0, 1.7)), c)
			if ny > 0.85 and t.clear_at(p.x, p.y) < 0.5:   # prés : massifs de fleurs, quelques érables
				var fd := _forest_density(p, h, ny)
				if fd > 0.25 and fd < 0.6 and h < 40.0 and vr.randf() < 0.008 and tree_room(p, 4.2):
					_add("momiji%d" % (vr.randi() % 4), Geo.at(pos - Vector3(0, 0.15, 0), yaw, Vector3.ONE * vr.randf_range(0.8, 1.05)))
					_trunks.append(_last)
				elif vr.randf() < 0.09 + Terrain.in_sakura(p) * 0.04:   # prés fleuris (2,5 fois plus qu'avant)
					var warm := t.noise.get_noise_2dv(p * 1.5) > 0.0
					_add("flowers_warm" if warm else "flowers_meadow", Geo.at(pos - Vector3(0, 0.03, 0), yaw, Vector3.ONE * vr.randf_range(0.9, 1.25)))
		x += step
	_path_flowers(vr)
	for p in MOMIJI:
		if t.path_at(p.x, p.y) < 0.1 and t.river_at(p.x, p.y) > Layout.RIVER_HALF_WIDTH + 2.5 and tree_room(p, 4.5):
			var pos := ground(p.x, p.y) - Vector3(0, 0.15, 0)
			_add("momiji%d" % (vr.randi() % 4), Geo.at(pos, Vector3(0, vr.randf() * TAU, 0), Vector3.ONE * vr.randf_range(0.95, 1.15)))
			_trunks.append(_last)
	_gardens(vr)


func _river_stones() -> void:
	## Rivière peinte : pierres moussues à moitié dans l'eau le long des berges, et quelques rochers dans le courant
	## (le shader d'eau dessine l'écume autour de tout ce qui perce la surface). Jamais sous les ponts.
	var r := RandomNumberGenerator.new()
	r.seed = 404
	for raw: Array in [Layout.RIVER_LOW]:
		var pts := Terrain.smooth(raw, 8)
		var along := 0.0
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var dir := Vector2(b.x - a.x, b.z - a.z)
			var seg := dir.length()
			dir = dir.normalized()
			var side := Vector2(-dir.y, dir.x)
			var d := along
			while d < along + seg:
				var u := (d - along) / seg
				var c := Vector2(lerpf(a.x, b.x, u), lerpf(a.z, b.z, u))
				var wl := lerpf(a.y, b.y, u)
				d += r.randf_range(1.3, 2.8)
				if wl < Layout.SEA_Y + 0.3:
					continue   # embouchure
				var bridged := false
				for br: Dictionary in Layout.BRIDGES:
					bridged = bridged or c.distance_to(br.p) < br.len * 0.6
				if bridged:
					continue
				var hw := Layout.RIVER_HALF_WIDTH * t.river_width(c)
				var roll := r.randf()
				var q: Vector2
				var s: float
				if roll < 0.24:      # au bord : à cheval sur la ligne d'eau
					q = c + side * (1.0 if r.randf() < 0.5 else -1.0) * hw * r.randf_range(0.75, 1.0)
					s = r.randf_range(0.6, 1.25)
				elif roll < 0.3:     # dans le courant
					q = c + side * r.randf_range(-0.5, 0.5) * hw
					s = r.randf_range(0.5, 0.9)
				else:                # roseaux en touffes, les pieds dans l'eau au bord (côté anses surtout)
					if _pending.has("reed") and r.randf() < 0.45 + 0.5 * smoothstep(0.8, 1.25, t.river_width(c)):
						var sgn := 1.0 if r.randf() < 0.5 else -1.0
						for k in r.randi_range(1, 3):
							var rq := c + side * sgn * hw * r.randf_range(0.8, 1.05) + dir * r.randf_range(-1.2, 1.2)
							var rs := r.randf_range(2.6, 3.6)   # 1,8 à 2,5 m : des roseaux, pas des touffes d'herbe
							_add("reed", Geo.at(Vector3(rq.x, wl - 0.15, rq.y), Vector3(0, r.randf() * TAU, 0), Vector3.ONE * rs))
							reed_count += 1
					continue
				var v := r.randi() % 4
				# le rocher Blender a son centre à mi-hauteur : base sous l'eau, le dos moussu en sort d'un tiers
				var xf := Geo.at(Vector3(q.x, wl - s * 0.05, q.y), Vector3(r.randf_range(-0.2, 0.2), r.randf() * TAU, 0), Vector3(s, s * r.randf_range(0.7, 0.95), s))
				_add("boulder%d" % v, xf)
				_rocks.append(["boulder%d" % v, Geo.boulder(v), xf])
			along += seg


func _path_flowers(vr: RandomNumberGenerator) -> void:
	## Bordure fleurie des chemins (image de référence : le sentier entre deux talus de marguerites et de boutons d'or).
	## Des touffes en lisière, de chaque côté, en paquets irréguliers ; jamais sur le chemin, les bâtiments ou l'eau.
	for path: Array in Layout.PATHS:
		for i in path.size() - 1:
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var along := (b - a).normalized()
			var side := Vector2(-along.y, along.x)
			var d := 0.0
			while d < a.distance_to(b):
				d += vr.randf_range(0.6, 1.3)
				for sgn: float in [-1.0, 1.0]:
					if vr.randf() < 0.3:   # des trous : la bordure respire
						continue
					# du centre du chemin, on s'écarte jusqu'à sa lisière (largeur variable), puis un peu dans l'herbe
					var c := a + along * d
					var off := 1.0
					# (0,3 : là où terrain.gdshader cesse de peindre la terre ; le masque déborde un peu dans l'herbe)
					while off < 8.0 and t.path_at(c.x + side.x * sgn * off, c.y + side.y * sgn * off) > 0.3:
						off += 0.3
					var q := c + side * sgn * (off + vr.randf_range(0.1, 1.4))
					# (le masque de construction suffit : near_slot réserve 16 m autour des bassins, la lisière resterait nue)
					if t.path_at(q.x, q.y) > 0.3 or t.build_at(q.x, q.y) > 0.3 or t.river_at(q.x, q.y) < Layout.RIVER_HALF_WIDTH + 0.5:
						continue
					if t.normal_at(q.x, q.y).y < 0.8:
						continue
					var warm := t.noise.get_noise_2dv(q * 1.5) > 0.15
					_add("flowers_warm" if warm else "flowers_meadow", Geo.at(ground(q.x, q.y) - Vector3(0, 0.03, 0), Vector3(0, vr.randf() * TAU, 0), Vector3.ONE * vr.randf_range(0.85, 1.3)))


func _gardens(vr: RandomNumberGenerator) -> void:
	## Massifs plantés : hortensias et azalées le long de l'enceinte de l'onsen et devant les maisons.
	var shrubs := ["hydrangea_blue", "azalea_pink", "hydrangea_pink", "azalea_red"]
	var avoid := []
	for g in OnsenData.GATHER:
		avoid.append(g[1])
	var k := 0
	var a := 0.0
	while a < TAU:   # le long de l'enceinte, à l'intérieur, sauf à la porte et devant les bâtiments
		var p := Vector2(0, -40) + Vector2(cos(a), sin(a)) * 33.8
		a += vr.randf_range(0.16, 0.26)
		if (absf(p.x) < 7.0 and p.y > -14.0) or near_slot(p, -3.0):
			continue
		var ok := true
		for q in avoid:
			ok = ok and p.distance_to(q) > 2.2
		if ok and t.path_at(p.x, p.y) < 0.2:
			_add(shrubs[k % shrubs.size()], Geo.at(ground(p.x, p.y), Vector3(0, vr.randf() * TAU, 0), Vector3.ONE * vr.randf_range(0.9, 1.3)))
			k += 1
	for s in Layout.slots():   # devant les maisons du village, de part et d'autre de l'entrée
		if not s.kind in ["house", "bakery", "bar", "restaurant", "mill"]:
			continue
		var b := Basis(Vector3.UP, s.rot)
		for sx in [-1, 1]:
			var off: Vector3 = b * Vector3(sx * vr.randf_range(2.6, 3.6), 0, 4.6)
			var p := Vector2(s.p.x + off.x, s.p.y + off.z)
			if t.path_at(p.x, p.y) < 0.25 and t.river_at(p.x, p.y) > Layout.RIVER_HALF_WIDTH + 1.0:
				_add(shrubs[vr.randi() % shrubs.size()], Geo.at(ground(p.x, p.y), Vector3(0, vr.randf() * TAU, 0), Vector3.ONE * vr.randf_range(0.8, 1.1)))


func _petal_carpet(center: Vector3, radius: float) -> void:
	## Tapis de pétales tombés sous les cerisiers.
	for i in 22:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var x := center.x + cos(a) * r
		var z := center.z + sin(a) * r
		if t.normal_at(x, z).y < 0.8:
			continue
		var c := (SAKURA_LIGHT if rng.randf() < 0.6 else SAKURA).srgb_to_linear()
		_add("petal", Geo.at(Vector3(x, t.height_at(x, z), z), Vector3(0, rng.randf() * TAU, 0), Vector3.ONE * rng.randf_range(0.8, 1.6)), c)


var _grass_m: ArrayMesh
var _grass_mat: ShaderMaterial


func grass_mesh() -> ArrayMesh:
	if _grass_m == null:
		_grass_m = _grass_mesh()
	return _grass_m


func grass_material() -> ShaderMaterial:
	## Matière des prés (partagée avec les îles flottantes).
	if _grass_mat == null:
		_grass_mat = ShaderMaterial.new()
		_grass_mat.shader = preload("res://shaders/grass.gdshader")
		_grass_mat.set_shader_parameter("blade_h", 0.42)
		_grass_mat.set_shader_parameter("noise_tex", Fx.noise_tex())
	return _grass_mat


func _grass() -> void:
	## Prés de L'Effacement : touffes denses par blocs de 32 m, chaque bloc centré sur lui-même (portée de visibilité).
	var mesh := grass_mesh()
	var lite := _grass_mesh(true)
	var mat := grass_material()
	var chunk := 32.0
	var spacing := 1.0 / sqrt(3.6)   # pré dense : on ne voit plus le sol entre les touffes
	var center := Vector2(10, 10)
	var clearings := []   # emplacements sans plancher (cabane perchée) : l'herbe pousse jusqu'au tronc
	for s in Layout.slots():
		if s.kind == "treehouse":
			clearings.append(s.p)
	var walks := []
	for wk in Layout.ONSEN_WALKS:
		walks.append([wk.a, wk.b])
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var cz := -Layout.HALF
	while cz < Layout.HALF:
		var cx := -Layout.HALF
		while cx < Layout.HALF:
			var cc := Vector2(cx + chunk * 0.5, cz + chunk * 0.5)
			if cc.distance_to(center) > 300.0:
				cx += chunk
				continue
			var xforms := []
			var cols := []
			var z := cz
			while z < cz + chunk:
				var x := cx
				while x < cx + chunk:
					var p := Vector2(x + r.randf() * spacing, z + r.randf() * spacing)
					x += spacing
					var fade := 1.0 - smoothstep(220.0, 290.0, p.distance_to(center))
					var mask := clampf(0.8 + t.detail.get_noise_2dv(p * 0.25) * 0.5, 0.0, 1.0) * fade
					if r.randf() > mask:
						continue
					var n := t.normal_at(p.x, p.y)
					var built := t.build_at(p.x, p.y) > 0.5
					for c: Vector2 in clearings:
						if p.distance_to(c) < 12.0 and p.distance_to(c) > 3.0:
							built = false
					if n.y < 0.7 or t.path_at(p.x, p.y) > 0.4 or built:
						continue
					var h := t.height_at(p.x, p.y)
					if h < 1.0 or h > 85.0 or t.river_at(p.x, p.y) < Layout.RIVER_HALF_WIDTH + 1.0:
						continue
					var on_deck := false
					if p.y < -35.0 and p.y > -70.0 and absf(p.x) < 30.0:
						for w in walks:
							on_deck = on_deck or Terrain.seg_dist(p, w[0], w[1]).x < 1.8
					if on_deck:
						continue
					var lawn := 0.85 if p.distance_to(Vector2(0, -40)) < 39.0 else 1.0   # pelouse un peu plus rase dans la cour de l'onsen
					var s := r.randf_range(0.85, 1.3) * (0.7 + mask * 0.4) * lerpf(1.0, 0.55, t.path_at(p.x, p.y) * 2.0) * lawn
					var tall := 1.0
					var wild := 0.0   # 1 = pré en friche : hautes herbes longues, plus claires, dorées en automne
					if lawn > 0.9 and t.path_at(p.x, p.y) < 0.05 and t.noise.get_noise_2dv(p * 2.3) > 0.25:
						tall = r.randf_range(1.4, 1.9)   # touffes hautes en îlots : le pré a du relief
					if lawn > 0.9 and t.path_at(p.x, p.y) < 0.02 and t.build_at(p.x, p.y) < 0.1:
						wild = smoothstep(0.15, 0.4, t.noise.get_noise_2dv(p * 0.9 + Vector2(73, 11)))
						tall = lerpf(tall, r.randf_range(2.4, 3.2), wild)   # grandes plaques où l'herbe monte aux genoux
					var sh := shade(p)   # sous-bois : herbe rase et clairsemée, on voit le sol et les troncs
					if r.randf() < sh * 0.45:
						continue
					wild *= 1.0 - sh
					tall = lerpf(tall, 0.7, sh)
					var b := Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s * (1.0 + wild * 0.25), s * r.randf_range(0.8, 1.3) * tall, s * (1.0 + wild * 0.25)))
					xforms.append(Transform3D(b, Vector3(p.x - cc.x, h - 0.05, p.y - cc.y)))
					var tint := clampf(t.noise.get_noise_2dv(p * 0.8) * 0.8 + 0.5, 0.0, 1.0)
					var base := Color(0.11, 0.27, 0.06).lerp(Color(0.24, 0.42, 0.1), tint)   # vert profond et naturel
					base = base.lerp(Color(0.62, 0.6, 0.3), Terrain.in_sakura(p) * 0.4)
					base = base.lerp(Color(0.32, 0.44, 0.14), wild * 0.6)   # friche : vert plus jaune, qui blondit à l'automne
					cols.append(base * r.randf_range(0.85, 1.12))
				z += spacing
			if not xforms.is_empty():
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_colors = true
				mm.mesh = mesh
				mm.instance_count = xforms.size()
				for i in xforms.size():
					mm.set_instance_transform(i, xforms[i])
					mm.set_instance_color(i, cols[i])
				var mmi := MultiMeshInstance3D.new()
				mmi.position = Vector3(cc.x, 0, cc.y)
				mmi.multimesh = mm
				mmi.material_override = mat
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mmi.visibility_range_end = 70.0
				mmi.visibility_range_end_margin = 10.0
				# pas de fondu : en fondu, Godot passe nos matériaux en transparent et sort des pixels NaN (carrés noirs
				# étalés par le halo, partout quand on survole le village en balai) ; la brume de distance masque l'apparition
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
				mmi.layers = GRASS_LAYER   # les guirlandes ne l'éclairent pas (sa translucidité en faisait une nappe jaune)
				mmi.add_to_group("grass_near")
				add_child(mmi)
				# même pré en touffes légères, au-delà de la distance du réglage Qualité (caché en Haute)
				var far := mmi.duplicate() as MultiMeshInstance3D
				var mm2 := MultiMesh.new()
				mm2.transform_format = MultiMesh.TRANSFORM_3D
				mm2.use_colors = true
				mm2.mesh = lite
				mm2.instance_count = xforms.size()
				for i in xforms.size():
					mm2.set_instance_transform(i, xforms[i])
					mm2.set_instance_color(i, cols[i])
				far.multimesh = mm2
				far.visible = false
				far.remove_from_group("grass_near")
				far.add_to_group("grass_far")
				add_child(far)
				grass_count += xforms.size()
			cx += chunk
		cz += chunk

func _rock_collision() -> void:
	for r in _rocks:
		if (r[2] as Transform3D).basis.get_scale().x > 0.7:   # les petits cailloux ne gênent pas
			add_child(Geo.hull_body(r[0], r[1], r[2]))   # forme du rocher Blender, même boîte que le modèle IA affiché


func _trunk_collision() -> void:
	## Arbres solides, à leur vraie taille : tronc sur toute la hauteur, couronne (deux étages pour les sapins, une
	## boule pour les arbres feuillus). En balai on ne traverse plus les feuillages ; les PNJ les contournent.
	## Un corps par arbre, créé dans le serveur physique (pas de nœud) : avec un seul corps de 20 000 formes, chaque
	## contact et chaque rayon des PNJ les passait toutes en revue (jeu figé, tests bloqués).
	var space := get_world_3d().space
	var shapes := {}   # formes partagées par modèle et par taille (arrondie à 5 %)
	for tk: Array in _trunks:
		var nm: String = tk[0]
		var xf: Transform3D = tk[1]
		var s := snappedf(xf.basis.get_scale().x, 0.05)
		var key := "%s@%.2f" % [nm, s]
		if not shapes.has(key):
			var box: AABB = _pending[nm].get("box", (_pending[nm].mesh as Mesh).get_aabb())
			var h := box.end.y * s
			var w := maxf(box.size.x, box.size.z) * s
			var list := []   # [forme, position locale]
			var trunk := CylinderShape3D.new()
			trunk.radius = 0.3 if nm == "bamboo" else 0.45
			trunk.height = h * (1.0 if nm == "bamboo" or nm == "pine" else 0.6)
			list.append([trunk, Vector3(0, trunk.height * 0.5, 0)])
			if nm == "pine":
				var low := CylinderShape3D.new()
				low.radius = w * 0.36
				low.height = h * 0.4
				list.append([low, Vector3(0, h * 0.35, 0)])
				var high := CylinderShape3D.new()
				high.radius = w * 0.2
				high.height = h * 0.35
				list.append([high, Vector3(0, h * 0.72, 0)])
			elif nm != "bamboo":
				var crown := SphereShape3D.new()
				crown.radius = minf(w * 0.42, h * 0.4)
				var c := box.get_center() * s
				list.append([crown, Vector3(c.x, h - crown.radius * 0.9, c.z)])
			shapes[key] = list
			_tree_shapes.append(list)   # garde les formes en vie (le serveur ne garde que leur RID)
		var rot := xf.basis.orthonormalized()
		var rid := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
		for sh: Array in shapes[key]:
			PhysicsServer3D.body_add_shape(rid, (sh[0] as Shape3D).get_rid(), Transform3D(rot, xf.origin + rot * (sh[1] as Vector3)))
		PhysicsServer3D.body_set_space(rid, space)
		_tree_bodies.append(rid)


func _exit_tree() -> void:
	for rid in _tree_bodies:
		PhysicsServer3D.free_rid(rid)
	_tree_bodies.clear()


# ---------------------------------------------------------------- eau

func _river(raw: Array) -> void:
	## Nappe d'eau au niveau de la rivière, plus large que le lit le plus large : son bord visible est là où la berge
	## sort de l'eau (festonné comme la berge, adouci par le shader), jamais le bord droit du ruban.
	var pts := Terrain.smooth(raw, 8)
	if pts[-1].y < 0.12:
		pts = pts.filter(func(p): return p.y > 0.12)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := Layout.RIVER_HALF_WIDTH * 1.4 + 2.5
	var dist := 0.0
	for i in pts.size():
		var a: Vector3 = pts[maxi(i - 1, 0)]
		var b: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var dir := (b - a)
		dir.y = 0.0
		var side := dir.normalized().cross(Vector3.UP) * hw
		if i > 0:
			dist += pts[i].distance_to(pts[i - 1])
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0, dist / 12.0))
		st.add_vertex(pts[i] - side)
		st.set_uv(Vector2(1, dist / 12.0))
		st.add_vertex(pts[i] + side)
	for i in pts.size() - 1:
		var k := i * 2
		st.add_index(k)
		st.add_index(k + 2)
		st.add_index(k + 1)
		st.add_index(k + 1)
		st.add_index(k + 2)
		st.add_index(k + 3)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	# eau claire des rivières peintes : turquoise transparent au bord (on voit les galets), vert-bleu profond au milieu,
	# peu de ciel reflété (vue d'en haut elle virait au gris-blanc), écume fine, bord qui se fond dans la berge
	mi.material_override = Mats.water({flow_speed = 1.2, streaks = 0.35, depth_scale = 1.6, wave = 0.0, ripple = 0.55, ripple_scale = 0.9,
		caustics = 0.35, opacity = 0.35, shallow = Color(0.42, 0.72, 0.62), deep = Color(0.1, 0.33, 0.38),
		sky_reflect = 0.35, sky_tint = Color(0.5, 0.74, 0.82), spec = 0.15, foam_amount = 0.6, shore_width = 0.18, soft_edge = 0.3,
		petals = 0.4, strip_width = hw * 2.0})   # reflet bleu d'eau, pas la nappe gris-lavande du ciel
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _pool() -> void:
	var m := CylinderMesh.new()
	m.top_radius = 15.0
	m.bottom_radius = 15.0
	m.height = 0.01
	m.radial_segments = 32
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = Vector3(120, 2.4, -103)
	mi.material_override = Mats.water({depth_scale = 2.5, wave = 0.03, ripple = 1.2, ripple_scale = 0.6, caustics = 0.25, opacity = 0.72,
		shallow = Color(0.4, 0.78, 0.76), deep = Color(0.1, 0.36, 0.5)})
	add_child(mi)


func _waterfall() -> void:
	var w: Dictionary = Layout.WATERFALL
	var bot: Vector3 = w.bottom
	var mi := MeshInstance3D.new()
	mi.mesh = _fall_mesh(w.top, bot, w.width)
	mi.material_override = _fall_mat()
	add_child(mi)
	# brume et éclaboussures au pied de la cascade
	add_child(Fx.mist(bot + Vector3(0, 1, 0), Vector3(7, 3, 7), 1.0))
	add_child(Fx.splash(bot + Vector3(0, 0.1, 0), 5.0, 160))
	var fog := FogVolume.new()
	fog.size = Vector3(30, 14, 30)
	fog.position = bot + Vector3(0, 4, 4)
	fog.material = Fx.fog_material(0.05, Color(1, 1, 1), 0.2)
	add_child(fog)


func _fall_mat() -> ShaderMaterial:
	return Mats.water({fall = true, flow_speed = 1.6, streaks = 1.0, shallow = Color(0.62, 0.86, 0.9), foam = Color(0.97, 0.99, 1.0)})


func _fall_mesh(top: Vector3, bot: Vector3, width: float) -> ArrayMesh:
	## Nappe d'eau qui part vers l'avant puis tombe (parabole) de top à bot.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 16
	var fwd := Vector3(bot.x - top.x, 0, bot.z - top.z).normalized()
	var side: Vector3 = fwd.cross(Vector3.UP) * width * 0.5
	for r in rows + 1:
		var u := float(r) / rows
		# la nappe d'eau part vers l'avant puis tombe (parabole)
		var p := top + fwd * (sin(u * PI * 0.5) * top.distance_to(Vector3(bot.x, top.y, bot.z))) + Vector3(0, (bot.y - top.y) * u * u, 0)
		var spread := 1.0 + u * 0.25
		st.set_normal(fwd)
		st.set_uv(Vector2(0, u * 4.0))
		st.add_vertex(p - side * spread)
		st.set_uv(Vector2(1, u * 4.0))
		st.add_vertex(p + side * spread)
	for r in rows:
		var k := r * 2
		st.add_index(k)
		st.add_index(k + 2)
		st.add_index(k + 1)
		st.add_index(k + 1)
		st.add_index(k + 2)
		st.add_index(k + 3)
	return st.commit()


# ---------------------------------------------------------------- ciel

func _cumulus() -> void:
	## Grands cumulus en tours sur l'horizon sud (au nord, ce sont les montagnes), comme dans les films Ghibli.
	var mat := Mats.toon(Color(1, 0.98, 0.96), {vertex_color = true, rim = 0.6, detail = 0.0})
	for i in 7:
		var a := lerpf(PI * 0.12, PI * 1.02, (i + rng.randf() * 0.6) / 7.0)
		# au-delà de l'archipel des esprits (mer de l'ouest, jusqu'à ~1000 m) : plus loin, donc plus grands
		var d := rng.randf_range(1080, 1220)
		var h := rng.randf_range(170, 320) * 1.8
		var parts := []
		var layers := 7
		for k in layers:   # base large et plate, puis des bourgeons de plus en plus petits vers le sommet
			var u := float(k) / (layers - 1)
			var rad := h * lerpf(0.34, 0.14, u)
			@warning_ignore("integer_division")
			for b in 3 + (layers - k) / 2:
				var off := Vector3(rng.randf_range(-1, 1) * rad * 0.8, u * h * 0.85, rng.randf_range(-1, 1) * rad * 0.5)
				parts.append([Geo.sphere(rad * rng.randf_range(0.7, 1.0), 12, 8), Geo.at(off, Vector3.ZERO, Vector3(1, 0.8 if k == 0 else 1.0, 1)), Color.WHITE])
		var mi := MeshInstance3D.new()
		mi.mesh = Geo.merge(parts)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(cos(a) * d + 60, 30, sin(a) * d - 60)
		add_child(mi)


func _far_mountains() -> void:
	## Couronne de sommets lointains : l'horizon n'est jamais vide.
	var mat := Mats.toon(Color.WHITE, {vertex_color = true, rim = 0.0})
	for i in 26:
		var a := lerpf(-PI * 0.9, PI * 0.2, float(i) / 25.0)   # de l'ouest au sud-est en passant par le nord
		var d := rng.randf_range(950, 1250)
		var h := rng.randf_range(110, 210)
		var parts := []
		for k in 3:   # trois cônes décalés : silhouette irrégulière plutôt que pyramide
			var hk := h * (1.0 - k * 0.22)
			var off := Vector3(rng.randf_range(-1, 1) * h * 0.5, 0, rng.randf_range(-1, 1) * h * 0.3)
			parts.append([Geo.cyl(0.0, hk * 1.7, hk, 12), Geo.at(off + Vector3(0, hk * 0.5, 0)), Color(0.58, 0.66, 0.78)])
			parts.append([Geo.cyl(0.0, hk * 0.51, hk * 0.3, 12), Geo.at(off + Vector3(0, hk * 0.851, 0)), Color(0.93, 0.95, 1.0)])
		var mi := MeshInstance3D.new()
		mi.mesh = Geo.merge(parts)
		mi.material_override = mat
		mi.position = Vector3(cos(a) * d + 60, -10, sin(a) * d - 60)
		mi.rotation.y = rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
