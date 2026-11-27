@tool
class_name BastideBuildingMesher
extends RefCounted
## Backend procédural des bâtiments : BastideBuildingLayout → BuildResult.
## Ne décide rien : ouvertures, couleurs et profils viennent du plan.
##
## Murs enduits percés de vraies ouvertures (avec leur tableau), puis selon le style :
## - maçonnerie : soubassement et chaînes d'angle en pierre, bandeaux, encadrements,
##   fenêtres à croisillons, volets, jardinières, porte cintrée à claveaux ;
## - ossature bois : poteaux et poutres apparents, bardage bas, fenêtres à
##   claire-voie devant un écran de papier, porte coulissante, noren, auvent ;
## puis le toit (BastideRoofMesher).

const Kind := BastideBuildingLayout.OpeningKind
const ROLE_BODY := &"body"
const ROLE_ROOF := &"roof"
const ROLE_GLASS := &"glass"
const ROLE_WOOD := &"wood"
const ROLE_PAPER := &"paper"
const FOOTING := 0.3
## Le haut des murs monte un peu dans l'épaisseur du toit : aucune fente sous l'égout.
const WALL_TOP_SINK := 0.05
## Profondeur des vitres, du papier et des vantaux dans le mur (lue aussi par l'intérieur).
const WINDOW_DEPTH_GLASS := -0.16
const WINDOW_DEPTH_LATTICE := -0.12
const DOOR_DEPTH_SLIDING := -0.16
const DOOR_DEPTH_HINGED := -0.22


## `open_doors` : variante « on peut entrer » (créée seulement quand on s'approche en
## promenade) : pas de fond sombre derrière les portes, des vantaux à part (maillages
## dans anchors["door_leaves"], que le nœud fait coulisser ou pivoter) et un passage
## dans la collision des façades.
static func build(layout: BastideBuildingLayout, style: BastideStyle, with_collision := true,
		open_doors := false) -> BastideBuildResult:
	var result := BastideBuildResult.new()
	var leaves: Array = []
	var mb := BastideMeshBuilder.new()
	var bs := style.get_building_style()
	var ws := style.get_wall_style()
	var t0 := Time.get_ticks_usec()

	var lattice := bs.window_kind == BastideBuildingStyle.WindowKind.LATTICE
	var sliding := bs.door_kind == BastideBuildingStyle.DoorKind.SLIDING
	# Place de l'enduit dans la hauteur de la maison (shader : humidité et mousse au
	# pied, ombre et salissures sous l'égout et sous les auvents des étages).
	var plaster_bottom := layout.base_y + maxf(maxf(bs.plinth_height, bs.wainscot_height), 0.0)
	mb.set_height_frame(ROLE_BODY, plaster_bottom, layout.eave_y, layout.base_y,
			layout.floor_height if layout.pent_roof and layout.floors > 1 else 1000.0)
	for f: BastideBuildingLayout.Facade in layout.facades:
		var grid := _grid(layout, f, bs)
		_plaster(mb, layout, f, grid[0], grid[1], bs)
		if bs.plinth_height > 0.0:
			_plinth(mb, layout, f, bs, ws)
		if layout.timber:
			_timber_frame(mb, layout, f, bs)
		elif bs.string_courses:
			for k in range(1, layout.floors):
				_band(mb, layout, f, layout.base_y + k * layout.floor_height - 0.07, 0.15, 0.05, ws.quoin_color, ws)
		for o in f.openings:
			match o.kind:
				Kind.WINDOW, Kind.ATTIC:
					if lattice:
						_lattice_window(mb, layout, f, o, bs, grid, o.kind == Kind.WINDOW)
					else:
						_window(mb, layout, f, o, bs, ws, o.kind == Kind.WINDOW, grid)
				Kind.DOOR:
					if sliding:
						_sliding_door(mb, layout, f, o, bs, ws, grid, leaves if open_doors else null, style)
					else:
						_door(mb, layout, f, o, bs, ws, grid, leaves if open_doors else null, style)
		if with_collision:
			_facade_collision(result, layout, f, open_doors)
	if layout.pent_roof:
		for level in range(1, layout.pent_levels + 1):
			_pent_roof(mb, result, layout, style, with_collision, level)
	if bs.quoins and not layout.timber:
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
		ROLE_WOOD: style.get_wood_material(),
		ROLE_PAPER: style.get_paper_material(),
	})
	result.anchors = anchors(layout)
	if open_doors:
		result.anchors["door_leaves"] = leaves
	result.stats = {
		"facades": layout.facades.size(),
		"windows": layout.count(Kind.WINDOW) + layout.count(Kind.ATTIC),
		"doors": layout.count(Kind.DOOR),
		"floors": layout.floors,
		"triangles": mb.triangle_count,
		"roof": _roof_name(layout.roof),
		"notes": ", ".join(layout.notes),
		"timings_us": {"walls": t_walls, "total": Time.get_ticks_usec() - t0},
	}
	return result


## Portes (milieu du seuil au sol, normale vers l'extérieur, largeur) et contour,
## pour le décor : chemins qui rejoignent les portes, galets au pied des murs.
static func anchors(layout: BastideBuildingLayout) -> Dictionary:
	var doors: Array = []
	var windows: Array = []
	var facades: Array = []
	for f: BastideBuildingLayout.Facade in layout.facades:
		facades.append({"a": f.point(0.0, layout.base_y), "b": f.point(f.length, layout.base_y), "out": f.out3(),
			"gable": f.gable, "posts": f.posts})
		for o in f.openings:
			if o.kind == Kind.DOOR and o.floor == 0:
				doors.append({"pos": f.point((o.u0 + o.u1) * 0.5, layout.base_y), "out": f.out3(), "width": o.u1 - o.u0})
			elif o.kind == Kind.WINDOW:
				# Fenêtres, pour l'habillage (jardinières, lierre qui les contourne).
				windows.append({"pos": f.point((o.u0 + o.u1) * 0.5, (float(o.y0) + float(o.y1)) * 0.5), "out": f.out3(),
					"width": o.u1 - o.u0, "height": float(o.y1) - float(o.y0), "floor": int(o.get("floor", 0))})
	return {"doors": doors, "windows": windows, "facades": facades, "eave_y": layout.eave_y,
		"floors": layout.floors, "floor_height": layout.floor_height, "footprint": layout.footprint,
		"base_y": layout.base_y, "pent": layout.pent_roof, "timber": layout.timber,
		"overhang": layout.roof.overhang if layout.roof else 0.5, "smoke": smoke_points(layout.roof)}


## Où la fumée du foyer s'échappe : le haut de la cheminée, sinon les bouts du plus
## haut faîtage (les évents sous les petits pignons d'un irimoya).
static func smoke_points(roof: BastideRoofLayout) -> PackedVector3Array:
	var out := PackedVector3Array()
	if roof == null:
		return out
	if not roof.chimney.is_empty():
		var p: Vector2 = roof.chimney.pos
		out.append(Vector3(p.x, float(roof.chimney.y1) + 0.15, p.y))
		return out
	var best := -INF
	var top: Dictionary = {}
	for arc: Dictionary in roof.arcs:
		var a: Vector3 = arc["a"]
		var b: Vector3 = arc["b"]
		if int(arc["kind"]) == BastideRoofLayout.ArcKind.RIDGE and absf(a.y - b.y) < 0.05 and a.y > best and a.distance_to(b) > 0.5:
			best = a.y
			top = arc
	if not top.is_empty():
		var a: Vector3 = top["a"]
		var b: Vector3 = top["b"]
		out.append(a.lerp(b, 0.12) + Vector3(0, 0.1, 0))
	return out


static func _roof_name(roof: BastideRoofLayout) -> String:
	if roof.fallback == "plat":
		return "plat"
	if not roof.gable_panels.is_empty():
		return "irimoya"
	return "pignons" if roof.weights.has(0.0) else "croupes"


# --- Enduit ------------------------------------------------------------------------

## Face extérieure enduite, percée des ouvertures : grille de rectangles entre les
## bords des ouvertures, plus le remplissage autour des arcs et le triangle du pignon.
## Tous les morceaux partagent exactement leurs sommets (aucune fente visible).
static func _plaster(mb: BastideMeshBuilder, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade,
		xs: PackedFloat32Array, ys: PackedFloat32Array, bs: BastideBuildingStyle) -> void:
	var wainscot_top := layout.base_y + bs.wainscot_height if bs.wainscot_height > 0.0 else -INF
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
			if cy < wainscot_top:
				# Bardage bas : planches de bois sombre.
				var wc := bs.wainscot_color
				mb.add_quad(ROLE_WOOD, f.point(x0, y0), f.point(x1, y0), f.point(x1, y1), f.point(x0, y1), hint,
					wc.darkened(0.15), wc.darkened(0.15), wc, wc)
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
static func _grid(layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade, bs: BastideBuildingStyle) -> Array:
	var y_bot := layout.base_y - FOOTING
	var y_top := layout.eave_y + WALL_TOP_SINK
	var xs := PackedFloat32Array([0.0, f.length])
	var ys := PackedFloat32Array([y_bot, y_top, layout.base_y + 1.6])
	if bs.wainscot_height > 0.0:
		ys.append(layout.base_y + bs.wainscot_height)
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
				# Le dessus d'un rang est caché par le rang suivant.
				var hidden_top := BastideMeshBuilder.FACE_TOP if r < rows - 1 else 0
				_facade_block(mb, f, acc, acc + lengths[li], ya, yb, -0.1, d, c, mortar.lerp(c, 0.3), ws.stone_bevel,
					false, ROLE_BODY, hidden_top)
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
		# Faces cachées : dans le mur, contre l'autre bloc de l'angle, sous le bloc suivant.
		# Le dessus n'est caché que si le bloc du dessus est plus long (rangs alternés).
		var not_last := y1 < top - 1e-4
		var top_a := BastideMeshBuilder.FACE_TOP if not_last and not long_side else 0
		var top_b := BastideMeshBuilder.FACE_TOP if not_last and long_side else 0
		var skips := [BastideMeshBuilder.FACE_BACK_23 | BastideMeshBuilder.FACE_SIDE_30 | top_a,
			BastideMeshBuilder.FACE_BACK_23 | BastideMeshBuilder.FACE_SIDE_12 | top_b]
		for qi in 2:
			var quad: Array = [fa, fb][qi]
			var k: Array = []
			for yy in [y, y1]:
				for p: Vector2 in quad:
					k.append(Vector3(p.x, yy, p.y))
			mb.add_block(ROLE_BODY, k, ws.stone_bevel * 0.8, 0.012, c, edge, false, skips[qi])
		y = y1
		row += 1


## Bloc collé à une façade : u0-u1 le long, y0-y1 en hauteur, d0-d1 en profondeur (vers l'extérieur).
static func _facade_block(mb: BastideMeshBuilder, f: BastideBuildingLayout.Facade, u0: float, u1: float,
		y0: float, y1: float, d0: float, d1: float, color: Color, edge: Color, bevel := 0.03, bottom := false,
		role := ROLE_BODY, extra_skip := 0) -> void:
	var k := [
		f.point(u0, y0, d0), f.point(u1, y0, d0), f.point(u1, y0, d1), f.point(u0, y0, d1),
		f.point(u0, y1, d0), f.point(u1, y1, d0), f.point(u1, y1, d1), f.point(u0, y1, d1),
	]
	# La face arrière d'un bloc qui part de l'intérieur du mur est cachée : pas émise.
	var skip := (BastideMeshBuilder.FACE_FRONT_01 if d0 <= 0.0 else 0) | extra_skip
	mb.add_block(role, k, bevel, 0.006, color, edge, bottom, skip)


## Pièce de bois simple (sans biseau) collée à une façade.
static func _wood_block(mb: BastideMeshBuilder, f: BastideBuildingLayout.Facade, u0: float, u1: float,
		y0: float, y1: float, d0: float, d1: float, color: Color, extra_skip := 0, bottom := false) -> void:
	_facade_block(mb, f, u0, u1, y0, y1, d0, d1, color, color, 0.0, bottom, ROLE_WOOD, extra_skip)


# --- Fenêtres -----------------------------------------------------------------------

static func _window(mb: BastideMeshBuilder, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade,
		o: Dictionary, bs: BastideBuildingStyle, ws: BastideWallStyle, real_hole: bool, grid: Array) -> void:
	var u0: float = o.u0
	var u1: float = o.u1
	var y0: float = o.y0
	var y1: float = o.y1
	var depth := WINDOW_DEPTH_GLASS if real_hole else 0.02
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
	_wood_block(mb, f, u0, u0 + fw, y0, y1, d0, d1, wood)
	_wood_block(mb, f, u1 - fw, u1, y0, y1, d0, d1, wood)
	_wood_block(mb, f, u0 + fw, u1 - fw, y1 - fw, y1, d0, d1, wood)
	_wood_block(mb, f, u0 + fw, u1 - fw, y0, y0 + fw, d0, d1, wood)
	var mid := (u0 + u1) * 0.5
	_wood_block(mb, f, mid - 0.022, mid + 0.022, y0 + fw, y1 - fw, d0, d1 - 0.01, wood)
	var ty := lerpf(y0, y1, 0.62)
	_wood_block(mb, f, u0 + fw, u1 - fw, ty - 0.022, ty + 0.022, d0, d1 - 0.01, wood)
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
	for side: float in [-1.0, 1.0]:
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
			_wood_block(mb, f, ba, bb, y0, y1, 0.02, 0.055, c)
		var batten := base.darkened(0.15)
		for yy in [lerpf(y0, y1, 0.18), lerpf(y0, y1, 0.82)]:
			_wood_block(mb, f, a + 0.03, b - 0.03, yy - 0.04, yy + 0.04, 0.05, 0.075, batten)


static func _flower_box(mb: BastideMeshBuilder, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade,
		o: Dictionary, bs: BastideBuildingStyle, key: int) -> void:
	var u0: float = o.u0 - 0.02
	var u1: float = o.u1 + 0.02
	var top: float = o.y0 - 0.11
	var wood := bs.wood_color.lightened(0.08)
	_facade_block(mb, f, u0, u1, top - 0.2, top, 0.1, 0.32, wood, wood.darkened(0.3), 0.012, true, ROLE_WOOD)
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
		o: Dictionary, bs: BastideBuildingStyle, ws: BastideWallStyle, grid: Array, leaves: Variant = null,
		style: BastideStyle = null) -> void:
	var u0: float = o.u0
	var u1: float = o.u1
	var y0: float = o.y0
	var y1: float = o.y1
	var r: float = o.arch
	var depth := DOOR_DEPTH_HINGED
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
	# Fond sombre derrière le vantail : rien ne transparaît par les joints. Porte qui
	# s'ouvre : pas de fond, mais un tympan sous l'arc (l'intérieur est rectangulaire).
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
	if leaves == null:
		for i in range(1, outline.size() - 1):
			mb.add_tri(ROLE_BODY, f.point(outline[0].x, outline[0].y, back), f.point(outline[i].x, outline[i].y, back),
				f.point(outline[i + 1].x, outline[i + 1].y, back), f.out3(), dark, dark, dark)
	elif r > 0.0:
		var tymp := bs.door_color.darkened(0.2)
		for i in pts.size() - 1:
			mb.add_tri(ROLE_WOOD, f.point(cx, y1, back), f.point(pts[i].x, pts[i].y, back), f.point(pts[i + 1].x, pts[i + 1].y, back),
				f.out3(), tymp, tymp, tymp)
	# Vantail à part (il pivote) quand la porte s'ouvre.
	var main := mb
	if leaves != null:
		mb = BastideMeshBuilder.new()
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
			mb.add_tri(ROLE_WOOD, f.point(poly[0].x, poly[0].y, depth), f.point(poly[k].x, poly[k].y, depth),
				f.point(poly[k + 1].x, poly[k + 1].y, depth), f.out3(), c.darkened(0.1), c, c)
		if i > 0:
			var seam := c.darkened(0.45)
			var ta := _line_at(top_line, a) - 0.01
			mb.add_quad(ROLE_WOOD, f.point(a - 0.008, y0, depth + 0.003), f.point(a + 0.008, y0, depth + 0.003),
				f.point(a + 0.008, ta, depth + 0.003), f.point(a - 0.008, ta, depth + 0.003), f.out3(), seam, seam, seam, seam)
	if leaves != null:
		# Dos du vantail, vu de l'intérieur.
		var bk := bs.door_color.darkened(0.15)
		var poly := PackedVector2Array([Vector2(u0, y0), Vector2(u1, y0)])
		for k in range(top_line.size() - 1, -1, -1):
			poly.append(top_line[k])
		for k in range(1, poly.size() - 1):
			mb.add_tri(ROLE_WOOD, f.point(poly[0].x, poly[0].y, depth - 0.04), f.point(poly[k].x, poly[k].y, depth - 0.04),
				f.point(poly[k + 1].x, poly[k + 1].y, depth - 0.04), -f.out3(), bk, bk, bk)
	var iron := Color(0.14, 0.13, 0.13)
	for yy in [y0 + 0.35, y0 + (y1 - y0) * 0.78]:
		_facade_block(mb, f, u0 + 0.06, u1 - 0.06, yy - 0.035, yy + 0.035, depth, depth + 0.025, iron, iron, 0.005)
	_facade_block(mb, f, u1 - 0.26, u1 - 0.2, y0 + 0.95, y0 + 1.05, depth, depth + 0.06, iron, iron, 0.01)
	if leaves != null:
		# Pivot sur le bord gauche ; la porte s'ouvre vers l'intérieur.
		var pivot := f.point(u0, y0, depth - 0.02)
		var inward := -f.out3()
		var d3 := f.dir3()
		var angle := atan2(d3.cross(inward).y, d3.dot(inward)) * 0.92
		(leaves as Array).append({"mesh": _commit_leaf(mb, style), "kind": "hinge", "pivot": pivot, "angle": angle,
			"door": (o.u0 + o.u1) * 0.5, "facade": f.index})
		mb = main
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


# --- Ossature bois --------------------------------------------------------------------

## Morceaux [u0, u1] d'une poutre le long d'une façade, interrompus par les portes.
static func _cut_at_doors(f: BastideBuildingLayout.Facade, span: Vector2, pad: float) -> Array:
	var pieces: Array = [span]
	for o in f.openings:
		if o.kind != Kind.DOOR:
			continue
		var cut := Vector2(o.u0 - pad, o.u1 + pad)
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


## Poteaux d'angle et intermédiaires, lisse basse, poutres d'étage, sablière, et
## lattes du bardage bas.
static func _timber_frame(mb: BastideMeshBuilder, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade,
		bs: BastideBuildingStyle) -> void:
	var wood := bs.timber_color
	var pw := bs.post_width
	var bh := bs.beam_height
	var y_sill := layout.base_y + bs.plinth_height
	var y_eave := layout.eave_y
	var tint := BastideRng.signed_at(layout.seed, "timber", f.index) * 0.04
	wood = wood.lightened(tint) if tint > 0.0 else wood.darkened(-tint)
	# Poteaux d'angle : un sur chaque façade, légèrement décalés pour ne pas se
	# chevaucher face contre face dans l'angle.
	var a0 := 0.05 if f.convex_start else 0.0
	var c1 := 0.03 if f.convex_end else 0.0
	_wood_block(mb, f, -a0, pw, y_sill, y_eave, -0.05, 0.04, wood)
	_wood_block(mb, f, f.length - pw, f.length + c1, y_sill, y_eave, -0.05, 0.045, wood)
	for u in f.posts:
		var c := wood.darkened(BastideRng.randf_at(layout.seed, "post", BastideRng.combine(f.index, int(u * 10.0))) * 0.06)
		_wood_block(mb, f, u - pw * 0.5, u + pw * 0.5, y_sill, y_eave, -0.05, 0.03, c)
	# Poutres horizontales.
	var beam := wood.darkened(0.06)
	var span := Vector2(-0.06 if f.convex_start else 0.0, f.length + (0.06 if f.convex_end else 0.0))
	for piece: Vector2 in _cut_at_doors(f, span, 0.0):
		_wood_block(mb, f, piece.x, piece.y, y_sill, y_sill + bh, -0.05, 0.05, beam)
	for k in range(1, layout.floors):
		var y := layout.base_y + k * layout.floor_height
		_wood_block(mb, f, span.x, span.y, y - bh * 0.5, y + bh * 0.5, -0.05, 0.055, beam)
	_wood_block(mb, f, span.x, span.y, y_eave - bh * 1.2, y_eave + WALL_TOP_SINK, -0.05, 0.06, beam.darkened(0.08))
	# Bardage bas : lattes verticales et lisse haute.
	if bs.wainscot_height > 0.0:
		var top := layout.base_y + bs.wainscot_height
		var batten := bs.wainscot_color.lightened(0.08)
		for piece: Vector2 in _cut_at_doors(f, Vector2(pw, f.length - pw), 0.02):
			var count := maxi(1, roundi((piece.y - piece.x) / 0.32))
			for i in range(1, count):
				var u := lerpf(piece.x, piece.y, float(i) / count)
				var on_post := false
				for p in f.posts:
					on_post = on_post or absf(u - p) < pw * 0.5 + 0.03
				if not on_post:
					mb.add_quad(ROLE_WOOD, f.point(u - 0.018, y_sill + bh, 0.012), f.point(u + 0.018, y_sill + bh, 0.012),
						f.point(u + 0.018, top, 0.012), f.point(u - 0.018, top, 0.012), f.out3(), batten, batten, batten, batten)
			_wood_block(mb, f, piece.x, piece.y, top - 0.03, top + 0.04, -0.05, 0.035, beam)


## Fenêtre à claire-voie : cadre de bois, lattes verticales devant un écran de papier
## quadrillé (shoji). `real_hole` : percée dans le mur (sinon posée sur un pignon).
static func _lattice_window(mb: BastideMeshBuilder, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade,
		o: Dictionary, bs: BastideBuildingStyle, grid: Array, real_hole: bool) -> void:
	var u0: float = o.u0
	var u1: float = o.u1
	var y0: float = o.y0
	var y1: float = o.y1
	var wood := bs.timber_color.lightened(0.06)
	var depth := WINDOW_DEPTH_LATTICE if real_hole else 0.01
	if real_hole:
		_reveals(mb, f, u0, u1, y0, y1, depth, wood.darkened(0.2), grid, true)
	# Papier et son quadrillage.
	var paper := bs.paper_color
	var pd := depth + 0.005
	mb.add_quad(ROLE_PAPER, f.point(u0, y0, pd), f.point(u1, y0, pd), f.point(u1, y1, pd), f.point(u0, y1, pd),
		f.out3(), paper.darkened(0.05), paper.darkened(0.05), paper, paper)
	var kumiko := wood.lightened(0.15)
	var gd := pd + 0.006
	var cols := maxi(2, roundi((u1 - u0) / 0.3))
	var rows := maxi(2, roundi((y1 - y0) / 0.3))
	for i in range(1, cols):
		var u := lerpf(u0, u1, float(i) / cols)
		mb.add_quad(ROLE_WOOD, f.point(u - 0.01, y0, gd), f.point(u + 0.01, y0, gd), f.point(u + 0.01, y1, gd),
			f.point(u - 0.01, y1, gd), f.out3(), kumiko, kumiko, kumiko, kumiko)
	for i in range(1, rows):
		var y := lerpf(y0, y1, float(i) / rows)
		mb.add_quad(ROLE_WOOD, f.point(u0, y - 0.01, gd), f.point(u1, y - 0.01, gd), f.point(u1, y + 0.01, gd),
			f.point(u0, y + 0.01, gd), f.out3(), kumiko, kumiko, kumiko, kumiko)
	# Cadre.
	var fw := 0.07
	var d1 := 0.035
	_wood_block(mb, f, u0 - fw, u0, y0 - fw, y1 + fw, depth, d1, wood)
	_wood_block(mb, f, u1, u1 + fw, y0 - fw, y1 + fw, depth, d1, wood)
	_wood_block(mb, f, u0, u1, y1, y1 + fw, depth, d1, wood)
	_wood_block(mb, f, u0 - fw - 0.04, u1 + fw + 0.04, y0 - fw, y0, depth, d1 + 0.03, wood.darkened(0.08), 0, true)
	# Lattes verticales (le dessus et le dessous touchent le cadre : non émis).
	var bar := wood.darkened(0.1)
	var count := maxi(3, roundi((u1 - u0) / bs.lattice_spacing))
	for i in range(1, count):
		var u := lerpf(u0, u1, float(i) / count)
		_wood_block(mb, f, u - 0.018, u + 0.018, y0, y1, depth + 0.04, 0.02, bar, BastideMeshBuilder.FACE_TOP)


## Porte coulissante : deux vantaux décalés (bas en planches, haut à claire-voie sur
## papier), linteau de bois, pierre de seuil et, selon la seed, un noren.
static func _sliding_door(mb: BastideMeshBuilder, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade,
		o: Dictionary, bs: BastideBuildingStyle, ws: BastideWallStyle, grid: Array, leaves: Variant = null,
		style: BastideStyle = null) -> void:
	var u0: float = o.u0
	var u1: float = o.u1
	var y0: float = o.y0
	var y1: float = o.y1
	var wood := bs.timber_color.lightened(0.08)
	var depth := DOOR_DEPTH_SLIDING
	_reveals(mb, f, u0, u1, y0, y1, depth, wood.darkened(0.25), grid, false)
	_reveal_h(mb, f, _between(grid[0], u0, u1), y1, depth, Vector3.DOWN, wood.darkened(0.3), wood.darkened(0.45))
	# Fond sombre (entrée) ; aucun quand on peut entrer.
	var dark := Color(0.06, 0.05, 0.045)
	if leaves == null:
		mb.add_quad(ROLE_BODY, f.point(u0, y0, depth - 0.03), f.point(u1, y0, depth - 0.03), f.point(u1, y1, depth - 0.03),
			f.point(u0, y1, depth - 0.03), f.out3(), dark, dark, dark, dark)
	# Deux vantaux : le gauche fermé, le droit à moitié ouvert (glissé derrière).
	# Porte qui s'ouvre : les deux fermés, chacun dans son maillage ; ils glissent
	# dans l'épaisseur du mur, de part et d'autre, sans passer derrière une fenêtre.
	var w := (u1 - u0) * 0.5
	var panes := [[u0, u0 + w + 0.03, depth + 0.07], [u0 + w * 1.55, u1, depth + 0.035]]
	if leaves != null:
		panes = [[u0, u0 + w + 0.03, depth + 0.07], [u0 + w - 0.03, u1, depth + 0.035]]
	var room := _pocket_room(layout, f, o)
	var paper := bs.paper_color
	var low := y0 + minf(0.75, (y1 - y0) * 0.38)
	var main := mb
	for li in panes.size():
		var leaf: Array = panes[li]
		if leaves != null:
			mb = BastideMeshBuilder.new()
		var a: float = leaf[0]
		var b: float = leaf[1]
		var d: float = leaf[2]
		var fw := 0.06
		# Planches du bas.
		var plank := bs.door_color
		_wood_block(mb, f, a + fw, b - fw, y0 + fw, low, d - 0.02, d, plank.darkened(0.1))
		for i in range(1, 4):
			var u := lerpf(a + fw, b - fw, float(i) / 4.0)
			mb.add_quad(ROLE_WOOD, f.point(u - 0.006, y0 + fw, d + 0.002), f.point(u + 0.006, y0 + fw, d + 0.002),
				f.point(u + 0.006, low, d + 0.002), f.point(u - 0.006, low, d + 0.002), f.out3(),
				plank.darkened(0.4), plank.darkened(0.4), plank.darkened(0.4), plank.darkened(0.4))
		# Haut : papier et lattes.
		mb.add_quad(ROLE_PAPER, f.point(a + fw, low, d - 0.015), f.point(b - fw, low, d - 0.015),
			f.point(b - fw, y1 - fw, d - 0.015), f.point(a + fw, y1 - fw, d - 0.015), f.out3(), paper.darkened(0.08), paper.darkened(0.08), paper, paper)
		if leaves != null:
			# Vu de dedans aussi (le vantail se voit des deux côtés une fois entré).
			mb.add_quad(ROLE_PAPER, f.point(a + fw, low, d - 0.022), f.point(b - fw, low, d - 0.022),
				f.point(b - fw, y1 - fw, d - 0.022), f.point(a + fw, y1 - fw, d - 0.022), -f.out3(), paper, paper, paper, paper)
		var bars := maxi(3, roundi((b - a - 2.0 * fw) / bs.lattice_spacing))
		for i in range(1, bars):
			var u := lerpf(a + fw, b - fw, float(i) / bars)
			_wood_block(mb, f, u - 0.014, u + 0.014, low, y1 - fw, d - 0.012, d, wood.darkened(0.12), BastideMeshBuilder.FACE_TOP)
		# Cadre du vantail.
		_wood_block(mb, f, a, a + fw, y0, y1, d - 0.025, d + 0.01, wood)
		_wood_block(mb, f, b - fw, b, y0, y1, d - 0.025, d + 0.01, wood)
		_wood_block(mb, f, a + fw, b - fw, y1 - fw, y1, d - 0.025, d + 0.01, wood)
		_wood_block(mb, f, a + fw, b - fw, y0, y0 + fw, d - 0.025, d + 0.01, wood)
		_wood_block(mb, f, a + fw, b - fw, low - 0.025, low + 0.025, d - 0.02, d + 0.008, wood)
		if leaves != null:
			var slide := minf(b - a - 0.12, room[li])
			(leaves as Array).append({"mesh": _commit_leaf(mb, style), "kind": "slide",
				"slide": f.dir3() * (-slide if li == 0 else slide), "door": (o.u0 + o.u1) * 0.5, "facade": f.index})
			mb = main
	# Linteau et montants.
	var beam := bs.timber_color
	_wood_block(mb, f, u0 - 0.14, u1 + 0.14, y1, y1 + 0.16, -0.05, 0.06, beam)
	_wood_block(mb, f, u0 - 0.12, u0, y0, y1, -0.05, 0.05, beam)
	_wood_block(mb, f, u1, u1 + 0.12, y0, y1, -0.05, 0.05, beam)
	# Pierre de seuil.
	var stone := ws.stone_color.darkened(0.05)
	_facade_block(mb, f, u0 + 0.1, u1 - 0.1, y0 - 0.15, y0 + 0.12, 0.05, 0.6, stone, ws.mortar_color.lerp(stone, 0.4),
		0.04, false)
	# Noren : trois pans de tissu suspendus sous le linteau, un peu écartés du mur.
	if layout.noren_color.a > 0.0:
		var cloth := layout.noren_color
		var top := y1 + 0.08
		var drop := minf(0.65, (y1 - y0) * 0.33)
		var dd := 0.12
		_wood_block(mb, f, u0 - 0.05, u1 + 0.05, top - 0.03, top + 0.02, dd - 0.02, dd + 0.02, beam.darkened(0.2))
		var panels := 3
		for i in panels:
			var a := lerpf(u0 - 0.02, u1 + 0.02, float(i) / panels) + 0.012
			var b := lerpf(u0 - 0.02, u1 + 0.02, float(i + 1) / panels) - 0.012
			var sway := BastideRng.signed_at(layout.seed, "noren", BastideRng.combine(f.index, i)) * 0.03
			var c := cloth.darkened(0.08 * i)
			var p0 := f.point(a, top - 0.03, dd)
			var p1 := f.point(b, top - 0.03, dd)
			var p2 := f.point(b, top - drop, dd + 0.03 + sway)
			var p3 := f.point(a, top - drop, dd + 0.03 + sway)
			mb.add_quad(ROLE_BODY, p0, p1, p2, p3, f.out3(), c, c, c.darkened(0.12), c.darkened(0.12))
			mb.add_quad(ROLE_BODY, p0, p1, p2, p3, -f.out3(), c.darkened(0.3), c.darkened(0.3), c.darkened(0.4), c.darkened(0.4))
			# Motif clair au centre du rideau.
			if i == panels / 2:
				var mu := (a + b) * 0.5
				var my := top - drop * 0.5
				var mc := cloth.lerp(Color(0.95, 0.93, 0.86), 0.85)
				var ms := minf(b - a, drop) * 0.22
				mb.add_quad(ROLE_BODY, f.point(mu - ms, my - ms, dd + 0.018 + sway * 0.5), f.point(mu + ms, my - ms, dd + 0.018 + sway * 0.5),
					f.point(mu + ms, my + ms, dd + 0.012 + sway * 0.3), f.point(mu - ms, my + ms, dd + 0.012 + sway * 0.3),
					f.out3(), mc, mc, mc, mc)


## Auvent de tuiles (hisashi) au-dessus de l'étage `level` - 1, tout autour. Sur
## une tour, chaque auvent est un peu moins profond que celui du dessous.
static func _pent_roof(mb: BastideMeshBuilder, col: BastideBuildResult, layout: BastideBuildingLayout,
		style: BastideStyle, with_collision: bool, level := 1) -> void:
	var bs := style.get_building_style()
	var rs := style.get_roof_style()
	var fp := layout.footprint
	var n := fp.size()
	var depth := bs.pent_depth * (1.0 - 0.12 * (level - 1))
	var outer := BastidePolygon.offset(fp, -depth, 3.0)
	if BastidePolygon.self_intersects(outer):
		return
	var tan_p := tan(deg_to_rad(bs.pent_pitch))
	var y_top := layout.base_y + layout.floor_height * level + 0.32
	var y_bot := y_top - depth * tan_p
	var tp := BastideRoofMesher.TileParams.from_style(rs, bs.pent_pitch, y_bot, layout.roof.color)
	var under := rs.underside_color
	var thick := 0.08
	for i in n:
		var j := (i + 1) % n
		var f: BastideBuildingLayout.Facade = layout.facades[i]
		var out := f.out3()
		var poly := PackedVector3Array([
			Vector3(outer[i].x, y_bot, outer[i].y), Vector3(outer[j].x, y_bot, outer[j].y),
			Vector3(fp[j].x, y_top, fp[j].y), Vector3(fp[i].x, y_top, fp[i].y)])
		var nrm := (out * tan_p + Vector3.UP).normalized()
		BastideRoofMesher.tile_polygon(mb, poly, nrm, f.dir3(), -out, tp, layout.seed, 1000 * level + i)
		var low := PackedVector3Array()
		for p in poly:
			low.append(p - Vector3(0.0, thick, 0.0))
		for t in range(1, 3):
			mb.add_tri(ROLE_WOOD, low[0], low[t], low[t + 1], Vector3.DOWN, under, under, under)
		mb.add_quad(ROLE_WOOD, poly[0], poly[1], low[1], low[0], out, under, under, under, under)
		if with_collision:
			for t in range(1, 3):
				col.collision_faces.append(poly[0])
				col.collision_faces.append(poly[t])
				col.collision_faces.append(poly[t + 1])
		# Arêtier (angle saillant) ou noue (angle rentrant) entre deux pans.
		var arc := {"a": Vector3(outer[i].x, y_bot, outer[i].y), "b": Vector3(fp[i].x, y_top, fp[i].y)}
		if BastidePolygon.is_convex_vertex(fp, i):
			BastideRoofMesher.stacked_ridge(mb, arc.a, arc.b, tan_p, rs.ridge_color, 0.12, 0.09, false)
		else:
			BastideRoofMesher.valley(mb, arc.a, arc.b, tan_p, rs.ridge_color.darkened(0.1), 0.0, false)


# --- Collisions --------------------------------------------------------------------------

static func _facade_collision(col: BastideBuildResult, layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade,
		open_doors := false) -> void:
	var th := layout.wall_thickness
	var y0 := layout.base_y - FOOTING
	var y1 := layout.eave_y
	var pieces: Array = [Vector2(0.0, f.length)]
	if open_doors:
		pieces = _cut_at_doors(f, pieces[0], 0.0)
		for o in f.openings:
			if o.kind == Kind.DOOR:
				# Linteau au-dessus du passage.
				var top: float = o.y1
				col.add_box([
					f.point(o.u0, top), f.point(o.u1, top), f.point(o.u1, top, -th), f.point(o.u0, top, -th),
					f.point(o.u0, y1), f.point(o.u1, y1), f.point(o.u1, y1, -th), f.point(o.u0, y1, -th)])
	for p: Vector2 in pieces:
		col.add_box([
			f.point(p.x, y0), f.point(p.y, y0), f.point(p.y, y0, -th), f.point(p.x, y0, -th),
			f.point(p.x, y1), f.point(p.y, y1), f.point(p.y, y1, -th), f.point(p.x, y1, -th),
		])
	if f.gable:
		for i in f.profile.size() - 1:
			var p := f.profile[i]
			var q := f.profile[i + 1]
			for tri in [[Vector2(p.x, y1), Vector2(q.x, y1), q], [Vector2(p.x, y1), q, p]]:
				for v: Vector2 in tri:
					col.collision_faces.append(f.point(v.x, v.y))


## Place pour ranger chaque vantail dans le mur, à gauche et à droite de la porte :
## jusqu'à la fenêtre voisine du rez-de-chaussée ou jusqu'à l'angle intérieur.
static func _pocket_room(layout: BastideBuildingLayout, f: BastideBuildingLayout.Facade, door: Dictionary) -> Array:
	var left: float = door.u0 - layout.wall_thickness - 0.1
	var right: float = f.length - layout.wall_thickness - 0.1 - door.u1
	for o in f.openings:
		if o == door or o.floor != 0 or o.kind == Kind.ATTIC:
			continue
		if o.u1 <= door.u0:
			left = minf(left, door.u0 - o.u1 - 0.18)
		elif o.u0 >= door.u1:
			right = minf(right, o.u0 - door.u1 - 0.18)
	return [maxf(left, 0.0), maxf(right, 0.0)]


static func _commit_leaf(mb: BastideMeshBuilder, style: BastideStyle) -> ArrayMesh:
	return mb.commit({
		ROLE_BODY: style.get_material(),
		ROLE_WOOD: style.get_wood_material(),
		ROLE_PAPER: style.get_paper_material(),
	})
