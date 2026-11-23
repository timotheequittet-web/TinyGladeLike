@tool
class_name BastideRoofMesher
extends RefCounted
## Backend procédural des toits : BastideRoofLayout → triangles.
##
## Chaque pan est découpé en rangs parallèles à l'égout. Deux sortes de tuiles :
## - plates (FLAT) : chaque rang est découpé en tuiles décalées d'un rang à l'autre,
##   le bas du rang est soulevé pour faire le ressaut (un seul ressaut par rang) ;
## - rondes (ROUND) : des côtes en relief descendent la pente, séparées par des
##   canaux ; les rangs ne servent qu'à suivre la courbure des bords relevés.
## S'y ajoutent le dessous du débord, les chevrons apparents, les planches d'égout et
## de rive, les faîtages (tuiles faîtières ou faîtage maçonné à épis), les petits
## pignons des toits irimoya et la cheminée.
##
## Bords relevés : tout le toit est construit plan, puis les sommets du débord sont
## soulevés par une fonction de la seule position (warp) : les pans restent jointifs.

const ArcKind := BastideRoofLayout.ArcKind
const ROLE_ROOF := &"roof"
const ROLE_BODY := &"body"
const ROLE_WOOD := &"wood"
## Longueur des morceaux quand le toit est déformé (bords relevés).
const WARP_STEP := 0.5
## Côtes des tuiles rondes, en fraction de la largeur d'une tuile : demi-largeur,
## hauteur, et part plate du dessus.
const RIB_HALF := 0.25
const RIB_HEIGHT := 0.2
const RIB_TOP := 0.4


## Paramètres d'un pan de tuiles, partagés par les toits et les auvents.
class TileParams:
	var kind := BastideRoofStyle.TileKind.FLAT
	var row_dh := 0.3       # hauteur verticale d'un rang
	var tile_width := 0.4
	var tt := 0.05          # ressaut (tuiles plates)
	var variance := 0.07
	var base_y := 0.0       # altitude de l'égout (premier rang)
	var color := Color.WHITE
	var warped := false     # découper plus finement pour suivre une déformation

	static func from_style(rs: BastideRoofStyle, pitch_deg: float, base_y: float, color: Color) -> TileParams:
		var tp := TileParams.new()
		tp.kind = rs.tile_kind
		tp.row_dh = rs.tile_row * sin(deg_to_rad(pitch_deg))
		tp.tile_width = rs.tile_width
		tp.tt = rs.tile_thickness if rs.tile_kind == BastideRoofStyle.TileKind.FLAT else 0.0
		tp.variance = rs.tile_variance
		tp.base_y = base_y
		tp.color = color
		return tp


static func build_into(mb: BastideMeshBuilder, col: BastideBuildResult, roof: BastideRoofLayout,
		style: BastideStyle, seed: int, with_collision: bool) -> void:
	if roof == null or roof.is_empty():
		return
	var rs := style.get_roof_style()
	var ws := style.get_wall_style()
	var flat := roof.fallback == "plat"
	var warped := rs.eave_curve > 0.0 and not flat and roof.overhang > 0.05
	var mark := mb.mark()
	var tp := TileParams.from_style(rs, roof.pitch_deg, roof.base_y, roof.color)
	tp.warped = warped
	var under := rs.underside_color

	for e in roof.faces.size():
		var face: Dictionary = roof.faces[e]
		if face.weight <= 0.0:
			continue
		var nrm: Vector3 = face.normal
		var dir: Vector3 = face.dir
		var up_dir: Vector3 = face.up_dir
		for poly: PackedVector3Array in face.polys:
			# Dessous (visible sous le débord).
			var low := PackedVector3Array()
			for p in poly:
				low.append(p - Vector3(0.0, roof.thickness, 0.0))
			if warped:
				for piece in _grid_pieces(low, roof.base_y - roof.thickness, tp.row_dh * 2.0, dir, 1.0):
					_polygon(mb, ROLE_WOOD, piece, Vector3.DOWN, under)
			else:
				_polygon(mb, ROLE_WOOD, low, Vector3.DOWN, under)
			if with_collision:
				_collide_polygon(col, poly)
			if flat:
				_polygon(mb, ROLE_ROOF, poly, Vector3.UP, roof.color)
				continue
			tile_polygon(mb, poly, nrm, dir, up_dir, tp, seed, e)

	# --- Égouts : planche le long des côtés en pente, chevrons apparents ---
	var n := roof.outline.size()
	if not flat:
		for e in n:
			if roof.weights[e] <= 0.0:
				continue
			var a := roof.outline[e]
			var b := roof.outline[(e + 1) % n]
			var out := -(roof.faces[e].up_dir as Vector3)
			var y := roof.base_y
			var steps := maxi(1, ceili(a.distance_to(b) / WARP_STEP)) if warped else 1
			for i in steps:
				var p := a.lerp(b, float(i) / steps)
				var q := a.lerp(b, float(i + 1) / steps)
				mb.add_quad(ROLE_WOOD, Vector3(p.x, y + tp.tt, p.y), Vector3(q.x, y + tp.tt, q.y),
					Vector3(q.x, y - roof.thickness, q.y), Vector3(p.x, y - roof.thickness, p.y),
					out, under, under, under, under)
			if rs.rafters:
				_rafters(mb, roof, e, under.darkened(0.12))
	else:
		_flat_edges(mb, roof, ws)

	# --- Petits pignons (irimoya) ---
	for panel in roof.gable_panels:
		_gable_panel(mb, col, roof, panel, rs, with_collision)

	# --- Rives, faîtages, arêtiers, noues ---
	var stacked := rs.ridge_kind == BastideRoofStyle.RidgeKind.STACKED
	var cap_color := rs.ridge_color if stacked else roof.color.darkened(0.18)
	for arc in roof.arcs:
		match arc.kind:
			ArcKind.VERGE:
				_verge(mb, roof, arc, tp.tt, rs.gable_color.darkened(0.15) if stacked else under, stacked)
			ArcKind.RIDGE:
				if stacked:
					stacked_ridge(mb, arc.a, arc.b, roof.tan_pitch, cap_color, rs.ridge_height, 0.2, warped)
				elif rs.ridge_caps:
					_ridge_caps(mb, roof, arc, cap_color, seed)
			ArcKind.HIP:
				if stacked:
					stacked_ridge(mb, arc.a, arc.b, roof.tan_pitch, cap_color, rs.ridge_height * 0.5, 0.13, warped)
				elif rs.ridge_caps:
					_ridge_caps(mb, roof, arc, cap_color, seed)
			ArcKind.VALLEY:
				if rs.ridge_caps or stacked:
					valley(mb, arc.a, arc.b, roof.tan_pitch, cap_color.darkened(0.1), tp.tt, warped)
	if stacked:
		_ridge_ends(mb, roof, cap_color, rs.ridge_height)

	# --- Cheminée ---
	if not roof.chimney.is_empty():
		_chimney(mb, col, roof, ws, seed, with_collision)

	if warped:
		var lift := _eave_lift(roof, rs.eave_curve, rs.corner_lift)
		mb.warp_since(mark, lift)


# --- Tuiles ---------------------------------------------------------------------------

## Couvre un polygone plan convexe de tuiles. `key` distingue les pans (couleurs).
## Utilisé pour les toits et pour les auvents des façades.
static func tile_polygon(mb: BastideMeshBuilder, poly: PackedVector3Array, nrm: Vector3, dir: Vector3,
		up_dir: Vector3, tp: TileParams, seed: int, key: int) -> void:
	var ymin := INF
	var ymax := -INF
	for p in poly:
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
	var row_dh := tp.row_dh
	var k0 := floori((ymin - tp.base_y) / row_dh + 1e-4)
	var k1 := ceili((ymax - tp.base_y) / row_dh - 1e-4)
	var down := -up_dir
	for k in range(k0, k1):
		var lo := tp.base_y + k * row_dh
		var hi := lo + row_dh
		var row := _clip(poly, Vector3.UP, lo, hi)
		if row.size() < 3:
			continue
		var rkey := BastideRng.combine(key, k)
		if tp.tile_width <= 0.0:
			_flat_tile(mb, row, tp, nrm, lo, BastideRng.randf_at(seed, "tile", rkey), true, down)
			continue
		var smin := INF
		var smax := -INF
		for p in row:
			var s := p.dot(dir)
			smin = minf(smin, s)
			smax = maxf(smax, s)
		var w := tp.tile_width
		if tp.kind == BastideRoofStyle.TileKind.ROUND:
			_round_row(mb, row, tp, nrm, dir, down, lo, smin, smax, seed, rkey, k == 0)
			continue
		var shift := w * 0.5 * float(posmod(k, 2))
		var j0 := floori((smin - shift) / w)
		var j1 := ceili((smax - shift) / w)
		for j in range(j0, j1):
			var s0 := shift + j * w
			var tile := _clip(row, dir, s0, s0 + w)
			if tile.size() >= 3:
				var tint := BastideRng.signed_at(seed, "tile", BastideRng.combine(rkey, j))
				_flat_tile(mb, tile, tp, nrm, lo, tint, tp.warped, down)
		# Un seul ressaut pour tout le rang (les tuiles d'un rang sont coplanaires).
		if not tp.warped and tp.tt > 0.0:
			_riser(mb, row, tp, nrm, lo, down, tp.color.darkened(0.35))


## Tuile plate : polygone soulevé vers le bas du rang, et son ressaut si demandé.
static func _flat_tile(mb: BastideMeshBuilder, poly: PackedVector3Array, tp: TileParams, nrm: Vector3,
		lo: float, tint_unit: float, with_riser: bool, down: Vector3) -> void:
	var tint := tint_unit * tp.variance
	var c := tp.color.lightened(tint) if tint > 0.0 else tp.color.darkened(-tint)
	var lifted := PackedVector3Array()
	var colors := PackedColorArray()
	for p in poly:
		var f := clampf((p.y - lo) / tp.row_dh, 0.0, 1.0)
		lifted.append(p + nrm * tp.tt * (1.0 - f))
		colors.append(c.darkened(0.12 * (1.0 - f)))
	for i in range(1, lifted.size() - 1):
		mb.add_tri(ROLE_ROOF, lifted[0], lifted[i], lifted[i + 1], nrm, colors[0], colors[i], colors[i + 1])
	if with_riser and tp.tt > 0.0:
		_riser(mb, poly, tp, nrm, lo, down, c.darkened(0.35))


## Ressaut : bande verticale sous le bord bas d'un rang.
static func _riser(mb: BastideMeshBuilder, poly: PackedVector3Array, tp: TileParams, nrm: Vector3, lo: float,
		down: Vector3, edge: Color) -> void:
	var m := poly.size()
	var top := tp.color
	for i in m:
		var p := poly[i]
		var q := poly[(i + 1) % m]
		if absf(p.y - lo) < 1e-4 and absf(q.y - lo) < 1e-4:
			mb.add_quad(ROLE_ROOF, p, q, q + nrm * tp.tt, p + nrm * tp.tt, down, edge, edge, top, top)


## Rang de tuiles rondes : côtes en relief (profil à trois facettes, dessus plat)
## et canaux entre elles.
static func _round_row(mb: BastideMeshBuilder, row: PackedVector3Array, tp: TileParams, nrm: Vector3,
		dir: Vector3, down: Vector3, lo: float, smin: float, smax: float, seed: int, rkey: int, eave_row: bool) -> void:
	var w := tp.tile_width
	var rw := w * RIB_HALF
	var h := w * RIB_HEIGHT
	var j0 := floori((smin + rw) / w)
	var j1 := ceili((smax + rw) / w)
	var channel := tp.color.darkened(0.22)
	var knots := [-rw, -rw * RIB_TOP, rw * RIB_TOP, rw]
	for j in range(j0, j1 + 1):
		var s0 := j * w
		var tint := BastideRng.signed_at(seed, "tile", BastideRng.combine(rkey, j)) * tp.variance
		var c := tp.color.lightened(tint) if tint > 0.0 else tp.color.darkened(-tint)
		# Canal entre cette côte et la suivante.
		var ch := _clip(row, dir, s0 + rw, s0 + w - rw)
		if ch.size() >= 3:
			_shaded_polygon(mb, ch, nrm, lo, tp.row_dh, channel)
		# Côte : trois facettes.
		var bottom: Array = []
		for part in 3:
			var piece := _clip(row, dir, s0 + knots[part], s0 + knots[part + 1])
			if piece.size() < 3:
				continue
			var lifted := PackedVector3Array()
			var colors := PackedColorArray()
			var shade := 0.12 if part != 1 else 0.0
			for p in piece:
				var u := rib_profile(absf(p.dot(dir) - s0), rw)
				lifted.append(p + nrm * h * u)
				var f := clampf((p.y - lo) / tp.row_dh, 0.0, 1.0)
				colors.append(c.darkened(0.1 * (1.0 - f) + shade))
				if eave_row and absf(p.y - tp.base_y) < 1e-4:
					bottom.append(p + nrm * h * u)
			for i in range(1, lifted.size() - 1):
				mb.add_tri(ROLE_ROOF, lifted[0], lifted[i], lifted[i + 1], nrm, colors[0], colors[i], colors[i + 1])
		# Bout de côte à l'égout : petit fronton qui ferme le relief.
		if bottom.size() >= 3:
			bottom.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.dot(dir) < b.dot(dir))
			var base_l: Vector3 = bottom[0]
			var cap := c.lightened(0.1)
			for i in range(1, bottom.size() - 1):
				mb.add_tri(ROLE_ROOF, base_l, bottom[i], bottom[i + 1], down, cap, cap, cap)


## Profil d'une côte de tuile ronde : 1 sur le dessus plat, 0 au bord.
static func rib_profile(d: float, rw: float) -> float:
	if d >= rw:
		return 0.0
	if d <= rw * RIB_TOP:
		return 1.0
	return (rw - d) / (rw * (1.0 - RIB_TOP))


## Polygone plan assombri vers le bas du rang.
static func _shaded_polygon(mb: BastideMeshBuilder, poly: PackedVector3Array, nrm: Vector3, lo: float,
		row_dh: float, color: Color) -> void:
	var colors := PackedColorArray()
	for p in poly:
		colors.append(color.darkened(0.1 * (1.0 - clampf((p.y - lo) / row_dh, 0.0, 1.0))))
	for i in range(1, poly.size() - 1):
		mb.add_tri(ROLE_ROOF, poly[0], poly[i], poly[i + 1], nrm, colors[0], colors[i], colors[i + 1])


# --- Bords relevés ----------------------------------------------------------------------

## Fonction de déformation : soulève le débord (au-delà de l'aplomb des murs) selon
## une courbe douce, davantage près des angles saillants.
static func _eave_lift(roof: BastideRoofLayout, curve: float, corner_lift: float) -> Callable:
	var outline := roof.outline
	var reach := maxf(roof.overhang, 0.3)
	var corners := PackedVector2Array()
	for i in outline.size():
		if BastidePolygon.is_convex_vertex(outline, i):
			corners.append(outline[i])
	var corner_r := reach * 3.5
	var top := roof.base_y + reach * roof.tan_pitch + 0.5
	return func(p: Vector3) -> Vector3:
		if p.y > top:
			return p
		var q := Vector2(p.x, p.z)
		var dist := INF
		for i in outline.size():
			var a := outline[i]
			var b := outline[(i + 1) % outline.size()]
			dist = minf(dist, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
		var t := 1.0 - dist / reach
		if t <= 0.0:
			return p
		var boost := 0.0
		for c in corners:
			var k := 1.0 - q.distance_to(c) / corner_r
			if k > boost:
				boost = k
		return p + Vector3(0.0, curve * t * t * (1.0 + corner_lift * boost * boost), 0.0)


## Découpe un polygone convexe en morceaux (rangs de hauteur `dh` à partir de `base`,
## colonnes de largeur `cw` le long de `dir`), pour qu'il suive une déformation.
static func _grid_pieces(poly: PackedVector3Array, base: float, dh: float, dir: Vector3, cw: float) -> Array:
	var out: Array = []
	var ymin := INF
	var ymax := -INF
	var smin := INF
	var smax := -INF
	for p in poly:
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
		smin = minf(smin, p.dot(dir))
		smax = maxf(smax, p.dot(dir))
	for k in range(floori((ymin - base) / dh + 1e-4), ceili((ymax - base) / dh - 1e-4)):
		var row := _clip(poly, Vector3.UP, base + k * dh, base + (k + 1) * dh)
		if row.size() < 3:
			continue
		for j in range(floori(smin / cw), ceili(smax / cw)):
			var piece := _clip(row, dir, j * cw, (j + 1) * cw)
			if piece.size() >= 3:
				out.append(piece)
	return out


# --- Égouts, rives, pignons ---------------------------------------------------------------

## Chevrons apparents sous le débord d'un côté, de l'égout jusqu'à l'aplomb du mur.
static func _rafters(mb: BastideMeshBuilder, roof: BastideRoofLayout, e: int, color: Color) -> void:
	var n := roof.outline.size()
	var a := roof.outline[e]
	var b := roof.outline[(e + 1) % n]
	var length := a.distance_to(b)
	var face: Dictionary = roof.faces[e]
	var dir2 := (b - a) / maxf(length, 1e-6)
	var inward := Vector2(face.up_dir.x, face.up_dir.z)
	var reach := roof.overhang + 0.05
	var spacing := 0.42
	var margin := roof.overhang * 1.1 + 0.1
	if length - 2.0 * margin < spacing:
		return
	var count := maxi(2, roundi((length - 2.0 * margin) / spacing) + 1)
	var w := 0.035
	var hgt := 0.09
	var y_under := roof.base_y - roof.thickness
	for i in count:
		var s := lerpf(margin, length - margin, float(i) / (count - 1))
		var c := a + dir2 * s
		var k: Array = []
		for yy in [-hgt, 0.0]:
			for q: Vector2 in [c - dir2 * w, c + dir2 * w, c + dir2 * w + inward * reach, c - dir2 * w + inward * reach]:
				var dist := (q - c).dot(inward)
				k.append(Vector3(q.x, y_under + dist * roof.tan_pitch + yy - 0.005, q.y))
		# Dessus collé sous le toit, bout intérieur dans le mur : non émis.
		mb.add_block(ROLE_WOOD, k, 0.0, 0.0, color, color, true,
			BastideMeshBuilder.FACE_TOP | BastideMeshBuilder.FACE_BACK_23)


## Planche de rive le long d'un pignon.
static func _verge(mb: BastideMeshBuilder, roof: BastideRoofLayout, arc: Dictionary, tt: float, color: Color,
		big: bool) -> void:
	var a: Vector3 = arc.a
	var b: Vector3 = arc.b
	var gable_face: int = arc.get("gable", -1)
	if gable_face < 0:
		return
	var out := -(roof.faces[gable_face].up_dir as Vector3)
	var w := 0.1 if big else 0.06
	var top := tt + (0.12 if big else 0.03)
	var bot := -roof.thickness - (0.2 if big else 0.02)
	var k := [
		a + Vector3(0, bot, 0), b + Vector3(0, bot, 0), b + Vector3(0, bot, 0) + out * w, a + Vector3(0, bot, 0) + out * w,
		a + Vector3(0, top, 0), b + Vector3(0, top, 0), b + Vector3(0, top, 0) + out * w, a + Vector3(0, top, 0) + out * w,
	]
	mb.add_block(ROLE_WOOD, k, 0.012, 0.0, color, color.darkened(0.2), true)


## Petit pignon d'un toit irimoya : panneau de bois à lattes verticales, sur une poutre.
static func _gable_panel(mb: BastideMeshBuilder, col: BastideBuildResult, roof: BastideRoofLayout,
		panel: Dictionary, rs: BastideRoofStyle, with_collision: bool) -> void:
	var out: Vector3 = panel.out
	var along := Vector3(-out.z, 0.0, out.x)
	var color := rs.gable_color
	var batten := color.darkened(0.25)
	for poly: PackedVector3Array in panel.polys:
		if poly.size() < 3:
			continue
		_polygon(mb, ROLE_WOOD, poly, out, color)
		if with_collision:
			_collide_polygon(col, poly)
		var smin := INF
		var smax := -INF
		var ybase := INF
		for p in poly:
			smin = minf(smin, p.dot(along))
			smax = maxf(smax, p.dot(along))
			ybase = minf(ybase, p.y)
		# Lattes verticales (claire-voie du pignon).
		var count := maxi(2, roundi((smax - smin) / 0.2))
		for i in range(1, count):
			var s := lerpf(smin, smax, float(i) / count)
			var strip := _clip(poly, along, s - 0.022, s + 0.022)
			if strip.size() < 3:
				continue
			var front := PackedVector3Array()
			for p in strip:
				front.append(p + out * 0.025)
			_polygon(mb, ROLE_WOOD, front, out, batten)
		# Poutre au pied du pignon.
		var a := poly[0]
		var b := poly[0]
		for p in poly:
			if p.dot(along) < a.dot(along):
				a = p
			if p.dot(along) > b.dot(along):
				b = p
		a.y = ybase
		b.y = ybase
		var k := [
			a - out * 0.05, b - out * 0.05, b + out * 0.06, a + out * 0.06,
			a - out * 0.05 + Vector3(0, 0.16, 0), b - out * 0.05 + Vector3(0, 0.16, 0),
			b + out * 0.06 + Vector3(0, 0.16, 0), a + out * 0.06 + Vector3(0, 0.16, 0),
		]
		mb.add_block(ROLE_WOOD, k, 0.0, 0.0, color.darkened(0.1), color, true, BastideMeshBuilder.FACE_FRONT_01)


# --- Faîtages -----------------------------------------------------------------------------

## Tuiles faîtières : petits chevrons posés en file le long de l'arc.
static func _ridge_caps(mb: BastideMeshBuilder, roof: BastideRoofLayout, arc: Dictionary, color: Color, seed: int) -> void:
	var a: Vector3 = arc.a
	var b: Vector3 = arc.b
	var flat_dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if flat_dir.length_squared() < 1e-6:
		return
	flat_dir = flat_dir.normalized()
	var side := Vector3(-flat_dir.z, 0.0, flat_dir.x)
	var length := a.distance_to(b)
	var count := maxi(1, roundi(length / 0.48))
	var w := 0.17
	var lift := 0.11
	var drop := w * roof.tan_pitch + 0.04
	var along := (b - a) / length
	for i in count:
		var p0 := a.lerp(b, float(i) / count) - along * 0.02
		var p1 := a.lerp(b, float(i + 1) / count) + along * 0.02
		var tint := BastideRng.signed_at(seed, "ridge", BastideRng.combine(int(a.x * 13.0 + a.z * 7.0), i)) * 0.05
		var c := color.lightened(tint) if tint > 0.0 else color.darkened(-tint)
		var t0 := p0 + Vector3.UP * lift
		var t1 := p1 + Vector3.UP * lift
		var l0 := p0 + side * w - Vector3.UP * drop
		var l1 := p1 + side * w - Vector3.UP * drop
		var r0 := p0 - side * w - Vector3.UP * drop
		var r1 := p1 - side * w - Vector3.UP * drop
		var dark := c.darkened(0.25)
		mb.add_quad(ROLE_ROOF, l0, l1, t1, t0, side + Vector3.UP, dark, dark, c, c)
		mb.add_quad(ROLE_ROOF, r0, r1, t1, t0, -side + Vector3.UP, dark, dark, c, c)
		mb.add_tri(ROLE_ROOF, l0, t0, r0, -along, dark, c, dark)
		mb.add_tri(ROLE_ROOF, l1, t1, r1, along, dark, c, dark)


## Faîtage maçonné : boudin haut et droit le long de l'arc, avec une bande claire
## en haut (rang de tuiles couvre-joint).
static func stacked_ridge(mb: BastideMeshBuilder, a: Vector3, b: Vector3, tan_pitch: float, color: Color,
		height: float, half_w: float, warped: bool) -> void:
	var flat_dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if flat_dir.length_squared() < 1e-6:
		return
	flat_dir = flat_dir.normalized()
	var side := Vector3(-flat_dir.z, 0.0, flat_dir.x)
	var drop := half_w * tan_pitch + 0.06
	var along := (b - a).normalized()
	var steps := maxi(1, ceili(a.distance_to(b) / WARP_STEP)) if warped else 1
	var light := color.lightened(0.12)
	var dark := color.darkened(0.2)
	var a_ext := a - along * half_w * 0.6
	var b_ext := b + along * half_w * 0.6
	for i in steps:
		var p0 := a_ext.lerp(b_ext, float(i) / steps)
		var p1 := a_ext.lerp(b_ext, float(i + 1) / steps)
		var l0 := p0 + side * half_w - Vector3.UP * drop
		var l1 := p1 + side * half_w - Vector3.UP * drop
		var r0 := p0 - side * half_w - Vector3.UP * drop
		var r1 := p1 - side * half_w - Vector3.UP * drop
		var lt0 := p0 + side * half_w * 0.9 + Vector3.UP * height
		var lt1 := p1 + side * half_w * 0.9 + Vector3.UP * height
		var rt0 := p0 - side * half_w * 0.9 + Vector3.UP * height
		var rt1 := p1 - side * half_w * 0.9 + Vector3.UP * height
		var ct0 := p0 + Vector3.UP * (height + half_w * 0.45)
		var ct1 := p1 + Vector3.UP * (height + half_w * 0.45)
		mb.add_quad(ROLE_ROOF, l0, l1, lt1, lt0, side, dark, dark, color, color)
		mb.add_quad(ROLE_ROOF, r0, r1, rt1, rt0, -side, dark, dark, color, color)
		mb.add_quad(ROLE_ROOF, lt0, lt1, ct1, ct0, side + Vector3.UP, light, light, light, light)
		mb.add_quad(ROLE_ROOF, rt0, rt1, ct1, ct0, -side + Vector3.UP, light, light, light, light)
		if i == 0 or i == steps - 1:
			var cap_at := 0 if i == 0 else 1
			var hint := -along if cap_at == 0 else along
			var ring := [l0, lt0, ct0, rt0, r0] if cap_at == 0 else [l1, lt1, ct1, rt1, r1]
			for k in range(1, 4):
				mb.add_tri(ROLE_ROOF, ring[0], ring[k], ring[k + 1], hint, dark, color, color)


## Épis (onigawara) aux bouts des faîtages horizontaux : au sommet d'un pignon, ou
## là où le faîtage rejoint deux arêtiers. Pas à la jonction de deux ailes (noues).
static func _ridge_ends(mb: BastideMeshBuilder, roof: BastideRoofLayout, color: Color, height: float) -> void:
	var ends := {}
	var dirs := {}
	var touch := {}  # clé -> { kind: nombre d'arcs }
	var key_of := func(p: Vector3) -> Vector3i:
		return Vector3i(roundi(p.x * 100.0), roundi(p.y * 100.0), roundi(p.z * 100.0))
	for arc in roof.arcs:
		for k in 2:
			var p: Vector3 = arc.a if k == 0 else arc.b
			var key: Vector3i = key_of.call(p)
			if not touch.has(key):
				touch[key] = {}
			touch[key][arc.kind] = int(touch[key].get(arc.kind, 0)) + 1
			if arc.kind == ArcKind.RIDGE:
				var q: Vector3 = arc.b if k == 0 else arc.a
				ends[key] = int(ends.get(key, 0)) + 1
				dirs[key] = [p, (p - q).normalized()]
	for key in ends:
		if ends[key] != 1:
			continue  # bout partagé par deux faîtages : pas d'épi
		var t: Dictionary = touch[key]
		if not t.has(ArcKind.VERGE) and (int(t.get(ArcKind.HIP, 0)) < 2 or t.has(ArcKind.VALLEY)):
			continue
		var p: Vector3 = dirs[key][0]
		var fwd: Vector3 = dirs[key][1]
		var side := Vector3(-fwd.z, 0.0, fwd.x)
		var base := p + fwd * 0.12
		var hw := 0.26
		var top_hw := 0.3
		var th := 0.08
		var h := height + 0.18
		var y0 := -0.25
		var k := [
			base - fwd * th - side * hw + Vector3(0, y0, 0), base + fwd * th - side * hw + Vector3(0, y0, 0),
			base + fwd * th + side * hw + Vector3(0, y0, 0), base - fwd * th + side * hw + Vector3(0, y0, 0),
			base - fwd * th - side * top_hw + Vector3(0, h, 0), base + fwd * th - side * top_hw + Vector3(0, h, 0),
			base + fwd * th + side * top_hw + Vector3(0, h, 0), base - fwd * th + side * top_hw + Vector3(0, h, 0),
		]
		mb.add_block(ROLE_ROOF, k, 0.03, 0.01, color.darkened(0.05), color.darkened(0.3), true)


## Noue : gouttière en V couchée dans le creux, qui cache la jonction des deux pans.
static func valley(mb: BastideMeshBuilder, a: Vector3, b: Vector3, tan_pitch: float, color: Color, tt: float,
		warped: bool) -> void:
	var flat_dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if flat_dir.length_squared() < 1e-6:
		return
	flat_dir = flat_dir.normalized()
	var side := Vector3(-flat_dir.z, 0.0, flat_dir.x)
	var w := 0.2
	var mid := Vector3.UP * (tt + 0.02)
	var rise := Vector3.UP * (w * tan_pitch * 0.6 + tt)
	var light := color.lightened(0.08)
	var steps := maxi(1, ceili(a.distance_to(b) / WARP_STEP)) if warped else 1
	for i in steps:
		var p := a.lerp(b, float(i) / steps)
		var q := a.lerp(b, float(i + 1) / steps)
		mb.add_quad(ROLE_ROOF, p + mid, q + mid, q + side * w + rise, p + side * w + rise, Vector3.UP - side,
			color, color, light, light)
		mb.add_quad(ROLE_ROOF, p + mid, q + mid, q - side * w + rise, p - side * w + rise, Vector3.UP + side,
			color, color, light, light)


# --- Cheminée, toit plat -------------------------------------------------------------------

static func _chimney(mb: BastideMeshBuilder, col: BastideBuildResult, roof: BastideRoofLayout,
		ws: BastideWallStyle, seed: int, with_collision: bool) -> void:
	var ch := roof.chimney
	var pos: Vector2 = ch.pos
	var half: float = ch.size * 0.5
	var y: float = ch.y0
	var top: float = ch.y1
	var row := 0
	var mortar := ws.mortar_color
	while y < top - 0.05:
		var y1 := minf(y + 0.3 * BastideRng.randf_range_at(seed, "chimney_row", row, 0.85, 1.15), top)
		if top - y1 < 0.12:
			y1 = top
		var h := half * (1.0 + BastideRng.signed_at(seed, "chimney_w", row) * 0.02)
		var tint := BastideRng.signed_at(seed, "chimney_tint", row) * ws.color_variance
		var c := ws.stone_color.lightened(tint) if tint > 0.0 else ws.stone_color.darkened(-tint)
		# Le dessus d'un rang est caché par le rang suivant.
		var skip := BastideMeshBuilder.FACE_TOP if y1 < top else 0
		mb.add_block(ROLE_BODY, _box(pos, h, y, y1), ws.stone_bevel * 0.6, 0.012, c, mortar.lerp(c, 0.35), false, skip)
		y = y1
		row += 1
	var cap := ws.quoin_color
	mb.add_block(ROLE_BODY, _box(pos, half + 0.07, top, top + 0.12), 0.03, 0.006, cap, mortar.lerp(cap, 0.4), true)
	# Conduit sombre.
	var soot := Color(0.08, 0.07, 0.06)
	var hi := half - 0.12
	mb.add_quad(ROLE_BODY, Vector3(pos.x - hi, top + 0.125, pos.y - hi), Vector3(pos.x + hi, top + 0.125, pos.y - hi),
		Vector3(pos.x + hi, top + 0.125, pos.y + hi), Vector3(pos.x - hi, top + 0.125, pos.y + hi),
		Vector3.UP, soot, soot, soot, soot)
	if with_collision:
		col.add_box(_box(pos, half, ch.y0, top + 0.12))


static func _box(c: Vector2, half: float, y0: float, y1: float) -> Array:
	return [
		Vector3(c.x - half, y0, c.y - half), Vector3(c.x + half, y0, c.y - half),
		Vector3(c.x + half, y0, c.y + half), Vector3(c.x - half, y0, c.y + half),
		Vector3(c.x - half, y1, c.y - half), Vector3(c.x + half, y1, c.y - half),
		Vector3(c.x + half, y1, c.y + half), Vector3(c.x - half, y1, c.y + half),
	]


## Toit plat de repli : un muret de pierre sur le pourtour.
static func _flat_edges(mb: BastideMeshBuilder, roof: BastideRoofLayout, ws: BastideWallStyle) -> void:
	var fp := roof.outline
	var n := fp.size()
	var y := roof.base_y
	var inner := BastidePolygon.offset(fp, 0.3, 3.0)
	for i in n:
		var j := (i + 1) % n
		var k := [
			Vector3(fp[i].x, y - 0.3, fp[i].y), Vector3(fp[j].x, y - 0.3, fp[j].y),
			Vector3(inner[j].x, y - 0.3, inner[j].y), Vector3(inner[i].x, y - 0.3, inner[i].y),
			Vector3(fp[i].x, y + 0.45, fp[i].y), Vector3(fp[j].x, y + 0.45, fp[j].y),
			Vector3(inner[j].x, y + 0.45, inner[j].y), Vector3(inner[i].x, y + 0.45, inner[i].y),
		]
		mb.add_block(ROLE_BODY, k, 0.03, 0.01, ws.quoin_color, ws.mortar_color)


# --- Outils ----------------------------------------------------------------------------------

## Polygone convexe en éventail.
static func _polygon(mb: BastideMeshBuilder, role: StringName, poly: PackedVector3Array, hint: Vector3, color: Color) -> void:
	for i in range(1, poly.size() - 1):
		mb.add_tri(role, poly[0], poly[i], poly[i + 1], hint, color, color, color)


static func _collide_polygon(col: BastideBuildResult, poly: PackedVector3Array) -> void:
	for i in range(1, poly.size() - 1):
		col.collision_faces.append(poly[0])
		col.collision_faces.append(poly[i])
		col.collision_faces.append(poly[i + 1])


## Découpe d'un polygone convexe entre deux plans : lo ≤ p·axis ≤ hi.
static func _clip(poly: PackedVector3Array, axis: Vector3, lo: float, hi: float) -> PackedVector3Array:
	return _clip_half(_clip_half(poly, axis, lo, 1.0), axis, hi, -1.0)


static func _clip_half(poly: PackedVector3Array, axis: Vector3, bound: float, sgn: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var m := poly.size()
	if m == 0:
		return out
	for i in m:
		var p := poly[i]
		var q := poly[(i + 1) % m]
		var dp := (p.dot(axis) - bound) * sgn
		var dq := (q.dot(axis) - bound) * sgn
		if dp >= 0.0:
			out.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			var t := dp / (dp - dq)
			var x := p.lerp(q, t)
			# Le point coupé tombe exactement sur le plan (utile pour repérer les ressauts).
			if axis == Vector3.UP:
				x.y = bound
			out.append(x)
	return out
