@tool
class_name BastideInteriorMesher
extends RefCounted
## Backend procédural des intérieurs : InteriorLayout (+ le plan du bâtiment) →
## BuildResult. Ne décide rien : niveaux, trémies et volées viennent du plan.
##
## Dessine : parquet en lames, entrée en contrebas et sa marche, face intérieure des
## murs percée des fenêtres (papier des shoji vu de dedans), poteaux et bandeaux de
## bois, dessous des planchers et solives, dessous du toit et chevrons, escaliers
## fermés (hako-kaidan) et garde-corps. Collisions : planchers, rampe de chaque
## volée, coffre sous l'escalier, garde-corps, seuil de la porte.
##
## Rien de tout cela n'existe tant qu'on n'entre pas : voir BastideBuilding.set_interior_active.

const Kind := BastideBuildingLayout.OpeningKind
const ROLE_BODY := BastideBuildingMesher.ROLE_BODY
const ROLE_WOOD := BastideBuildingMesher.ROLE_WOOD
const ROLE_PAPER := BastideBuildingMesher.ROLE_PAPER
const ROLE_GLASS := BastideBuildingMesher.ROLE_GLASS
const ROLE_EARTH := &"earth"
const PLANK_WIDTH := 0.19
const PLANK_LENGTH := 1.85


static func build(il: BastideInteriorLayout, layout: BastideBuildingLayout, style: BastideStyle) -> BastideBuildResult:
	var result := BastideBuildResult.new()
	if il == null or il.is_empty():
		return result
	var t0 := Time.get_ticks_usec()
	var mb := BastideMeshBuilder.new()
	var bs := style.get_building_style()
	var pal := _palette(il, layout, bs)

	_floors(mb, result, il, layout, pal)
	_entrance(mb, result, il, pal)
	for f: BastideBuildingLayout.Facade in layout.facades:
		_inner_wall(mb, result, il, layout, f, bs, pal)
	_roof_underside(mb, il, layout, pal)
	for fl: BastideInteriorLayout.Flight in il.flights:
		_flight(mb, result, fl, pal)
	for lv: BastideInteriorLayout.Level in il.levels:
		for r: Array in lv.railings:
			_railing(mb, result, r[0], r[1], lv.y, pal)

	result.mesh = mb.commit({
		ROLE_BODY: style.get_material(),
		ROLE_WOOD: style.get_wood_material(),
		ROLE_PAPER: style.get_paper_material(),
		ROLE_GLASS: style.get_glass_material(),
		ROLE_EARTH: style.get_earth_material(),
	})
	var lights := PackedVector3Array()
	var c := BastidePolygon.centroid(il.inner)
	for lv: BastideInteriorLayout.Level in il.levels:
		var h := minf(2.0, ((lv.ceiling_y if is_finite(lv.ceiling_y) else lv.y + 2.6) - lv.y) * 0.8)
		lights.append(Vector3(c.x, lv.y + h, c.y))
	result.anchors = {"lights": lights}
	result.stats = {"triangles": mb.triangle_count, "levels": il.levels.size(), "flights": il.flights.size(),
		"interior_us": Time.get_ticks_usec() - t0}
	return result


static func _palette(il: BastideInteriorLayout, layout: BastideBuildingLayout, bs: BastideBuildingStyle) -> Dictionary:
	var wood := bs.timber_color
	if il.timber:
		return {
			"floor": Color(0.66, 0.47, 0.29), "wall": Color(0.82, 0.74, 0.6), "earth": Color(0.42, 0.38, 0.33),
			"timber": wood.lightened(0.05), "ceiling": wood.lightened(0.22), "stair": Color(0.58, 0.41, 0.25),
			"stone": Color(0.55, 0.53, 0.5), "paper": bs.paper_color,
		}
	var plaster: Color = layout.facades[0].plaster if not layout.facades.is_empty() else Color(0.9, 0.88, 0.82)
	return {
		"floor": Color(0.5, 0.36, 0.22), "wall": plaster.lightened(0.04), "earth": Color(0.45, 0.42, 0.38),
		"timber": Color(0.36, 0.25, 0.16), "ceiling": Color(0.46, 0.33, 0.21), "stair": Color(0.44, 0.31, 0.19),
		"stone": Color(0.6, 0.58, 0.55), "paper": bs.paper_color,
	}


# --- Planchers ---------------------------------------------------------------------------

static func _floors(mb: BastideMeshBuilder, col: BastideBuildResult, il: BastideInteriorLayout,
		layout: BastideBuildingLayout, pal: Dictionary) -> void:
	var axis := _plank_axis(il.inner)
	for lv: BastideInteriorLayout.Level in il.levels:
		for piece: PackedVector2Array in lv.pieces:
			_parquet(mb, piece, lv.y, axis, layout.seed + lv.index * 131, pal["floor"])
			_flat_collision(col, piece, lv.y)
			if lv.index > 0:
				# Dessous du plancher : plafond du niveau du dessous.
				var y := lv.y - il.slab_thickness
				_flat(mb, ROLE_WOOD, piece, y, Vector3.DOWN, pal["ceiling"])
		if lv.index > 0:
			var y_low := lv.y - il.slab_thickness
			for h: PackedVector2Array in lv.holes:
				# Chant du plancher autour de la trémie.
				for i in h.size():
					var a := h[i]
					var b := h[(i + 1) % h.size()]
					var inward := Vector2(-(b - a).y, (b - a).x).normalized()
					mb.add_quad(ROLE_WOOD, Vector3(a.x, y_low, a.y), Vector3(b.x, y_low, b.y), Vector3(b.x, lv.y, b.y),
						Vector3(a.x, lv.y, a.y), Vector3(inward.x, 0, inward.y), pal["timber"], pal["timber"], pal["floor"], pal["floor"])
			# Solives sous le plancher, en travers de l'axe des lames.
			_joists(mb, lv, il, axis, pal)


## Lames dans le sens de la plus longue façade.
static func _plank_axis(poly: PackedVector2Array) -> Vector2:
	var best := Vector2.RIGHT
	var best_len := 0.0
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		if e.length() > best_len:
			best_len = e.length()
			best = e / e.length()
	return best


## Parquet : lames de PLANK_WIDTH, coupées en longueurs décalées, teinte propre à chaque lame.
static func _parquet(mb: BastideMeshBuilder, piece: PackedVector2Array, y: float, axis: Vector2, seed: int, base: Color) -> void:
	var perp := Vector2(-axis.y, axis.x)
	var lo_a := INF
	var hi_a := -INF
	var lo_p := INF
	var hi_p := -INF
	for p in piece:
		lo_a = minf(lo_a, p.dot(axis))
		hi_a = maxf(hi_a, p.dot(axis))
		lo_p = minf(lo_p, p.dot(perp))
		hi_p = maxf(hi_p, p.dot(perp))
	var row := 0
	var v := floorf(lo_p / PLANK_WIDTH) * PLANK_WIDTH
	while v < hi_p:
		var shift := BastideRng.randf_at(seed, "plank_row", row) * PLANK_LENGTH
		var u := floorf((lo_a - shift) / PLANK_LENGTH) * PLANK_LENGTH + shift
		var k := 0
		while u < hi_a:
			var rect := PackedVector2Array([axis * u + perp * v, axis * (u + PLANK_LENGTH) + perp * v,
				axis * (u + PLANK_LENGTH) + perp * (v + PLANK_WIDTH), axis * u + perp * (v + PLANK_WIDTH)])
			var t := BastideRng.signed_at(seed, "plank", BastideRng.combine(row, k)) * 0.055
			var c := base.lightened(t) if t > 0.0 else base.darkened(-t)
			for part in Geometry2D.intersect_polygons(rect, piece):
				_flat(mb, ROLE_WOOD, part, y, Vector3.UP, c, 0.0)
			u += PLANK_LENGTH
			k += 1
		v += PLANK_WIDTH
		row += 1


## Polygone horizontal plein. `edge` > 0 : bord assombri (joint des lames).
static func _flat(mb: BastideMeshBuilder, role: StringName, poly: PackedVector2Array, y: float, hint: Vector3,
		c: Color, edge := 0.0) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for t in range(0, idx.size(), 3):
		var a := poly[idx[t]]
		var b := poly[idx[t + 1]]
		var d := poly[idx[t + 2]]
		mb.add_tri(role, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(d.x, y, d.y), hint, c, c, c)


static func _flat_collision(col: BastideBuildResult, poly: PackedVector2Array, y: float) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for t in idx:
		var p := poly[t]
		col.collision_faces.append(Vector3(p.x, y, p.y))


## Prisme vertical sur un polygone (dessus, côtés ; dessous si demandé).
static func _prism(mb: BastideMeshBuilder, role: StringName, poly: PackedVector2Array, y0: float, y1: float,
		c_top: Color, c_side: Color, bottom := false) -> void:
	_flat(mb, role, poly, y1, Vector3.UP, c_top)
	if bottom:
		_flat(mb, role, poly, y0, Vector3.DOWN, c_side.darkened(0.2))
	var center := BastidePolygon.centroid(poly)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var mid := (a + b) * 0.5 - center
		mb.add_quad(role, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y),
			Vector3(mid.x, 0, mid.y), c_side.darkened(0.12), c_side.darkened(0.12), c_side, c_side)


static func _joists(mb: BastideMeshBuilder, lv: BastideInteriorLayout.Level, il: BastideInteriorLayout, axis: Vector2,
		pal: Dictionary) -> void:
	# Les solives portent les lames : elles vont en travers, tous les 0,9 m.
	var y1 := lv.y - il.slab_thickness
	var y0 := y1 - 0.13
	var lo := INF
	var hi := -INF
	var perp := Vector2(-axis.y, axis.x)
	for p in il.inner:
		lo = minf(lo, p.dot(axis))
		hi = maxf(hi, p.dot(axis))
	var u := lo + 0.9
	while u < hi - 0.4:
		var strip := PackedVector2Array([axis * (u - 0.06) - perp * 500.0, axis * (u + 0.06) - perp * 500.0,
			axis * (u + 0.06) + perp * 500.0, axis * (u - 0.06) + perp * 500.0])
		for piece: PackedVector2Array in lv.pieces:
			for part in Geometry2D.intersect_polygons(strip, piece):
				_prism(mb, ROLE_WOOD, part, y0, y1, pal["timber"], pal["timber"], true)
		u += 0.9


# --- Entrée ----------------------------------------------------------------------------

static func _entrance(mb: BastideMeshBuilder, col: BastideBuildResult, il: BastideInteriorLayout, pal: Dictionary) -> void:
	if il.genkan.is_empty():
		return
	var ground: BastideInteriorLayout.Level = il.levels[0]
	for part in Geometry2D.intersect_polygons(il.genkan, il.inner):
		_flat(mb, ROLE_EARTH, part, il.genkan_y, Vector3.UP, pal["earth"])
		_flat_collision(col, part, il.genkan_y)
	# Le bord du plancher (agarikamachi) : une poutre polie sur les côtés ouverts.
	var g := il.genkan
	var c := BastidePolygon.centroid(g)
	for i in g.size():
		var a := g[i]
		var b := g[(i + 1) % g.size()]
		if not il.contains((a + b) * 0.5):
			continue
		var out := (a + b) * 0.5 - c
		var beam: Color = pal["timber"].lightened(0.1)
		mb.add_quad(ROLE_WOOD, Vector3(a.x, il.genkan_y, a.y), Vector3(b.x, il.genkan_y, b.y), Vector3(b.x, ground.y, b.y),
			Vector3(a.x, ground.y, a.y), Vector3(out.x, 0, out.y), beam.darkened(0.25), beam.darkened(0.25), beam, beam)
	if not il.step_stone.is_empty():
		var s: Color = pal["stone"]
		_prism(mb, ROLE_EARTH, il.step_stone, il.genkan_y, il.step_stone_y, s.lightened(0.05), s.darkened(0.1))
		_flat_collision(col, il.step_stone, il.step_stone_y)


# --- Murs vus de l'intérieur ----------------------------------------------------------------

static func _inner_wall(mb: BastideMeshBuilder, col: BastideBuildResult, il: BastideInteriorLayout,
		layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade, bs: BastideBuildingStyle, pal: Dictionary) -> void:
	var th := layout.wall_thickness
	var n := il.inner.size()
	var ia := il.inner[f.index]
	var ib := il.inner[(f.index + 1) % n]
	var us := (ia - f.a).dot(f.dir)
	var ue := (ib - f.a).dot(f.dir)
	if ue - us < 0.05:
		return
	var hint := -f.out3()
	var y_bot := layout.base_y
	# Haut du mur : le dessous du toit à l'aplomb de la face intérieure.
	var tops := PackedVector2Array()
	for t in _crossings(layout.roof, ia, ib):
		var u := lerpf(us, ue, t)
		tops.append(Vector2(u, _underside(layout, ia.lerp(ib, t)) + 0.03))
	var holes: Array = []
	for o in f.openings:
		if o.kind == Kind.ATTIC:
			continue
		holes.append(o)
	var xs := PackedFloat32Array([us, ue])
	for p in tops:
		xs.append(p.x)
	for o in holes:
		xs.append(clampf(o.u0, us, ue))
		xs.append(clampf(o.u1, us, ue))
	xs = BastideBuildingMesher._uniq(xs, us, ue)
	var wall: Color = pal["wall"]
	for i in xs.size() - 1:
		var x0 := xs[i]
		var x1 := xs[i + 1]
		var cx := (x0 + x1) * 0.5
		var top0 := _top_at(tops, x0)
		var top1 := _top_at(tops, x1)
		var cuts: Array = []
		for o in holes:
			if cx > o.u0 and cx < o.u1:
				cuts.append(Vector2(o.y0, o.y1))
		cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var y := y_bot
		for c: Vector2 in cuts:
			if c.x > y + 1e-3:
				mb.add_quad(ROLE_BODY, f.point(x0, y, -th), f.point(x1, y, -th), f.point(x1, c.x, -th), f.point(x0, c.x, -th),
					hint, wall.darkened(0.05), wall.darkened(0.05), wall, wall)
			y = maxf(y, c.y)
		if minf(top0, top1) > y + 1e-3:
			mb.add_quad(ROLE_BODY, f.point(x0, y, -th), f.point(x1, y, -th), f.point(x1, top1, -th), f.point(x0, top0, -th),
				hint, wall, wall, wall.lightened(0.04), wall.lightened(0.04))
	for o in holes:
		_opening_inside(mb, col, il, layout, f, o, bs, pal)
	# Bois : poteaux (ossature), plinthes et bandeaux sous chaque plafond.
	var timber: Color = pal["timber"]
	if il.timber:
		var pw := bs.post_width * 0.85
		var posts := PackedFloat32Array([us + pw * 0.5, ue - pw * 0.5])
		for u in f.posts:
			if u > us + pw and u < ue - pw:
				posts.append(u)
		for u in posts:
			_strip(mb, f, th, u - pw * 0.5, u + pw * 0.5, y_bot, _top_at(tops, u), 0.035, timber, holes)
	for lv: BastideInteriorLayout.Level in il.levels:
		_band(mb, f, th, us, ue, lv.y, lv.y + 0.09, 0.02, timber.darkened(0.1), holes)
		if is_finite(lv.ceiling_y):
			_band(mb, f, th, us, ue, lv.ceiling_y - 0.17, lv.ceiling_y, 0.05, timber, holes)
	if il.timber:
		_band(mb, f, th, us, ue, layout.eave_y - 0.22, layout.eave_y, 0.06, timber.darkened(0.05), holes)


## Altitudes où le dessous du toit change de pente le long d'un segment (0 → 1).
static func _crossings(roof: BastideRoofLayout, a: Vector2, b: Vector2) -> PackedFloat32Array:
	if roof == null:
		return PackedFloat32Array([0.0, 1.0])
	var ts := roof.crossings(a, b)
	if ts.is_empty() or ts[0] > 1e-4:
		ts.insert(0, 0.0)
	if ts[ts.size() - 1] < 1.0 - 1e-4:
		ts.append(1.0)
	return ts


static func _underside(layout: BastideBuildingLayout, p: Vector2) -> float:
	var h := layout.roof.height_at(p) - layout.roof.thickness if layout.roof else INF
	return maxf(layout.eave_y, h) if is_finite(h) else layout.eave_y


static func _top_at(tops: PackedVector2Array, u: float) -> float:
	return BastideBuildingMesher._line_at(tops, u)


## Morceaux [u0, u1] d'un bandeau horizontal qui ne traversent aucune ouverture.
static func _free_spans(u0: float, u1: float, y0: float, y1: float, holes: Array) -> Array:
	var pieces: Array = [Vector2(u0, u1)]
	for o in holes:
		if o.y1 <= y0 or o.y0 >= y1:
			continue
		var cut := Vector2(o.u0 - 0.04, o.u1 + 0.04)
		var next: Array = []
		for p: Vector2 in pieces:
			if cut.y <= p.x or cut.x >= p.y:
				next.append(p)
				continue
			if cut.x > p.x:
				next.append(Vector2(p.x, cut.x))
			if cut.y < p.y:
				next.append(Vector2(cut.y, p.y))
		pieces = next
	return pieces


static func _band(mb: BastideMeshBuilder, f: BastideBuildingLayout.Facade, th: float, u0: float, u1: float,
		y0: float, y1: float, prot: float, c: Color, holes: Array) -> void:
	for p: Vector2 in _free_spans(u0, u1, y0, y1, holes):
		_board(mb, f, th, p.x, p.y, y0, y1, prot, c)


## Poteau vu de l'intérieur, interrompu par les ouvertures qu'il croiserait.
static func _strip(mb: BastideMeshBuilder, f: BastideBuildingLayout.Facade, th: float, u0: float, u1: float,
		y0: float, y1: float, prot: float, c: Color, holes: Array) -> void:
	var spans: Array = [Vector2(y0, y1)]
	for o in holes:
		if o.u1 <= u0 or o.u0 >= u1:
			continue
		var next: Array = []
		for s: Vector2 in spans:
			if o.y1 <= s.x or o.y0 >= s.y:
				next.append(s)
				continue
			if o.y0 > s.x:
				next.append(Vector2(s.x, o.y0))
			if o.y1 < s.y:
				next.append(Vector2(o.y1, s.y))
		spans = next
	for s: Vector2 in spans:
		_board(mb, f, th, u0, u1, s.x, s.y, prot, c)


## Planche posée contre la face intérieure (face avant, dessus, dessous, bouts).
static func _board(mb: BastideMeshBuilder, f: BastideBuildingLayout.Facade, th: float, u0: float, u1: float,
		y0: float, y1: float, prot: float, c: Color) -> void:
	if u1 - u0 < 1e-3 or y1 - y0 < 1e-3:
		return
	var d0 := -th
	var d1 := -th - prot
	var inward := -f.out3()
	mb.add_quad(ROLE_WOOD, f.point(u0, y0, d1), f.point(u1, y0, d1), f.point(u1, y1, d1), f.point(u0, y1, d1), inward,
		c.darkened(0.06), c.darkened(0.06), c, c)
	mb.add_quad(ROLE_WOOD, f.point(u0, y1, d0), f.point(u1, y1, d0), f.point(u1, y1, d1), f.point(u0, y1, d1), Vector3.UP, c, c, c, c)
	mb.add_quad(ROLE_WOOD, f.point(u0, y0, d0), f.point(u1, y0, d0), f.point(u1, y0, d1), f.point(u0, y0, d1), Vector3.DOWN,
		c.darkened(0.3), c.darkened(0.3), c.darkened(0.3), c.darkened(0.3))
	mb.add_quad(ROLE_WOOD, f.point(u0, y0, d0), f.point(u0, y1, d0), f.point(u0, y1, d1), f.point(u0, y0, d1), -f.dir3(),
		c.darkened(0.15), c.darkened(0.15), c.darkened(0.15), c.darkened(0.15))
	mb.add_quad(ROLE_WOOD, f.point(u1, y0, d0), f.point(u1, y1, d0), f.point(u1, y1, d1), f.point(u1, y0, d1), f.dir3(),
		c.darkened(0.15), c.darkened(0.15), c.darkened(0.15), c.darkened(0.15))


## Fenêtre ou porte vue de dedans : tableau jusqu'à la face intérieure, dos du papier
## (ou de la vitre), appui de bois ; seuil de porte franchissable.
static func _opening_inside(mb: BastideMeshBuilder, col: BastideBuildResult, il: BastideInteriorLayout,
		layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade, o: Dictionary, bs: BastideBuildingStyle,
		pal: Dictionary) -> void:
	var th := layout.wall_thickness
	var u0: float = o.u0
	var u1: float = o.u1
	var y0: float = o.y0
	var y1: float = o.y1
	var lattice := bs.window_kind == BastideBuildingStyle.WindowKind.LATTICE
	var door: bool = o.kind == Kind.DOOR
	var depth: float
	if door:
		depth = BastideBuildingMesher.DOOR_DEPTH_SLIDING if bs.door_kind == BastideBuildingStyle.DoorKind.SLIDING \
				else BastideBuildingMesher.DOOR_DEPTH_HINGED
	else:
		depth = BastideBuildingMesher.WINDOW_DEPTH_LATTICE if lattice else BastideBuildingMesher.WINDOW_DEPTH_GLASS
	var rv: Color = pal["timber"] if il.timber else pal["wall"].darkened(0.12)
	var d1 := -th
	mb.add_quad(ROLE_WOOD if il.timber else ROLE_BODY, f.point(u0, y0, depth), f.point(u0, y1, depth), f.point(u0, y1, d1),
		f.point(u0, y0, d1), f.dir3(), rv, rv, rv.darkened(0.1), rv.darkened(0.1))
	mb.add_quad(ROLE_WOOD if il.timber else ROLE_BODY, f.point(u1, y0, depth), f.point(u1, y1, depth), f.point(u1, y1, d1),
		f.point(u1, y0, d1), -f.dir3(), rv, rv, rv.darkened(0.1), rv.darkened(0.1))
	mb.add_quad(ROLE_WOOD if il.timber else ROLE_BODY, f.point(u0, y1, depth), f.point(u1, y1, depth), f.point(u1, y1, d1),
		f.point(u0, y1, d1), Vector3.DOWN, rv.darkened(0.2), rv.darkened(0.2), rv.darkened(0.25), rv.darkened(0.25))
	if door:
		# Seuil : du dehors jusqu'au sol de l'entrée (ou au plancher), on y marche.
		var sill: Color = pal["timber"].darkened(0.05)
		var floor_y: float = il.genkan_y if not il.genkan.is_empty() else il.levels[0].y
		var y_in := minf(floor_y, y0 + 0.14)
		mb.add_quad(ROLE_WOOD, f.point(u0, y0, 0.02), f.point(u1, y0, 0.02), f.point(u1, y_in, d1 - 0.02), f.point(u0, y_in, d1 - 0.02),
			Vector3.UP, sill, sill, sill.lightened(0.05), sill.lightened(0.05))
		for tri in [[f.point(u0, y0, 0.02), f.point(u1, y0, 0.02), f.point(u1, y_in, d1 - 0.02)],
				[f.point(u0, y0, 0.02), f.point(u1, y_in, d1 - 0.02), f.point(u0, y_in, d1 - 0.02)]]:
			for p: Vector3 in tri:
				col.collision_faces.append(p)
		return
	# Appui intérieur.
	var board: Color = pal["timber"].lightened(0.08)
	_board(mb, f, th, u0 - 0.05, u1 + 0.05, y0 - 0.04, y0, 0.05, board)
	mb.add_quad(ROLE_WOOD, f.point(u0, y0, depth), f.point(u1, y0, depth), f.point(u1, y0, d1), f.point(u0, y0, d1),
		Vector3.UP, board, board, board, board)
	var back := depth - 0.006
	var inward := -f.out3()
	if lattice:
		# Le shoji vu de dedans : papier qui laisse passer le jour, quadrillage de baguettes.
		var paper: Color = pal["paper"]
		mb.add_quad(ROLE_PAPER, f.point(u0, y0, back), f.point(u1, y0, back), f.point(u1, y1, back), f.point(u0, y1, back),
			inward, paper, paper, paper.lightened(0.05), paper.lightened(0.05))
		var kumiko: Color = pal["timber"].lightened(0.18)
		var gd := back - 0.008
		var cols := maxi(2, roundi((u1 - u0) / 0.3))
		var rows := maxi(2, roundi((y1 - y0) / 0.3))
		for i in range(1, cols):
			var u := lerpf(u0, u1, float(i) / cols)
			mb.add_quad(ROLE_WOOD, f.point(u - 0.011, y0, gd), f.point(u + 0.011, y0, gd), f.point(u + 0.011, y1, gd),
				f.point(u - 0.011, y1, gd), inward, kumiko, kumiko, kumiko, kumiko)
		for i in range(1, rows):
			var y := lerpf(y0, y1, float(i) / rows)
			mb.add_quad(ROLE_WOOD, f.point(u0, y - 0.011, gd), f.point(u1, y - 0.011, gd), f.point(u1, y + 0.011, gd),
				f.point(u0, y + 0.011, gd), inward, kumiko, kumiko, kumiko, kumiko)
	else:
		var glass := Color(0.62, 0.72, 0.78)
		mb.add_quad(ROLE_GLASS, f.point(u0, y0, back), f.point(u1, y0, back), f.point(u1, y1, back), f.point(u0, y1, back),
			inward, glass, glass, glass.lightened(0.1), glass.lightened(0.1))
		var bar: Color = pal["timber"]
		var cu := (u0 + u1) * 0.5
		var cy := (y0 + y1) * 0.5
		mb.add_quad(ROLE_WOOD, f.point(cu - 0.02, y0, back - 0.01), f.point(cu + 0.02, y0, back - 0.01),
			f.point(cu + 0.02, y1, back - 0.01), f.point(cu - 0.02, y1, back - 0.01), inward, bar, bar, bar, bar)
		mb.add_quad(ROLE_WOOD, f.point(u0, cy - 0.02, back - 0.01), f.point(u1, cy - 0.02, back - 0.01),
			f.point(u1, cy + 0.02, back - 0.01), f.point(u0, cy + 0.02, back - 0.01), inward, bar, bar, bar, bar)


# --- Sous le toit --------------------------------------------------------------------------

static func _roof_underside(mb: BastideMeshBuilder, il: BastideInteriorLayout, layout: BastideBuildingLayout,
		pal: Dictionary) -> void:
	var roof := layout.roof
	if roof == null or roof.is_empty():
		return
	var plank: Color = pal["ceiling"]
	var rafter: Color = pal["timber"]
	for face in roof.faces:
		if face.weight <= 0.0:
			continue
		var up3: Vector3 = face.up_dir
		var along3: Vector3 = face.dir
		var up := Vector2(up3.x, up3.z).normalized()
		var along := Vector2(along3.x, along3.z).normalized()
		for poly: PackedVector3Array in face.polys:
			var plane := _plane(poly)
			if plane.is_empty():
				continue
			var flat := PackedVector2Array()
			for p in poly:
				flat.append(Vector2(p.x, p.z))
			for part in Geometry2D.intersect_polygons(flat, il.inner):
				_sloped(mb, part, plane, -roof.thickness, plank, Vector3.DOWN)
				# Chevrons dans le sens de la pente, tous les 45 cm.
				var lo := INF
				var hi := -INF
				for p in part:
					lo = minf(lo, p.dot(along))
					hi = maxf(hi, p.dot(along))
				var s := ceilf(lo / 0.45) * 0.45
				while s < hi:
					var strip := PackedVector2Array([along * (s - 0.035) - up * 500.0, along * (s + 0.035) - up * 500.0,
						along * (s + 0.035) + up * 500.0, along * (s - 0.035) + up * 500.0])
					for r in Geometry2D.intersect_polygons(strip, part):
						_sloped_block(mb, r, plane, -roof.thickness, 0.07, rafter)
					s += 0.45
	# Petits pignons de l'irimoya : visibles aussi de dedans.
	for gp in roof.gable_panels:
		var out: Vector3 = gp.out
		for poly: PackedVector3Array in gp.polys:
			for i in range(1, poly.size() - 1):
				for side in [-1.0, 1.0]:
					var o: Vector3 = out * 0.03 * side
					mb.add_tri(ROLE_WOOD, poly[0] - o, poly[i] - o, poly[i + 1] - o, -o, plank, plank, plank)


## Plan d'un polygone 3D : { a: Vector3, n: Vector3 } (vide s'il est vertical ou dégénéré).
static func _plane(poly: PackedVector3Array) -> Dictionary:
	for i in range(1, poly.size() - 1):
		var n := (poly[i] - poly[0]).cross(poly[i + 1] - poly[0])
		if n.length_squared() > 1e-8:
			n = n.normalized()
			if absf(n.y) < 0.05:
				return {}
			return {"a": poly[0], "n": n}
	return {}


static func _plane_y(plane: Dictionary, p: Vector2) -> float:
	var a: Vector3 = plane.a
	var n: Vector3 = plane.n
	return a.y - (n.x * (p.x - a.x) + n.z * (p.y - a.z)) / n.y


static func _sloped(mb: BastideMeshBuilder, poly: PackedVector2Array, plane: Dictionary, dy: float, c: Color, hint: Vector3) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for t in range(0, idx.size(), 3):
		var pts: Array = []
		for k in 3:
			var p := poly[idx[t + k]]
			pts.append(Vector3(p.x, _plane_y(plane, p) + dy, p.y))
		mb.add_tri(ROLE_WOOD, pts[0], pts[1], pts[2], hint, c, c, c)


static func _sloped_block(mb: BastideMeshBuilder, poly: PackedVector2Array, plane: Dictionary, dy: float, depth: float, c: Color) -> void:
	_sloped(mb, poly, plane, dy - depth, c.darkened(0.05), Vector3.DOWN)
	var center := BastidePolygon.centroid(poly)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var ya := _plane_y(plane, a) + dy
		var yb := _plane_y(plane, b) + dy
		var mid := (a + b) * 0.5 - center
		mb.add_quad(ROLE_WOOD, Vector3(a.x, ya - depth, a.y), Vector3(b.x, yb - depth, b.y), Vector3(b.x, yb, b.y),
			Vector3(a.x, ya, a.y), Vector3(mid.x, 0, mid.y), c.darkened(0.15), c.darkened(0.15), c, c)


# --- Escaliers et garde-corps -------------------------------------------------------------

## Volée fermée à la japonaise (hako-kaidan) : marches pleines, joue côté pièce qui
## descend jusqu'au sol, bout fermé. Collision : une rampe (on monte sans buter) et le coffre.
static func _flight(mb: BastideMeshBuilder, col: BastideBuildResult, fl: BastideInteriorLayout.Flight, pal: Dictionary) -> void:
	var wood: Color = pal["stair"]
	var side: Color = pal["timber"]
	var w := fl.width
	var r := fl.riser()
	var dir3 := Vector3(fl.dir.x, 0, fl.dir.y)
	var side3 := Vector3(fl.side.x, 0, fl.side.y)
	for i in fl.steps:
		var a0 := i * fl.tread
		var a1 := (i + 1) * fl.tread
		var ytop := fl.y0 + (i + 1) * r
		var ylow := fl.y0 + i * r
		var t := BastideRng.signed_at(int(fl.start.x * 100.0), "step", i) * 0.05
		var c := wood.lightened(t) if t > 0.0 else wood.darkened(-t)
		var nose := 0.025
		# Marche (dessus et nez) et contremarche.
		var p := func(al: float, ac: float, y: float) -> Vector3:
			var q := fl.at(al, ac)
			return Vector3(q.x, y, q.y)
		mb.add_quad(ROLE_WOOD, p.call(a0 - nose, 0.0, ytop), p.call(a1, 0.0, ytop), p.call(a1, w, ytop), p.call(a0 - nose, w, ytop),
			Vector3.UP, c, c, c.lightened(0.04), c.lightened(0.04))
		mb.add_quad(ROLE_WOOD, p.call(a0 - nose, 0.0, ytop - 0.035), p.call(a0 - nose, w, ytop - 0.035), p.call(a0 - nose, w, ytop),
			p.call(a0 - nose, 0.0, ytop), -dir3, c.darkened(0.1), c.darkened(0.1), c, c)
		mb.add_quad(ROLE_WOOD, p.call(a0, 0.0, ylow), p.call(a0, w, ylow), p.call(a0, w, ytop - 0.035), p.call(a0, 0.0, ytop - 0.035),
			-dir3, c.darkened(0.25), c.darkened(0.25), c.darkened(0.18), c.darkened(0.18))
		# Joue côté pièce : un panneau en escalier qui ferme le coffre.
		mb.add_quad(ROLE_WOOD, p.call(a0, w, fl.y0), p.call(a1, w, fl.y0), p.call(a1, w, ytop), p.call(a0, w, ytop),
			side3, side.darkened(0.08), side.darkened(0.08), side, side)
	# Bout fermé sous l'arrivée.
	var e0 := fl.at(fl.run(), 0.0)
	var e1 := fl.at(fl.run(), w)
	mb.add_quad(ROLE_WOOD, Vector3(e0.x, fl.y0, e0.y), Vector3(e1.x, fl.y0, e1.y), Vector3(e1.x, fl.y1, e1.y),
		Vector3(e0.x, fl.y1, e0.y), dir3, side.darkened(0.1), side.darkened(0.1), side, side)
	# Main courante le long de la joue.
	var rail: Color = pal["timber"].lightened(0.06)
	var h := 0.85
	var b0 := fl.at(0.0, w - 0.03)
	var b1 := fl.at(fl.run(), w - 0.03)
	_beam(mb, Vector3(b0.x, fl.y0 + h, b0.y), Vector3(b1.x, fl.y1 + h, b1.y), 0.05, rail)
	for al: float in [0.05, fl.run() - 0.05]:
		var q := fl.at(al, w - 0.03)
		_beam(mb, Vector3(q.x, fl.height_at(al), q.y), Vector3(q.x, fl.height_at(al) + h, q.y), 0.06, rail.darkened(0.08))
	# Collisions : rampe, joue, bout.
	var s0 := fl.at(0.0, 0.0)
	var s1 := fl.at(0.0, w)
	var quads := [
		[Vector3(s0.x, fl.y0, s0.y), Vector3(e0.x, fl.y1, e0.y), Vector3(e1.x, fl.y1, e1.y), Vector3(s1.x, fl.y0, s1.y)],
		[Vector3(e0.x, fl.y0, e0.y), Vector3(e1.x, fl.y0, e1.y), Vector3(e1.x, fl.y1, e1.y), Vector3(e0.x, fl.y1, e0.y)],
	]
	for q: Array in quads:
		col.collision_faces.append(q[0]); col.collision_faces.append(q[1]); col.collision_faces.append(q[2])
		col.collision_faces.append(q[0]); col.collision_faces.append(q[2]); col.collision_faces.append(q[3])
	# Joue (triangle sous la rampe).
	col.collision_faces.append(Vector3(s1.x, fl.y0, s1.y))
	col.collision_faces.append(Vector3(e1.x, fl.y0, e1.y))
	col.collision_faces.append(Vector3(e1.x, fl.y1, e1.y))


## Garde-corps autour d'une trémie : poteaux, lisse haute et lisse basse.
static func _railing(mb: BastideMeshBuilder, col: BastideBuildResult, a: Vector2, b: Vector2, y: float, pal: Dictionary) -> void:
	var c: Color = pal["timber"].lightened(0.06)
	var length := a.distance_to(b)
	if length < 0.1:
		return
	var count := maxi(1, ceili(length / 0.9))
	for i in count + 1:
		var p := a.lerp(b, float(i) / count)
		_beam(mb, Vector3(p.x, y, p.y), Vector3(p.x, y + 0.9, p.y), 0.07, c.darkened(0.06))
	for h: float in [0.88, 0.45]:
		_beam(mb, Vector3(a.x, y + h, a.y), Vector3(b.x, y + h, b.y), 0.05, c)
	var d := (b - a) / length
	var n := Vector2(-d.y, d.x) * 0.03
	col.add_box([Vector3(a.x - n.x, y, a.y - n.y), Vector3(b.x - n.x, y, b.y - n.y), Vector3(b.x + n.x, y, b.y + n.y),
		Vector3(a.x + n.x, y, a.y + n.y), Vector3(a.x - n.x, y + 0.95, a.y - n.y), Vector3(b.x - n.x, y + 0.95, b.y - n.y),
		Vector3(b.x + n.x, y + 0.95, b.y + n.y), Vector3(a.x + n.x, y + 0.95, a.y + n.y)])


## Pièce de bois de section carrée entre deux points.
static func _beam(mb: BastideMeshBuilder, p0: Vector3, p1: Vector3, size: float, c: Color) -> void:
	var axis := p1 - p0
	if axis.length() < 1e-4:
		return
	var ref := Vector3.UP if absf(axis.normalized().y) < 0.9 else Vector3.RIGHT
	var u := axis.cross(ref).normalized() * size * 0.5
	var v := axis.cross(u).normalized() * size * 0.5
	var k := [p0 - u - v, p0 + u - v, p0 + u + v, p0 - u + v, p1 - u - v, p1 + u - v, p1 + u + v, p1 - u + v]
	mb.add_block(ROLE_WOOD, k, 0.0, 0.0, c, c, true)
