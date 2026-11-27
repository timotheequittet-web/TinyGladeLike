@tool
class_name BastideForestBuilder
extends RefCounted
## Forêt : une zone tracée (contour fermé) remplie de grands arbres du kit nature et
## d'un sous-bois (fougères, fleurs, massifs), en fonctions pures (thread de génération).
##
## Règles « toujours beau » :
## - les arbres sont espacés selon leur couronne (on circule entre les troncs) et
##   un peu tassés vers l'intérieur : la lisière est plus claire, le cœur plus dense ;
## - ils évitent les maisons, terrasses, chemins, murs et portes voisins ;
## - au pied des troncs : fougères et buissons à l'ombre ; dans les trouées : fleurs
##   des champs, hortensias, azalées, iris ;
## - une essence n'a que quelques tailles (cache partagé) ; chaque arbre est tourné.

enum Kind { MIXED, CEDARS, OAKS, MAPLES, SAKURA, PINES }

## Essences et poids par sorte de forêt.
const MIX := {
	Kind.MIXED: {"chene": 0.3, "hetre": 0.25, "cedre": 0.2, "momiji": 0.15, "sakura": 0.1},
	Kind.CEDARS: {"cedre": 0.85, "hetre": 0.15},
	Kind.OAKS: {"chene": 0.55, "hetre": 0.4, "camphrier": 0.05},
	Kind.MAPLES: {"momiji": 0.75, "hetre": 0.25},
	Kind.SAKURA: {"sakura": 0.8, "hetre": 0.2},
	Kind.PINES: {"matsu": 0.7, "cedre": 0.3},
}
## Échelle des modèles à tree_scale = 1 (chênes, hêtres, cèdres et camphriers vers 17 à 19 m ;
## érables, cerisiers et pins restent des arbres moyens, 10 à 12 m).
const BASE_SCALE := {"cedre": 1.8, "chene": 1.5, "hetre": 1.5, "camphrier": 1.3, "momiji": 1.5, "sakura": 1.5, "matsu": 1.2}
## Rayon de couronne relatif à la hauteur (espacement).
const CROWN := {"cedre": 0.17, "chene": 0.3, "hetre": 0.28, "camphrier": 0.3, "momiji": 0.36, "sakura": 0.42, "matsu": 0.36}
## Taille de case des groupes d'instances : chaque groupe s'efface selon sa propre distance.
const CHUNK := 48.0
const NEAR_CROWN := 75.0      # au-delà : couronnes lointaines (peu de grandes cartes)
const SHADOW_RANGE := 160.0
const PLANT_RANGE := 55.0
const TRUNK_COLLISION_H := 6.0


## Plan : {trees: [{species, variant, size, pos, rot, jitter}], plants: [{type, pos, rot, size}]}
static func plan(points: PackedVector3Array, seed: int, kind: int, tree_scale: float, density: float,
		undergrowth: float, ctx: BastideGardenContext) -> Dictionary:
	var trees: Array = []
	var plants: Array = []
	if points.size() < 3:
		return {"trees": trees, "plants": plants}
	if ctx == null:
		ctx = BastideGardenContext.new()
	var poly := PackedVector2Array()
	for p in points:
		poly.append(Vector2(p.x, p.z))
	var y := points[0].y
	var bounds := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		bounds = bounds.expand(q)
	var mix: Dictionary = MIX.get(kind, MIX[Kind.MIXED])
	density = clampf(density, 0.3, 2.0)
	# Grille jitterée assez fine ; chaque candidat tire son essence, puis on garde ceux
	# qui ont la place (couronnes qui se touchent à peine).
	var cell := 3.0
	var nx := ceili(bounds.size.x / cell)
	var nz := ceili(bounds.size.y / cell)
	var cand: Array = []
	for ix in nx:
		for iz in nz:
			var k := BastideRng.combine(BastideRng.combine(seed, ix * 7919 + 13), iz)
			var q := bounds.position + Vector2((ix + BastideRng.unit(k)) * cell, (iz + BastideRng.unit(k + 1)) * cell)
			if not Geometry2D.is_point_in_polygon(q, poly):
				continue
			cand.append([BastideRng.unit(k + 2), q, k])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var edge_soft := 6.0
	# Les festons suivent la taille du bois : un bosquet garde son cœur.
	var scallop_amp := clampf((minf(bounds.size.x, bounds.size.y) - 14.0) * 0.3, 0.5, 8.0)
	for c: Array in cand:
		var q: Vector2 = c[1]
		var k: int = c[2]
		var species := _pick(mix, BastideRng.unit(k + 3))
		var big := BastideRng.unit(k + 4) < 0.55
		var size := snappedf(float(BASE_SCALE[species]) * tree_scale * (1.0 if big else 0.82), 0.1)
		var height := float(BastideKitNature.SPECIES[species]["height"]) * size
		var crown_r := height * float(CROWN[species])
		var trunk_r := 0.45 * size
		# Lisière : moins dense au bord.
		var d_edge := _dist_to_poly(q, poly)
		# Lisière festonnée : la forêt ne s'arrête jamais en ligne droite.
		var scallop := _noise2(seed, q * 0.07) * scallop_amp
		if d_edge < trunk_r + 0.6 + scallop:
			continue
		var spacing := crown_r * 1.3 / density * (1.0 + 0.5 * (1.0 - clampf(d_edge / minf(edge_soft, scallop_amp + 1.0), 0.0, 1.0)))
		if ctx.blocked(q, trunk_r + 1.2):
			continue
		# Les branches basses restent hors des maisons.
		if ctx.house_clearance(q, crown_r) < crown_r * 0.75:
			continue
		var ok := true
		for t: Dictionary in trees:
			var tq := Vector2((t["pos"] as Vector3).x, (t["pos"] as Vector3).z)
			if q.distance_to(tq) < (spacing + float(t["spacing"])) * 0.5:
				ok = false
				break
		if not ok:
			continue
		trees.append({"species": species, "variant": int(BastideRng.unit(k + 5) * 8.0), "size": size,
			"pos": Vector3(q.x, y, q.y), "rot": BastideRng.unit(k + 6) * TAU,
			"jitter": lerpf(0.94, 1.06, BastideRng.unit(k + 7)), "spacing": spacing, "crown_r": crown_r, "trunk_r": trunk_r})
	# Sous-bois.
	if undergrowth > 0.0:
		var pc := 1.9 / sqrt(clampf(undergrowth, 0.1, 3.0))
		var px := ceili(bounds.size.x / pc)
		var pz := ceili(bounds.size.y / pc)
		for ix in px:
			for iz in pz:
				var k := BastideRng.combine(BastideRng.combine(seed + 77, ix * 6151 + 5), iz)
				var q := bounds.position + Vector2((ix + BastideRng.unit(k)) * pc, (iz + BastideRng.unit(k + 1)) * pc)
				if not Geometry2D.is_point_in_polygon(q, poly) or _dist_to_poly(q, poly) < 0.4:
					continue
				if ctx.blocked(q, 0.5):
					continue
				# Ombre : distance au tronc le plus proche, relative à sa couronne.
				var shade := 0.0
				var too_close := false
				for t: Dictionary in trees:
					var tq := Vector2((t["pos"] as Vector3).x, (t["pos"] as Vector3).z)
					var d := q.distance_to(tq)
					if d < float(t["trunk_r"]) + 0.5:
						too_close = true
						break
					shade = maxf(shade, 1.0 - d / float(t["crown_r"]))
				if too_close:
					continue
				var roll := BastideRng.unit(k + 2)
				var type := ""
				if shade > 0.35:
					type = "fern" if roll < 0.5 else ("bush_1" if roll < 0.58 else ("hydrangea_blue" if roll < 0.62 else ""))
				elif shade > 0.0:
					type = "fern" if roll < 0.25 else ("meadow" if roll < 0.45 else ("azalea_pink" if roll < 0.5 else ("hydrangea_pink" if roll < 0.53 else ("iris" if roll < 0.57 else ""))))
				else:
					type = "meadow" if roll < 0.3 else ("meadow_warm" if roll < 0.45 else ("flowers_meadow" if roll < 0.5 else ("azalea_red" if roll < 0.53 else ("iris" if roll < 0.57 else ""))))
				if type == "":
					continue
				plants.append({"type": type, "pos": Vector3(q.x, y, q.y), "rot": BastideRng.unit(k + 3) * TAU,
					"size": lerpf(0.85, 1.25, BastideRng.unit(k + 4))})
	return {"trees": trees, "plants": plants}


## Bruit de valeur 2D lissé dans [0, 1].
static func _noise2(seed: int, p: Vector2) -> float:
	var i := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(i)
	f = f * f * (Vector2(3, 3) - f * 2.0)
	var h := func(x: int, y: int) -> float: return BastideRng.unit(BastideRng.combine(BastideRng.combine(seed, x), y))
	var a: float = lerpf(h.call(i.x, i.y), h.call(i.x + 1, i.y), f.x)
	var b: float = lerpf(h.call(i.x, i.y + 1), h.call(i.x + 1, i.y + 1), f.x)
	return lerpf(a, b, f.y)


static func _pick(mix: Dictionary, u: float) -> String:
	var total := 0.0
	for w in mix.values():
		total += float(w)
	var r := u * total
	for sp in mix:
		r -= float(mix[sp])
		if r <= 0.0:
			return sp
	return mix.keys()[0]


static func _dist_to_poly(q: Vector2, poly: PackedVector2Array) -> float:
	var d := INF
	for i in poly.size():
		d = minf(d, q.distance_to(Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])))
	return d


static func _chunk(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))


static func build(points: PackedVector3Array, seed: int, kind: int, tree_scale: float, density: float,
		undergrowth: float, ctx: BastideGardenContext, with_collision := true) -> BastideBuildResult:
	var result := BastideBuildResult.new()
	var pl := plan(points, seed, kind, tree_scale, density, undergrowth, ctx)
	var trees: Array = pl["trees"]
	var plants: Array = pl["plants"]
	# Groupes : (maillage, case) → transformations.
	var groups := {}
	# Instances de l'arbre en cours, [clé du groupe, rang] (pour l'abattage, voir BastideTreeBody).
	var cur := {"parts": []}
	var add := func(gkey: String, m: Mesh, mat: Material, xf: Transform3D, shadow: int, vb: float, ve: float) -> void:
		if m == null:
			return
		if not groups.has(gkey):
			groups[gkey] = {"mesh": m, "mat": mat, "xf": [], "shadow": shadow, "vb": vb, "ve": ve}
		(cur["parts"] as Array).append([gkey, (groups[gkey]["xf"] as Array).size()])
		(groups[gkey]["xf"] as Array).append(xf)
	var bark := BastideKitNature.trunk_material()
	var cards := 0
	for t: Dictionary in trees:
		var sp: String = t["species"]
		var near := BastideKitNature.tree(sp, t["variant"], t["size"])
		var far := BastideKitNature.tree(sp, t["variant"], t["size"], true)
		var xf := Transform3D(Basis(Vector3.UP, t["rot"]).scaled(Vector3.ONE * float(t["jitter"])), t["pos"])
		var ck := _chunk(t["pos"])
		var id := "%s/%d/%.1f@%d,%d" % [sp, int(t["variant"]), float(t["size"]), ck.x, ck.y]
		cur["parts"] = []
		add.call("trunk/" + id, near["trunk"], bark, xf, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 0.0, 0.0)
		add.call("crown/" + id, near["crown"], near["crown_mat"], xf, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 0.0, NEAR_CROWN)
		add.call("far/" + id, far["crown"], far["crown_mat"], xf, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, NEAR_CROWN, 0.0)
		add.call("shadow/" + id, near["shadow"], bark, xf, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, 0.0, SHADOW_RANGE)
		if near["crown"]:
			cards += (near["crown"] as ArrayMesh).surface_get_array_len(0) / 4
		if with_collision:
			result.add_trunk(t["pos"], float(near["trunk_r"]) * float(t["jitter"]), TRUNK_COLLISION_H, cur["parts"])
	for p: Dictionary in plants:
		var type: String = p["type"]
		var m: Mesh = null
		var mat: Material = null
		var extra: Dictionary = {}
		match type:
			"fern":
				var tf := BastideKitNature.tuft("fern", Color.WHITE, 1.4)
				if tf.is_empty():
					extra = BastideKitNature.plant("fern")
				else:
					extra = {"mesh": tf["mesh"], "mat": tf["mat"]}
			"meadow":
				extra = BastideKitNature.tuft("meadow")
			"meadow_warm":
				extra = BastideKitNature.tuft("meadow", Color(1.0, 0.86, 0.74))
			_:
				extra = BastideKitNature.plant(type)
		if extra.is_empty():
			continue
		m = extra["mesh"]
		mat = extra["mat"]
		var xf := Transform3D(Basis(Vector3.UP, p["rot"]).scaled(Vector3.ONE * float(p["size"])), p["pos"])
		var ck := _chunk(p["pos"])
		add.call("plant/%s@%d,%d" % [type, ck.x, ck.y], m, mat, xf, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 0.0, PLANT_RANGE)
		if extra.has("trunk") and extra["trunk"] != null:
			add.call("plantwood/%s@%d,%d" % [type, ck.x, ck.y], extra["trunk"], bark, xf, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 0.0, PLANT_RANGE)
	_add_groups(result, groups)
	var outline := PackedVector2Array()
	for p in points:
		outline.append(Vector2(p.x, p.z))
	result.anchors = {"outline": outline, "trees": trees.map(func(t: Dictionary) -> Vector3: return t["pos"])}
	result.stats = {"trees": trees.size(), "plants": plants.size(), "groups": groups.size(), "cards": cards}
	return result


## Pose les groupes d'instances et traduit les `parts` des troncs (clé de groupe →
## indice dans result.instances).
static func _add_groups(result: BastideBuildResult, groups: Dictionary, vis := true) -> void:
	var index := {}
	for k: String in groups:
		var g: Dictionary = groups[k]
		index[k] = result.instances.size()
		if vis:
			result.add_instances(g["mesh"], g["mat"], g["xf"], g["shadow"], g["vb"], g["ve"])
		else:
			var vr: Vector2 = g["vr"]
			result.add_instances(g["mesh"], g["mat"], g["xf"], g["shadow"], vr.x, vr.y)
	for t: Dictionary in result.trunks:
		var out: Array = []
		for p: Array in t.get("parts", []):
			if p[0] is String and index.has(p[0]):
				out.append([index[p[0]], p[1]])
		t["parts"] = out
