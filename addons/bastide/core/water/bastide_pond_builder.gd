@tool
class_name BastidePondBuilder
extends RefCounted
## Jardin d'eau : un étang creusé dans le relief, et tout ce qui le rend vivant.
##
## - la rive naturelle (BastidePondShape) et l'eau, à plat même sur une pente ;
## - des groupes de rochers posés sur les avancées de la berge (ishi-gumi), une
##   rive de galets (suhama), des pierres qui bordent le reste de la rive ;
## - des iris et des roseaux les pieds dans l'eau, des nénuphars, des massifs
##   fleuris sur la berge, des carpes koï qui tournent lentement ;
## - un pont, une passerelle en zigzag ou des pierres de gué quand un chemin
##   traverse l'eau.
##
## Trois sortes : étang de jardin, source chaude (onsen), mare sauvage.
## Fonction pure : build() tourne sur un thread de génération.

enum Kind { GARDEN, ONSEN, WILD }

const ROLE_STONE := BastideGardenMesher.ROLE_STONE
const ROLE_WOOD := BastideGardenMesher.ROLE_WOOD
const ROLE_WATER := &"water"
const ROLE_LILY := &"lily"

const WATER_SHADER := preload("res://addons/bastide/shaders/bastide_water.gdshader")
const KOI_SHADER := preload("res://addons/bastide/shaders/bastide_koi.gdshader")

## Distance d'affichage des plantes (m).
const PLANT_RANGE := 110.0

static var _mutex := Mutex.new()
static var _materials := {}


## Palette d'eau et de pierre de chaque sorte.
static func look(kind: int) -> Dictionary:
	match kind:
		Kind.ONSEN:
			return {"shallow": Color(0.7, 0.8, 0.76), "deep": Color(0.22, 0.36, 0.35), "scatter": Color(0.42, 0.54, 0.52),
				"absorption": 1.3, "milky": 0.42, "milky_color": Color(0.64, 0.73, 0.7), "foam": 0.12,
				"rock": Color(0.3, 0.28, 0.27), "rock_b": Color(0.4, 0.36, 0.33), "caustics": 0.25, "moss": Color(0.3, 0.36, 0.18)}
		Kind.WILD:
			return {"shallow": Color(0.56, 0.62, 0.44), "deep": Color(0.05, 0.1, 0.06), "scatter": Color(0.14, 0.21, 0.1),
				"absorption": 2.6, "milky": 0.0, "milky_color": Color(0.5, 0.55, 0.4), "foam": 0.18,
				"rock": Color(0.46, 0.47, 0.39), "rock_b": Color(0.36, 0.4, 0.3), "caustics": 0.35, "moss": Color(0.3, 0.4, 0.15)}
	return {"shallow": Color(0.66, 0.8, 0.64), "deep": Color(0.07, 0.2, 0.15), "scatter": Color(0.17, 0.36, 0.25),
		"absorption": 1.4, "milky": 0.0, "milky_color": Color(0.6, 0.8, 0.82), "foam": 0.32,
		"rock": Color(0.57, 0.54, 0.48), "rock_b": Color(0.5, 0.5, 0.43), "caustics": 0.6, "moss": Color(0.4, 0.48, 0.2)}


static func water_material(kind: int) -> ShaderMaterial:
	var key := "water/%d" % kind
	_mutex.lock()
	var m: ShaderMaterial = _materials.get(key)
	if m == null:
		var l := look(kind)
		m = ShaderMaterial.new()
		m.shader = WATER_SHADER
		m.set_shader_parameter("shallow_tint", l["shallow"])
		m.set_shader_parameter("deep_color", l["deep"])
		m.set_shader_parameter("scatter_color", l["scatter"])
		m.set_shader_parameter("absorption", l["absorption"])
		m.set_shader_parameter("milky", l["milky"])
		m.set_shader_parameter("milky_color", l["milky_color"])
		m.set_shader_parameter("shore_foam", l["foam"])
		m.set_shader_parameter("caustics", l["caustics"])
		_materials[key] = m
	_mutex.unlock()
	return m


static func lily_material() -> StandardMaterial3D:
	_mutex.lock()
	var m: StandardMaterial3D = _materials.get("lily")
	if m == null:
		m = StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.45
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials["lily"] = m
	_mutex.unlock()
	return m


static func koi_material() -> ShaderMaterial:
	_mutex.lock()
	var m: ShaderMaterial = _materials.get("koi")
	if m == null:
		m = ShaderMaterial.new()
		m.shader = KOI_SHADER
		_materials["koi"] = m
	_mutex.unlock()
	return m


## Tout l'étang. `xf` : repère local → monde ; `field` : relief d'origine (sans
## étang), ou null (sol plat à y = 0).
static func build(points: PackedVector3Array, seed: int, kind: int, style: BastideStyle, ctx: BastideGardenContext,
		field: BastideHeightField, xf: Transform3D, with_collision := true) -> BastideBuildResult:
	var result := BastideBuildResult.new()
	var poly := BastidePondShape.outline(points, seed, 1.2 if kind == Kind.WILD else 1.0)
	if poly.is_empty():
		return result
	if ctx == null:
		ctx = BastideGardenContext.new()
	var world_poly := PackedVector2Array()
	for p in poly:
		var w := xf * Vector3(p.x, 0.0, p.y)
		world_poly.append(Vector2(w.x, w.z))
	var level := BastidePondShape.water_level(field, world_poly) if field else -BastidePondShape.FREEBOARD
	var carve := BastidePondShape.carve_info(world_poly, level)
	var b := _Ctx.new()
	b.poly = poly
	b.seed = seed
	b.kind = kind
	b.field = field
	b.xf = xf
	b.carve = carve
	b.level_local = level - xf.origin.y
	b.ctx = ctx
	b.gs = style.get_garden_style()
	b.look = look(kind)
	b.mb = BastideMeshBuilder.new()
	b.result = result
	b.area = absf(BastidePolygon.signed_area(poly))
	b.perimeter = BastidePolygon.perimeter(poly)
	b.collision = with_collision

	_water(b)
	_bridges(b)
	if kind != Kind.ONSEN:
		_pier(b)
	_rocks(b)
	if kind == Kind.GARDEN:
		_beach(b)
	_edge_stones(b)
	_plants(b)
	if kind != Kind.ONSEN:
		_lilies(b)
	if kind == Kind.GARDEN:
		_koi(b)
	for g: Dictionary in b.groups.values():
		result.add_instances(g["mesh"], g["mat"], g["xf"], GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 0.0, PLANT_RANGE)

	var mats := BastideGardenMesher.materials(style)
	mats[ROLE_WATER] = water_material(kind)
	mats[ROLE_LILY] = lily_material()
	result.mesh = b.mb.commit(mats)
	# L'eau est dessinée par-dessus le reste : sa surface d'abord dans la liste
	# ne change rien au rendu, mais garde l'ordre stable d'une génération à l'autre.
	var steam := PackedVector3Array()
	if kind == Kind.ONSEN:
		var rng := BastideRng.derive(seed, "steam")
		var box := BastidePondShape.rect_of(poly)
		var tries := 0
		while steam.size() < clampi(int(b.area / 6.0), 3, 14) and tries < 200:
			tries += 1
			var q := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
			if BastidePondShape.signed_distance(q, poly) < -0.5:
				steam.append(Vector3(q.x, b.level_local + 0.05, q.y))
	result.anchors = {"shore": poly, "level": b.level_local, "carve": carve, "steam": steam,
		"bridges": b.bridges, "kind": kind}
	result.stats = {"area": snappedf(b.area, 0.1), "level": snappedf(level, 0.01), "depth": snappedf(float(carve["depth"]), 0.01),
		"rocks": b.rocks, "stones": b.stones, "pebbles": b.pebbles, "plants": b.plants, "lilies": b.lilies, "koi": b.koi,
		"bridges": b.bridges.size(), "piers": b.piers, "triangles": b.mb.triangle_count}
	return result


## État partagé d'une génération.
class _Ctx:
	var poly: PackedVector2Array
	var seed: int
	var kind: int
	var field: BastideHeightField
	var xf: Transform3D
	var carve: Dictionary
	var level_local: float
	var ctx: BastideGardenContext
	var gs: BastideGardenStyle
	var look: Dictionary
	var mb: BastideMeshBuilder
	var result: BastideBuildResult
	var area: float
	var perimeter: float
	var collision := true
	var groups := {}
	## Zones déjà occupées (rochers, ponts) : [Vector3(x, z, rayon)].
	var taken: Array[Vector3] = []
	## Tronçons de rive occupés par un pont : [Vector2(début, fin)] en abscisse de rive.
	var bridges: Array = []
	var rock_spots: Array[Vector2] = []
	var rocks := 0
	var stones := 0
	var pebbles := 0
	var plants := 0
	var lilies := 0
	var koi := 0
	var piers := 0

	## Hauteur du sol (local) en un point, étang creusé compris.
	func ground(q: Vector2) -> float:
		var w := xf * Vector3(q.x, 0.0, q.y)
		var base := field.height(w.x, w.z) if field else 0.0
		var d := BastidePondShape.signed_distance(q, poly)
		return BastidePondShape.carve_height(base, d, carve) - xf.origin.y

	func dist(q: Vector2) -> float:
		return BastidePondShape.signed_distance(q, poly)

	func is_free(q: Vector2, r: float) -> bool:
		for t in taken:
			if Vector2(t.x, t.y).distance_to(q) < t.z + r:
				return false
		return true

	## Vrai si un objet de rayon r posé en q gênerait un chemin, une maison…
	func blocked(q: Vector2, r: float) -> bool:
		return ctx.blocked(q, r) or not is_free(q, r)

	func add(gkey: String, m: Mesh, mat: Material, t: Transform3D) -> void:
		if m == null:
			return
		var g: Dictionary = groups.get(gkey, {})
		if g.is_empty():
			g = {"mesh": m, "mat": mat, "xf": []}
			groups[gkey] = g
		(g["xf"] as Array).append(t)


# --- Eau --------------------------------------------------------------------------

static func _water(b: _Ctx) -> void:
	var idx := BastidePolygon.triangulate(b.poly)
	if idx.is_empty():
		return
	var y := b.level_local
	var c := Color(1, 1, 1, 1)
	for i in range(0, idx.size(), 3):
		var p0 := b.poly[idx[i]]
		var p1 := b.poly[idx[i + 1]]
		var p2 := b.poly[idx[i + 2]]
		var a := Vector3(p0.x, y, p0.y)
		var bb := Vector3(p1.x, y, p1.y)
		var cc := Vector3(p2.x, y, p2.y)
		b.mb.add_tri(ROLE_WATER, a, bb, cc, Vector3.UP, c, c, c)
		if b.collision:
			b.result.collision_faces.append(a)
			b.result.collision_faces.append(bb)
			b.result.collision_faces.append(cc)


# --- Ponts -------------------------------------------------------------------------

## Un chemin qui traverse l'eau la franchit : pierres de gué sur un passage court,
## pont arqué en bois au-dessus d'un bras d'eau, passerelle en zigzag (yatsuhashi)
## sur une longue traversée.
static func _bridges(b: _Ctx) -> void:
	for e: Dictionary in b.ctx.paths:
		var pts: PackedVector3Array = e["points"]
		if pts.size() < 2:
			continue
		var line := BastideStroke.resample(pts, 0.25)
		var inside := []
		for p in line:
			inside.append(b.dist(Vector2(p.x, p.z)) < 0.0)
		var i := 0
		while i < line.size():
			if not inside[i]:
				i += 1
				continue
			var j := i
			while j + 1 < line.size() and inside[j + 1]:
				j += 1
			# Traversée de i à j : on ne bâtit que si le chemin ressort de l'eau des deux côtés.
			if i > 0 and j < line.size() - 1:
				var deepest := 0.0
				for k in range(i, j + 1):
					deepest = maxf(deepest, -b.dist(Vector2(line[k].x, line[k].z)))
				_crossing(b, line, i - 1, j + 1, float(e.get("width", 1.5)), deepest)
			i = j + 1


## `deepest` : jusqu'où le chemin s'avance dans l'eau (m depuis la rive).
static func _crossing(b: _Ctx, line: PackedVector3Array, i0: int, i1: int, width: float, deepest: float) -> void:
	var a3 := line[i0]
	var c3 := line[i1]
	var a := Vector2(a3.x, a3.z)
	var c := Vector2(c3.x, c3.z)
	var span := a.distance_to(c)
	if span < 0.6:
		return
	var dir := (c - a).normalized()
	var key := BastideGardenMesher.key_at(b.seed, Vector3(a.x, 0, a.y), 9)
	# Un passage court, ou qui ne fait qu'écorner la rive (eau peu profonde) : des
	# pierres de gué. Au-dessus d'un vrai bras d'eau : un pont arqué. Une longue
	# traversée : la passerelle en zigzag.
	var kind := "stones"
	if span > 12.5 or b.kind == Kind.WILD and span > 6.0:
		kind = "zigzag"
	elif span > 2.8 and not (deepest < 1.3 and span < 6.5):
		kind = "arch"
	b.bridges.append({"kind": kind, "a": Vector3(a.x, 0, a.y), "b": Vector3(c.x, 0, c.y), "span": snappedf(span, 0.01)})
	# Le pont occupe la rive : pas de rocher ni d'iris dessus.
	var steps := maxi(2, ceili(span / 0.8))
	for k in steps + 1:
		var q := a.lerp(c, float(k) / steps)
		b.taken.append(Vector3(q.x, q.y, width * 0.5 + 0.5))
	match kind:
		"stones":
			_ford(b, a, c, key)
		"arch":
			_arch_bridge(b, a, c, width, key)
		_:
			_zigzag(b, a, c, width, key)


## Ponton : une terrasse posée au bord de l'eau avance sur l'étang par une jetée
## de planches sur pilotis, juste au-dessus de l'eau, avec deux poteaux d'amarrage
## au bout. Un seul ponton par étang, depuis la terrasse la plus proche.
static func _pier(b: _Ctx) -> void:
	if b.ctx.terraces.is_empty() or b.area < 14.0:
		return
	var shore := _resample2(b.poly, 0.4)
	var best := INF
	var q_best := Vector2.ZERO
	var start := Vector2.ZERO
	var height := 0.45
	for t: Dictionary in b.ctx.terraces:
		var fp: PackedVector2Array = t["footprint"]
		if not (t["rect"] as Rect2).grow(3.0).intersects(BastidePondShape.rect_of(b.poly)):
			continue
		for q in shore:
			if Geometry2D.is_point_in_polygon(q, fp):
				continue
			var c := _closest_on_poly(fp, q)
			var d := c.distance_to(q)
			if d < best:
				best = d
				q_best = q
				start = c
				height = float(t.get("height", 0.45))
	if best > 2.2:
		return
	var i := _nearest_index(b.poly, q_best)
	var dir := -BastidePondShape.outward(b.poly, i)
	# La jetée part du bord de la terrasse et s'avance tant que l'eau est franche.
	var length := 0.0
	var step := 0.25
	var max_len := clampf(sqrt(b.area) * 0.45, 2.4, 5.0)
	while length < max_len:
		var p := start + dir * (length + step)
		if b.dist(p) > -0.6 and length > best + 0.5:
			break
		length += step
	var reach := length - best
	if reach < 1.6:
		return
	var a := start
	var c := start + dir * length
	for k in 9:
		var q := a.lerp(c, k / 8.0)
		if not b.is_free(q, 0.3):
			return
	var key := BastideGardenMesher.key_at(b.seed, Vector3(a.x, 0, a.y), 13)
	var side := Vector2(-dir.y, dir.x)
	var w := 0.6
	var y := b.level_local + 0.3
	var deck := b.gs.terrace_color
	var frame := b.gs.terrace_frame_color
	var mb := b.mb
	# Planches en travers, légèrement disjointes.
	var n := maxi(4, int(length / 0.24))
	for k in n:
		var p0 := a.lerp(c, float(k) / n)
		var p1 := a.lerp(c, (k + 0.86) / n)
		var tone := BastideGardenMesher.tint(deck, BastideGardenMesher.hs(key, k) * 0.08)
		var dy := BastideGardenMesher.hs(key, 300 + k) * 0.008
		var wk := w + BastideGardenMesher.hs(key, 200 + k) * 0.03
		var corners := [
			Vector3(p0.x - side.x * wk, y - 0.06 + dy, p0.y - side.y * wk), Vector3(p0.x + side.x * wk, y - 0.06 + dy, p0.y + side.y * wk),
			Vector3(p1.x + side.x * wk, y - 0.06 + dy, p1.y + side.y * wk), Vector3(p1.x - side.x * wk, y - 0.06 + dy, p1.y - side.y * wk),
			Vector3(p0.x - side.x * wk, y + dy, p0.y - side.y * wk), Vector3(p0.x + side.x * wk, y + dy, p0.y + side.y * wk),
			Vector3(p1.x + side.x * wk, y + dy, p1.y + side.y * wk), Vector3(p1.x - side.x * wk, y + dy, p1.y - side.y * wk)]
		mb.add_block(ROLE_WOOD, corners, 0.01, 0.0, tone, tone.darkened(0.12), true)
	# Deux longerons et des pilotis plantés dans le fond.
	for sg: float in [-1.0, 1.0]:
		var o := side * (w - 0.1) * sg
		BastideGardenMesher.tube(mb, ROLE_WOOD, Vector3(a.x + o.x, y - 0.1, a.y + o.y), Vector3(c.x + o.x, y - 0.1, c.y + o.y), 0.06, 0.06, frame, 6)
	var posts := maxi(2, ceili(length / 1.2))
	for k in range(1, posts + 1):
		var p := a.lerp(c, float(k) / posts)
		for sg: float in [-1.0, 1.0]:
			var q := p + side * (w - 0.1) * sg
			var top := y - 0.08
			if k == posts:
				top = y + 0.55
			BastideGardenMesher.prism(mb, ROLE_WOOD, Vector3(q.x, 0, q.y), 0.065, 0.06, b.ground(q) - 0.1, top, 6, frame)
			if k == posts:
				# Poteaux d'amarrage : tête arrondie et une corde de chanvre.
				BastideGardenMesher.blob(mb, ROLE_WOOD, Vector3(q.x, top + 0.03, q.y), Vector3(0.07, 0.05, 0.07), frame.darkened(0.1),
						BastideRng.combine(key, 40), 3, 6)
				BastideGardenMesher.tube(mb, ROLE_WOOD, Vector3(q.x, top - 0.18, q.y), Vector3(q.x, top - 0.12, q.y), 0.085, 0.085,
						Color(0.72, 0.62, 0.42), 7)
	# Une marche si la terrasse est plus haute que la jetée.
	var terrace_y := b.ground(a) + height
	if terrace_y - y > 0.22:
		var sy := (terrace_y + y) * 0.5
		var p0 := a
		var p1 := a + dir * 0.4
		var tone := deck.darkened(0.05)
		var corners := [
			Vector3(p0.x - side.x * w, y - 0.05, p0.y - side.y * w), Vector3(p0.x + side.x * w, y - 0.05, p0.y + side.y * w),
			Vector3(p1.x + side.x * w, y - 0.05, p1.y + side.y * w), Vector3(p1.x - side.x * w, y - 0.05, p1.y - side.y * w),
			Vector3(p0.x - side.x * w, sy, p0.y - side.y * w), Vector3(p0.x + side.x * w, sy, p0.y + side.y * w),
			Vector3(p1.x + side.x * w, sy, p1.y + side.y * w), Vector3(p1.x - side.x * w, sy, p1.y - side.y * w)]
		mb.add_block(ROLE_WOOD, corners, 0.01, 0.0, tone, tone.darkened(0.12))
	if b.collision:
		var mid := a.lerp(c, 0.5)
		_box_collision(b, Vector3(mid.x, y - 0.06, mid.y), Vector3(w, 0.06, length * 0.5), atan2(dir.x, dir.y))
	# La jetée occupe la rive : ni rocher, ni iris, ni nénuphar dessous.
	for k in 9:
		var q := a.lerp(c, k / 8.0)
		b.taken.append(Vector3(q.x, q.y, w + 0.5))
	b.bridges.append({"kind": "pier", "a": Vector3(a.x, 0, a.y), "b": Vector3(c.x, 0, c.y), "span": snappedf(length, 0.01)})
	b.piers += 1


static func _closest_on_poly(poly: PackedVector2Array, q: Vector2) -> Vector2:
	var best := poly[0]
	var bd := INF
	for i in poly.size():
		var c := Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])
		var d := c.distance_squared_to(q)
		if d < bd:
			bd = d
			best = c
	return best


## Pierres de gué (sawatari-ishi) : grosses pierres plates qui dépassent de l'eau.
static func _ford(b: _Ctx, a: Vector2, c: Vector2, key: int) -> void:
	var span := a.distance_to(c)
	var dir := (c - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var n := maxi(1, int(round(span / 0.72)))
	var col: Color = b.gs.stepping_stone_color
	for k in n:
		var t := (k + 0.5) / n
		var q := a.lerp(c, t) + side * (0.12 if k % 2 == 0 else -0.12)
		var bottom := b.ground(q)
		var top := b.level_local + 0.1 + BastideGardenMesher.h(key, k) * 0.04
		var center := Vector3(q.x, bottom, q.y)
		BastideGardenMesher.slab(b.mb, center, 0.34, top - bottom, atan2(dir.y, dir.x) + BastideGardenMesher.hs(key, 10 + k) * 0.3,
				BastideRng.combine(key, k), BastideGardenMesher.tint(col, BastideGardenMesher.hs(key, 20 + k) * 0.05), 8, 1.35, -0.1)
		if b.collision:
			_box_collision(b, Vector3(q.x, bottom, q.y), Vector3(0.36, top - bottom, 0.3), atan2(dir.y, dir.x))
		b.stones += 1


## Pont arqué en bois (sori-bashi) : tablier courbe de planches, deux poutres,
## garde-corps à poteaux coiffés de giboshi.
static func _arch_bridge(b: _Ctx, a: Vector2, c: Vector2, width: float, key: int) -> void:
	var span := a.distance_to(c)
	var dir := (c - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var w := maxf(width, 1.2) * 0.5 + 0.15
	var ya := b.ground(a) + 0.04
	var yc := b.ground(c) + 0.04
	var rise := clampf(span * 0.13, 0.4, 1.2)
	var deck := b.gs.terrace_color
	var frame := b.gs.terrace_frame_color
	var mb := b.mb
	var y_at := func(t: float) -> float:
		return lerpf(ya, yc, t) + sin(t * PI) * rise
	# Planches en travers.
	var n := maxi(4, int(span / 0.28))
	for k in n:
		var t0 := float(k) / n
		var t1 := (k + 0.88) / n
		var p0 := a.lerp(c, t0)
		var p1 := a.lerp(c, t1)
		var y0: float = y_at.call(t0)
		var y1: float = y_at.call(t1)
		var tone := BastideGardenMesher.tint(deck, BastideGardenMesher.hs(key, k) * 0.07)
		var corners := [
			Vector3(p0.x - side.x * w, y0 - 0.07, p0.y - side.y * w), Vector3(p0.x + side.x * w, y0 - 0.07, p0.y + side.y * w),
			Vector3(p1.x + side.x * w, y1 - 0.07, p1.y + side.y * w), Vector3(p1.x - side.x * w, y1 - 0.07, p1.y - side.y * w),
			Vector3(p0.x - side.x * w, y0, p0.y - side.y * w), Vector3(p0.x + side.x * w, y0, p0.y + side.y * w),
			Vector3(p1.x + side.x * w, y1, p1.y + side.y * w), Vector3(p1.x - side.x * w, y1, p1.y - side.y * w)]
		mb.add_block(ROLE_WOOD, corners, 0.012, 0.0, tone, tone.darkened(0.12))
	# Poutres latérales sous le tablier.
	for s: float in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		for k in n + 1:
			var t := float(k) / n
			var p := a.lerp(c, t) + side * (w - 0.08) * s
			var y: float = y_at.call(t) - 0.08
			var cur := Vector3(p.x, y, p.y)
			if k > 0:
				BastideGardenMesher.tube(mb, ROLE_WOOD, prev, cur, 0.09, 0.09, frame, 6)
			prev = cur
	# Piliers dans l'eau.
	for t: float in [0.25, 0.5, 0.75]:
		if span < 4.0 and t != 0.5:
			continue
		for s: float in [-1.0, 1.0]:
			var p := a.lerp(c, t) + side * (w - 0.1) * s
			var y: float = y_at.call(t) - 0.1
			BastideGardenMesher.prism(mb, ROLE_WOOD, Vector3(p.x, 0, p.y), 0.08, 0.08, b.ground(p) - 0.1, y, 6, frame)
	# Garde-corps : poteaux, lisse courbe, giboshi aux extrémités.
	var posts := maxi(3, int(span / 1.3) + 1)
	for s: float in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		for k in posts:
			var t := float(k) / (posts - 1)
			var p := a.lerp(c, t) + side * (w - 0.05) * s
			var y: float = y_at.call(t)
			var top := y + 0.72
			BastideGardenMesher.prism(mb, ROLE_WOOD, Vector3(p.x, 0, p.y), 0.055, 0.05, y - 0.02, top, 6, frame)
			if (k == 0 or k == posts - 1) and b.gs.giboshi:
				BastideGardenMesher.blob(mb, ROLE_WOOD, Vector3(p.x, top + 0.07, p.y), Vector3(0.07, 0.09, 0.07), b.gs.giboshi_color, BastideRng.combine(key, 500 + k), 3, 6)
			var cur := Vector3(p.x, top - 0.08, p.y)
			if k > 0:
				BastideGardenMesher.tube(mb, ROLE_WOOD, prev, cur, 0.04, 0.04, deck.darkened(0.08), 6)
				var mid_prev := prev - Vector3(0, 0.3, 0)
				BastideGardenMesher.tube(mb, ROLE_WOOD, mid_prev, cur - Vector3(0, 0.3, 0), 0.03, 0.03, frame, 6)
			prev = cur
	if b.collision:
		var m := 8
		for k in m:
			var t0 := float(k) / m
			var t1 := float(k + 1) / m
			var p0 := a.lerp(c, t0)
			var p1 := a.lerp(c, t1)
			var y0: float = y_at.call(t0)
			var y1: float = y_at.call(t1)
			b.result.add_box([
				Vector3(p0.x - side.x * w, y0 - 0.15, p0.y - side.y * w), Vector3(p0.x + side.x * w, y0 - 0.15, p0.y + side.y * w),
				Vector3(p1.x + side.x * w, y1 - 0.15, p1.y + side.y * w), Vector3(p1.x - side.x * w, y1 - 0.15, p1.y - side.y * w),
				Vector3(p0.x - side.x * w, y0, p0.y - side.y * w), Vector3(p0.x + side.x * w, y0, p0.y + side.y * w),
				Vector3(p1.x + side.x * w, y1, p1.y + side.y * w), Vector3(p1.x - side.x * w, y1, p1.y - side.y * w)])


## Passerelle en zigzag (yatsuhashi) : de longues planches décalées, posées bas
## sur l'eau, entre lesquelles on change de direction.
static func _zigzag(b: _Ctx, a: Vector2, c: Vector2, width: float, key: int) -> void:
	var span := a.distance_to(c)
	var dir := (c - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var n := maxi(2, int(round(span / 2.4)))
	var y := b.level_local + 0.32
	var deck := b.gs.terrace_color.darkened(0.05)
	var frame := b.gs.terrace_frame_color
	var w := 0.42
	var prev_end := a
	for k in n:
		var t1 := float(k + 1) / n
		var zig := side * (0.55 if k % 2 == 0 else -0.55) * (0.0 if k == n - 1 else 1.0)
		var end := a.lerp(c, t1) + zig
		var start := prev_end
		var d := (end - start)
		var len := d.length()
		var u := d / maxf(len, 1e-4)
		var v := Vector2(-u.y, u.x)
		# Deux larges planches côte à côte par tronçon.
		for s: float in [-0.5, 0.5]:
			var off := v * w * s
			var p0 := start + off - u * 0.15
			var p1 := end + off + u * 0.15
			var hw := w * 0.48
			var tone := BastideGardenMesher.tint(deck, BastideGardenMesher.hs(key, k * 2 + int(s > 0)) * 0.06)
			var ya := y if k > 0 else maxf(y, b.ground(start) + 0.05)
			var yb := y if k < n - 1 else maxf(y, b.ground(end) + 0.05)
			var corners := [
				Vector3(p0.x - v.x * hw, ya - 0.08, p0.y - v.y * hw), Vector3(p0.x + v.x * hw, ya - 0.08, p0.y + v.y * hw),
				Vector3(p1.x + v.x * hw, yb - 0.08, p1.y + v.y * hw), Vector3(p1.x - v.x * hw, yb - 0.08, p1.y - v.y * hw),
				Vector3(p0.x - v.x * hw, ya, p0.y - v.y * hw), Vector3(p0.x + v.x * hw, ya, p0.y + v.y * hw),
				Vector3(p1.x + v.x * hw, yb, p1.y + v.y * hw), Vector3(p1.x - v.x * hw, yb, p1.y - v.y * hw)]
			b.mb.add_block(ROLE_WOOD, corners, 0.015, 0.0, tone, tone.darkened(0.14))
			if b.collision:
				b.result.add_box(corners)
		# Pieux sous chaque bout de tronçon.
		for q: Vector2 in [start + u * 0.3, end - u * 0.3]:
			for s: float in [-1.0, 1.0]:
				var pp: Vector2 = q + v * w * 0.5 * s
				BastideGardenMesher.prism(b.mb, ROLE_WOOD, Vector3(pp.x, 0, pp.y), 0.07, 0.07, b.ground(pp) - 0.1, y - 0.08, 6, frame)
		prev_end = end


static func _box_collision(b: _Ctx, base: Vector3, half: Vector3, rot: float) -> void:
	var u := Vector3(cos(rot), 0, sin(rot)) * half.x
	var v := Vector3(-sin(rot), 0, cos(rot)) * half.z
	var up := Vector3(0, half.y, 0)
	b.result.add_box([base - u - v, base + u - v, base + u + v, base - u + v,
		base - u - v + up, base + u - v + up, base + u + v + up, base - u + v + up])


# --- Rochers et pierres ----------------------------------------------------------------

## Groupes de rochers (ishi-gumi) : un grand rocher et ses compagnons, posés sur les
## avancées de la berge, à moitié dans l'eau. Un onsen est entièrement cerné de
## rochers sombres.
static func _rocks(b: _Ctx) -> void:
	var poly := b.poly
	var n := poly.size()
	var scale := clampf(sqrt(b.area) / 6.0, 0.7, 1.6)
	if b.kind == Kind.ONSEN:
		_onsen_ring(b, scale)
		return
	var count := clampi(int(b.perimeter / 13.0), 1, 5)
	if b.kind == Kind.WILD:
		count = maxi(1, count / 2)
	# Les avancées de la berge (angles rentrants de l'eau) d'abord.
	var order: Array = []
	for i in n:
		var cross := BastidePolygon.turn_cross(poly, i)
		order.append([cross + BastideGardenMesher.h(b.seed, i) * 0.05, i])
	order.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var min_gap := b.perimeter / count * 0.55
	var chosen: Array[int] = []
	for o: Array in order:
		if chosen.size() >= count:
			break
		var i: int = o[1]
		var ok := true
		for j in chosen:
			if _arc(poly, i, j, b.perimeter) < min_gap:
				ok = false
				break
		if not ok:
			continue
		var q := poly[i]
		if b.blocked(q + BastidePondShape.outward(poly, i) * 0.8, 1.0):
			continue
		chosen.append(i)
	for gi in chosen.size():
		var i := chosen[gi]
		var out := BastidePondShape.outward(poly, i)
		var along := Vector2(-out.y, out.x)
		var key := BastideRng.combine(b.seed, 1000 + i)
		var main := poly[i] + out * 0.25
		var big := Vector3(0.75, 0.62, 0.6) * scale * (0.85 + BastideGardenMesher.h(key, 1) * 0.4)
		_rock(b, main, big, key, b.look["rock"], 0.32)
		b.rock_spots.append(main)
		b.taken.append(Vector3(main.x, main.y, big.x))
		# Compagnons : un moyen en retrait sur la berge, un petit dans l'eau.
		var mates := [
			[main + along * (big.x + 0.45) + out * 0.55, Vector3(0.48, 0.4, 0.42) * scale],
			[main - along * (big.x + 0.25) - out * 0.55, Vector3(0.32, 0.22, 0.3) * scale],
			[main - along * (big.x * 0.2) + out * (big.z + 0.75), Vector3(0.3, 0.26, 0.28) * scale],
		]
		for m in mates.size():
			var q: Vector2 = mates[m][0]
			var sz: Vector3 = mates[m][1] * (0.8 + BastideGardenMesher.h(key, 10 + m) * 0.4)
			if b.ctx.blocked(q, sz.x):
				continue
			_rock(b, q, sz, BastideRng.combine(key, m + 1), b.look["rock_b"] if m % 2 == 0 else b.look["rock"], 0.3)
			b.taken.append(Vector3(q.x, q.y, sz.x * 0.9))


## Onsen : la source est cernée de rochers sombres serrés, quelques gros pour s'asseoir.
static func _onsen_ring(b: _Ctx, scale: float) -> void:
	var path := _resample2(b.poly, 0.62)
	for k in path.size():
		var q: Vector2 = path[k]
		var i := _nearest_index(b.poly, q)
		var out := BastidePondShape.outward(b.poly, i)
		var key := BastideRng.combine(b.seed, 2000 + k)
		var big := BastideGardenMesher.h(key, 0) > 0.84
		var sz := Vector3(0.36, 0.26, 0.32) * (0.85 + BastideGardenMesher.h(key, 1) * 0.5)
		if big:
			sz = Vector3(0.62, 0.48, 0.55) * scale
		var p := q + out * (0.15 + sz.z * 0.3)
		if b.blocked(p, sz.x * 0.6):
			continue
		_rock(b, p, sz, key, b.look["rock"] if BastideGardenMesher.h(key, 2) > 0.4 else b.look["rock_b"], 0.25)
		if big:
			b.rock_spots.append(p)


static func _rock(b: _Ctx, q: Vector2, size: Vector3, key: int, col: Color, sink: float) -> void:
	var g := b.ground(q)
	# Sous l'eau, un rocher repose sur le fond ; il dépasse toujours un peu.
	var y := g
	if g < b.level_local:
		size.y = maxf(size.y, (b.level_local - g) * 0.6 + size.y * 0.6)
	var tone := BastideGardenMesher.tint(col, BastideGardenMesher.hs(key, 7) * 0.07)
	mossy_rock(b.mb, Vector3(q.x, y, q.y), size, key, tone, b.look.get("moss", Color(0.36, 0.44, 0.2)), b.level_local, sink)
	if b.collision and size.x > 0.4:
		_box_collision(b, Vector3(q.x, y - 0.1, q.y), Vector3(size.x * 0.75, size.y * 0.9, size.z * 0.75), 0.0)
	b.rocks += 1


## Rocher de rive : bloc bosselé à facettes, aplati dessus, avec de la mousse sur
## les faces qui regardent le ciel et une bande plus sombre (mouillée) au ras de l'eau.
static func mossy_rock(mb: BastideMeshBuilder, center: Vector3, size: Vector3, key: int, col: Color, moss: Color,
		water_y: float, sink := 0.3) -> void:
	var rings := 5
	var segs := 9
	var grid: Array = []
	for i in rings + 1:
		var v := float(i) / rings
		var phi := v * PI
		var row := PackedVector3Array()
		for j in segs:
			var th := TAU * (float(j) + (0.5 if i % 2 == 1 else 0.0)) / segs
			var bump := 1.0 + (BastideGardenMesher.hs(key, i * 31 + j) * 0.2 if i > 0 and i < rings else 0.0)
			var y := cos(phi) * size.y
			# Dessus plus plat (un rocher posé, pas une boule), dessous tassé.
			if y > 0.0:
				y = size.y * pow(cos(phi), 0.6) * (0.9 + BastideGardenMesher.h(key, 200 + j) * 0.12)
			else:
				y *= 0.5
			var skew := 1.0 + 0.25 * cos(th * 2.0 + BastideGardenMesher.h(key, 3) * TAU)
			row.append(center + Vector3(sin(phi) * cos(th) * size.x * bump * skew, y - size.y * sink,
					sin(phi) * sin(th) * size.z * bump))
		grid.append(row)
	var wet := col.darkened(0.35)
	for i in rings:
		var r0: PackedVector3Array = grid[i]
		var r1: PackedVector3Array = grid[i + 1]
		for j in segs:
			var a := r0[j]
			var bb := r0[(j + 1) % segs]
			var c := r1[(j + 1) % segs]
			var d := r1[j]
			var mid := (a + bb + c + d) * 0.25
			# Diagonales : les calottes (pôle dégénéré) gardent une vraie normale.
			var nrm := (c - a).cross(d - bb).normalized()
			if nrm.dot(mid - center) < 0.0:
				nrm = -nrm
			var shade := col * (1.0 + BastideGardenMesher.hs(key, 500 + i * 17 + j) * 0.07)
			# Mousse sur le dessus, plus ou moins selon la face.
			var up := clampf((nrm.y - 0.45) / 0.5, 0.0, 1.0) * (0.45 + BastideGardenMesher.h(key, 700 + i * 13 + j) * 0.55)
			shade = shade.lerp(moss * (0.9 + BastideGardenMesher.h(key, 800 + j) * 0.2), up)
			# Liseré mouillé au ras de l'eau.
			if absf(mid.y - water_y) < 0.12:
				shade = shade.lerp(wet, 0.55)
			shade.a = 1.0
			if i == 0:
				mb.add_tri(ROLE_STONE, a, c, d, mid - center, shade, shade, shade)
			elif i == rings - 1:
				mb.add_tri(ROLE_STONE, a, bb, c, mid - center, shade, shade, shade)
			else:
				mb.add_quad(ROLE_STONE, a, bb, c, d, mid - center, shade, shade, shade, shade)


## Rive de galets (suhama) : une plage de petits galets clairs qui descend dans
## l'eau, sur la partie la plus douce de la rive.
static func _beach(b: _Ctx) -> void:
	var poly := b.poly
	var n := poly.size()
	if b.perimeter < 9.0:
		return
	var len := minf(b.perimeter * 0.22, 9.0)
	var steps := int(len / BastidePondShape.SPACING)
	# La partie la plus bombée de la rive (convexe), loin des rochers et des ponts.
	var best := -INF
	var best_i := -1
	for i in n:
		var score := 0.0
		var ok := true
		for k in steps:
			var j := (i + k) % n
			score += BastidePolygon.turn_cross(poly, j)
			if not b.is_free(poly[j], 1.2):
				ok = false
				break
		if not ok:
			continue
		score += BastideGardenMesher.h(b.seed, 77 + i) * 0.02
		if score > best:
			best = score
			best_i = i
	if best_i < 0:
		return
	var col: Color = b.gs.stepping_stone_color.lightened(0.12)
	for k in steps:
		var j := (best_i + k) % n
		var q := poly[j]
		var out := BastidePondShape.outward(poly, j)
		var along := Vector2(-out.y, out.x)
		# Plus large au milieu de la plage, effilée aux bouts.
		var t := float(k) / maxf(steps - 1, 1)
		var reach := sin(t * PI)
		var rows := int(4 + reach * 6)
		for r in rows:
			var key := BastideRng.combine(b.seed, 5000 + k * 31 + r)
			var off := lerpf(-0.75, 1.1, float(r) / maxf(rows - 1, 1)) * (0.4 + reach * 0.6)
			var p := q + out * off + along * BastideGardenMesher.hs(key, 0) * 0.22
			if b.ctx.blocked(p, 0.08):
				continue
			var s := 0.07 + BastideGardenMesher.h(key, 1) * 0.07
			var tone := BastideGardenMesher.tint(col, BastideGardenMesher.hs(key, 2) * 0.1)
			BastideGardenMesher.rock(b.mb, Vector3(p.x, b.ground(p), p.y), Vector3(s, s * 0.45, s * 0.85), key, tone, 2, 5, 0.3)
			b.pebbles += 1
	for k in steps:
		var q := poly[(best_i + k) % n]
		b.taken.append(Vector3(q.x, q.y, 0.6))


## Pierres de bord : elles cachent la ligne de rive là où il n'y a ni rocher ni
## plage, avec des trous (une rive naturelle n'est pas un collier).
static func _edge_stones(b: _Ctx) -> void:
	if b.kind == Kind.ONSEN:
		return
	var path := _resample2(b.poly, 0.85 if b.kind == Kind.GARDEN else 1.3)
	var per := path.size()
	for k in per:
		var q: Vector2 = path[k]
		var x := float(k) / per * 9.0
		var keep := BastideRng.noise1(b.seed, "edge", x, 9) + BastideGardenMesher.h(b.seed, 900 + k) * 0.2
		if keep < (0.42 if b.kind == Kind.GARDEN else 0.6):
			continue
		if not b.is_free(q, 0.3):
			continue
		var i := _nearest_index(b.poly, q)
		var out := BastidePondShape.outward(b.poly, i)
		var key := BastideRng.combine(b.seed, 3000 + k)
		var s := 0.16 + BastideGardenMesher.h(key, 1) * 0.16
		var p := q + out * BastideGardenMesher.hs(key, 2) * 0.12
		if b.ctx.blocked(p, s):
			continue
		var tone := BastideGardenMesher.tint(b.look["rock_b"] if BastideGardenMesher.h(key, 3) > 0.5 else b.look["rock"], BastideGardenMesher.hs(key, 4) * 0.08)
		mossy_rock(b.mb, Vector3(p.x, b.ground(p), p.y), Vector3(s, s * 0.6, s * 0.85), key, tone, b.look["moss"], b.level_local, 0.35)
		b.stones += 1


# --- Plantes ----------------------------------------------------------------------

## Iris et roseaux les pieds dans l'eau, massifs fleuris et fougères sur la berge.
static func _plants(b: _Ctx) -> void:
	var gs := b.gs
	var use_kit := gs.kit_plants
	var iris := BastideKitNature.plant("iris") if use_kit else {}
	var reed := BastideKitNature.tuft("reed", Color(0.92, 0.95, 0.8), 1.6) if use_kit else {}
	var fern := BastideKitNature.tuft("fern", Color.WHITE, 1.1) if use_kit else {}
	var n := b.poly.size()
	# Bouquets au bord de l'eau : iris (jardin), roseaux (mare sauvage).
	var clusters := 0
	match b.kind:
		Kind.GARDEN:
			clusters = clampi(int(b.perimeter / 10.0), 1, 5)
		Kind.WILD:
			clusters = clampi(int(b.perimeter / 5.0), 2, 10)
	for ci in clusters:
		var key := BastideRng.combine(b.seed, 7000 + ci)
		var i := int((float(ci) + BastideGardenMesher.h(key, 0) * 0.6) / clusters * n) % n
		var q0 := b.poly[i]
		var out0 := BastidePondShape.outward(b.poly, i)
		var along := Vector2(-out0.y, out0.x)
		var count := 6 + int(BastideGardenMesher.h(key, 1) * 6) + (6 if b.kind == Kind.WILD else 0)
		for k in count:
			var kk := BastideRng.combine(key, k)
			var p := q0 + along * BastideGardenMesher.hs(kk, 0) * (1.2 if b.kind == Kind.GARDEN else 2.2) \
					+ out0 * lerpf(-0.75, 0.15, BastideGardenMesher.h(kk, 1))
			if b.ctx.blocked(p, 0.2) or not b.is_free(p, 0.15):
				continue
			var g := b.ground(p)
			var y := maxf(g, b.level_local - 0.3)
			var rot := BastideGardenMesher.h(kk, 2) * TAU
			var use_reed := b.kind == Kind.WILD and BastideGardenMesher.h(kk, 3) > 0.25 or b.kind == Kind.GARDEN and BastideGardenMesher.h(kk, 3) > 0.8
			if use_reed and not reed.is_empty():
				var s := 0.9 + BastideGardenMesher.h(kk, 4) * 0.7
				b.add("reed", reed["mesh"], reed["mat"], Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y)))
			elif not iris.is_empty():
				var s := 0.8 + BastideGardenMesher.h(kk, 4) * 0.5
				b.add("iris", iris["mesh"], iris["mat"], Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y)))
			else:
				BastideGardenMesher.grass(b.mb, Vector3(p.x, y, p.y), 0.5, gs, kk)
			b.plants += 1
	# Sur la berge : quelques massifs fleuris (jardin), des fougères au pied des rochers.
	var shrubs := ["hydrangea_blue", "azalea_pink", "hydrangea_pink", "azalea_red"]
	if b.kind == Kind.GARDEN and use_kit:
		var m := clampi(int(b.perimeter / 9.0), 1, 6)
		for si in m:
			var key := BastideRng.combine(b.seed, 8000 + si)
			var i := int((float(si) + 0.5 + BastideGardenMesher.hs(key, 0) * 0.3) / m * n) % n
			var p := b.poly[i] + BastidePondShape.outward(b.poly, i) * (1.3 + BastideGardenMesher.h(key, 1) * 0.9)
			if b.blocked(p, 0.8):
				continue
			var model: String = shrubs[int(BastideGardenMesher.h(key, 2) * shrubs.size()) % shrubs.size()]
			var pl := BastideKitNature.plant(model, 0.9 + BastideGardenMesher.h(key, 3) * 0.3)
			if pl.is_empty():
				continue
			var t := Transform3D(Basis(Vector3.UP, BastideGardenMesher.h(key, 4) * TAU), Vector3(p.x, b.ground(p), p.y))
			b.add("bank/" + model, pl["mesh"], pl["mat"], t)
			if pl.has("trunk") and pl["trunk"] != null:
				b.add("bankwood/" + model, pl["trunk"], BastideKitNature.trunk_material(), t)
			b.taken.append(Vector3(p.x, p.y, 0.7))
			b.plants += 1
	if not fern.is_empty():
		for ri in b.rock_spots.size():
			var c: Vector2 = b.rock_spots[ri]
			for k in 3:
				var key := BastideRng.combine(b.seed, 9000 + ri * 7 + k)
				var a := BastideGardenMesher.h(key, 0) * TAU
				var p := c + Vector2(cos(a), sin(a)) * (0.9 + BastideGardenMesher.h(key, 1) * 0.6)
				if b.dist(p) < 0.25 or b.ctx.blocked(p, 0.3):
					continue
				var s := 0.7 + BastideGardenMesher.h(key, 2) * 0.5
				b.add("fern", fern["mesh"], fern["mat"], Transform3D(Basis(Vector3.UP, a).scaled(Vector3.ONE * s), Vector3(p.x, b.ground(p), p.y)))
				b.plants += 1


## Nénuphars : feuilles rondes fendues, quelques fleurs roses et blanches, en
## colonies loin de la rive.
static func _lilies(b: _Ctx) -> void:
	var box := BastidePondShape.rect_of(b.poly)
	var colonies := clampi(int(b.area / 30.0), 1, 4) + (2 if b.kind == Kind.WILD else 0)
	var rng := BastideRng.derive(b.seed, "lilies")
	var y := b.level_local + 0.012
	for ci in colonies:
		var c := Vector2.ZERO
		var found := false
		for tries in 40:
			c = Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
			if b.dist(c) < -1.0 and b.is_free(c, 1.0):
				found = true
				break
		if not found:
			continue
		var count := rng.randi_range(5, 11) + (5 if b.kind == Kind.WILD else 0)
		for k in count:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * 1.3
			var p := c + Vector2(cos(a), sin(a)) * r
			if b.dist(p) > -0.4 or not b.is_free(p, 0.2):
				continue
			var size := rng.randf_range(0.16, 0.3)
			_pad(b, Vector3(p.x, y + k * 0.0008, p.y), size, rng.randf() * TAU, rng.randf())
			if rng.randf() < (0.3 if b.kind == Kind.GARDEN else 0.15):
				var pink := rng.randf() < 0.6
				_lotus(b, Vector3(p.x + size * 0.3, y + 0.01, p.y), size * 0.5, pink, rng.randf() * TAU)
			b.lilies += 1


static func _pad(b: _Ctx, c: Vector3, r: float, rot: float, shade: float) -> void:
	var col := Color(0.24, 0.42, 0.17).lerp(Color(0.38, 0.5, 0.2), shade)
	var rim := col.darkened(0.15)
	var segs := 14
	var notch := 0.42  # fente du nénuphar
	var prev := Vector3.ZERO
	for i in segs + 1:
		var a := rot + notch * 0.5 + (TAU - notch) * float(i) / segs
		var p := c + Vector3(cos(a) * r, 0.0, sin(a) * r)
		if i > 0:
			b.mb.add_tri(ROLE_LILY, c + Vector3(0, 0.004, 0), prev, p, Vector3.UP, col.lightened(0.06), rim, rim)
		prev = p


static func _lotus(b: _Ctx, c: Vector3, r: float, pink: bool, rot: float) -> void:
	var outer := Color(0.96, 0.62, 0.74) if pink else Color(0.97, 0.95, 0.9)
	var inner := Color(0.99, 0.9, 0.92) if pink else Color(1.0, 0.98, 0.9)
	var heart := Color(0.98, 0.82, 0.3)
	for layer in 2:
		var petals := 7 - layer * 2
		var rr := r * (1.0 - layer * 0.35)
		var lift := 0.05 + layer * 0.04
		for i in petals:
			var a := rot + TAU * (i + layer * 0.5) / petals
			var d := Vector3(cos(a), 0, sin(a))
			var s := Vector3(-d.z, 0, d.x) * rr * 0.32
			var base := c + d * rr * 0.12 + Vector3(0, 0.01, 0)
			var tip := c + d * rr + Vector3(0, lift + rr * 0.6, 0)
			var col := outer if layer == 0 else inner
			b.mb.add_tri(ROLE_LILY, base - s, base + s, tip, d + Vector3(0, 0.6, 0), col.darkened(0.08), col.darkened(0.08), col)
	BastideGardenMesher.blob(b.mb, ROLE_LILY, c + Vector3(0, 0.05, 0), Vector3(r * 0.16, r * 0.1, r * 0.16), heart, 7, 2, 6)


# --- Koï ------------------------------------------------------------------------------

## Carpes koï : chacune tourne lentement sur son propre cercle, sous la surface
## (animées dans leur shader : rien à faire à chaque image).
static func _koi(b: _Ctx) -> void:
	var rng := BastideRng.derive(b.seed, "koi")
	var want := clampi(int(b.area / 7.0), 2, 11)
	var box := BastidePondShape.rect_of(b.poly)
	var meshes := [_koi_mesh(0), _koi_mesh(1), _koi_mesh(2)]
	var mat := koi_material()
	var koi_groups := {}
	var tries := 0
	while b.koi < want and tries < 300:
		tries += 1
		var c := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
		var d := b.dist(c)
		if d > -1.3:
			continue
		var radius := minf(-d - 0.8, rng.randf_range(0.7, 2.4))
		if radius < 0.45:
			continue
		var depth := clampf(b.level_local - b.ground(c), 0.2, 2.0)
		var y := b.level_local - clampf(depth * 0.4, 0.14, 0.35)
		var s := rng.randf_range(0.75, 1.25)
		var t := Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(c.x, y, c.y))
		var variant := rng.randi_range(0, 2)
		var speed := rng.randf_range(0.16, 0.32) * (1.0 if rng.randf() < 0.5 else -1.0)
		var g: Dictionary = koi_groups.get(variant, {})
		if g.is_empty():
			g = {"mesh": meshes[variant], "xf": [], "custom": []}
			koi_groups[variant] = g
		# Le cercle (rayon, vitesse en m/s, phase) est lu par le shader.
		(g["xf"] as Array).append(t)
		(g["custom"] as Array).append(Color(radius, speed, rng.randf() * TAU, s))
		b.koi += 1
	for g: Dictionary in koi_groups.values():
		b.result.add_instances(g["mesh"], mat, g["xf"], GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 0.0, 70.0)
		b.result.instances[b.result.instances.size() - 1]["custom"] = g["custom"]


## Une carpe (environ 45 cm), vue de dessus : corps fuselé, nageoires, couleurs
## kohaku (blanc et rouge), ogon (or) ou showa (noir, rouge, blanc).
static func _koi_mesh(variant: int) -> ArrayMesh:
	var key := "koi_mesh/%d" % variant
	_mutex.lock()
	var cached: ArrayMesh = _materials.get(key)
	_mutex.unlock()
	if cached:
		return cached
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 10
	var segs := 8
	var length := 0.46
	var grid: Array = []
	for i in rings + 1:
		var t := float(i) / rings  # 0 = tête, 1 = queue
		var z := (0.5 - t) * length
		var r := sin(pow(t, 0.75) * PI) * 0.055 * (1.0 - t * 0.35) + 0.004
		var row := []
		for j in segs:
			var a := TAU * j / segs
			row.append(Vector3(cos(a) * r * 1.15, sin(a) * r * 0.85, z))
		grid.append(row)
	for i in rings:
		for j in segs:
			var a: Vector3 = grid[i][j]
			var bb: Vector3 = grid[i][(j + 1) % segs]
			var c: Vector3 = grid[i + 1][(j + 1) % segs]
			var d: Vector3 = grid[i + 1][j]
			for v in [a, bb, c, a, c, d]:
				st.set_color(_koi_color(variant, v, length))
				st.set_normal(Vector3(v.x, v.y * 1.5, 0).normalized() if Vector2(v.x, v.y).length() > 1e-4 else Vector3.UP)
				st.add_vertex(v)
	# Queue en éventail et nageoires pectorales (deux faces).
	var tail_root := Vector3(0, 0, -length * 0.5)
	var fin_col := _koi_color(variant, Vector3(0, 0.05, -length * 0.5), length).lightened(0.15)
	fin_col.a = 1.0
	for tri in [[tail_root, tail_root + Vector3(-0.07, 0.0, -0.11), tail_root + Vector3(0.0, 0.0, -0.07)],
			[tail_root, tail_root + Vector3(0.0, 0.0, -0.07), tail_root + Vector3(0.07, 0.0, -0.11)],
			[Vector3(0.05, -0.01, 0.1), Vector3(0.12, -0.02, 0.05), Vector3(0.05, -0.01, 0.05)],
			[Vector3(-0.05, -0.01, 0.1), Vector3(-0.05, -0.01, 0.05), Vector3(-0.12, -0.02, 0.05)]]:
		for v: Vector3 in tri:
			st.set_color(fin_col)
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mesh := st.commit()
	_mutex.lock()
	_materials[key] = mesh
	_mutex.unlock()
	return mesh


static func _koi_color(variant: int, v: Vector3, length: float) -> Color:
	var white := Color(0.96, 0.94, 0.9)
	var red := Color(0.9, 0.25, 0.08)
	var gold := Color(0.98, 0.66, 0.18)
	var black := Color(0.08, 0.07, 0.07)
	var t := 0.5 - v.z / length
	var belly := v.y < -0.015
	var n := sin(v.x * 70.0 + t * 9.0 + variant * 2.0) * 0.5 + sin(t * 17.0 + variant) * 0.5
	match variant:
		0:
			if belly:
				return white
			return red if n > 0.05 and t > 0.08 and t < 0.85 else white
		1:
			return gold.lerp(Color(1.0, 0.85, 0.5), clampf(n * 0.5 + 0.3, 0.0, 1.0)) if not belly else gold.lightened(0.3)
		_:
			if belly:
				return white
			if n > 0.45:
				return black
			return red if n > -0.2 else white


# --- Outils ----------------------------------------------------------------------------

static func _resample2(poly: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var pts := PackedVector3Array()
	for p in poly:
		pts.append(Vector3(p.x, 0, p.y))
	var r := BastideStroke.resample(pts, spacing, true)
	var out := PackedVector2Array()
	for p in r:
		out.append(Vector2(p.x, p.z))
	return out


static func _nearest_index(poly: PackedVector2Array, q: Vector2) -> int:
	var best := 0
	var bd := INF
	for i in poly.size():
		var d := poly[i].distance_squared_to(q)
		if d < bd:
			bd = d
			best = i
	return best


## Distance le long de la rive entre deux sommets (la plus courte des deux).
static func _arc(poly: PackedVector2Array, i: int, j: int, perimeter: float) -> float:
	var n := poly.size()
	var k := absi(i - j)
	var d := float(mini(k, n - k)) * BastidePondShape.SPACING
	return minf(d, perimeter)
