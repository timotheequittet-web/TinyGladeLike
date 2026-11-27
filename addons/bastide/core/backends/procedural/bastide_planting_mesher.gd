@tool
class_name BastidePlantingMesher
extends RefCounted
## Végétation : massifs tracés à la main, arbres isolés, et le jardin automatique
## qui fait pousser des plantes au pied des murs, des maisons, des clôtures et le
## long des chemins.
##
## Les plans (plan_*) ne contiennent que des données (type, position, taille, clé) ;
## draw_items() les dessine. Règles « toujours beau » :
## - jamais une plante sur un chemin, dans une maison, devant une porte, contre un
##   torii ou à cheval sur un mur ;
## - grosses touffes aux angles des maisons, petites plantes basses le long des
##   façades (sous les fenêtres), un petit arbre dans les angles rentrants ;
## - les plantes vont par groupes (bruit le long des murs), pas en rang d'oignons ;
## - chaque plante tire son allure de sa position : modifier une maison ne fait pas
##   repousser tout le jardin autrement.

const BUSH := "bush"
const HYDRANGEA := "hydrangea"
const FERN := "fern"
const GRASS := "grass"
const ROCK := "rock"
const MAPLE := "maple"
const SAKURA := "sakura"
const PINE := "pine"
const BAMBOO := "bamboo"
const TREES := [MAPLE, SAKURA, PINE]


static func _item(type: String, pos: Vector3, size: float, key: int, bloom := false) -> Dictionary:
	return {"type": type, "pos": pos, "size": size, "key": key, "bloom": bloom}


## Rayon au sol occupé par une plante (pour l'espacement et les collisions).
static func footprint(item: Dictionary) -> float:
	match String(item["type"]):
		MAPLE, SAKURA, PINE:
			return 0.5
		BAMBOO:
			return item["size"] * 0.6
		ROCK:
			return item["size"]
		_:
			return item["size"] * 0.8


## Rayon de la couronne d'un arbre de jardin (m), selon sa hauteur : ce qu'il
## faut laisser entre le tronc et les murs pour que les branches restent dehors.
static func crown_reach(type: String, height: float) -> float:
	match type:
		MAPLE:
			return height * 0.74
		SAKURA:
			return height * 0.7
		PINE:
			return height * 0.58
	return 0.0


## Un arbre trop près d'une maison est rapetissé pour que sa couronne ne traverse
## pas les murs ; faux s'il faudrait le rendre plus petit que `min_height`.
static func fit_tree(item: Dictionary, ctx: BastideGardenContext, min_height := 2.0) -> bool:
	var reach := crown_reach(String(item["type"]), float(item["size"]))
	if reach <= 0.0 or ctx == null or ctx.houses.is_empty():
		return true
	var p: Vector3 = item["pos"]
	var room := ctx.house_clearance(Vector2(p.x, p.z), reach + 0.5) - 0.25
	if room >= reach:
		return true
	var h: float = float(item["size"]) * room / reach
	if h < min_height:
		return false
	item["size"] = h
	return true


## Espèce d'arbre selon les poids du style.
static func tree_species(gs: BastideGardenStyle, key: int) -> String:
	var w := gs.tree_weights
	var total := maxf(w.x + w.y + w.z, 1e-4)
	var r := BastideGardenMesher.h(key, 777) * total
	if r < w.x:
		return MAPLE
	if r < w.x + w.y:
		return SAKURA
	return PINE


static func tree_height(type: String, key: int) -> float:
	var t := BastideGardenMesher.h(key, 778)
	match type:
		SAKURA:
			return lerpf(3.6, 5.0, t)
		PINE:
			return lerpf(2.6, 3.6, t)
		_:
			return lerpf(3.0, 4.4, t)


## Ajoute `item` s'il ne gêne rien et ne chevauche pas une plante déjà placée.
static func _try(items: Array, item: Dictionary, ctx: BastideGardenContext, check := true, spacing := 0.8) -> bool:
	var p: Vector3 = item["pos"]
	var r := footprint(item)
	if check and ctx.blocked(Vector2(p.x, p.z), r):
		return false
	if check and not fit_tree(item, ctx):
		return false
	for o: Dictionary in items:
		var q: Vector3 = o["pos"]
		if Vector2(p.x - q.x, p.z - q.z).length() < (r + footprint(o)) * spacing:
			return false
	items.append(item)
	return true


# --- Massifs et arbres --------------------------------------------------------------

## Plan d'un massif tracé (au moins deux points) ou d'un arbre (un seul point).
static func plan_planting(points: PackedVector3Array, seed: int, gs: BastideGardenStyle,
		ctx: BastideGardenContext) -> Array:
	var items: Array = []
	if points.is_empty():
		return items
	if ctx == null:
		ctx = BastideGardenContext.new()
	if points.size() == 1 or BastideStroke.length(points) < 0.8:
		var p := points[0]
		var k := BastideRng.key(seed, "tree")
		var type := tree_species(gs, k)
		var tree := _item(type, p, tree_height(type, k), k)
		# Arbre posé à la main : on le garde, au pire tout petit.
		fit_tree(tree, ctx, 0.0)
		tree["size"] = maxf(tree["size"], 1.2)
		items.append(tree)
		# Sous-bois : quelques herbes, fougères et une pierre au pied.
		for i in 5:
			var a := TAU * (float(i) / 5.0 + BastideGardenMesher.hs(k, 10 + i) * 0.1)
			var q := p + Vector3(cos(a), 0, sin(a)) * (0.9 + BastideGardenMesher.h(k, 20 + i) * 0.7)
			var kk := BastideRng.combine(k, 30 + i)
			var roll := BastideGardenMesher.h(kk, 1)
			var t := GRASS if roll < 0.45 else (FERN if roll < 0.8 else ROCK)
			_try(items, _item(t, q, 0.32 + BastideGardenMesher.h(kk, 2) * 0.2, kk), ctx)
		return items
	var pts := BastideStroke.resample(points, 0.85)
	var cum := BastidePolyline.cumulative(pts)
	var total := cum[cum.size() - 1]
	var next_tree := 3.2 if total > 5.0 else INF
	for i in pts.size():
		var s := cum[i]
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var side := BastidePolyline.right_of(BastidePolyline.flat_dir(a, b))
		var k := BastideGardenMesher.key_at(seed, pts[i], 1)
		var p := pts[i] + side * BastideGardenMesher.hs(k, 1) * 0.25
		if s >= next_tree:
			var tk := BastideRng.combine(k, 5)
			var type := tree_species(gs, tk)
			if _try(items, _item(type, p, tree_height(type, tk), tk), ctx):
				next_tree = s + 6.5
				continue
		var zone := BastideRng.noise1(seed, "massif_zone", s / 3.0)
		var size := 0.45 + BastideGardenMesher.h(k, 2) * 0.35
		var type := BUSH if zone < 0.38 else (HYDRANGEA if zone < 0.68 else (GRASS if BastideGardenMesher.h(k, 3) < 0.5 else FERN))
		if BastideGardenMesher.h(k, 4) < 0.1:
			type = ROCK
			size = 0.3 + BastideGardenMesher.h(k, 5) * 0.25
		_try(items, _item(type, p, size, k, BastideGardenMesher.h(k, 6) < 0.35), ctx)
		# Compagnes plus petites de part et d'autre.
		for j in 2:
			var kk := BastideRng.combine(k, 40 + j)
			if BastideGardenMesher.h(kk, 1) < 0.35:
				continue
			var sgn := -1.0 if j == 0 else 1.0
			var q := pts[i] + side * sgn * (0.6 + BastideGardenMesher.h(kk, 2) * 0.35) + (b - a).normalized() * BastideGardenMesher.hs(kk, 3) * 0.3
			var roll := BastideGardenMesher.h(kk, 4)
			var t := GRASS if roll < 0.4 else (FERN if roll < 0.75 else BUSH)
			_try(items, _item(t, q, 0.3 + BastideGardenMesher.h(kk, 5) * 0.18, kk, false), ctx)
	return items


static func build_planting(points: PackedVector3Array, seed: int, style: BastideStyle, ctx: BastideGardenContext,
		with_collision := true) -> BastideBuildResult:
	var result := BastideBuildResult.new()
	var gs := style.get_garden_style()
	var items := plan_planting(points, seed, gs, ctx)
	if items.is_empty():
		return result
	var mb := BastideMeshBuilder.new()
	draw_items(mb, kit_split(items, gs, result), gs)
	if with_collision:
		for it: Dictionary in items:
			var p: Vector3 = it["pos"]
			var tall: bool = TREES.has(it["type"])
			var r := 0.35 if tall else footprint(it) * 0.8
			var hh: float = it["size"] * 0.9 if tall else it["size"] * 1.1
			result.add_box([p + Vector3(-r, 0, -r), p + Vector3(r, 0, -r), p + Vector3(r, 0, r), p + Vector3(-r, 0, r),
				p + Vector3(-r, hh, -r), p + Vector3(r, hh, -r), p + Vector3(r, hh, r), p + Vector3(-r, hh, r)])
	result.mesh = mb.commit(BastideGardenMesher.materials(style))
	result.stats = {"triangles": mb.triangle_count, "plants": items.size()}
	return result


# --- Jardin automatique ----------------------------------------------------------

## Plan du jardin : {items, bands (galets au pied des maisons), curbs (pierres de bordure)}.
static func plan_garden(ctx: BastideGardenContext, seed: int, gs: BastideGardenStyle) -> Dictionary:
	var items: Array = []
	var bands: Array = []
	var curbs: Array = []
	var dens := gs.plant_density
	var th := func(base: float) -> float: return 1.0 - (1.0 - base) * dens
	for hi in ctx.houses.size():
		var house: Dictionary = ctx.houses[hi]
		var fp: PackedVector2Array = house["footprint"]
		var n := fp.size()
		var y := 0.0
		var band_w := 0.6
		if gs.drip_edge:
			var inner := BastidePolygon.offset(fp, -0.03)
			var outer := BastidePolygon.offset(fp, -band_w)
			bands.append({"inner": inner, "outer": outer})
			for i in n:
				var a := outer[i]
				var b := outer[(i + 1) % n]
				var length := a.distance_to(b)
				var steps := maxi(1, roundi(length / 0.27))
				for k in steps:
					var q2 := a.lerp(b, (k + 0.5) / steps)
					if ctx.path_clearance(q2) < 0.1 or ctx.near_door(q2, 1.1):
						continue
					curbs.append({"pos": Vector3(q2.x, y, q2.y), "key": BastideGardenMesher.key_at(seed, Vector3(q2.x, 0, q2.y), 2)})
		# Angles : touffes aux angles saillants, petit arbre dans les angles rentrants.
		for i in n:
			var m := -BastidePolygon.miter(fp, i, 2.0)
			var convex := BastidePolygon.is_convex_vertex(fp, i)
			var corner := fp[i]
			if convex:
				var p2 := corner + m.normalized() * 1.25
				var k := BastideGardenMesher.key_at(seed, Vector3(p2.x, 0, p2.y), 3)
				if BastideGardenMesher.h(k, 1) > th.call(0.25):
					continue
				var main := _item(BUSH if BastideGardenMesher.h(k, 2) < 0.6 else HYDRANGEA, Vector3(p2.x, y, p2.y),
						0.55 + BastideGardenMesher.h(k, 3) * 0.3, k, BastideGardenMesher.h(k, 4) < 0.4)
				_try(items, main, ctx)
				for j in 2:
					var kk := BastideRng.combine(k, 10 + j)
					var e := BastidePolygon.edge_dir(fp, i) if j == 0 else -BastidePolygon.edge_dir(fp, posmod(i - 1, n))
					var q := corner + m.normalized() * 0.75 + e * (1.1 + BastideGardenMesher.h(kk, 1) * 0.5)
					_try(items, _item(FERN if BastideGardenMesher.h(kk, 2) < 0.5 else GRASS, Vector3(q.x, y, q.y),
							0.32 + BastideGardenMesher.h(kk, 3) * 0.15, kk), ctx)
			else:
				var p2 := corner + m.normalized() * 1.6
				var k := BastideGardenMesher.key_at(seed, Vector3(p2.x, 0, p2.y), 4)
				if ctx.house_clearance(p2) > 1.0:
					var type := MAPLE if BastideGardenMesher.h(k, 1) < 0.65 else BAMBOO
					var size := tree_height(MAPLE, k) * 0.8 if type == MAPLE else 0.8
					if type == BAMBOO:
						_try(items, _item(type, Vector3(p2.x, y, p2.y), size, k), ctx, true, 0.6)
					else:
						# L'érable recule dans l'angle jusqu'à ce que sa couronne tienne
						# dehors ; sinon, un bosquet de bambous.
						var placed := false
						for d: float in [1.6, 2.3, 3.0, 3.7]:
							var q2 := corner + m.normalized() * d
							if _try(items, _item(type, Vector3(q2.x, y, q2.y), size, k), ctx, true, 0.6):
								placed = true
								break
						if not placed:
							_try(items, _item(BAMBOO, Vector3(p2.x, y, p2.y), 0.8, k), ctx, true, 0.6)
		# Le long des façades : petites plantes basses, en groupes.
		for i in n:
			var a := fp[i]
			var b := fp[(i + 1) % n]
			var length := a.distance_to(b)
			var dir := (b - a) / maxf(length, 1e-5)
			var out := -BastidePolygon.inward_normal(fp, i)
			var s := 1.5
			while s < length - 1.5:
				var p2 := a + dir * s + out * (band_w + 0.42)
				var k := BastideGardenMesher.key_at(seed, Vector3(p2.x, 0, p2.y), 5)
				if BastideRng.noise1(seed, "facade_group", (p2.x + p2.y) / 2.5) < th.call(0.55):
					s += 0.9
					continue
				var roll := BastideGardenMesher.h(k, 1)
				var type := HYDRANGEA if roll < 0.3 else (FERN if roll < 0.65 else GRASS)
				_try(items, _item(type, Vector3(p2.x, y, p2.y), 0.36 + BastideGardenMesher.h(k, 2) * 0.16, k), ctx)
				s += 0.8 + BastideGardenMesher.h(k, 3) * 0.6
	# Murs et clôtures : herbes et fougères au pied, des deux côtés.
	for list: Array in [ctx.walls, ctx.fences]:
		for e: Dictionary in list:
			var is_fence := list == ctx.fences
			var bamboo: bool = is_fence and int(e.get("variant", 0)) == BastideGardenStyle.FenceKind.BAMBOO
			var pts := BastideStroke.resample(e["points"], 0.7, e["closed"])
			var cum := BastidePolyline.cumulative(pts)
			for side_sign: float in [-1.0, 1.0]:
				for i in pts.size():
					var a := pts[maxi(i - 1, 0)]
					var b := pts[mini(i + 1, pts.size() - 1)]
					var side := BastidePolyline.right_of(BastidePolyline.flat_dir(a, b)) * side_sign
					var p := pts[i] + side * (float(e["thickness"]) * 0.5 + 0.38)
					var g := BastideRng.noise1(seed, "wall_group%d" % int(side_sign), cum[i] / 2.2 + p.x * 0.05)
					if g < th.call(0.62 if bamboo else (0.56 if is_fence else 0.5)):
						continue
					var k := BastideGardenMesher.key_at(seed, p, 6)
					var roll := BastideGardenMesher.h(k, 1)
					var type := GRASS if roll < 0.45 else (FERN if roll < 0.85 else HYDRANGEA)
					if bamboo and roll > 0.7:
						type = GRASS
					_try(items, _item(type, p, 0.34 + BastideGardenMesher.h(k, 2) * 0.2, k), ctx)
	# Bords des chemins : quelques touffes, un rocher de temps en temps.
	for e: Dictionary in ctx.paths:
		var pts := BastideStroke.resample(e["points"], 0.9)
		var cum := BastidePolyline.cumulative(pts)
		for side_sign: float in [-1.0, 1.0]:
			for i in range(1, pts.size() - 1):
				var side := BastidePolyline.right_of(BastidePolyline.flat_dir(pts[i - 1], pts[i + 1])) * side_sign
				var p := pts[i] + side * (float(e["width"]) * 0.5 + 0.5)
				if BastideRng.noise1(seed, "path_group%d" % int(side_sign), cum[i] / 2.8) < th.call(0.66):
					continue
				var k := BastideGardenMesher.key_at(seed, p, 7)
				var roll := BastideGardenMesher.h(k, 1)
				var type := GRASS if roll < 0.5 else (FERN if roll < 0.85 else ROCK)
				_try(items, _item(type, p, 0.3 + BastideGardenMesher.h(k, 2) * 0.18, k), ctx)
	return {"items": items, "bands": bands, "curbs": curbs}


static func build_garden(ctx: BastideGardenContext, seed: int, style: BastideStyle) -> BastideBuildResult:
	var result := BastideBuildResult.new()
	var gs := style.get_garden_style()
	var pl := plan_garden(ctx, seed, gs)
	var mb := BastideMeshBuilder.new()
	for band: Dictionary in pl["bands"]:
		var inner: PackedVector2Array = band["inner"]
		var outer: PackedVector2Array = band["outer"]
		var n := inner.size()
		for i in n:
			var j := (i + 1) % n
			var y := 0.03
			var col := Color(gs.pebble_color.r, gs.pebble_color.g, gs.pebble_color.b, 0.0)
			mb.add_quad(BastideGardenMesher.ROLE_GRAVEL, Vector3(inner[i].x, y, inner[i].y), Vector3(inner[j].x, y, inner[j].y),
					Vector3(outer[j].x, y, outer[j].y), Vector3(outer[i].x, y, outer[i].y), Vector3.UP, col, col, col, col)
	for c: Dictionary in pl["curbs"]:
		var k: int = c["key"]
		BastideGardenMesher.rock(mb, c["pos"], Vector3(0.12 + BastideGardenMesher.h(k, 1) * 0.05, 0.07 + BastideGardenMesher.h(k, 2) * 0.03,
				0.1 + BastideGardenMesher.h(k, 3) * 0.04), k, BastideGardenMesher.tint(gs.edging_color, BastideGardenMesher.hs(k, 4) * 0.08), 3, 6, 0.25)
	draw_items(mb, kit_split(pl["items"], gs, result), gs)
	if mb.triangle_count == 0 and result.instances.is_empty():
		return result
	result.mesh = mb.commit(BastideGardenMesher.materials(style))
	result.stats = {"triangles": mb.triangle_count, "plants": (pl["items"] as Array).size(), "curbs": (pl["curbs"] as Array).size()}
	return result


## Distance (m) jusqu'à laquelle les fleurs et buissons des jardins restent affichés
## (un groupe couvre tout le jardin : on la prend large).
const GARDEN_PLANT_RANGE := 140.0


## Plantes confiées au kit nature (arbres, buissons, hortensias, fougères) : posées en instances
## dans `result`, retirées de la liste rendue. Renvoie les plantes restantes.
static func kit_split(items: Array, gs: BastideGardenStyle, result: BastideBuildResult) -> Array:
	if not gs.kit_plants:
		return items
	var rest: Array = []
	var groups := {}
	# Distances d'affichage (multipliées par le réglage graphique, voir BastideGraphics) :
	# plantes basses jusqu'à PLANT_RANGE, couronnes d'arbres détaillées jusqu'à
	# NEAR_CROWN puis version lointaine.
	var ranges := {"plant": Vector2(0, GARDEN_PLANT_RANGE), "crown": Vector2(0, BastideForestBuilder.NEAR_CROWN),
		"far": Vector2(BastideForestBuilder.NEAR_CROWN, 0), "shadow": Vector2(0, BastideForestBuilder.SHADOW_RANGE)}
	var add := func(gkey: String, m: Mesh, mat: Material, xf: Transform3D, shadow: int) -> void:
		if m == null:
			return
		if not groups.has(gkey):
			var kind := gkey.get_slice("/", 0)
			var vr: Vector2 = ranges.get(kind, ranges["plant"] if kind != "trunk" else Vector2.ZERO)
			groups[gkey] = {"mesh": m, "mat": mat, "xf": [], "shadow": shadow, "vr": vr}
		(groups[gkey]["xf"] as Array).append(xf)
	var bark := BastideKitNature.trunk_material()
	for it: Dictionary in items:
		var type: String = it["type"]
		var p: Vector3 = it["pos"]
		var size: float = it["size"]
		var k: int = it["key"]
		var rot := BastideGardenMesher.h(k, 701) * TAU
		match type:
			MAPLE, SAKURA, PINE:
				var sp := "momiji" if type == MAPLE else ("sakura" if type == SAKURA else "matsu")
				var hmodel := float(BastideKitNature.SPECIES[sp]["height"])
				var sc := snappedf(size * 1.15 / hmodel, 0.1)
				var variant := int(BastideGardenMesher.h(k, 702) * 4.0)
				var tr := BastideKitNature.tree(sp, variant, sc)
				var trf := BastideKitNature.tree(sp, variant, sc, true)
				var xf := Transform3D(Basis(Vector3.UP, rot), p)
				var id := "%s/%d/%.1f" % [sp, variant, sc]
				add.call("trunk/" + id, tr["trunk"], bark, xf, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
				add.call("crown/" + id, tr["crown"], tr["crown_mat"], xf, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
				add.call("far/" + id, trf["crown"], trf["crown_mat"], xf, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
				add.call("shadow/" + id, tr["shadow"], bark, xf, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
			HYDRANGEA:
				var model := "hydrangea_blue" if BastideGardenMesher.h(k, 703) < 0.55 else "hydrangea_pink"
				if it.get("bloom", false) and BastideGardenMesher.h(k, 704) < 0.5:
					model = "azalea_pink"
				var pl := BastideKitNature.plant(model)
				var xf := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * size * 1.5), p)
				add.call("plant/" + model, pl["mesh"], pl["mat"], xf, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
				if pl.get("trunk") != null:
					add.call("plantcore/" + model, pl["trunk"], bark, xf, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			BUSH:
				# Buisson en cartes de feuillage, comme les arbres (plus de boule lisse) ;
				# les buissons fleuris sont des azalées.
				var model := "bush_1"
				if it.get("bloom", false):
					model = "azalea_pink" if BastideGardenMesher.h(k, 705) < 0.6 else "azalea_red"
				var pl := BastideKitNature.plant(model)
				var xf := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * size * (1.25 if model == "bush_1" else 1.6)), p)
				add.call("plant/" + model, pl["mesh"], pl["mat"], xf, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
				if pl.get("trunk") != null:
					add.call("plantcore/" + model, pl["trunk"], bark, xf, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			FERN:
				var tf := BastideKitNature.tuft("fern", Color.WHITE, 1.4)
				if tf.is_empty():
					rest.append(it)
					continue
				var xf := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * size * 1.6), p)
				add.call("fern", tf["mesh"], tf["mat"], xf, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			_:
				rest.append(it)
	for g: Dictionary in groups.values():
		var vr: Vector2 = g["vr"]
		result.add_instances(g["mesh"], g["mat"], g["xf"], g["shadow"], vr.x, vr.y)
	return rest


## Dessine une liste de plantes (voir plan_*).
static func draw_items(mb: BastideMeshBuilder, items: Array, gs: BastideGardenStyle) -> void:
	for it: Dictionary in items:
		var p: Vector3 = it["pos"]
		var size: float = it["size"]
		var k: int = it["key"]
		match String(it["type"]):
			BUSH:
				BastideGardenMesher.bush(mb, p, size, gs, k, it["bloom"])
			HYDRANGEA:
				BastideGardenMesher.hydrangea(mb, p, size, gs, k)
			FERN:
				BastideGardenMesher.fern(mb, p, size * 1.3, gs, k)
			GRASS:
				BastideGardenMesher.grass(mb, p, size * 1.4, gs, k)
			ROCK:
				BastideGardenMesher.rock(mb, p, Vector3(size, size * 0.62, size * 0.85), k,
						BastideGardenMesher.tint(gs.fence_stone_color, BastideGardenMesher.hs(k, 9) * 0.08), 4, 7, 0.3)
			MAPLE:
				BastideGardenMesher.maple(mb, p, size, gs, k)
			SAKURA:
				BastideGardenMesher.sakura(mb, p, size, gs, k)
			PINE:
				BastideGardenMesher.pine(mb, p, size, gs, k)
			BAMBOO:
				BastideGardenMesher.bamboo_clump(mb, p, size, gs, k)
