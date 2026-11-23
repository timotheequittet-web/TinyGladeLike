@tool
class_name BastideBuildingMesher
extends RefCounted
## Backend procédural des bâtiments : BastideBuildingLayout → BuildResult.
## Ne décide rien : ouvertures, couleurs et profils viennent du plan.
##
## Murs enduits percés de vraies ouvertures (avec leur tableau), soubassement et
## chaînes d'angle en pierre, bandeaux, encadrements, volets, jardinières, porte
## cintrée à claveaux, puis le toit (BastideRoofMesher).

const Kind := BastideBuildingLayout.OpeningKind
const ROLE_BODY := &"body"
const ROLE_ROOF := &"roof"
const ROLE_GLASS := &"glass"
const FOOTING := 0.3
## Le haut des murs monte un peu dans l'épaisseur du toit : aucune fente sous l'égout.
const WALL_TOP_SINK := 0.05


static func build(layout: BastideBuildingLayout, style: BastideStyle, with_collision := true) -> BastideBuildResult:
	var result := BastideBuildResult.new()
	var mb := BastideMeshBuilder.new()
	var bs := style.get_building_style()
	var ws := style.get_wall_style()
	var t0 := Time.get_ticks_usec()

	for f: BastideBuildingLayout.Facade in layout.facades:
		var grid := _grid(layout, f)
		_plaster(mb, layout, f, grid[0], grid[1])
		if bs.plinth_height > 0.0:
			_plinth(mb, layout, f, bs, ws)
		if bs.string_courses:
			for k in range(1, layout.floors):
				_band(mb, layout, f, layout.base_y + k * layout.floor_height - 0.07, 0.15, 0.05, ws.quoin_color, ws)
		for o in f.openings:
			match o.kind:
				Kind.WINDOW:
					_window(mb, layout, f, o, bs, ws, true, grid)
				Kind.ATTIC:
					_window(mb, layout, f, o, bs, ws, false, grid)
				Kind.DOOR:
					_door(mb, layout, f, o, bs, ws, grid)
		if with_collision:
			_facade_collision(result, layout, f)
	if bs.quoins:
		for i in layout.facades.size():
			var f: BastideBuildingLayout.Facade = layout.facades[i]
			if f.convex_start:
				var prev: BastideBuildingLayout.Facade = layout.facades[posmod(i - 1, layout.facades.size())]
				_quoins(mb, layout, prev, f, bs, ws, i)
	var t_walls := Time.get_ticks_usec() - t0

	BastideRoofMesher.build_into(mb, result, layout.roof, style, layout.seed, with_collision)

	result.mesh = mb.commit({
		ROLE_BODY: style.get_material(),
		ROLE_ROOF: style.get_roof_material(),
		ROLE_GLASS: style.get_glass_material(),
	})
	result.stats = {
		"facades": layout.facades.size(),
		"windows": layout.count(Kind.WINDOW) + layout.count(Kind.ATTIC),
		"doors": layout.count(Kind.DOOR),
		"floors": layout.floors,
		"triangles": mb.triangle_count,
		"roof": "plat" if layout.roof.fallback == "plat" else ("pignons" if layout.roof.weights.has(0.0) else "croupes"),
		"notes": ", ".join(layout.notes),
		"timings_us": {"walls": t_walls, "total": Time.get_ticks_usec() - t0},
	}
	return result


# --- Enduit ------------------------------------------------------------------------

## Face extérieure enduite, percée des ouvertures : grille de rectangles entre les
## bords des ouvertures, plus le remplissage autour des arcs et le triangle du pignon.
## Tous les morceaux partagent exactement leurs sommets (aucune fente visible).
static func _plaster(mb: BastideMeshBuilder, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade,
		xs: PackedFloat32Array, ys: PackedFloat32Array) -> void:
	var hint := f.out3()
	for xi in xs.size() - 1:
		for yi in ys.size() - 1:
			var x0 := xs[xi]
			var x1 := xs[xi + 1]
			var y0 := ys[yi]
			var y1 := ys[yi + 1]
			var cx := (x0 + x1) * 0.5
			var cy := (y0 + y1) * 0.5
			var skip := false
			for o in f.openings:
				if o.kind == Kind.ATTIC or cx <= o.u0 or cx >= o.u1:
					continue
				if cy > o.y0 and cy < o.y1 + o.arch:
					skip = true
			if skip:
				continue
			mb.add_quad(ROLE_BODY, f.point(x0, y0), f.point(x1, y0), f.point(x1, y1), f.point(x0, y1), hint,
				_plaster_at(layout, f, y0), _plaster_at(layout, f, y0), _plaster_at(layout, f, y1), _plaster_at(layout, f, y1))
	for o in f.openings:
		if o.kind == Kind.DOOR and o.arch > 0.0:
			_arch_fill(mb, layout, f, o)
	# Pignon : polygone au-dessus de l'égout, dont la base reprend les sommets de la grille.
	if f.gable:
		var y_top := ys[ys.size() - 1]
		var poly := PackedVector2Array()
		for i in range(xs.size() - 1, -1, -1):
			poly.append(Vector2(xs[i], y_top))
		for i in range(1, f.profile.size() - 1):
			poly.append(f.profile[i] + Vector2(0.0, WALL_TOP_SINK))
		var idx := BastidePolygon.triangulate(poly)
		if idx.is_empty():
			poly = PackedVector2Array([Vector2(f.length, y_top), Vector2(0.0, y_top)])
			for i in range(1, f.profile.size() - 1):
				poly.append(f.profile[i] + Vector2(0.0, WALL_TOP_SINK))
			idx = BastidePolygon.triangulate(poly)
		var c := f.plaster
		for t in range(0, idx.size(), 3):
			var a := poly[idx[t]]
			var b := poly[idx[t + 1]]
			var d := poly[idx[t + 2]]
			mb.add_tri(ROLE_BODY, f.point(a.x, a.y), f.point(b.x, b.y), f.point(d.x, d.y), hint, c, c, c)


## Lignes de la grille d'une façade : bords des ouvertures, axe des arcs.
static func _grid(layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade) -> Array:
	var y_bot := layout.base_y - FOOTING
	var y_top := layout.eave_y + WALL_TOP_SINK
	var xs := PackedFloat32Array([0.0, f.length])
	var ys := PackedFloat32Array([y_bot, y_top, layout.base_y + 1.6])
	for o in f.openings:
		if o.kind == Kind.ATTIC:
			continue
		xs.append(o.u0)
		xs.append(o.u1)
		ys.append(o.y0)
		ys.append(o.y1)
		if o.arch > 0.0:
			xs.append((o.u0 + o.u1) * 0.5)
			ys.append(o.y1 + o.arch)
	return [_uniq(xs, 0.0, f.length), _uniq(ys, y_bot, y_top)]


## Valeurs de `v` comprises entre lo et hi (bornes incluses).
static func _between(v: PackedFloat32Array, lo: float, hi: float) -> PackedFloat32Array:
	var out := PackedFloat32Array([lo])
	for x in v:
		if x > lo + 1e-4 and x < hi - 1e-4:
			out.append(x)
	out.append(hi)
	return out


static func _plaster_at(layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade, y: float) -> Color:
	var t := clampf((y - layout.base_y) / 1.6, 0.0, 1.0)
	return f.plaster.darkened(0.16 * (1.0 - t * t))


## Enduit entre un arc et le rectangle qui l'entoure : deux éventails depuis les coins.
static func _arch_fill(mb: BastideMeshBuilder, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade, o: Dictionary) -> void:
	var pts := _arch_points(o, 0.0)
	var top: float = o.y1 + o.arch
	var c := _plaster_at(layout, f, top)
	var half := pts.size() / 2
	var corners := [Vector2(o.u0, top), Vector2(o.u1, top)]
	for side in 2:
		var corner: Vector2 = corners[side]
		var from := 0 if side == 0 else half
		var to := half if side == 0 else pts.size() - 1
		for i in range(from, to):
			var p := pts[i]
			var q := pts[i + 1]
			mb.add_tri(ROLE_BODY, f.point(corner.x, corner.y), f.point(p.x, p.y), f.point(q.x, q.y), f.out3(), c, c, c)


## Points de l'arc d'une ouverture, de gauche à droite, à un rayon augmenté de `grow`.
static func _arch_points(o: Dictionary, grow: float, segments := 12) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cx: float = (o.u0 + o.u1) * 0.5
	var r: float = o.arch + grow
	for i in segments + 1:
		var a := PI - PI * float(i) / segments
		pts.append(Vector2(cx + cos(a) * r, o.y1 + sin(a) * r))
	return pts


static func _uniq(v: PackedFloat32Array, lo: float, hi: float) -> PackedFloat32Array:
	v.sort()
	var out := PackedFloat32Array()
	for x in v:
		x = clampf(x, lo, hi)
		if out.is_empty() or x - out[out.size() - 1] > 1e-4:
			out.append(x)
	return out


## Tableaux d'une ouverture, découpés aux lignes de la grille pour coller à l'enduit.
static func _reveals(mb: BastideMeshBuilder, f: BastideBuildingLayout.Facade, u0: float, u1: float,
		y0: float, y1: float, depth: float, reveal: Color, grid: Array, top_and_bottom: bool) -> void:
	var ys := _between(grid[1], y0, y1)
	for i in ys.size() - 1:
		var ya := ys[i]
		var yb := ys[i + 1]
		mb.add_quad(ROLE_BODY, f.point(u0, ya), f.point(u0, yb), f.point(u0, yb, depth), f.point(u0, ya, depth),
			f.dir3(), reveal, reveal, reveal.darkened(0.2), reveal.darkened(0.2))
		mb.add_quad(ROLE_BODY, f.point(u1, ya), f.point(u1, yb), f.point(u1, yb, depth), f.point(u1, ya, depth),
			-f.dir3(), reveal, reveal, reveal.darkened(0.2), reveal.darkened(0.2))
	if top_and_bottom:
		var xs := _between(grid[0], u0, u1)
		_reveal_h(mb, f, xs, y1, depth, Vector3.DOWN, reveal.darkened(0.25), reveal.darkened(0.4))
		_reveal_h(mb, f, xs, y0, depth, Vector3.UP + f.out3() * 0.2, reveal, reveal.darkened(0.1))


static func _reveal_h(mb: BastideMeshBuilder, f: BastideBuildingLayout.Facade, xs: PackedFloat32Array, y: float,
		depth: float, hint: Vector3, c_out: Color, c_in: Color) -> void:
	for i in xs.size() - 1:
		var a := xs[i]
		var b := xs[i + 1]
		mb.add_quad(ROLE_BODY, f.point(a, y), f.point(b, y), f.point(b, y, depth), f.point(a, y, depth),
			hint, c_out, c_out, c_in, c_in)


# --- Pierre : soubassement, bandeaux, chaînes d'angle -------------------------------

## Étendue d'un élément saillant le long d'une façade : il couvre l'angle saillant
## de départ et s'arrête avant l'angle rentrant (pas de faces superposées).
static func _span(f: BastideBuildingLayout.Facade, prot: float) -> Vector2:
	var u0 := -prot if f.convex_start else prot
	var u1 := f.length
	return Vector2(u0, u1)


static func _plinth(mb: BastideMeshBuilder, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade,
		bs: BastideBuildingStyle, ws: BastideWallStyle) -> void:
	var prot := bs.plinth_protrusion
	var span := _span(f, prot)
	# Morceaux de soubassement, interrompus par les portes.
	var pieces: Array = [span]
	for o in f.openings:
		if o.kind != Kind.DOOR:
			continue
		var cut := Vector2(o.u0 - 0.24, o.u1 + 0.24)
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
	var y0 := layout.base_y - FOOTING
	var y_top := layout.base_y + bs.plinth_height
	var rows := maxi(1, roundi((y_top - y0) / 0.42))
	var mortar := ws.mortar_color
	for pi in pieces.size():
		var p: Vector2 = pieces[pi]
		if p.y - p.x < 0.1:
			continue
		for r in rows:
			var ya := lerpf(y0, y_top, float(r) / rows)
			var yb := lerpf(y0, y_top, float(r + 1) / rows)
			var key := BastideRng.combine(BastideRng.combine(f.index, pi), r)
			var lengths := BastideDistributor.split_lengths(layout.seed, "plinth", key, p.y - p.x,
				ws.stone_length_min, ws.stone_length_max)
			var acc := p.x
			for li in lengths.size():
				var sk := BastideRng.combine(key, li)
				var tint := BastideRng.signed_at(layout.seed, "plinth_tint", sk) * ws.color_variance
				var base := ws.stone_color.lerp(ws.stone_color_alt, BastideRng.randf_at(layout.seed, "plinth_alt", sk))
				var c := base.lightened(tint) if tint > 0.0 else base.darkened(-tint)
				var d := prot * (0.85 + BastideRng.randf_at(layout.seed, "plinth_d", sk) * 0.3)
				_facade_block(mb, f, acc, acc + lengths[li], ya, yb, -0.1, d, c, mortar.lerp(c, 0.3), ws.stone_bevel)
				acc += lengths[li]


static func _band(mb: BastideMeshBuilder, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade,
		y: float, h: float, prot: float, color: Color, ws: BastideWallStyle) -> void:
	var span := _span(f, prot)
	var lengths := BastideDistributor.split_lengths(layout.seed, "band", BastideRng.combine(f.index, int(y * 10.0)),
		span.y - span.x, 0.8, 1.4)
	var acc := span.x
	for li in lengths.size():
		var tint := BastideRng.signed_at(layout.seed, "band_tint", BastideRng.combine(f.index, li)) * 0.04
		var c := color.lightened(tint) if tint > 0.0 else color.darkened(-tint)
		_facade_block(mb, f, acc, acc + lengths[li], y, y + h, -0.1, prot, c, ws.mortar_color.lerp(c, 0.4), 0.025)
		acc += lengths[li]


## Chaîne d'angle : blocs alternativement longs et courts sur les deux façades.
static func _quoins(mb: BastideMeshBuilder, layout: BastideBuildingLayout, prev: BastideBuildingLayout.Facade,
		f: BastideBuildingLayout.Facade, bs: BastideBuildingStyle, ws: BastideWallStyle, corner: int) -> void:
	var c2 := f.a
	var m := (f.out + prev.out)
	if m.length_squared() < 1e-6:
		return
	m = m.normalized()
	m *= 1.0 / maxf(m.dot(f.out), 0.3)
	var prot := 0.065
	var depth := 0.18
	var y := layout.base_y + bs.plinth_height
	var top := layout.eave_y - 0.04
	var row := 0
	var mortar := ws.mortar_color
	while y < top - 0.1:
		var key := BastideRng.combine(corner, row)
		var y1 := minf(y + 0.36 * BastideRng.randf_range_at(layout.seed, "quoin_h", key, 0.85, 1.15), top)
		if top - y1 < 0.15:
			y1 = top
		var long_side := row % 2 == 0
		var la := 0.62 if long_side else 0.36
		var lb := 0.36 if long_side else 0.62
		la = minf(la, f.length * 0.3)
		lb = minf(lb, prev.length * 0.3)
		var tint := BastideRng.signed_at(layout.seed, "quoin_tint", key) * ws.color_variance * 0.6
		var c := ws.quoin_color.lightened(tint) if tint > 0.0 else ws.quoin_color.darkened(-tint)
		var edge := mortar.lerp(c, 0.35)
		var o_out := c2 + m * prot
		var o_in := c2 - m * depth
		# Bloc sur la façade f (départ de l'angle).
		var fa := [o_out, c2 + f.dir * la + f.out * prot, c2 + f.dir * la - f.out * depth, o_in]
		# Bloc sur la façade précédente (fin de l'angle).
		var fb := [c2 - prev.dir * lb + prev.out * prot, o_out, o_in, c2 - prev.dir * lb - prev.out * depth]
		for quad in [fa, fb]:
			var k: Array = []
			for yy in [y, y1]:
				for p: Vector2 in quad:
					k.append(Vector3(p.x, yy, p.y))
			mb.add_block(ROLE_BODY, k, ws.stone_bevel * 0.8, 0.012, c, edge)
		y = y1
		row += 1


## Bloc collé à une façade : u0-u1 le long, y0-y1 en hauteur, d0-d1 en profondeur (vers l'extérieur).
static func _facade_block(mb: BastideMeshBuilder, f: BastideBuildingLayout.Facade, u0: float, u1: float,
		y0: float, y1: float, d0: float, d1: float, color: Color, edge: Color, bevel := 0.03, bottom := false) -> void:
	var k := [
		f.point(u0, y0, d0), f.point(u1, y0, d0), f.point(u1, y0, d1), f.point(u0, y0, d1),
		f.point(u0, y1, d0), f.point(u1, y1, d0), f.point(u1, y1, d1), f.point(u0, y1, d1),
	]
	mb.add_block(ROLE_BODY, k, bevel, 0.006, color, edge, bottom)


# --- Fenêtres -----------------------------------------------------------------------

static func _window(mb: BastideMeshBuilder, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade,
		o: Dictionary, bs: BastideBuildingStyle, ws: BastideWallStyle, real_hole: bool, grid: Array) -> void:
	var u0: float = o.u0
	var u1: float = o.u1
	var y0: float = o.y0
	var y1: float = o.y1
	var depth := -0.16 if real_hole else 0.02
	var wood := bs.wood_color
	var stone := ws.quoin_color
	var mortar := ws.mortar_color
	var key := BastideRng.combine(BastideRng.combine(f.index, int(o.floor)), int(u0 * 10.0))
	if real_hole:
		var reveal := f.plaster.darkened(0.22)
		_reveals(mb, f, u0, u1, y0, y1, depth, reveal, grid, true)
	# Vitre.
	var glass := bs.glass_color.lightened(BastideRng.randf_at(layout.seed, "glass", key) * 0.08)
	mb.add_quad(ROLE_GLASS, f.point(u0, y0, depth), f.point(u1, y0, depth), f.point(u1, y1, depth), f.point(u0, y1, depth),
		f.out3(), glass, glass, glass.lightened(0.1), glass.lightened(0.1))
	# Huisserie : cadre, meneau et traverse.
	var fw := 0.055
	var d0 := depth - 0.01
	var d1 := depth + 0.035
	_facade_block(mb, f, u0, u0 + fw, y0, y1, d0, d1, wood, wood.darkened(0.3), 0.008)
	_facade_block(mb, f, u1 - fw, u1, y0, y1, d0, d1, wood, wood.darkened(0.3), 0.008)
	_facade_block(mb, f, u0 + fw, u1 - fw, y1 - fw, y1, d0, d1, wood, wood.darkened(0.3), 0.008)
	_facade_block(mb, f, u0 + fw, u1 - fw, y0, y0 + fw, d0, d1, wood, wood.darkened(0.3), 0.008)
	var mid := (u0 + u1) * 0.5
	_facade_block(mb, f, mid - 0.022, mid + 0.022, y0 + fw, y1 - fw, d0, d1 - 0.01, wood, wood.darkened(0.3), 0.006)
	var ty := lerpf(y0, y1, 0.62)
	_facade_block(mb, f, u0 + fw, u1 - fw, ty - 0.022, ty + 0.022, d0, d1 - 0.01, wood, wood.darkened(0.3), 0.006)
	# Encadrement de pierre.
	var jw := 0.13
	var sp := 0.035
	var sc := stone.darkened(BastideRng.randf_at(layout.seed, "frame", key) * 0.06)
	var edge := mortar.lerp(sc, 0.4)
	_facade_block(mb, f, u0 - jw, u0, y0, y1, -0.05, sp, sc, edge, 0.02)
	_facade_block(mb, f, u1, u1 + jw, y0, y1, -0.05, sp, sc, edge, 0.02)
	_facade_block(mb, f, u0 - jw, u1 + jw, y1, y1 + 0.17, -0.05, sp + 0.01, sc.lightened(0.03), edge, 0.025)
	_facade_block(mb, f, u0 - jw - 0.05, u1 + jw + 0.05, y0 - 0.11, y0, -0.05, sp + 0.06, sc, edge, 0.02, true)
	if o.shutters:
		_shutters(mb, layout, f, o, jw, key)
	if o.flowers:
		_flower_box(mb, layout, f, o, bs, key)


## Volets ouverts, rabattus contre le mur de part et d'autre.
static func _shutters(mb: BastideMeshBuilder, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade,
		o: Dictionary, jw: float, key: int) -> void:
	var w: float = (o.u1 - o.u0) * 0.5
	var y0: float = o.y0 + 0.02
	var y1: float = o.y1 - 0.02
	var base := layout.shutter_color
	for side in [-1.0, 1.0]:
		var inner: float = o.u0 - jw - 0.02 if side < 0.0 else o.u1 + jw + 0.02
		var outer: float = inner + w * side
		var a := minf(inner, outer)
		var b := maxf(inner, outer)
		var boards := 3
		for i in boards:
			var t := BastideRng.signed_at(layout.seed, "shutter", BastideRng.combine(key, i + (0 if side < 0.0 else 7))) * 0.05
			var c := base.lightened(t) if t > 0.0 else base.darkened(-t)
			var ba := lerpf(a, b, float(i) / boards) + 0.006
			var bb := lerpf(a, b, float(i + 1) / boards) - 0.006
			_facade_block(mb, f, ba, bb, y0, y1, 0.02, 0.055, c, c.darkened(0.25), 0.008)
		var batten := base.darkened(0.15)
		for yy in [lerpf(y0, y1, 0.18), lerpf(y0, y1, 0.82)]:
			_facade_block(mb, f, a + 0.03, b - 0.03, yy - 0.04, yy + 0.04, 0.05, 0.075, batten, batten.darkened(0.2), 0.008)


static func _flower_box(mb: BastideMeshBuilder, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade,
		o: Dictionary, bs: BastideBuildingStyle, key: int) -> void:
	var u0: float = o.u0 - 0.02
	var u1: float = o.u1 + 0.02
	var top: float = o.y0 - 0.11
	var wood := bs.wood_color.lightened(0.08)
	_facade_block(mb, f, u0, u1, top - 0.2, top, 0.1, 0.32, wood, wood.darkened(0.3), 0.012, true)
	var leaf := Color(0.3, 0.45, 0.2)
	_facade_block(mb, f, u0 + 0.03, u1 - 0.03, top, top + 0.07, 0.13, 0.29, leaf, leaf.darkened(0.3), 0.03)
	if bs.flower_colors.is_empty():
		return
	var count := maxi(3, roundi((u1 - u0) / 0.13))
	for i in count:
		var k := BastideRng.combine(key, 100 + i)
		var ci := int(BastideRng.randf_at(layout.seed, "flower_c", k) * bs.flower_colors.size()) % bs.flower_colors.size()
		var c := bs.flower_colors[ci]
		var u := lerpf(u0 + 0.07, u1 - 0.07, (i + 0.5) / count) + BastideRng.signed_at(layout.seed, "flower_u", k) * 0.02
		var s := 0.045 + BastideRng.randf_at(layout.seed, "flower_s", k) * 0.03
		var h := top + 0.06 + BastideRng.randf_at(layout.seed, "flower_h", k) * 0.07
		var d := 0.21 + BastideRng.signed_at(layout.seed, "flower_d", k) * 0.05
		_facade_block(mb, f, u - s, u + s, h, h + s * 1.6, d - s, d + s, c, c.darkened(0.25), s * 0.4)


# --- Porte ---------------------------------------------------------------------------

static func _door(mb: BastideMeshBuilder, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade,
		o: Dictionary, bs: BastideBuildingStyle, ws: BastideWallStyle, grid: Array) -> void:
	var u0: float = o.u0
	var u1: float = o.u1
	var y0: float = o.y0
	var y1: float = o.y1
	var r: float = o.arch
	var depth := -0.22
	var reveal := f.plaster.darkened(0.25)
	var stone := ws.quoin_color
	var mortar := ws.mortar_color
	# Tableau (côtés et intrados de l'arc).
	_reveals(mb, f, u0, u1, y0, y1, depth, reveal, grid, false)
	var pts := _arch_points(o, 0.0)
	var cx := (u0 + u1) * 0.5
	if r > 0.0:
		for i in pts.size() - 1:
			var p := pts[i]
			var q := pts[i + 1]
			var mid := (p + q) * 0.5
			var hint := f.point(cx, y1) - f.point(mid.x, mid.y)
			mb.add_quad(ROLE_BODY, f.point(p.x, p.y), f.point(q.x, q.y), f.point(q.x, q.y, depth), f.point(p.x, p.y, depth),
				hint, reveal.darkened(0.1), reveal.darkened(0.1), reveal.darkened(0.3), reveal.darkened(0.3))
	else:
		_reveal_h(mb, f, _between(grid[0], u0, u1), y1, depth, Vector3.DOWN, reveal.darkened(0.25), reveal.darkened(0.4))
	# Fond sombre derrière le vantail : rien ne transparaît par les joints.
	var back := depth - 0.03
	var dark := Color(0.05, 0.04, 0.035)
	var outline := PackedVector2Array([Vector2(u0 - 0.03, y0), Vector2(u1 + 0.03, y0)])
	if r > 0.0:
		var big := _arch_points(o, 0.03)
		for i in range(big.size() - 1, -1, -1):
			outline.append(big[i])
	else:
		outline.append(Vector2(u1 + 0.03, y1 + 0.03))
		outline.append(Vector2(u0 - 0.03, y1 + 0.03))
	for i in range(1, outline.size() - 1):
		mb.add_tri(ROLE_BODY, f.point(outline[0].x, outline[0].y, back), f.point(outline[i].x, outline[i].y, back),
			f.point(outline[i + 1].x, outline[i + 1].y, back), f.out3(), dark, dark, dark)
	# Vantail en planches verticales, dont le haut suit exactement l'arc.
	var top_line := pts if r > 0.0 else PackedVector2Array([Vector2(u0, y1), Vector2(u1, y1)])
	var planks := maxi(4, roundi((u1 - u0) / 0.19))
	for i in planks:
		var a := lerpf(u0, u1, float(i) / planks)
		var b := lerpf(u0, u1, float(i + 1) / planks)
		var t := BastideRng.signed_at(layout.seed, "plank", BastideRng.combine(f.index, i)) * 0.07
		var c := bs.door_color.lightened(t) if t > 0.0 else bs.door_color.darkened(-t)
		var poly := PackedVector2Array([Vector2(a, y0), Vector2(b, y0), Vector2(b, _line_at(top_line, b))])
		for k in range(top_line.size() - 1, -1, -1):
			if top_line[k].x > a + 1e-4 and top_line[k].x < b - 1e-4:
				poly.append(top_line[k])
		poly.append(Vector2(a, _line_at(top_line, a)))
		for k in range(1, poly.size() - 1):
			mb.add_tri(ROLE_BODY, f.point(poly[0].x, poly[0].y, depth), f.point(poly[k].x, poly[k].y, depth),
				f.point(poly[k + 1].x, poly[k + 1].y, depth), f.out3(), c.darkened(0.1), c, c)
		if i > 0:
			var seam := c.darkened(0.45)
			var ta := _line_at(top_line, a) - 0.01
			mb.add_quad(ROLE_BODY, f.point(a - 0.008, y0, depth + 0.003), f.point(a + 0.008, y0, depth + 0.003),
				f.point(a + 0.008, ta, depth + 0.003), f.point(a - 0.008, ta, depth + 0.003), f.out3(), seam, seam, seam, seam)
	var iron := Color(0.14, 0.13, 0.13)
	for yy in [y0 + 0.35, y0 + (y1 - y0) * 0.78]:
		_facade_block(mb, f, u0 + 0.06, u1 - 0.06, yy - 0.035, yy + 0.035, depth, depth + 0.025, iron, iron, 0.005)
	_facade_block(mb, f, u1 - 0.26, u1 - 0.2, y0 + 0.95, y0 + 1.05, depth, depth + 0.06, iron, iron, 0.01)
	# Piédroits en blocs alternés et claveaux.
	var row := 0
	var y := y0
	while y < y1 - 0.05:
		var y2 := minf(y + 0.38, y1)
		if y1 - y2 < 0.15:
			y2 = y1
		var w := 0.3 if row % 2 == 0 else 0.2
		var key := BastideRng.combine(f.index, row)
		var tint := BastideRng.signed_at(layout.seed, "jamb", key) * 0.05
		var c := stone.lightened(tint) if tint > 0.0 else stone.darkened(-tint)
		_facade_block(mb, f, u0 - w, u0, y, y2, -0.08, 0.05, c, mortar.lerp(c, 0.35), 0.025)
		_facade_block(mb, f, u1, u1 + w, y, y2, -0.08, 0.05, c.darkened(0.03), mortar.lerp(c, 0.35), 0.025)
		y = y2
		row += 1
	if r > 0.0:
		var count := 9
		var inner := _arch_points(o, 0.0, count)
		var outer := _arch_points(o, 0.26, count)
		for i in count:
			var tint := BastideRng.signed_at(layout.seed, "voussoir", BastideRng.combine(f.index, i)) * 0.05
			var c := stone.lightened(tint) if tint > 0.0 else stone.darkened(-tint)
			if i == count / 2:
				c = stone.lightened(0.05)
			var q := [inner[i], inner[i + 1], outer[i + 1], outer[i]]
			var k: Array = []
			for d in [-0.08, 0.06]:
				for p: Vector2 in q:
					k.append(f.point(p.x, p.y, d))
			mb.add_block(ROLE_BODY, k, 0.02, 0.006, c, mortar.lerp(c, 0.35))
	else:
		_facade_block(mb, f, u0 - 0.3, u1 + 0.3, y1, y1 + 0.22, -0.08, 0.06, stone, mortar.lerp(stone, 0.35), 0.025)
	# Marche.
	var step := stone.darkened(0.08)
	_facade_block(mb, f, u0 - 0.2, u1 + 0.2, y0 - 0.2, y0 + 0.13, -0.05, 0.42, step, mortar.lerp(step, 0.4), 0.03)


## Hauteur d'une polyligne (x croissants) à l'abscisse x.
static func _line_at(line: PackedVector2Array, x: float) -> float:
	for i in line.size() - 1:
		var p := line[i]
		var q := line[i + 1]
		if x >= p.x - 1e-5 and x <= q.x + 1e-5:
			return lerpf(p.y, q.y, clampf((x - p.x) / maxf(q.x - p.x, 1e-6), 0.0, 1.0))
	return line[0].y


# --- Collisions --------------------------------------------------------------------------

static func _facade_collision(col: BastideBuildResult, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade) -> void:
	var th := layout.wall_thickness
	var y0 := layout.base_y - FOOTING
	var y1 := layout.eave_y
	col.add_box([
		f.point(0.0, y0), f.point(f.length, y0), f.point(f.length, y0, -th), f.point(0.0, y0, -th),
		f.point(0.0, y1), f.point(f.length, y1), f.point(f.length, y1, -th), f.point(0.0, y1, -th),
	])
	if f.gable:
		for i in f.profile.size() - 1:
			var p := f.profile[i]
			var q := f.profile[i + 1]
			for tri in [[Vector2(p.x, y1), Vector2(q.x, y1), q], [Vector2(p.x, y1), q, p]]:
				for v: Vector2 in tri:
					col.collision_faces.append(f.point(v.x, v.y))
