@tool
class_name BastideFarmBuilder
extends RefCounted
## Cultures dans une zone tracée : potager, rizière, champ de thé.
##
## La zone est découpée en une grille fine (cases de 50 cm) alignée sur le champ :
## les rangs suivent les courbes de niveau sur une pente, l'axe long du champ sur le
## plat. Chaque case porte sa terre, à sa hauteur :
## - potager : la terre suit le relief ; planches de culture surélevées, rangs de
##   choux, daikon, negi, aubergines et tomates sur tuteurs, potirons ; une clôture
##   basse de bambou s'ouvre vers le chemin le plus proche ; un épouvantail ;
## - rizière : la pente est taillée en terrasses de niveau (tanada), retenues par des
##   murets de pierres sèches ; chaque terrasse est une nappe d'eau peu profonde
##   bordée de levées de terre herbue, avec ses touffes de riz alignées ;
## - champ de thé : longues haies arrondies et taillées, qui suivent les courbes,
##   paille entre les rangs et ventilateurs antigel sur leurs mâts.
##
## Le sol (BastideTerrain) est abaissé sous le champ (ancre « carve ») ; la terre du
## champ est posée par-dessus, ses bords descendent en talus ou en muret.
## Fonction pure : build() tourne sur un thread de génération.

enum Kind { VEGETABLE, RICE, TEA }

const ROLE_SOIL := &"soil"
const ROLE_HEDGE := &"hedge"
const ROLE_WATER := &"water"
const ROLE_CLOTH := &"cloth"
const ROLE_STONE := BastideGardenMesher.ROLE_STONE
const ROLE_WOOD := BastideGardenMesher.ROLE_WOOD
const ROLE_PAINT := BastideGardenMesher.ROLE_PAINT

const SOIL_SHADER := preload("res://addons/bastide/shaders/bastide_soil.gdshader")
const WATER_SHADER := preload("res://addons/bastide/shaders/bastide_water.gdshader")

## Taille d'une case (m).
const CELL := 0.5
## La terre du champ est posée un peu au-dessus du relief d'origine.
const LIFT := 0.04
## Le relief est abaissé d'autant sous le champ (jamais d'herbe qui perce).
const DROP := 0.14
## Rizière : hauteur visée entre deux terrasses, largeur maximale d'une terrasse.
const STEP := 0.55
const TERRACE_MAX := 8.0
const TERRACE_MIN := 2.0
## Levées : hauteur au-dessus du fond, eau au-dessus du fond.
const DIKE_H := 0.22
const WATER_H := 0.1
## Potager : largeur d'une planche et du passage entre deux.
const BED_W := 0.9
const BED_GAP := 0.55
const BED_H := 0.18
## Thé : largeur et hauteur d'une haie, écart entre deux rangs.
const TEA_W := 1.3
const TEA_H := 0.9
const TEA_PERIOD := 1.7
const MIN_AREA := 8.0
## Distance d'affichage des plantes (m).
const PLANT_RANGE := 80.0

enum Cell { OUT, SOIL, WATER, DIKE }

static var _mutex := Mutex.new()
static var _materials := {}


static func soil_material() -> ShaderMaterial:
	_mutex.lock()
	var m: ShaderMaterial = _materials.get("soil")
	if m == null:
		m = ShaderMaterial.new()
		m.shader = SOIL_SHADER
		m.set_shader_parameter("fleck_color", Color(0.66, 0.57, 0.38))
		m.set_shader_parameter("fleck_amount", 0.1)
		_materials["soil"] = m
	_mutex.unlock()
	return m


static func hedge_material() -> ShaderMaterial:
	_mutex.lock()
	var m: ShaderMaterial = _materials.get("hedge")
	if m == null:
		m = ShaderMaterial.new()
		m.shader = SOIL_SHADER
		m.set_shader_parameter("grain_strength", 0.08)
		m.set_shader_parameter("clod_scale", 1.4)
		m.set_shader_parameter("clod_strength", 0.16)
		m.set_shader_parameter("roughness_value", 0.85)
		m.set_shader_parameter("specular_value", 0.25)
		m.set_shader_parameter("fleck_color", Color(0.6, 0.7, 0.28))
		m.set_shader_parameter("leafy", 1.0)
		m.set_shader_parameter("leaf_scale", 8.0)
		_materials["hedge"] = m
	_mutex.unlock()
	return m


## Eau des rizières : peu profonde, boueuse, qui renvoie le ciel.
static func paddy_water_material() -> ShaderMaterial:
	_mutex.lock()
	var m: ShaderMaterial = _materials.get("water")
	if m == null:
		m = ShaderMaterial.new()
		m.shader = WATER_SHADER
		m.set_shader_parameter("shallow_tint", Color(0.8, 0.8, 0.68))
		m.set_shader_parameter("deep_color", Color(0.36, 0.34, 0.24))
		m.set_shader_parameter("scatter_color", Color(0.46, 0.44, 0.31))
		m.set_shader_parameter("absorption", 3.5)
		m.set_shader_parameter("milky", 0.12)
		m.set_shader_parameter("milky_color", Color(0.5, 0.48, 0.36))
		m.set_shader_parameter("shore_foam", 0.0)
		m.set_shader_parameter("caustics", 0.0)
		m.set_shader_parameter("ripple_strength", 0.07)
		m.set_shader_parameter("ripple_scale", 1.6)
		m.set_shader_parameter("sky_reflection", 1.0)
		_materials["water"] = m
	_mutex.unlock()
	return m


static func cloth_material() -> StandardMaterial3D:
	_mutex.lock()
	var m: StandardMaterial3D = _materials.get("cloth")
	if m == null:
		m = StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.92
		_materials["cloth"] = m
	_mutex.unlock()
	return m


## Tout le champ. `xf` : repère local → monde ; `field` : relief d'origine (sans
## creusement), ou null (sol plat à y = 0).
static func build(points: PackedVector3Array, seed: int, kind: int, style: BastideStyle, ctx: BastideGardenContext,
		field: BastideHeightField, xf: Transform3D, with_collision := true) -> BastideBuildResult:
	var result := BastideBuildResult.new()
	if points.size() < 3:
		return result
	var poly := BastidePondShape.outline(points, seed, 0.0)
	if poly.size() < 3 or absf(BastidePolygon.signed_area(poly)) < MIN_AREA:
		return result
	if ctx == null:
		ctx = BastideGardenContext.new()
	var b := _Ctx.new()
	b.poly = poly
	b.seed = seed
	b.kind = kind
	b.field = field
	b.xf = xf
	b.ctx = ctx
	b.gs = style.get_garden_style()
	b.mb = BastideMeshBuilder.new()
	b.result = result
	b.collision = with_collision
	b.fol = style.get_foliage_material()
	b.area = absf(BastidePolygon.signed_area(poly))

	_frame(b)
	_grid(b)
	match kind:
		Kind.RICE:
			_terraces(b)
		Kind.TEA:
			_cells_soil(b, Color(0.45, 0.36, 0.26))
		_:
			_cells_soil(b, Color(0.37, 0.3, 0.24))
	_ground_mesh(b)
	match kind:
		Kind.RICE:
			_rice(b)
			_scarecrow_on(b)
		Kind.TEA:
			_tea_rows(b)
			_frost_fans(b)
		_:
			_scarecrow_on(b)
			_shed(b)
			_beds(b)
			_fence(b)
	for g: Dictionary in b.groups.values():
		result.add_instances(g["mesh"], g["mat"], g["xf"], GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 0.0, PLANT_RANGE)

	var mats := BastideGardenMesher.materials(style)
	mats[ROLE_SOIL] = soil_material()
	mats[ROLE_HEDGE] = hedge_material()
	mats[ROLE_WATER] = paddy_water_material()
	mats[ROLE_CLOTH] = cloth_material()
	result.mesh = b.mb.commit(mats)
	var carve := _carve(b)
	result.anchors = {"outline": poly, "carve": carve, "kind": kind, "axis": b.u}
	if b.shed_at != Vector2.INF:
		result.anchors["shed"] = b.shed_at
	result.stats = {"area": snappedf(b.area, 0.1), "cells": b.cells, "beds": b.beds, "crops": b.crops,
		"terraces": b.terraces, "paddies": b.paddies, "rice": b.rice, "hedges": b.hedges, "fence_posts": b.posts,
		"gate": b.gate, "fans": b.fans, "scarecrows": b.scarecrows, "sheds": b.sheds, "triangles": b.mb.triangle_count}
	return result


## État partagé d'une génération.
class _Ctx:
	var poly: PackedVector2Array
	var seed: int
	var kind: int
	var field: BastideHeightField
	var xf: Transform3D
	var ctx: BastideGardenContext
	var gs: BastideGardenStyle
	var mb: BastideMeshBuilder
	var result: BastideBuildResult
	var collision := true
	var fol: Material
	var area := 0.0
	## Repère du champ : centre, axe des rangs (u), axe montant (v).
	var c0 := Vector2.ZERO
	var u := Vector2.RIGHT
	var v := Vector2.DOWN
	var s0 := 0.0
	var t0 := 0.0
	var ns := 0
	var nt := 0
	## Par case : 0 dehors, 1 pleine, 2 coupée par le bord.
	var state := PackedByteArray()
	## Par case : distance au bord du champ (m).
	var edge := PackedFloat32Array()
	## Par case : sur un chemin qui traverse.
	var on_path := PackedByteArray()
	## Hauteurs (locales) du relief d'origine aux coins des cases.
	var corner := PackedFloat32Array()
	## Par case : type (Cell) et hauteur du fond (rizière).
	var ctype := PackedByteArray()
	var floor_h := PackedFloat32Array()
	var color := PackedColorArray()
	## Morceaux des cases coupées : index -> Array[PackedVector2Array].
	var clips := {}
	## Rizière : terrasse de chaque rangée de cases.
	var row_terrace := PackedInt32Array()
	var groups := {}
	var taken: Array[Vector3] = []
	var cells := 0
	var beds := 0
	var crops := 0
	var terraces := 0
	var paddies := 0
	var rice := 0
	var hedges := 0
	var posts := 0
	var gate := false
	var fans := 0
	var scarecrows := 0
	var sheds := 0
	var shed_at := Vector2.INF

	func at(s: float, t: float) -> Vector2:
		return c0 + u * s + v * t

	func st(q: Vector2) -> Vector2:
		var d := q - c0
		return Vector2(d.dot(u), d.dot(v))

	func idx(i: int, j: int) -> int:
		return j * ns + i

	## Hauteur (locale) du relief d'origine.
	func base(q: Vector2) -> float:
		if field == null:
			return 0.0
		var w := xf * Vector3(q.x, 0.0, q.y)
		return field.height(w.x, w.z) - xf.origin.y

	## Case sous q, ou -1.
	func cell_of(q: Vector2) -> int:
		var f := st(q)
		var i := floori((f.x - s0) / CELL)
		var j := floori((f.y - t0) / CELL)
		if i < 0 or j < 0 or i >= ns or j >= nt:
			return -1
		return idx(i, j)

	## Relief d'origine, interpolé dans la grille des coins.
	func corner_base(q: Vector2) -> float:
		var f := st(q)
		var fx := clampf((f.x - s0) / CELL, 0.0, ns - 0.0001)
		var fz := clampf((f.y - t0) / CELL, 0.0, nt - 0.0001)
		var i := int(fx)
		var j := int(fz)
		var tx := fx - i
		var tz := fz - j
		var w := ns + 1
		var a := corner[j * w + i]
		var bb := corner[j * w + i + 1]
		var c := corner[(j + 1) * w + i]
		var d := corner[(j + 1) * w + i + 1]
		return lerpf(lerpf(a, bb, tx), lerpf(c, d, tx), tz)

	## Dessus de la terre du champ en q (local).
	func ground(q: Vector2) -> float:
		if kind == Kind.RICE:
			var k := cell_of(q)
			if k < 0 or state[k] == 0:
				return corner_base(q) + LIFT
			return floor_h[k] + (DIKE_H if ctype[k] == Cell.DIKE else 0.0)
		return corner_base(q) + LIFT

	func edge_at(q: Vector2) -> float:
		var k := cell_of(q)
		return edge[k] if k >= 0 and state[k] != 0 else -1.0

	func is_free(q: Vector2, r: float) -> bool:
		for t in taken:
			if Vector2(t.x, t.y).distance_to(q) < t.z + r:
				return false
		return true

	func add(gkey: String, m: Mesh, mat: Material, t: Transform3D) -> void:
		if m == null:
			return
		var g: Dictionary = groups.get(gkey, {})
		if g.is_empty():
			g = {"mesh": m, "mat": mat, "xf": []}
			groups[gkey] = g
		(g["xf"] as Array).append(t)


static func h(key: int, i: int) -> float:
	return BastideGardenMesher.h(key, i)


static func hs(key: int, i: int) -> float:
	return BastideGardenMesher.hs(key, i)


# --- Repère et grille ------------------------------------------------------------------

## Axe des rangs : le long des courbes de niveau sur une pente, l'axe long du champ
## sur le plat.
static func _frame(b: _Ctx) -> void:
	var poly := b.poly
	b.c0 = BastidePolygon.centroid(poly)
	# Plan moyen du relief sous le champ (moindres carrés), sur la rive et l'intérieur.
	var pts: Array[Vector2] = []
	for i in range(0, poly.size(), 2):
		pts.append(poly[i])
	var box := BastidePondShape.rect_of(poly)
	var step := maxf(1.5, maxf(box.size.x, box.size.y) / 12.0)
	var x := box.position.x + step * 0.5
	while x < box.end.x:
		var z := box.position.y + step * 0.5
		while z < box.end.y:
			if Geometry2D.is_point_in_polygon(Vector2(x, z), poly):
				pts.append(Vector2(x, z))
			z += step
		x += step
	var sxx := 0.0
	var sxz := 0.0
	var szz := 0.0
	var sxh := 0.0
	var szh := 0.0
	var hm := 0.0
	for p in pts:
		hm += b.base(p)
	hm /= maxf(pts.size(), 1)
	for p in pts:
		var d := p - b.c0
		var hh := b.base(p) - hm
		sxx += d.x * d.x
		sxz += d.x * d.y
		szz += d.y * d.y
		sxh += d.x * hh
		szh += d.y * hh
	var det := sxx * szz - sxz * sxz
	var grad := Vector2.ZERO
	if absf(det) > 1e-6:
		grad = Vector2((sxh * szz - szh * sxz) / det, (szh * sxx - sxh * sxz) / det)
	if grad.length() > 0.035:
		b.v = grad.normalized()
		b.u = Vector2(b.v.y, -b.v.x)
	else:
		# Axe principal (covariance du contour).
		var a := 0.5 * atan2(2.0 * sxz, sxx - szz)
		b.u = Vector2(cos(a), sin(a))
		b.v = Vector2(-b.u.y, b.u.x)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		var f := b.st(p)
		lo = Vector2(minf(lo.x, f.x), minf(lo.y, f.y))
		hi = Vector2(maxf(hi.x, f.x), maxf(hi.y, f.y))
	b.s0 = lo.x - CELL * 0.5
	b.t0 = lo.y - CELL * 0.5
	b.ns = ceili((hi.x - b.s0) / CELL) + 1
	b.nt = ceili((hi.y - b.t0) / CELL) + 1


static func _grid(b: _Ctx) -> void:
	var n := b.ns * b.nt
	b.state.resize(n)
	b.state.fill(0)
	b.edge.resize(n)
	b.on_path.resize(n)
	b.on_path.fill(0)
	b.ctype.resize(n)
	b.ctype.fill(Cell.OUT)
	b.floor_h.resize(n)
	b.floor_h.fill(0.0)
	b.color.resize(n)
	b.corner.resize((b.ns + 1) * (b.nt + 1))
	for j in b.nt + 1:
		for i in b.ns + 1:
			b.corner[j * (b.ns + 1) + i] = b.base(b.at(b.s0 + i * CELL, b.t0 + j * CELL))
	# Les cases traversées par le bord sont coupées ; les autres, dedans ou dehors.
	var poly := b.poly
	for e in poly.size():
		var p0 := poly[e]
		var p1 := poly[(e + 1) % poly.size()]
		var m := maxi(1, ceili(p0.distance_to(p1) / (CELL * 0.25)))
		for k in m + 1:
			var c := b.cell_of(p0.lerp(p1, float(k) / m))
			if c >= 0:
				b.state[c] = 2
	for j in b.nt:
		for i in b.ns:
			var k := b.idx(i, j)
			var q := b.at(b.s0 + (i + 0.5) * CELL, b.t0 + (j + 0.5) * CELL)
			if b.state[k] == 2:
				var quad := PackedVector2Array([b.at(b.s0 + i * CELL, b.t0 + j * CELL), b.at(b.s0 + (i + 1) * CELL, b.t0 + j * CELL),
					b.at(b.s0 + (i + 1) * CELL, b.t0 + (j + 1) * CELL), b.at(b.s0 + i * CELL, b.t0 + (j + 1) * CELL)])
				var parts := Geometry2D.intersect_polygons(quad, poly)
				var keep: Array = []
				for part: PackedVector2Array in parts:
					if part.size() >= 3 and absf(BastidePolygon.signed_area(part)) > 0.002:
						keep.append(part)
				if keep.is_empty():
					b.state[k] = 0
				else:
					b.clips[k] = keep
			elif Geometry2D.is_point_in_polygon(q, poly):
				b.state[k] = 1
			if b.state[k] == 0:
				continue
			# Maisons, terrasses, étangs, murs : le champ s'écarte. Un chemin traverse.
			if b.ctx.path_clearance(q) < 0.45:
				b.on_path[k] = 1
			elif b.ctx.blocked(q, 0.2):
				b.state[k] = 0
				b.clips.erase(k)
	# Distance au bord (chanfrein, deux passes).
	var big := 1e6
	for k in n:
		b.edge[k] = big if b.state[k] == 1 else 0.0
	var d1 := CELL
	var d2 := CELL * 1.4142
	for j in b.nt:
		for i in b.ns:
			var k := b.idx(i, j)
			if b.edge[k] == 0.0:
				continue
			var best: float = b.edge[k]
			best = minf(best, _edge_n(b, i - 1, j) + d1)
			best = minf(best, _edge_n(b, i, j - 1) + d1)
			best = minf(best, _edge_n(b, i - 1, j - 1) + d2)
			best = minf(best, _edge_n(b, i + 1, j - 1) + d2)
			b.edge[k] = best
	for j in range(b.nt - 1, -1, -1):
		for i in range(b.ns - 1, -1, -1):
			var k := b.idx(i, j)
			if b.edge[k] == 0.0:
				continue
			var best: float = b.edge[k]
			best = minf(best, _edge_n(b, i + 1, j) + d1)
			best = minf(best, _edge_n(b, i, j + 1) + d1)
			best = minf(best, _edge_n(b, i + 1, j + 1) + d2)
			best = minf(best, _edge_n(b, i - 1, j + 1) + d2)
			b.edge[k] = best
	for k in n:
		if b.state[k] != 0:
			b.cells += 1


static func _edge_n(b: _Ctx, i: int, j: int) -> float:
	if i < 0 or j < 0 or i >= b.ns or j >= b.nt:
		return 0.0
	return b.edge[b.idx(i, j)]


static func _cells_soil(b: _Ctx, col: Color) -> void:
	for k in b.state.size():
		if b.state[k] == 0:
			continue
		b.ctype[k] = Cell.SOIL
		var key := BastideRng.combine(b.seed, k)
		b.color[k] = BastideGardenMesher.tint(col, hs(key, 1) * 0.04)


# --- Rizière en terrasses -----------------------------------------------------------------

## La pente est découpée en terrasses de même largeur, chacune à son niveau (la moyenne
## du relief sous elle : autant de déblai que de remblai). Une levée borde le bas de
## chaque terrasse et tout le tour du champ ; d'autres levées recoupent les longues
## terrasses en rizières.
static func _terraces(b: _Ctx) -> void:
	var row_sum := PackedFloat32Array()
	var row_n := PackedInt32Array()
	row_sum.resize(b.nt)
	row_n.resize(b.nt)
	var j_lo := -1
	var j_hi := -1
	for j in b.nt:
		for i in b.ns:
			var k := b.idx(i, j)
			if b.state[k] == 0:
				continue
			row_sum[j] += b.corner_base(b.at(b.s0 + (i + 0.5) * CELL, b.t0 + (j + 0.5) * CELL))
			row_n[j] += 1
		if row_n[j] > 0:
			if j_lo < 0:
				j_lo = j
			j_hi = j
	if j_lo < 0:
		return
	var span := (j_hi - j_lo + 1) * CELL
	var rise := row_sum[j_hi] / row_n[j_hi] - row_sum[j_lo] / row_n[j_lo]
	var count := maxi(ceili(absf(rise) / STEP), ceili(span / TERRACE_MAX))
	count = clampi(count, 1, maxi(1, floori(span / TERRACE_MIN)))
	var rows := float(j_hi - j_lo + 1) / count
	b.row_terrace.resize(b.nt)
	var lvl_sum := PackedFloat32Array()
	var lvl_n := PackedInt32Array()
	lvl_sum.resize(count)
	lvl_n.resize(count)
	for j in b.nt:
		var tk := clampi(floori((j - j_lo) / rows), 0, count - 1)
		b.row_terrace[j] = tk
		lvl_sum[tk] += row_sum[j]
		lvl_n[tk] += row_n[j]
	var levels := PackedFloat32Array()
	for tk in count:
		levels.append(lvl_sum[tk] / maxi(lvl_n[tk], 1))
	# Jamais une terrasse plus basse que celle d'en dessous (relief bosselé).
	for tk in range(1, count):
		levels[tk] = maxf(levels[tk], levels[tk - 1] + (0.0 if absf(rise) < STEP * 0.5 else 0.12))
	b.terraces = count
	# Levées qui recoupent : tous les ~9 m le long des rangs.
	var s_lo := INF
	var s_hi := -INF
	for p in b.poly:
		var f := b.st(p)
		s_lo = minf(s_lo, f.x)
		s_hi = maxf(s_hi, f.x)
	var cuts := maxi(1, roundi((s_hi - s_lo) / 9.0))
	var cut_cols: Array[int] = []
	for c in range(1, cuts):
		var s := s_lo + (s_hi - s_lo) * c / cuts + hs(b.seed, 70 + c) * 0.8
		cut_cols.append(floori((s - b.s0) / CELL))
	b.paddies = count * cuts
	for j in b.nt:
		var tk: int = b.row_terrace[j]
		var first := j == j_lo or (j > 0 and b.row_terrace[j - 1] != tk)
		for i in b.ns:
			var k := b.idx(i, j)
			if b.state[k] == 0:
				continue
			b.floor_h[k] = levels[tk]
			var key := BastideRng.combine(b.seed, k)
			var dike: bool = b.state[k] == 2 or b.edge[k] < 0.6 or first or b.on_path[k] == 1 or i in cut_cols
			if dike:
				b.ctype[k] = Cell.DIKE
				b.color[k] = BastideGardenMesher.tint(Color(0.4, 0.47, 0.22), hs(key, 1) * 0.06)
			else:
				b.ctype[k] = Cell.WATER
				b.color[k] = BastideGardenMesher.tint(Color(0.47, 0.41, 0.3), hs(key, 1) * 0.04)


## Touffes de riz repiquées en lignes, une par case d'eau loin des levées.
static func _rice(b: _Ctx) -> void:
	# Herbes folles sur les levées.
	var tuft := BastideKitNature.tuft("meadow", Color(0.62, 0.76, 0.46), 0.5)
	if not tuft.is_empty():
		for k in b.state.size():
			if b.ctype[k] != Cell.DIKE or b.state[k] == 0 or h(b.seed + 11, k) > 0.16:
				continue
			var i := k % b.ns
			var j := k / b.ns
			var q := b.at(b.s0 + (i + 0.2 + h(b.seed, k * 5) * 0.6) * CELL, b.t0 + (j + 0.2 + h(b.seed, k * 5 + 1) * 0.6) * CELL)
			if b.cell_of(q) != k:
				continue
			var basis := Basis(Vector3.UP, h(b.seed, k * 5 + 2) * TAU).scaled(Vector3.ONE * (0.7 + h(b.seed, k * 5 + 3) * 0.5))
			b.add("dike_grass", tuft["mesh"], tuft["mat"], Transform3D(basis, Vector3(q.x, b.floor_h[k] + DIKE_H - 0.02, q.y)))
	var meshes := [BastideCrops.mesh("rice", 0), BastideCrops.mesh("rice", 1), BastideCrops.mesh("rice", 2)]
	var fol := b.fol
	for j in b.nt:
		for i in b.ns:
			var k := b.idx(i, j)
			if b.ctype[k] != Cell.WATER:
				continue
			var key := BastideRng.combine(b.seed, k * 3 + 1)
			for a in 2:
				var q := b.at(b.s0 + (i + 0.25 + a * 0.5) * CELL, b.t0 + (j + 0.5) * CELL)
				var y: float = b.floor_h[k]
				var basis := Basis(Vector3.UP, h(key, a) * TAU).scaled(Vector3.ONE * (0.85 + h(key, 5 + a) * 0.3))
				var vi := int(h(key, 9 + a) * 3.0) % 3
				b.add("rice%d" % vi, meshes[vi], fol, Transform3D(basis, Vector3(q.x, y, q.y)))
				b.rice += 1


# --- Maillage du sol --------------------------------------------------------------------

## La terre de chaque case, à sa hauteur ; les marches entre cases voisines (levées,
## murets entre terrasses) et le bord du champ qui descend jusque sous le relief.
static func _ground_mesh(b: _Ctx) -> void:
	var mb := b.mb
	var rice := b.kind == Kind.RICE
	for j in b.nt:
		for i in b.ns:
			var k := b.idx(i, j)
			if b.state[k] == 0:
				continue
			var parts: Array = b.clips.get(k, [])
			if parts.is_empty():
				parts = [PackedVector2Array([b.at(b.s0 + i * CELL, b.t0 + j * CELL), b.at(b.s0 + (i + 1) * CELL, b.t0 + j * CELL),
					b.at(b.s0 + (i + 1) * CELL, b.t0 + (j + 1) * CELL), b.at(b.s0 + i * CELL, b.t0 + (j + 1) * CELL)])]
			var col: Color = b.color[k]
			var top := _top(b, k)
			for part: PackedVector2Array in parts:
				var tri := Geometry2D.triangulate_polygon(part)
				for n in range(0, tri.size(), 3):
					var p0 := part[tri[n]]
					var p1 := part[tri[n + 1]]
					var p2 := part[tri[n + 2]]
					var a := Vector3(p0.x, top if rice else b.corner_base(p0) + LIFT, p0.y)
					var bb := Vector3(p1.x, top if rice else b.corner_base(p1) + LIFT, p1.y)
					var c := Vector3(p2.x, top if rice else b.corner_base(p2) + LIFT, p2.y)
					mb.add_tri(ROLE_SOIL, a, bb, c, Vector3.UP, col, col, col)
					if b.collision:
						b.result.collision_faces.append(a)
						b.result.collision_faces.append(bb)
						b.result.collision_faces.append(c)
					if rice and b.ctype[k] == Cell.WATER:
						var wy: float = b.floor_h[k] + WATER_H
						var w := Color(1, 1, 1, 1)
						mb.add_tri(ROLE_WATER, Vector3(a.x, wy, a.z), Vector3(bb.x, wy, bb.z), Vector3(c.x, wy, c.z), Vector3.UP, w, w, w)
				# Le bord du champ : les arêtes du morceau qui ne sont pas sur le
				# pourtour de la case suivent le contour.
				if b.clips.has(k):
					for e in part.size():
						var q0 := part[e]
						var q1 := part[(e + 1) % part.size()]
						if _on_cell_side(b, i, j, q0, q1):
							continue
						_skirt(b, q0, q1, k, Vector3.ZERO)
			# Marches vers les voisines (de la plus haute vers la plus basse).
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni := i + dir.x
				var nj := j + dir.y
				var e0: Vector2
				var e1: Vector2
				if dir.x == 1:
					e0 = b.at(b.s0 + (i + 1) * CELL, b.t0 + j * CELL)
					e1 = b.at(b.s0 + (i + 1) * CELL, b.t0 + (j + 1) * CELL)
				elif dir.x == -1:
					e0 = b.at(b.s0 + i * CELL, b.t0 + (j + 1) * CELL)
					e1 = b.at(b.s0 + i * CELL, b.t0 + j * CELL)
				elif dir.y == 1:
					e0 = b.at(b.s0 + (i + 1) * CELL, b.t0 + (j + 1) * CELL)
					e1 = b.at(b.s0 + i * CELL, b.t0 + (j + 1) * CELL)
				else:
					e0 = b.at(b.s0 + i * CELL, b.t0 + j * CELL)
					e1 = b.at(b.s0 + (i + 1) * CELL, b.t0 + j * CELL)
				var inside := ni >= 0 and nj >= 0 and ni < b.ns and nj < b.nt and b.state[b.idx(ni, nj)] != 0
				if not inside:
					# Case pleine contre une zone évitée (maison, chemin…) : talus.
					if not b.clips.has(k):
						var o := b.u * dir.x + b.v * dir.y
						_skirt(b, e0, e1, k, Vector3(o.x, 0, o.y))
					continue
				if not rice:
					continue
				var nk := b.idx(ni, nj)
				var other := _top(b, nk)
				if other >= top - 0.01:
					continue
				var segs := [[e0, e1]]
				if b.clips.has(k) or b.clips.has(nk):
					segs = []
					for piece: PackedVector2Array in Geometry2D.clip_polyline_with_polygon(PackedVector2Array([e0, e1]), b.poly):
						if piece.size() >= 2:
							segs.append([piece[0], piece[piece.size() - 1]])
				var riser := top - other > 0.3
				for sg: Array in segs:
					var o := b.u * dir.x + b.v * dir.y
					_wall(b, sg[0], sg[1], other - 0.02, top, Vector3(o.x, 0, o.y), riser, b.color[k], k)


static func _top(b: _Ctx, k: int) -> float:
	if b.kind == Kind.RICE:
		return b.floor_h[k] + (DIKE_H if b.ctype[k] == Cell.DIKE else 0.0)
	return 0.0


static func _on_cell_side(b: _Ctx, i: int, j: int, q0: Vector2, q1: Vector2) -> bool:
	var f0 := b.st(q0)
	var f1 := b.st(q1)
	var sa := b.s0 + i * CELL
	var sb := sa + CELL
	var ta := b.t0 + j * CELL
	var tb := ta + CELL
	var eps := 0.003
	for s: float in [sa, sb]:
		if absf(f0.x - s) < eps and absf(f1.x - s) < eps:
			return true
	for t: float in [ta, tb]:
		if absf(f0.y - t) < eps and absf(f1.y - t) < eps:
			return true
	return false


## Bord du champ entre q0 et q1 : la terre descend sous le relief (muret de pierres
## sèches autour d'une rizière, simple tranche de terre ailleurs).
static func _skirt(b: _Ctx, q0: Vector2, q1: Vector2, k: int, outward: Vector3) -> void:
	var rice := b.kind == Kind.RICE
	var top0 := _top(b, k) if rice else b.corner_base(q0) + LIFT
	var top1 := _top(b, k) if rice else b.corner_base(q1) + LIFT
	var low := minf(b.base(q0), b.base(q1)) - (0.45 if rice else 0.25)
	var nrm := outward
	if nrm == Vector3.ZERO:
		# Bord du contour : la normale qui sort du polygone.
		var mid := (q0 + q1) * 0.5
		nrm = Vector3(q1.x - q0.x, 0, q1.y - q0.y).cross(Vector3.UP)
		if Geometry2D.is_point_in_polygon(mid + Vector2(nrm.x, nrm.z).normalized() * 0.03, b.poly):
			nrm = -nrm
	if rice:
		var stone := BastideGardenMesher.tint(Color(0.52, 0.5, 0.44), hs(BastideRng.combine(b.seed, k), 3) * 0.05)
		stone.a = 0.0
		b.mb.add_quad(ROLE_STONE, Vector3(q0.x, low, q0.y), Vector3(q1.x, low, q1.y), Vector3(q1.x, top1, q1.y),
				Vector3(q0.x, top0, q0.y), nrm, stone, stone, stone, stone)
	else:
		var col: Color = b.color[k].darkened(0.12)
		b.mb.add_quad(ROLE_SOIL, Vector3(q0.x, low, q0.y), Vector3(q1.x, low, q1.y), Vector3(q1.x, top1, q1.y),
				Vector3(q0.x, top0, q0.y), nrm, col, col, col, col)
	if b.collision:
		for p: Vector3 in [Vector3(q0.x, low, q0.y), Vector3(q1.x, low, q1.y), Vector3(q1.x, top1, q1.y),
				Vector3(q0.x, low, q0.y), Vector3(q1.x, top1, q1.y), Vector3(q0.x, top0, q0.y)]:
			b.result.collision_faces.append(p)


## Marche verticale entre deux cases : muret de pierres sèches (entre terrasses) ou
## flanc de levée.
static func _wall(b: _Ctx, q0: Vector2, q1: Vector2, y0: float, y1: float, toward: Vector3, riser: bool, col: Color, k: int) -> void:
	var a := Vector3(q0.x, y0, q0.y)
	var bb := Vector3(q1.x, y0, q1.y)
	var c := Vector3(q1.x, y1, q1.y)
	var d := Vector3(q0.x, y1, q0.y)
	if riser:
		var stone := BastideGardenMesher.tint(Color(0.5, 0.49, 0.42), hs(BastideRng.combine(b.seed, k), 5) * 0.06)
		stone.a = 0.0
		b.mb.add_quad(ROLE_STONE, a, bb, c, d, toward, stone, stone, stone, stone)
	else:
		var lo := Color(0.36, 0.3, 0.2)
		b.mb.add_quad(ROLE_SOIL, a, bb, c, d, toward, lo, lo, col, col)
	if b.collision:
		for p: Vector3 in [a, bb, c, a, c, d]:
			b.result.collision_faces.append(p)


# --- Potager ----------------------------------------------------------------------------

## Planches surélevées le long des rangs, chacune avec sa culture.
static func _beds(b: _Ctx) -> void:
	var fol := b.fol
	var period := BED_W + BED_GAP
	var t_lo := b.t0 + CELL
	var t_hi := b.t0 + b.nt * CELL
	var t := t_lo + 0.35
	var row := 0
	while t + BED_W < t_hi:
		var runs := _runs(b, t, t + BED_W, 0.55, 0.35)
		for r: Vector2 in runs:
			var key := BastideRng.combine(b.seed, 500 + row * 31 + roundi(r.x))
			var crop := BastideCrops.pick(key)
			_bed(b, r.x, r.y, t, crop, key, fol)
		t += period
		row += 1


## Tronçons [s début, s fin] où une bande [ta, tb] tient dans le champ (à `margin` du
## bord, sans chemin ni obstacle). Longueur minimale `min_len`.
static func _runs(b: _Ctx, ta: float, tb: float, margin: float, clear: float, min_len := 1.4) -> Array:
	var out: Array = []
	var step := CELL * 0.5
	var s := b.s0
	var start := INF
	var s_end := b.s0 + b.ns * CELL
	while s <= s_end:
		var ok := true
		for t: float in [ta, (ta + tb) * 0.5, tb]:
			var q := b.at(s, t)
			var k := b.cell_of(q)
			if k < 0 or b.state[k] == 0 or b.on_path[k] == 1 or b.edge[k] < margin:
				ok = false
				break
			if b.ctx.path_clearance(q) < clear + 0.3 or not b.is_free(q, clear):
				ok = false
				break
		if ok and start == INF:
			start = s
		elif not ok and start != INF:
			if s - step - start >= min_len:
				out.append(Vector2(start, s - step))
			start = INF
		s += step
	if start != INF and s_end - start >= min_len:
		out.append(Vector2(start, s_end))
	return out


static func _bed(b: _Ctx, sa: float, sb: float, ta: float, crop: String, key: int, fol: Material) -> void:
	var mb := b.mb
	# Profil en travers : pied, épaule arrondie, dessus légèrement bombé.
	var prof_t := [0.0, 0.07, 0.17, 0.45, 0.73, 0.83, 0.9]
	var prof_y := [0.0, 0.11, 0.17, 0.19, 0.17, 0.11, 0.0]
	var top_col := BastideGardenMesher.tint(Color(0.31, 0.24, 0.19), hs(key, 1) * 0.05)
	var side_col := top_col.darkened(0.06)
	var n := maxi(2, ceili((sb - sa) / 0.4))
	var prev: Array = []
	var u3 := Vector3(b.u.x, 0, b.u.y)
	var v3 := Vector3(b.v.x, 0, b.v.y)
	for si in n + 1:
		var s := lerpf(sa, sb, float(si) / n)
		var sec: Array = []
		for pi in prof_t.size():
			var q := b.at(s, ta + float(prof_t[pi]) * (BED_W / 0.9))
			var y := b.corner_base(q) + LIFT - 0.02 + float(prof_y[pi]) * (BED_H / 0.19)
			sec.append(Vector3(q.x, y, q.y))
		if si > 0:
			for pi in prof_t.size() - 1:
				var flat: bool = pi == 2 or pi == 3
				var c := top_col if flat else side_col
				var hint := Vector3.UP if flat else (v3 * (-1.0 if pi < 2 else 1.0) + Vector3.UP * 0.3)
				mb.add_quad(ROLE_SOIL, prev[pi], sec[pi], sec[pi + 1], prev[pi + 1], hint, c, c, c, c)
		# Bouts de la planche : un pan en biais jusqu'au sol.
		if si == 0 or si == n:
			var dir := -1.0 if si == 0 else 1.0
			var tip := b.at(s + dir * 0.12, ta + BED_W * 0.5)
			var tip3 := Vector3(tip.x, b.corner_base(tip) + LIFT - 0.02, tip.y)
			for pi in prof_t.size() - 1:
				mb.add_tri(ROLE_SOIL, sec[pi], sec[pi + 1], tip3, u3 * dir + Vector3.UP * 0.5, side_col, side_col, side_col)
		prev = sec
	b.beds += 1
	# Les pieds, en lignes.
	var sp := float(BastideCrops.SPACING[crop])
	var lines := int(BastideCrops.LINES[crop])
	var count := maxi(1, floori((sb - sa - 0.15) / sp))
	var start := sa + (sb - sa - (count - 1) * sp) * 0.5
	var m0 := BastideCrops.mesh(crop, 0)
	var m1 := BastideCrops.mesh(crop, 1)
	for li in lines:
		var tt := ta + BED_W * (0.5 if lines == 1 else (0.3 if li == 0 else 0.7))
		for ci in count:
			var s := start + ci * sp + (sp * 0.5 if li == 1 else 0.0)
			if s > sb - 0.08:
				continue
			var q := b.at(s, tt)
			if not b.is_free(q, 0.15):
				continue
			var y := b.corner_base(q) + LIFT - 0.02 + BED_H
			var kk := BastideRng.combine(key, li * 997 + ci)
			# Les pieds d'une même planche se ressemblent sans être identiques.
			var basis := Basis(Vector3.UP, h(kk, 1) * TAU).scaled(Vector3.ONE * (0.82 + h(kk, 2) * 0.32))
			var variant := 1 if h(kk, 3) < 0.4 else 0
			b.add("%s%d" % [crop, variant], m1 if variant == 1 else m0, fol, Transform3D(basis, Vector3(q.x, y, q.y)))
			b.crops += 1


## Clôture basse de bambou (yotsume-gaki) à l'intérieur du bord, ouverte vers le
## chemin le plus proche (ou vers le village), et partout où un chemin la traverse.
static func _fence_ring(b: _Ctx) -> PackedVector2Array:
	return _resample(BastidePolygon.offset(BastidePolygon.ensure_direct(b.poly), 0.22), 1.6)


## Milieu de l'entrée du potager : vers le chemin le plus proche, une porte, ou le village.
static func _gate_center(b: _Ctx, ring: PackedVector2Array) -> Vector2:
	var target := Vector2.INF
	var best := INF
	for e: Dictionary in b.ctx.paths:
		for p: Vector3 in e["points"]:
			var q := Vector2(p.x, p.z)
			var d := BastidePondShape.signed_distance(q, b.poly)
			if d > -0.5 and d < best:
				best = d
				target = q
	for door: Dictionary in b.ctx.doors():
		var pos: Vector3 = door["pos"]
		var q := Vector2(pos.x, pos.z)
		var d := BastidePondShape.signed_distance(q, b.poly) + 1.5
		if d > -0.5 and d < best:
			best = d
			target = q
	if target == Vector2.INF:
		var o := b.xf.affine_inverse() * Vector3.ZERO
		target = Vector2(o.x, o.z)
	var gi := 0
	var gd := INF
	for i in ring.size():
		var d := ring[i].distance_to(target)
		if d < gd:
			gd = d
			gi = i
	return ring[gi].lerp(ring[(gi + 1) % ring.size()], 0.5)


static func _fence(b: _Ctx) -> void:
	var ring := _fence_ring(b)
	if ring.size() < 4:
		return
	b.gate = true
	var gate_c := _gate_center(b, ring)
	var col := Color(0.7, 0.64, 0.44)
	var present: Array[bool] = []
	for i in ring.size():
		var q := ring[i]
		var ok := q.distance_to(gate_c) > 0.75 and b.ctx.path_clearance(q) > 0.5 and not b.ctx.blocked(q, 0.1)
		present.append(ok)
	for i in ring.size():
		if not present[i]:
			continue
		var q := ring[i]
		var g := b.corner_base(q) + LIFT
		var key := BastideRng.combine(b.seed, 9000 + i)
		var top := 0.86 + hs(key, 1) * 0.04
		if not present[(i + 1) % ring.size()] or not present[posmod(i - 1, ring.size())]:
			top += 0.12
		BastideGardenMesher.bamboo_pole(b.mb, Vector3(q.x, g - 0.1, q.y), Vector3(q.x, g + top, q.y), 0.03,
				BastideGardenMesher.tint(col, hs(key, 2) * 0.05), key, 0.4)
		b.posts += 1
		var j := (i + 1) % ring.size()
		if present[j]:
			var q1 := ring[j]
			var g1 := b.corner_base(q1) + LIFT
			for r: float in [0.32, 0.68]:
				var over := (q1 - q).normalized() * 0.08
				BastideGardenMesher.bamboo_pole(b.mb, Vector3(q.x - over.x, g + r, q.y - over.y),
						Vector3(q1.x + over.x, g1 + r, q1.y + over.y), 0.017,
						BastideGardenMesher.tint(col, hs(key, 3) * 0.05), key + 1, 0.5)
		if b.collision:
			b.result.add_prism(Vector3(q.x, g, q.y), 0.05, top, 4)


static func _resample(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	var per := BastidePolygon.perimeter(poly)
	var n := maxi(3, roundi(per / step))
	var out := PackedVector2Array()
	var seg := 0
	var acc := 0.0
	var m := poly.size()
	for k in n:
		var want := per * k / n
		while seg < m:
			var a := poly[seg]
			var bb := poly[(seg + 1) % m]
			var l := a.distance_to(bb)
			if acc + l >= want or seg == m - 1:
				out.append(a.lerp(bb, clampf((want - acc) / maxf(l, 1e-5), 0.0, 1.0)))
				break
			acc += l
			seg += 1
	return out


## Cabane à outils : un petit appentis de planches près de l'entrée, ouvert vers le
## potager, ses outils appuyés contre la paroi, paniers et sacs au pied.
static func _shed(b: _Ctx) -> void:
	if b.area < 45.0:
		return
	var ring := _fence_ring(b)
	if ring.size() < 4:
		return
	var gate_c := _gate_center(b, ring)
	var centre := BastidePolygon.centroid(b.poly)
	var best := Vector2.INF
	var best_score := INF
	for k in b.state.size():
		if b.state[k] != 1 or b.on_path[k] == 1 or b.edge[k] < 1.1 or b.edge[k] > 2.4:
			continue
		var i := k % b.ns
		var j := k / b.ns
		var q := b.at(b.s0 + (i + 0.5) * CELL, b.t0 + (j + 0.5) * CELL)
		var dg := q.distance_to(gate_c)
		if dg < 2.2 or dg > 8.0:
			continue
		var f := (centre - q).normalized()
		var r := Vector2(-f.y, f.x)
		var ok := b.is_free(q, 1.3) and not b.ctx.blocked(q, 1.2)
		for c: Vector2 in [r * 1.0 + f * 0.7, -r * 1.0 + f * 0.7, r * 1.0 - f * 0.7, -r * 1.0 - f * 0.7]:
			if not ok:
				break
			if b.edge_at(q + c) < 0.3:
				ok = false
		if not ok:
			continue
		var score := dg + h(b.seed, k) * 1.5
		if score < best_score:
			best_score = score
			best = q
	if best == Vector2.INF:
		return
	var f := (centre - best).normalized()
	b.taken.append(Vector3(best.x, best.y, 1.35))
	shed(b.mb, best, f, b, BastideRng.combine(b.seed, 555))
	b.sheds += 1
	b.shed_at = best


## Boîte orientée : centre au sol c (local), axes r et f (unitaires), demi-tailles.
static func _box(mb: BastideMeshBuilder, role: StringName, c: Vector3, r: Vector3, f: Vector3, hx: float, hz: float,
		y0: float, y1: float, col: Color, y1_back := INF) -> void:
	var yb := y1 if y1_back == INF else y1_back
	var corners := [
		c - r * hx - f * hz + Vector3.UP * y0, c + r * hx - f * hz + Vector3.UP * y0,
		c + r * hx + f * hz + Vector3.UP * y0, c - r * hx + f * hz + Vector3.UP * y0,
		c - r * hx - f * hz + Vector3.UP * yb, c + r * hx - f * hz + Vector3.UP * yb,
		c + r * hx + f * hz + Vector3.UP * y1, c - r * hx + f * hz + Vector3.UP * y1]
	mb.add_block(role, corners, 0.008, 0.0, col, col.darkened(0.15))


static func shed(mb: BastideMeshBuilder, q: Vector2, fwd: Vector2, b: _Ctx, key: int) -> void:
	var f := Vector3(fwd.x, 0, fwd.y)
	var r := Vector3(-fwd.y, 0, fwd.x)
	var c2 := q
	var g := -INF
	for o: Vector2 in [Vector2(0.95, 0.65), Vector2(-0.95, 0.65), Vector2(0.95, -0.65), Vector2(-0.95, -0.65)]:
		var p := c2 + Vector2(r.x, r.z) * o.x + fwd * o.y
		g = maxf(g, b.ground(p))
	var c := Vector3(q.x, 0, q.y)
	var hx := 0.9
	var hz := 0.6
	var front_h := 1.95
	var back_h := 1.6
	var frame := Color(0.3, 0.23, 0.17)
	var board := Color(0.52, 0.41, 0.3)
	# Pierres d'assise et poteaux d'angle.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := c + r * hx * sx + f * hz * sz
			BastideGardenMesher.slab(mb, Vector3(p.x, g - 0.05, p.z), 0.13, 0.1, h(key, 1) * TAU, BastideRng.combine(key, int(sx * 3 + sz)),
					Color(0.55, 0.53, 0.48), 6, 1.0, -0.05)
			var top := front_h if sz > 0 else back_h
			_box(mb, ROLE_WOOD, p, r, f, 0.045, 0.045, g + 0.04, g + top, frame)
	# Parois de planches verticales : le fond et les deux côtés (l'avant reste ouvert).
	var nb := 9
	for k in nb:
		var x := -hx + (k + 0.5) * (2.0 * hx / nb)
		var tone := BastideGardenMesher.tint(board, hs(key, 10 + k) * 0.08)
		_box(mb, ROLE_WOOD, c + r * x - f * hz, r, f, hx / nb - 0.012, 0.015, g + 0.06, g + back_h - 0.02, tone)
	for sx: float in [-1.0, 1.0]:
		var ns := 6
		for k in ns:
			var z := -hz + (k + 0.5) * (2.0 * hz / ns)
			var t := (z + hz) / (2.0 * hz)
			var tone := BastideGardenMesher.tint(board, hs(key, 30 + k + int(sx) * 7) * 0.08)
			# Le côté suit la pente du toit (plus haut devant).
			var top := lerpf(back_h, front_h, t) - 0.02
			_box(mb, ROLE_WOOD, c + r * hx * sx + f * z, r, f, 0.015, hz / ns - 0.01, g + 0.06, g + top, tone)
	# Toit en appentis : planches dans le sens de la pente, débord généreux.
	var roof := Color(0.34, 0.3, 0.26)
	var nr := 8
	var over := 0.28
	for k in nr:
		var x := -(hx + over) + (k + 0.5) * (2.0 * (hx + over) / nr)
		var tone := BastideGardenMesher.tint(roof, hs(key, 60 + k) * 0.07)
		var zf := hz + over
		var zb := -hz - over * 0.7
		var yf := front_h + over * (front_h - back_h) / (2.0 * hz) + 0.04
		var yb := back_h - over * 0.7 * (front_h - back_h) / (2.0 * hz) + 0.04
		var a := c + r * x
		var w := (hx + over) / nr - 0.008
		var corners := [
			a - r * w + f * zb + Vector3.UP * (g + yb), a + r * w + f * zb + Vector3.UP * (g + yb),
			a + r * w + f * zf + Vector3.UP * (g + yf), a - r * w + f * zf + Vector3.UP * (g + yf),
			a - r * w + f * zb + Vector3.UP * (g + yb + 0.045), a + r * w + f * zb + Vector3.UP * (g + yb + 0.045),
			a + r * w + f * zf + Vector3.UP * (g + yf + 0.045), a - r * w + f * zf + Vector3.UP * (g + yf + 0.045)]
		mb.add_block(ROLE_WOOD, corners, 0.006, 0.0, tone, tone.darkened(0.2), true)
	# Outils appuyés contre la paroi gauche : une houe et un râteau de bambou.
	var handle := Color(0.6, 0.5, 0.34)
	var tool_base := c - r * (hx - 0.15) + f * 0.05 + Vector3.UP * g
	var lean := (Vector3.UP * 1.0 - r * 0.22).normalized()
	BastideGardenMesher.tube(mb, ROLE_WOOD, tool_base, tool_base + lean * 1.25, 0.016, 0.015, handle, 5)
	var blade_p := tool_base + lean * 1.25
	_box(mb, ROLE_PAINT, blade_p + f * 0.06 - Vector3.UP * 0.02, r, f, 0.09, 0.012, -0.11, 0.02, Color(0.32, 0.32, 0.33))
	var rake_base := tool_base + f * 0.25
	BastideGardenMesher.tube(mb, ROLE_WOOD, rake_base, rake_base + lean * 1.4, 0.014, 0.013, Color(0.66, 0.62, 0.42), 5)
	var head := rake_base + lean * 1.4
	for n in 7:
		var o := f * (-0.15 + n * 0.05)
		BastideGardenMesher.tube(mb, ROLE_WOOD, head + o, head + o + f * 0.02 + Vector3.UP * 0.18, 0.005, 0.004, Color(0.7, 0.64, 0.42), 4)
	# Paniers, sacs de toile et un seau de bois au pied, côté droit.
	var straw := Color(0.72, 0.6, 0.38)
	var bp := c + r * (hx - 0.3) - f * 0.25 + Vector3.UP * g
	BastideGardenMesher.prism(mb, ROLE_WOOD, bp, 0.2, 0.24, g, g + 0.3, 9, straw)
	BastideGardenMesher.prism(mb, ROLE_WOOD, bp, 0.2, 0.18, g + 0.3, g + 0.33, 9, straw.darkened(0.25))
	for n in 2:
		var sp := c + r * (0.1 + n * 0.34) - f * 0.3 + Vector3.UP * (g + 0.18)
		BastideGardenMesher.blob(b.mb, ROLE_CLOTH, sp, Vector3(0.17, 0.2, 0.15), Color(0.74, 0.68, 0.55), BastideRng.combine(key, 90 + n), 4, 8, 0.25, 0.08)
	var bucket := c + r * (hx - 0.3) + f * 0.25
	BastideGardenMesher.prism(mb, ROLE_WOOD, Vector3(bucket.x, 0, bucket.z), 0.14, 0.17, g, g + 0.3, 10, Color(0.56, 0.44, 0.3))
	if b.collision:
		b.result.add_box([c - r * hx - f * hz + Vector3.UP * g, c + r * hx - f * hz + Vector3.UP * g,
			c + r * hx - f * (hz - 0.1) + Vector3.UP * g, c - r * hx - f * (hz - 0.1) + Vector3.UP * g,
			c - r * hx - f * hz + Vector3.UP * (g + back_h), c + r * hx - f * hz + Vector3.UP * (g + back_h),
			c + r * hx - f * (hz - 0.1) + Vector3.UP * (g + back_h), c - r * hx - f * (hz - 0.1) + Vector3.UP * (g + back_h)])


## Épouvantail (kakashi) : chapeau de paille, kimono indigo, bras en croix.
static func _scarecrow_on(b: _Ctx) -> void:
	if b.area < 30.0:
		return
	var best := -1
	var best_d := INF
	var c := BastidePolygon.centroid(b.poly)
	for k in b.state.size():
		if b.state[k] == 0 or b.edge[k] < 1.2 or b.on_path[k] == 1:
			continue
		if b.kind == Kind.RICE and b.ctype[k] != Cell.DIKE:
			continue
		var i := k % b.ns
		var j := k / b.ns
		var q := b.at(b.s0 + (i + 0.5) * CELL, b.t0 + (j + 0.5) * CELL)
		var d := q.distance_to(c) + h(b.seed, k) * 2.0
		if d < best_d:
			best_d = d
			best = k
	if best < 0:
		return
	var i := best % b.ns
	var j := best / b.ns
	var q := b.at(b.s0 + (i + 0.5) * CELL, b.t0 + (j + 0.5) * CELL)
	var y := b.ground(q)
	b.taken.append(Vector3(q.x, q.y, 0.45))
	scarecrow(b.mb, Vector3(q.x, y, q.y), b.u.angle() + (h(b.seed, 77) - 0.5) * 0.6, BastideRng.combine(b.seed, 77))
	if b.collision:
		b.result.add_prism(Vector3(q.x, y, q.y), 0.06, 1.5, 4)
	b.scarecrows += 1


static func scarecrow(mb: BastideMeshBuilder, p: Vector3, rot: float, key: int) -> void:
	var up := Vector3.UP
	var side := Vector3(cos(rot), 0, sin(rot))
	var fwd := side.cross(up)
	var wood := Color(0.42, 0.34, 0.25)
	var cloth: Color = [Color(0.2, 0.27, 0.42), Color(0.45, 0.24, 0.2), Color(0.3, 0.36, 0.28)][int(h(key, 1) * 3.0) % 3]
	var straw := Color(0.78, 0.68, 0.42)
	var lean := fwd * 0.04 + side * hs(key, 2) * 0.05
	BastideGardenMesher.tube(mb, ROLE_WOOD, p - up * 0.15, p + up * 1.62 + lean, 0.035, 0.03, wood, 6)
	var arm := p + up * 1.22 + lean * 0.75
	BastideGardenMesher.tube(mb, ROLE_WOOD, arm - side * 0.62, arm + side * 0.62, 0.025, 0.022, wood, 6)
	# Kimono : corps et manches larges.
	BastideGardenMesher.blob(mb, ROLE_CLOTH, arm - up * 0.22, Vector3(0.2, 0.34, 0.2), cloth, key + 3, 5, 8, 0.3, 0.08)
	BastideGardenMesher.tube(mb, ROLE_CLOTH, arm - side * 0.5, arm + side * 0.5, 0.11, 0.11, cloth.lightened(0.05), 7)
	BastideGardenMesher.blob(mb, ROLE_CLOTH, arm - up * 0.12, Vector3(0.16, 0.06, 0.16), cloth.darkened(0.3), key + 4, 3, 8, 0.2, 0.0)
	# Bouquets de paille au bout des bras.
	for sgn: float in [-1.0, 1.0]:
		BastideGardenMesher.blob(mb, ROLE_CLOTH, arm + side * 0.6 * sgn, Vector3(0.07, 0.06, 0.07), straw, key + 5, 3, 6, 0.3, 0.3)
	# Tête de tissu clair et chapeau conique (sugegasa).
	var head := p + up * 1.5 + lean
	BastideGardenMesher.blob(mb, ROLE_CLOTH, head, Vector3(0.12, 0.13, 0.12), Color(0.88, 0.85, 0.76), key + 6, 4, 8, 0.25, 0.04)
	var hat := head + up * 0.08
	BastideGardenMesher.tube(mb, ROLE_CLOTH, hat, hat + up * 0.2, 0.36, 0.015, straw, 10)
	for n in 10:
		var a0 := TAU * n / 10.0
		var a1 := TAU * (n + 1) / 10.0
		mb.add_tri(ROLE_CLOTH, hat, hat + Vector3(cos(a0), 0, sin(a0)) * 0.36, hat + Vector3(cos(a1), 0, sin(a1)) * 0.36,
				Vector3.DOWN, straw.darkened(0.35), straw.darkened(0.35), straw.darkened(0.35))


# --- Thé ----------------------------------------------------------------------------------

## Longues haies arrondies le long des rangs (courbes de niveau sur une pente).
static func _tea_rows(b: _Ctx) -> void:
	var t := b.t0 + CELL + TEA_PERIOD * 0.5
	var t_hi := b.t0 + b.nt * CELL
	var row := 0
	while t + TEA_W * 0.5 < t_hi:
		for r: Vector2 in _runs(b, t - TEA_W * 0.5, t + TEA_W * 0.5, 0.35, 0.45, 1.6):
			_hedge(b, r.x, r.y, t, BastideRng.combine(b.seed, 800 + row * 37 + roundi(r.x)))
		t += TEA_PERIOD
		row += 1


static func _hedge(b: _Ctx, sa: float, sb: float, tc: float, key: int) -> void:
	var mb := b.mb
	var nseg := 12
	var length := sb - sa
	var n := maxi(3, ceili(length / 0.3))
	var prev: Array = []
	var prev_n: Array = []
	var prev_c: Array = []
	var v3 := Vector3(b.v.x, 0, b.v.y)
	var u3 := Vector3(b.u.x, 0, b.u.y)
	var dark := Color(0.13, 0.23, 0.11)
	var mid := Color(0.24, 0.38, 0.14)
	var top := Color(0.36, 0.5, 0.17)
	for si in n + 1:
		var f := float(si) / n
		var s := lerpf(sa, sb, f)
		# Bouts arrondis : la haie se resserre et s'abaisse sur ses derniers 60 cm.
		var e := minf(s - sa, sb - s)
		var k := sqrt(clampf(e / 0.6, 0.0, 1.0))
		var wk := lerpf(0.45, 1.0, k)
		var hk := lerpf(0.55, 1.0, k)
		var cq := b.at(s, tc)
		var g := b.corner_base(cq) + LIFT - 0.06
		var sec: Array = []
		var nrm: Array = []
		var cols: Array = []
		for ai in nseg + 1:
			var a := PI * ai / nseg
			# Bosses douces le long du rang (taille au cordeau, mais vivante).
			var bump := 1.0 + 0.035 * sin(s * 2.3 + float(key % 97)) + 0.02 * sin(s * 5.1 + ai * 1.7) + hs(key, si * 31 + ai) * 0.015
			var w := TEA_W * 0.5 * wk * bump
			var hh := TEA_H * hk * bump * pow(sin(a), 0.4)
			var lat := cos(a) * w
			var q := cq + b.v * lat
			sec.append(Vector3(q.x, g + hh, q.y))
			nrm.append((v3 * cos(a) / maxf(w, 0.05) + Vector3.UP * sin(a) / maxf(TEA_H * hk, 0.05)).normalized())
			var up_k := sin(a)
			var c := dark.lerp(mid, clampf(up_k * 1.4, 0.0, 1.0)).lerp(top, clampf((up_k - 0.75) * 4.0, 0.0, 1.0))
			cols.append(BastideGardenMesher.tint(c, hs(key, 400 + si * 13 + ai) * 0.05))
		if si > 0:
			for ai in nseg:
				mb.add_tri_smooth(ROLE_HEDGE, prev[ai], sec[ai], sec[ai + 1], prev_n[ai], nrm[ai], nrm[ai + 1],
						prev_c[ai], cols[ai], cols[ai + 1])
				mb.add_tri_smooth(ROLE_HEDGE, prev[ai], sec[ai + 1], prev[ai + 1], prev_n[ai], nrm[ai + 1], prev_n[ai + 1],
						prev_c[ai], cols[ai + 1], prev_c[ai + 1])
		if si == 0 or si == n:
			var dir := -1.0 if si == 0 else 1.0
			var tipq := b.at(s + dir * 0.18, tc)
			var tip := Vector3(tipq.x, g + TEA_H * 0.32, tipq.y)
			for ai in nseg:
				mb.add_tri_smooth(ROLE_HEDGE, sec[ai], sec[ai + 1], tip, nrm[ai], nrm[ai + 1], u3 * dir,
						cols[ai], cols[ai + 1], mid)
		prev = sec
		prev_n = nrm
		prev_c = cols
	b.hedges += 1
	if b.collision:
		var m := maxi(1, ceili(length / 1.5))
		for i in m:
			var q := b.at(lerpf(sa, sb, (i + 0.5) / m), tc)
			b.result.add_prism(Vector3(q.x, b.corner_base(q), q.y), TEA_W * 0.45, TEA_H, 6)


## Ventilateurs antigel (bōshō-sen) : un mât fin, un moteur, une hélice inclinée.
static func _frost_fans(b: _Ctx) -> void:
	var want := clampi(int(b.area / 140.0), 0, 5)
	if want == 0:
		return
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < want and tries < 200:
		tries += 1
		var k := BastideRng.combine(b.seed, 3000 + tries)
		var i := int(h(k, 0) * b.ns)
		var j := int(h(k, 1) * b.nt)
		var t := b.t0 + CELL + TEA_PERIOD * float(roundi((b.t0 + (j + 0.5) * CELL - b.t0 - CELL) / TEA_PERIOD))
		var q := b.at(b.s0 + (i + 0.5) * CELL, t)
		if b.edge_at(q) < 0.8:
			continue
		var far := true
		for p in placed:
			if p.distance_to(q) < 10.0:
				far = false
				break
		if not far:
			continue
		placed.append(q)
		_fan(b, Vector3(q.x, b.corner_base(q), q.y), h(k, 3) * TAU, k)
		b.fans += 1


static func _fan(b: _Ctx, p: Vector3, rot: float, key: int) -> void:
	var mb := b.mb
	var grey := Color(0.6, 0.61, 0.6)
	var h_top := 5.2 + h(key, 1) * 0.6
	BastideGardenMesher.tube(mb, ROLE_PAINT, p - Vector3.UP * 0.2, p + Vector3.UP * h_top, 0.05, 0.04, grey, 6)
	var dir := Vector3(cos(rot), 0, sin(rot))
	var head := p + Vector3.UP * h_top
	BastideGardenMesher.tube(mb, ROLE_PAINT, head - dir * 0.15, head + dir * 0.22, 0.09, 0.08, grey.darkened(0.25), 7)
	# Hélice : trois pales, tournée vers le sol devant elle.
	var axis := (dir + Vector3.DOWN * 0.35).normalized()
	var hub := head + dir * 0.26
	var side := axis.cross(Vector3.UP).normalized()
	var up2 := side.cross(axis).normalized()
	var blade := Color(0.75, 0.76, 0.74)
	for n in 3:
		var a := TAU * n / 3.0 + h(key, 2)
		var r := (side * cos(a) + up2 * sin(a))
		var w := (side * cos(a + PI * 0.5) + up2 * sin(a + PI * 0.5)) * 0.07
		mb.add_tri_2s(ROLE_PAINT, hub, hub + r * 0.62 + w, hub + r * 0.62 - w, axis, blade, blade, blade)
	if b.collision:
		b.result.add_prism(p, 0.08, h_top, 4)


# --- Relief ----------------------------------------------------------------------------

## Abaisse le relief sous le champ : chaque sommet de la grille du terrain descend sous
## la terre la plus basse du champ autour de lui. {type, rect, i0, j0, w, d, heights}
## en monde ; NAN = sommet laissé tel quel. {} sans relief.
static func _carve(b: _Ctx) -> Dictionary:
	var field := b.field
	if field == null:
		return {}
	var world := PackedVector2Array()
	for p in b.poly:
		var w := b.xf * Vector3(p.x, 0.0, p.y)
		world.append(Vector2(w.x, w.z))
	var reach := 1.7 if b.kind == Kind.RICE else 0.0
	var r := BastidePondShape.rect_of(world).grow(reach + field.cell)
	var i0 := maxi(0, floori((r.position.x - field.origin.x) / field.cell))
	var j0 := maxi(0, floori((r.position.y - field.origin.y) / field.cell))
	var i1 := mini(field.width - 1, ceili((r.end.x - field.origin.x) / field.cell))
	var j1 := mini(field.depth - 1, ceili((r.end.y - field.origin.y) / field.cell))
	if i1 < i0 or j1 < j0:
		return {}
	var w := i1 - i0 + 1
	var d := j1 - j0 + 1
	var heights := PackedFloat32Array()
	heights.resize(w * d)
	heights.fill(NAN)
	var inv := b.xf.affine_inverse()
	var offs: Array[Vector2] = [Vector2.ZERO]
	var rr := field.cell * 1.05
	for a in 8:
		offs.append(Vector2(cos(TAU * a / 8.0), sin(TAU * a / 8.0)) * rr)
		offs.append(Vector2(cos(TAU * a / 8.0), sin(TAU * a / 8.0)) * rr * 0.5)
	var touched := 0
	for jj in d:
		for ii in w:
			var wp := field.origin + Vector2(i0 + ii, j0 + jj) * field.cell
			var lp3 := inv * Vector3(wp.x, 0.0, wp.y)
			var lp := Vector2(lp3.x, lp3.z)
			var k := b.cell_of(lp)
			var inside := k >= 0 and b.state[k] != 0
			if not inside and reach <= 0.0:
				continue
			var lowest := INF
			for o in offs:
				var q := lp + o
				var kq := b.cell_of(q)
				if kq < 0 or b.state[kq] == 0:
					continue
				var top := b.floor_h[kq] if b.kind == Kind.RICE else b.corner_base(q) + LIFT
				lowest = minf(lowest, top)
			if lowest == INF:
				continue
			heights[jj * w + ii] = lowest - DROP + b.xf.origin.y
			touched += 1
	if touched == 0:
		return {}
	return {"type": "floor", "rect": r, "i0": i0, "j0": j0, "w": w, "d": d, "heights": heights,
		"poly": world, "level": 0.0, "depth": 0.0}
