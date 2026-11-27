@tool
class_name BastideKitNature
extends RefCounted
## Kit nature : les arbres et plantes faits dans Blender pour « L'onsen de la colline »
## (addons/bastide/kit/nature/models, couleurs par sommet), habillés comme dans Onsen.
##
## Un arbre = son tronc (le modèle sans le feuillage) + une couronne « peinte » faite de
## cartes face caméra posées sur les boules de feuillage du modèle (shader
## bastide_crown.gdshader) + une silhouette légère qui ne sert qu'à porter l'ombre.
## Repris de docs/onsen_ref/scripts/blossom.gd et nature.gd.
##
## Tout est calculé une fois par (modèle, réglages, échelle) puis gardé en cache :
## les forêts posent ensuite des centaines d'instances des mêmes maillages. Les
## fonctions peuvent tourner sur un thread de génération (cache protégé).

const MODELS := "res://addons/bastide/kit/nature/models/%s.glb"
const PAINTED := "res://addons/bastide/kit/nature/foliage/%s.png"
const CROWN_SHADER := preload("res://addons/bastide/shaders/bastide_crown.gdshader")
const BARK_SHADER := preload("res://addons/bastide/shaders/bastide_bark.gdshader")

const COVER := 5.0           # recouvrement : cartes ≈ COVER × surface de la boîte / taille²
const INNER := 0.33          # part de cartes plus sombres en retrait (profondeur, pas de trous)
const SIZE := Vector2(0.9, 1.4)   # demi-taille d'une carte (m) pour une couronne de cerisier
const REF_REACH := 16.0      # diagonale de couronne de référence : les petits buissons ont des cartes plus petites
const BARK_MAX := 0.12       # écorce : aucune composante au-dessus (bruns très sombres des modèles)
const SAKURA := [Color(0.9, 0.6, 0.66), Color(1.0, 0.84, 0.86)]   # cœur, bord au soleil (sRGB)

## Réglages des couronnes par famille (voir crown()).
const WOOD := {"kind": "leaf", "cover": 2.6, "card": 1.25}
const SHRUB := {"kind": "bloom", "autumn": 0.0, "all_leafy": true, "card": 0.5, "cover": 12.0, "pull": 0.26}
const MOMI := {"kind": "needle", "autumn": 0.0, "green_only": true, "card": 1.15, "depth": 0.6}
const CONIFER := {"kind": "needle", "autumn": 0.0, "green_only": true, "card": 0.5, "depth": 0.2, "cover": 3.6}
const MATSU := {"kind": "needle", "autumn": 0.0, "green_only": true, "card": 0.45, "depth": 0.35}

## Essences : modèles (variantes), silhouette d'ombre, couronne, hauteur du modèle (m),
## recoloration éventuelle du feuillage (chênes dorés → verts).
const SPECIES := {
	# Conifères dessinés ici (voir conifer_arrays) : quatre variantes, sugi élancés et momi en étages.
	"cedre": {"conifer": ["sugi", "momi", "sugi", "momi"], "opts": CONIFER, "height": 9.7},
	"chene": {"models": ["oak_1", "oak_2", "oak_3"], "shadows": ["oak_1_shadow", "oak_2_shadow", "oak_3_shadow"],
		"opts": WOOD, "height": 11.7, "recolor": [Color(0.36, 0.55, 0.2), Color(0.48, 0.64, 0.24), Color(0.62, 0.72, 0.3)]},
	"hetre": {"models": ["oak_2", "oak_3"], "shadows": ["oak_2_shadow", "oak_3_shadow"],
		"opts": WOOD, "height": 11.4, "recolor": [Color(0.26, 0.44, 0.2), Color(0.36, 0.54, 0.24), Color(0.5, 0.64, 0.3)]},
	"momiji": {"models": ["momiji_1", "momiji_2", "momiji_3", "momiji_4"],
		"shadows": ["momiji_1_shadow", "momiji_2_shadow", "momiji_1_shadow", "momiji_2_shadow"],
		"opts": {"kind": "maple", "autumn": 0.0}, "height": 7.8},
	"sakura": {"models": ["sakura_1", "sakura_2", "sakura_3"], "shadows": ["sakura_1_shadow", "sakura_2_shadow", "sakura_3_shadow"],
		"opts": {"palette": SAKURA}, "height": 7.1},
	"matsu": {"models": ["matsu_1", "matsu_2"], "shadows": ["matsu_1", "matsu_2"], "opts": MATSU, "height": 9.0},
	"camphrier": {"models": ["camphor"], "shadows": ["camphor_shadow"], "opts": WOOD, "height": 14.7},
}

static var _mutex := Mutex.new()
static var _arrays := {}
static var _cache := {}
static var _tex := {}
static var _trunk_mat: ShaderMaterial
static var _plant_mat: StandardMaterial3D


## Tableau de surface (tous les maillages du modèle fusionnés), en cache.
static func arrays(model: String) -> Array:
	_mutex.lock()
	var cached: Variant = _arrays.get(model)
	_mutex.unlock()
	if cached != null:
		return cached
	var out: Array = []
	var ps := load(MODELS % model) as PackedScene
	if ps:
		var inst := ps.instantiate()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_merge_node(inst, Transform3D.IDENTITY, st)
		inst.free()
		out = st.commit_to_arrays()
	_mutex.lock()
	_arrays[model] = out
	_mutex.unlock()
	return out


static func _merge_node(n: Node, xf: Transform3D, st: SurfaceTool) -> void:
	var nxf: Transform3D = xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var m := (n as MeshInstance3D).mesh
		for s in m.get_surface_count():
			st.append_from(m, s, nxf)
	for c in n.get_children():
		_merge_node(c, nxf, st)


## Copie mise à l'échelle (et repeinte si `tones` : feuillage haut et clair) d'un tableau de surface.
static func _scaled(src: Array, scale: float, tones: Array) -> Array:
	var arr := src.duplicate()
	var v: PackedVector3Array = (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var cols: PackedColorArray = (src[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate() if src[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var lin := []
	for c in tones:
		lin.append((c as Color).srgb_to_linear())
	for i in v.size():
		if not lin.is_empty() and i < cols.size() and v[i].y > 2.6 and leaf_color(cols[i]):
			var c := cols[i]
			var shade := clampf(0.55 + c.r / 0.9, 0.75, 1.3)
			var k := fposmod(sin(v[i].x * 3.1 + v[i].y * 1.7 + v[i].z * 2.3) * 43758.5, 1.0)
			var base: Color = (lin[0] as Color).lerp(lin[1], k) if k < 0.75 else lin[2]
			cols[i] = Color(base.r * shade, base.g * shade, base.b * shade, 1.0)
		v[i] *= scale
	arr[Mesh.ARRAY_VERTEX] = v
	if not cols.is_empty():
		arr[Mesh.ARRAY_COLOR] = cols
	return arr


static func leaf_color(c: Color) -> bool:
	## Feuillage plutôt qu'écorce : assez clair, ou vert même très sombre. L'écorce brune a r > g.
	return maxf(c.r, maxf(c.g, c.b)) > BARK_MAX or (c.g > c.r and c.g > c.b * 1.1)


## Arbre d'une essence, à l'échelle donnée (arrondie au dixième pour partager le cache) :
## {trunk: ArrayMesh, crown: ArrayMesh, crown_mat, shadow: ArrayMesh, box: AABB, trunk_r: float, height}.
## `far` : version lointaine (peu de grandes cartes, même silhouette).
static func tree(species: String, variant: int, scale: float, far := false) -> Dictionary:
	var sp: Dictionary = SPECIES.get(species, SPECIES["chene"])
	var models: Array = sp.get("models", sp.get("conifer", []))
	var vi := posmod(variant, models.size())
	var model: String = models[vi]
	var conifer := sp.has("conifer")
	scale = snappedf(scale, 0.1)
	var key := "%s/%d/%.1f/%s" % [species, vi, scale, "far" if far else "near"]
	_mutex.lock()
	var cached: Variant = _cache.get(key)
	_mutex.unlock()
	if cached != null:
		return cached
	var arr := _scaled(conifer_arrays(model, vi, float(sp["height"])) if conifer else arrays(model), scale, sp.get("recolor", []))
	var opts: Dictionary = (sp["opts"] as Dictionary).duplicate()
	# Les cartes grandissent avec l'arbre (sinon un géant demande des dizaines de milliers de cartes).
	opts["card"] = float(opts.get("card", 1.0)) * sqrt(scale)
	if far:
		opts["cover"] = float(opts.get("cover", COVER)) * 0.3
		opts["card"] = float(opts["card"]) * 1.9
	var built := crown(key, arr, opts)
	var shadow_arr := _scaled(conifer_shadow(model, vi, float(sp["height"])) if conifer else arrays((sp["shadows"] as Array)[vi]), scale, [])
	var shadow := ArrayMesh.new()
	if not (shadow_arr as Array).is_empty():
		shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shadow_arr)
	built["shadow"] = shadow
	# Rayon mesuré sur l'écorce seule (le feuillage bas ne compte pas).
	var bark_mesh := built.get("trunk") as ArrayMesh
	built["trunk_r"] = _trunk_radius(bark_mesh.surface_get_arrays(0) if bark_mesh and bark_mesh.get_surface_count() > 0 else arr)
	built["height"] = float(sp["height"]) * scale
	_mutex.lock()
	_cache[key] = built
	_mutex.unlock()
	return built


## Conifère dessiné (pas de modèle Blender) : tronc effilé et étages de branches
## tombantes dont le dessus porte des points de feuillage. crown() pose ensuite les
## cartes d'aiguilles peintes sur ces points, comme pour les autres arbres : même
## style, mais une vraie silhouette de résineux, étagée, avec du vide entre les étages.
##  kind = "sugi" (cryptomère : étroit, très conique, branches qui retombent)
##       | "momi" (sapin : plus large, étages réguliers, bouts relevés).
## Les feuilles sont des triangles dégénérés (trois fois le même point) : seul le
## sommet compte pour crown(), qui les écarte du tronc.
static func conifer_arrays(kind: String, variant: int, height: float) -> Array:
	var key := "conifer/%s/%d/%.1f" % [kind, variant, height]
	_mutex.lock()
	var cached: Variant = _arrays.get(key)
	_mutex.unlock()
	if cached != null:
		return cached
	var r := RandomNumberGenerator.new()
	r.seed = key.hash()
	var sugi := kind == "sugi"
	var h := height * r.randf_range(0.94, 1.06)
	var base_y := h * (0.2 if sugi else 0.14)             # sous le premier étage : tronc nu
	var width := h * (0.19 if sugi else 0.27)             # rayon des branches du bas
	var tiers := (13 if sugi else 10) + r.randi_range(-1, 1)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	# --- Tronc : cône à 9 pans, écorce brun rouge (sugi) ou gris brun (momi) ---
	var bark := Color(0.11, 0.055, 0.035) if sugi else Color(0.085, 0.07, 0.055)
	var tr := h * (0.026 if sugi else 0.022)
	var sides := 9
	var rings := 6
	for j in rings + 1:
		var t := float(j) / rings
		var y := t * h * 0.96
		var rr := tr * (1.0 - t * 0.92) * (1.25 if j == 0 else 1.0)
		for i in sides:
			var a := TAU * i / sides
			var n := Vector3(cos(a), 0.15, sin(a)).normalized()
			verts.append(Vector3(cos(a) * rr, y, sin(a) * rr))
			normals.append(n)
			var c := bark * (0.8 + 0.4 * fposmod(sin(i * 7.1 + j * 3.3) * 43758.5, 1.0))
			cols.append(Color(c.r, c.g, c.b, 1.0))
	for j in rings:
		for i in sides:
			var a := j * sides + i
			var b := j * sides + (i + 1) % sides
			idx.append_array([a, b, a + sides, b, b + sides, a + sides])
	# --- Étages de branches ---
	var dark := Color(0.035, 0.085, 0.045) if sugi else Color(0.03, 0.075, 0.05)
	var mid := Color(0.08, 0.17, 0.07) if sugi else Color(0.06, 0.15, 0.08)
	var tip := Color(0.17, 0.28, 0.09) if sugi else Color(0.13, 0.25, 0.11)
	var leaf := func(p: Vector3, n: Vector3, c: Color) -> void:
		var k := verts.size()
		verts.append(p)
		normals.append(n.normalized())
		cols.append(Color(c.r, c.g, c.b, 1.0))
		idx.append_array([k, k, k])
	for ti in tiers:
		var t := (float(ti) + r.randf_range(-0.3, 0.3)) / float(tiers)
		var y := base_y + (h * 0.97 - base_y) * pow(t, 0.92)
		var u := (y - base_y) / (h - base_y)            # 0 au premier étage, 1 au sommet
		var reach := width * pow(1.0 - u, 0.85 if sugi else 1.0) * r.randf_range(0.85, 1.12) + 0.1
		var branches := 5 + int((1.0 - u) * (4.0 if sugi else 3.0)) + r.randi_range(0, 1)
		var spin := r.randf() * TAU
		for bi in branches:
			var az := spin + TAU * (bi + r.randf_range(-0.25, 0.25)) / branches
			var dir := Vector3(cos(az), 0, sin(az))
			var side := Vector3(-dir.z, 0, dir.x)
			var blen := reach * r.randf_range(0.75, 1.05)
			# Branches qui retombent ; le sapin relève le bout.
			var droop := blen * (0.42 if sugi else 0.3) * r.randf_range(0.7, 1.25)
			var lift := 0.0 if sugi else blen * 0.1
			var pts := maxi(3, int(blen * (5.5 if sugi else 4.5)))
			for k in pts:
				var sb := 0.22 + 0.78 * (float(k) + r.randf()) / pts   # position sur la branche
				var p := Vector3(0, y, 0) + dir * blen * sb
				p.y += -droop * sb * sb + lift * pow(sb, 4.0)
				# Les rameaux s'étalent en éventail, plus larges vers le bout.
				p += side * r.randf_range(-1.0, 1.0) * blen * 0.28 * sb
				p.y += r.randf_range(-0.12, 0.08) * blen * 0.3
				var n := (dir * (0.6 + 0.4 * sb) + Vector3(0, 0.75, 0)).normalized()
				var c: Color = dark.lerp(mid, sb).lerp(tip, maxf(0.0, sb - 0.7) / 0.3 * 0.7)
				# Le haut de l'arbre (pousses de l'année) est plus clair.
				c = c.lerp(tip, u * u * 0.25)
				leaf.call(p, n, c)
			# Dessous de l'étage, sombre : donne l'épaisseur de la jupe.
			for k in maxi(1, pts / 3):
				var sb := r.randf_range(0.3, 0.8)
				var p := Vector3(0, y, 0) + dir * blen * sb
				p.y += -droop * sb * sb - blen * 0.12
				leaf.call(p, (dir * 0.5 + Vector3(0, -0.2, 0)), dark)
	# --- Flèche du sommet ---
	for k in 3:
		var t := float(k) / 2.0
		leaf.call(Vector3(r.randf_range(-0.05, 0.05), h * (0.95 + 0.05 * t), r.randf_range(-0.05, 0.05)),
				Vector3(0, 1, 0), mid)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	_mutex.lock()
	_arrays[key] = arr
	_mutex.unlock()
	return arr


## Silhouette d'ombre d'un conifère : quelques cônes empilés (peu de triangles).
static func conifer_shadow(kind: String, variant: int, height: float) -> Array:
	var key := "conifer_shadow/%s/%d/%.1f" % [kind, variant, height]
	_mutex.lock()
	var cached: Variant = _arrays.get(key)
	_mutex.unlock()
	if cached != null:
		return cached
	var src := conifer_arrays(kind, variant, height)
	var v: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var top := 0.0
	for p in v:
		top = maxf(top, p.y)
	var sugi := kind == "sugi"
	var base_y := top * (0.17 if sugi else 0.11)
	var width := top * (0.17 if sugi else 0.24)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stacks := 4
	var sides := 8
	for s in stacks:
		var y0 := base_y + (top - base_y) * float(s) / stacks
		var y1 := top if s == stacks - 1 else base_y + (top - base_y) * float(s + 1.6) / stacks
		var rr := width * (1.0 - float(s) / stacks)
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			st.add_vertex(Vector3(0, y1, 0))
			st.add_vertex(Vector3(cos(a1) * rr, y0, sin(a1) * rr))
			st.add_vertex(Vector3(cos(a0) * rr, y0, sin(a0) * rr))
	st.generate_normals()
	var arr := st.commit_to_arrays()
	_mutex.lock()
	_arrays[key] = arr
	_mutex.unlock()
	return arr


## Rayon du tronc à hauteur d'homme (sommets d'écorce entre 0,9 et 1,7 m, au-dessus de
## l'évasement des racines), pour les collisions. On prend la médiane des distances à l'axe :
## une branche basse isolée n'élargit pas le cylindre.
static func _trunk_radius(arr: Array) -> float:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var pts: Array[Vector2] = []
	for lo_hi: Vector2 in [Vector2(0.9, 1.7), Vector2(0.1, 1.2)]:
		for i in v.size():
			if v[i].y < lo_hi.y and v[i].y > lo_hi.x:
				pts.append(Vector2(v[i].x, v[i].z))
		if pts.size() >= 6:
			break
	if pts.is_empty():
		return 0.3
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var d: Array[float] = []
	for p in pts:
		d.append(p.distance_to(c))
	d.sort()
	return clampf(d[d.size() / 2], 0.12, 1.0)


## Tronc + couronne en cartes d'un tableau de surface (repris de Blossom.build).
## Options : kind = flower | maple | leaf | needle | bloom ; autumn (0 : ne roussit pas) ;
## palette = [cœur, bord] (sRGB) ; green_only ; card (échelle des cartes) ; depth ;
## cover (recouvrement) ; min_y ; all_leafy ; pull (rapproche les cartes du centre).
static func crown(key: String, arrays_in: Array, opts := {}) -> Dictionary:
	var kind: String = opts.get("kind", "flower")
	var palette: Array = opts.get("palette", [])
	var green_only: bool = opts.get("green_only", false)
	var min_y: float = opts.get("min_y", -1e9)
	var all_leafy: bool = opts.get("all_leafy", false)
	var depth: float = opts.get("depth", 1.0)
	var pull: float = opts.get("pull", 0.0)
	var v: PackedVector3Array = arrays_in[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays_in[Mesh.ARRAY_NORMAL]
	var col: PackedColorArray = arrays_in[Mesh.ARRAY_COLOR]
	var leafy := PackedByteArray()
	leafy.resize(v.size())
	for i in v.size():
		var lf := false
		if v[i].y >= min_y:
			if all_leafy:
				lf = true
			elif green_only:
				lf = col[i].g > col[i].r and col[i].g > col[i].b * 1.1
			else:
				lf = leaf_color(col[i])
		leafy[i] = 1 if lf else 0
	# Tronc : les triangles sans sommet de feuillage.
	var idx: PackedInt32Array = arrays_in[Mesh.ARRAY_INDEX] if arrays_in[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
	var keep := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if leafy[idx[t]] == 0 and leafy[idx[t + 1]] == 0 and leafy[idx[t + 2]] == 0:
			keep.append(idx[t])
			keep.append(idx[t + 1])
			keep.append(idx[t + 2])
	var crown_ids := PackedInt32Array()
	var box := AABB()
	for i in v.size():
		if leafy[i] == 1:
			box = AABB(v[i], Vector3.ZERO) if crown_ids.is_empty() else box.expand(v[i])
			crown_ids.append(i)
	var trunk: ArrayMesh = null
	if not keep.is_empty():
		var ta := arrays_in.duplicate()
		ta[Mesh.ARRAY_INDEX] = keep
		trunk = ArrayMesh.new()
		trunk.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)
	var whole := AABB(v[0], Vector3.ZERO)
	for p in v:
		whole = whole.expand(p)
	if crown_ids.is_empty():
		return {"trunk": trunk, "crown": null, "crown_mat": null, "box": whole}
	# Couronne : cartes posées sur des sommets de feuillage tirés au hasard.
	var r := RandomNumberGenerator.new()
	r.seed = key.hash()
	var c := box.get_center()
	var reach := maxf(box.size.length() * 0.5, 0.01)
	var area := box.size.x * box.size.z + box.size.y * (box.size.x + box.size.z)
	var size: Vector2 = SIZE * clampf(reach * 2.0 / REF_REACH, 0.25, 1.0) * float(opts.get("card", 1.0))
	var count := maxi(60, int(float(opts.get("cover", COVER)) * area / (size.x * size.y)))
	var pal := [(palette[0] as Color).srgb_to_linear(), (palette[1] as Color).srgb_to_linear()] if not palette.is_empty() else []
	if not pal.is_empty() and painted(kind):
		pal = [Color(0.76, 0.66, 0.64), Color(1.04, 0.98, 0.95)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in int(count * (1.0 + INNER)):
		var i := crown_ids[r.randi() % crown_ids.size()]
		var inner := k >= count
		var out := (v[i] - c).normalized()
		var n := (nrm[i] + out * 0.6).normalized()
		var p := v[i] - nrm[i] * (r.randf_range(0.5, 1.1) if inner else r.randf_range(-0.1, 0.25)) * depth
		p = c + (p - c) * (1.0 - pull)
		var shade := clampf(0.25 + 0.55 * (p - c).length() / reach + 0.3 * n.y, 0.0, 1.0) * (0.7 if inner else 1.0)
		var base: Color = (pal[0] as Color).lerp(pal[1], shade) if not pal.is_empty() else col[i] * (0.75 + 0.4 * shade)
		base = Color(minf(base.r, 1.0), minf(base.g, 1.0), minf(base.b, 1.0))
		var ang := r.randf_range(-0.35, 0.35) if painted(kind) else r.randf() * TAU
		_card(st, p, n, r.randf_range(size.x, size.y), ang, Color(base.r, base.g, base.b, shade))
	st.index()
	var crown_mesh := st.commit()
	crown_mesh.custom_aabb = box.grow(size.y * 1.5)
	var m := ShaderMaterial.new()
	m.shader = CROWN_SHADER
	m.set_shader_parameter("clump_tex", clump_tex(kind))
	m.set_shader_parameter("autumn_k", float(opts.get("autumn", 1.0)))
	return {"trunk": trunk, "crown": crown_mesh, "crown_mat": m, "box": whole}


## Touffe peinte au sol (fougère, fleurs des champs, roseaux) : trois cartes debout.
## {mesh, mat} ou {} si la touffe peinte n'existe pas.
static func tuft(kind: String, tint := Color.WHITE, scale := 1.0) -> Dictionary:
	if not painted(kind):
		return {}
	var key := "tuft_%s_%s_%.2f" % [kind, str(tint), scale]
	_mutex.lock()
	var cached: Variant = _cache.get(key)
	_mutex.unlock()
	if cached != null:
		return cached
	var r := RandomNumberGenerator.new()
	r.seed = key.hash()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var s := r.randf_range(0.3, 0.42) * scale
		var p := Vector3(r.randf_range(-0.25, 0.25) * scale, s * 0.82, r.randf_range(-0.25, 0.25) * scale)
		var c := tint * r.randf_range(0.9, 1.05)
		_card(st, p, Vector3.UP, s, 0.0, Color(c.r, c.g, c.b, 1.0))
	st.index()
	var mesh := st.commit()
	mesh.custom_aabb = AABB(Vector3(-0.8, -0.1, -0.8) * scale, Vector3(1.6, 1.2, 1.6) * scale)
	var m := ShaderMaterial.new()
	m.shader = CROWN_SHADER
	m.set_shader_parameter("clump_tex", clump_tex(kind))
	m.set_shader_parameter("upright", true)
	m.set_shader_parameter("wind", 0.06)
	m.set_shader_parameter("translucency", 0.15)
	var out := {"mesh": mesh, "mat": m}
	_mutex.lock()
	_cache[key] = out
	_mutex.unlock()
	return out


## Plante du jardin (hortensia, azalée, iris, fleurs, buisson, bambou) :
## massifs fleuris en petites cartes serrées, les autres en maillage plein.
## {mesh, mat, crown?, crown_mat?}
static func plant(model: String, scale := 1.0) -> Dictionary:
	scale = snappedf(scale, 0.1)
	var key := "plant/%s/%.1f" % [model, scale]
	_mutex.lock()
	var cached: Variant = _cache.get(key)
	_mutex.unlock()
	if cached != null:
		return cached
	var arr := _scaled(arrays(model), scale, [])
	var out := {}
	if model.begins_with("hydrangea") or model.begins_with("azalea"):
		var b := crown(key, arr, SHRUB)
		# Un cœur plein et sombre sous les fleurs : de près, l'arbuste a du volume
		# au lieu d'un nuage de pétales.
		out = {"mesh": b["crown"], "mat": b["crown_mat"], "trunk": _shrub_core(arr)}
	elif model == "bush_1":
		var b := crown(key, arr, {"kind": "leaf"})
		out = {"mesh": b["crown"], "mat": b["crown_mat"], "trunk": b["trunk"]}
	else:
		var mesh := ArrayMesh.new()
		if not arr.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out = {"mesh": mesh, "mat": plant_material()}
	_mutex.lock()
	_cache[key] = out
	_mutex.unlock()
	return out


static func _shrub_core(arr: Array) -> ArrayMesh:
	var v: PackedVector3Array = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	if v.is_empty():
		return null
	var box := AABB(v[0], Vector3.ZERO)
	for p in v:
		box = box.expand(p)
	var pivot := Vector3(box.get_center().x, box.position.y + box.size.y * 0.25, box.get_center().z)
	for i in v.size():
		var d := v[i] - pivot
		v[i] = pivot + Vector3(d.x * 0.78, d.y * 0.8, d.z * 0.78)
	var cols := PackedColorArray()
	var src: Variant = arr[Mesh.ARRAY_COLOR]
	cols.resize(v.size())
	for i in v.size():
		var c: Color = (src as PackedColorArray)[i] if src != null and i < (src as PackedColorArray).size() else Color(0.2, 0.3, 0.15)
		# Vert profond tiré de la couleur d'origine (l'écorce l'éclaircit ensuite).
		var g := Color(c.r * 0.25 + 0.03, c.g * 0.35 + 0.07, c.b * 0.25 + 0.03)
		cols[i] = g
	var out := arr.duplicate()
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return m


static func _card(st: SurfaceTool, p: Vector3, n: Vector3, s: float, ang: float, color: Color) -> void:
	## Quatre coins au même centre p : le shader les écarte face caméra (UV2).
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


## Texture d'une touffe : peinte si elle existe (kit/nature/foliage), sinon dessinée ici.
static func clump_tex(kind: String) -> ImageTexture:
	_mutex.lock()
	var cached: Variant = _tex.get(kind)
	_mutex.unlock()
	if cached != null:
		return cached
	var img: Image
	if painted(kind):
		img = (load(PAINTED % kind) as Texture2D).get_image()
		img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
	else:
		img = _draw_clump(kind)
	var tex := ImageTexture.create_from_image(img)
	_mutex.lock()
	_tex[kind] = tex
	_mutex.unlock()
	return tex


static func _draw_clump(kind: String) -> Image:
	## Touffe (128 px) : une grosse masse au centre, des formes plus petites qui festonnent le bord.
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 5
	if kind == "ivy":
		return _draw_ivy()
	var n := 34 if kind == "flower" else (90 if kind == "bloom" else 60)
	for f in n:
		var d := 0.0 if f == 0 else sqrt(r.randf()) * 44.0
		var a := r.randf() * TAU
		var fc := Vector2(64, 64) + Vector2(cos(a), sin(a)) * d
		var fr: float
		if kind == "bloom":
			fr = 20.0 if f == 0 else r.randf_range(6.0, 10.0) * (1.0 - d / 90.0)
		else:
			fr = 30.0 if f == 0 else r.randf_range(9.0, 16.0) * (1.0 - d / 80.0)
		var spin := r.randf() * TAU
		var tone := Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.82, 0.88), r.randf()) if kind == "flower" else Color.WHITE * r.randf_range(0.78, 1.0)
		for y in range(maxi(0, int(fc.y - fr - 1)), mini(sz, int(fc.y + fr + 2))):
			for x in range(maxi(0, int(fc.x - fr - 1)), mini(sz, int(fc.x + fr + 2))):
				var q := Vector2(x, y) - fc
				var inside := false
				match kind:
					"flower", "bloom":
						inside = q.length() < fr * (0.82 + 0.18 * cos(5.0 * q.angle() + f))
					"maple":
						inside = q.length() < fr * (0.55 + 0.45 * absf(cos(2.5 * (q.angle() + spin))))
					"needle":
						inside = q.length() < fr * (0.4 + 0.6 * pow(absf(cos(4.5 * (q.angle() + spin))), 6.0))
					_:
						var qr := q.rotated(spin)
						inside = (f == 0 and q.length() < fr) or pow(qr.x / fr, 2.0) + pow(qr.y / (fr * 0.5), 2.0) < 1.0
				if inside:
					var k := q.length() / fr
					img.set_pixel(x, y, Color(tone.r, tone.g * (0.92 + 0.08 * k), tone.b * (0.94 + 0.06 * k), 1.0))
	img.generate_mipmaps()
	return img


## Feuilles de lierre (128 px) : cinq à sept feuilles à trois lobes pointus, nervure
## centrale plus claire, tons un peu différents (le vert vient des sommets).
static func _draw_ivy() -> Image:
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var centers := [Vector2(64, 60), Vector2(36, 40), Vector2(92, 42), Vector2(40, 90), Vector2(90, 88), Vector2(64, 24), Vector2(64, 102)]
	for f in centers.size():
		var fc: Vector2 = centers[f] + Vector2(r.randf_range(-5, 5), r.randf_range(-5, 5))
		var fr := 26.0 if f == 0 else r.randf_range(15.0, 21.0)
		var spin := r.randf_range(-0.6, 0.6) + (0.0 if f == 0 else (fc - Vector2(64, 64)).angle() + PI * 0.5)
		var tone := r.randf_range(0.72, 1.0)
		for y in range(maxi(0, int(fc.y - fr - 1)), mini(sz, int(fc.y + fr + 2))):
			for x in range(maxi(0, int(fc.x - fr - 1)), mini(sz, int(fc.x + fr + 2))):
				var q := (Vector2(x, y) - fc).rotated(-spin)
				var ang := atan2(q.x, -q.y)   # 0 = pointe du lobe central
				var lobe := 0.5 + 0.5 * pow(absf(cos(ang * 1.5)), 1.6)
				lobe *= 1.0 - 0.35 * smoothstep(2.4, PI, absf(ang))   # échancrure du pétiole
				if q.length() < fr * lobe:
					var k := q.length() / fr
					var vein := 1.0 - smoothstep(0.0, 1.6, absf(q.x)) * 1.0
					var c := tone * (0.82 + 0.18 * k) + vein * 0.12 * float(q.y < 0.0)
					img.set_pixel(x, y, Color(c, c, c, 1.0))
	img.generate_mipmaps()
	return img


## Écorce et branches : couleurs des sommets éclaircies (shader bastide_bark).
static func trunk_material() -> ShaderMaterial:
	if _trunk_mat == null:
		var m := ShaderMaterial.new()
		m.shader = BARK_SHADER
		_trunk_mat = m
	return _trunk_mat


## Plantes en maillage plein (iris, fleurs, bambou) : couleurs des sommets, un peu de lumière traversante.
static func plant_material() -> StandardMaterial3D:
	if _plant_mat == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.85
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.backlight_enabled = true
		m.backlight = Color(0.25, 0.3, 0.15)
		_plant_mat = m
	return _plant_mat
