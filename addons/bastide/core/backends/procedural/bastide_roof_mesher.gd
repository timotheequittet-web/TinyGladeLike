@tool
class_name BastideRoofMesher
extends RefCounted
## Backend procédural des toits : BastideRoofLayout → triangles.
##
## Chaque pan est découpé en rangs parallèles à l'égout puis en tuiles décalées
## d'un rang à l'autre ; le bas de chaque rang est soulevé pour faire le ressaut.
## S'y ajoutent le dessous du débord, les planches de rive, les tuiles faîtières
## et la cheminée.

const ArcKind := BastideRoofLayout.ArcKind
const ROLE_ROOF := &"roof"
const ROLE_BODY := &"body"


static func build_into(mb: BastideMeshBuilder, col: BastideBuildResult, roof: BastideRoofLayout,
		style: BastideStyle, seed: int, with_collision: bool) -> void:
	if roof == null or roof.is_empty():
		return
	var rs := style.get_roof_style()
	var ws := style.get_wall_style()
	var flat := roof.fallback == "plat"
	var sin_p := sin(deg_to_rad(roof.pitch_deg))
	var row_dh := rs.tile_row * sin_p if not flat else INF
	var tt := rs.tile_thickness if not flat else 0.0
	var under := rs.underside_color

	for e in roof.faces.size():
		var face: Dictionary = roof.faces[e]
		if face.weight <= 0.0:
			continue
		var nrm: Vector3 = face.normal
		var dir: Vector3 = face.dir
		var down: Vector3 = -(face.up_dir as Vector3)
		for poly: PackedVector3Array in face.polys:
			# Dessous (visible sous le débord).
			var low := PackedVector3Array()
			for p in poly:
				low.append(p - Vector3(0.0, roof.thickness, 0.0))
			_polygon(mb, ROLE_BODY, low, Vector3.DOWN, under)
			if with_collision:
				for i in range(1, poly.size() - 1):
					col.collision_faces.append(poly[0])
					col.collision_faces.append(poly[i])
					col.collision_faces.append(poly[i + 1])
			if flat:
				_polygon(mb, ROLE_ROOF, poly, Vector3.UP, roof.color)
				continue
			var ymin := INF
			var ymax := -INF
			for p in poly:
				ymin = minf(ymin, p.y)
				ymax = maxf(ymax, p.y)
			var k0 := floori((ymin - roof.base_y) / row_dh + 1e-4)
			var k1 := ceili((ymax - roof.base_y) / row_dh - 1e-4)
			for k in range(k0, k1):
				var lo := roof.base_y + k * row_dh
				var hi := lo + row_dh
				var row := _clip(poly, Vector3.UP, lo, hi)
				if row.size() < 3:
					continue
				if rs.tile_width <= 0.0:
					_tile(mb, row, roof, nrm, down, lo, row_dh, tt, seed, BastideRng.combine(e, k), rs)
					continue
				var smin := INF
				var smax := -INF
				for p in row:
					var s := p.dot(dir)
					smin = minf(smin, s)
					smax = maxf(smax, s)
				var shift := rs.tile_width * 0.5 * float(posmod(k, 2))
				var j0 := floori((smin - shift) / rs.tile_width)
				var j1 := ceili((smax - shift) / rs.tile_width)
				for j in range(j0, j1):
					var s0 := shift + j * rs.tile_width
					var tile := _clip(row, dir, s0, s0 + rs.tile_width)
					if tile.size() >= 3:
						_tile(mb, tile, roof, nrm, down, lo, row_dh, tt, seed,
							BastideRng.combine(BastideRng.combine(e, k), j), rs)

	# --- Égouts : planche le long des côtés en pente ---
	var n := roof.outline.size()
	if not flat:
		for e in n:
			if roof.weights[e] <= 0.0:
				continue
			var a := roof.outline[e]
			var b := roof.outline[(e + 1) % n]
			var out := -(roof.faces[e].up_dir as Vector3)
			var y := roof.base_y
			mb.add_quad(ROLE_BODY, Vector3(a.x, y + tt, a.y), Vector3(b.x, y + tt, b.y),
				Vector3(b.x, y - roof.thickness, b.y), Vector3(a.x, y - roof.thickness, a.y),
				out, under, under, under, under)
	else:
		_flat_edges(mb, roof, ws)

	# --- Rives, faîtages, arêtiers ---
	var cap_color := roof.color.darkened(0.18)
	for arc in roof.arcs:
		match arc.kind:
			ArcKind.VERGE:
				_verge(mb, roof, arc, tt, under)
			ArcKind.RIDGE, ArcKind.HIP:
				if rs.ridge_caps:
					_ridge_caps(mb, roof, arc, cap_color, seed)
			ArcKind.VALLEY:
				if rs.ridge_caps:
					_valley(mb, roof, arc, cap_color.darkened(0.1), tt)

	# --- Cheminée ---
	if not roof.chimney.is_empty():
		_chimney(mb, col, roof, ws, seed, with_collision)


## Une tuile : polygone soulevé vers le bas du rang, plus son ressaut.
static func _tile(mb: BastideMeshBuilder, poly: PackedVector3Array, roof: BastideRoofLayout, nrm: Vector3,
		down: Vector3, lo: float, row_dh: float, tt: float, seed: int, key: int, rs: BastideRoofStyle) -> void:
	var tint := BastideRng.signed_at(seed, "tile", key) * rs.tile_variance
	var c := roof.color.lightened(tint) if tint > 0.0 else roof.color.darkened(-tint)
	var lifted := PackedVector3Array()
	var colors := PackedColorArray()
	for p in poly:
		var f := clampf((p.y - lo) / row_dh, 0.0, 1.0)
		lifted.append(p + nrm * tt * (1.0 - f))
		colors.append(c.darkened(0.12 * (1.0 - f)))
	for i in range(1, lifted.size() - 1):
		mb.add_tri(ROLE_ROOF, lifted[0], lifted[i], lifted[i + 1], nrm, colors[0], colors[i], colors[i + 1])
	if tt <= 0.0:
		return
	var m := poly.size()
	var edge := c.darkened(0.35)
	for i in m:
		var p := poly[i]
		var q := poly[(i + 1) % m]
		if absf(p.y - lo) < 1e-4 and absf(q.y - lo) < 1e-4:
			mb.add_quad(ROLE_ROOF, p, q, q + nrm * tt, p + nrm * tt, down, edge, edge, c, c)


## Planche de rive le long d'un pignon.
static func _verge(mb: BastideMeshBuilder, roof: BastideRoofLayout, arc: Dictionary, tt: float, color: Color) -> void:
	var a: Vector3 = arc.a
	var b: Vector3 = arc.b
	var gable_face := -1
	for fc in arc.faces:
		if roof.weights[fc] <= 0.0:
			gable_face = fc
	if gable_face < 0:
		return
	var out := -(roof.faces[gable_face].up_dir as Vector3)
	var w := 0.06
	var top := tt + 0.03
	var bot := -roof.thickness - 0.02
	var k := [
		a + Vector3(0, bot, 0), b + Vector3(0, bot, 0), b + Vector3(0, bot, 0) + out * w, a + Vector3(0, bot, 0) + out * w,
		a + Vector3(0, top, 0), b + Vector3(0, top, 0), b + Vector3(0, top, 0) + out * w, a + Vector3(0, top, 0) + out * w,
	]
	mb.add_block(ROLE_BODY, k, 0.012, 0.0, color, color.darkened(0.2), true)


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


## Noue : gouttière en V couchée dans le creux, qui cache la jonction des deux pans.
static func _valley(mb: BastideMeshBuilder, roof: BastideRoofLayout, arc: Dictionary, color: Color, tt: float) -> void:
	var a: Vector3 = arc.a
	var b: Vector3 = arc.b
	var flat_dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if flat_dir.length_squared() < 1e-6:
		return
	flat_dir = flat_dir.normalized()
	var side := Vector3(-flat_dir.z, 0.0, flat_dir.x)
	var w := 0.2
	var mid := Vector3.UP * (tt + 0.02)
	var rise := Vector3.UP * (w * roof.tan_pitch * 0.6 + tt)
	var la := a + side * w + rise
	var lb := b + side * w + rise
	var ra := a - side * w + rise
	var rb := b - side * w + rise
	var light := color.lightened(0.08)
	mb.add_quad(ROLE_ROOF, a + mid, b + mid, lb, la, Vector3.UP - side, color, color, light, light)
	mb.add_quad(ROLE_ROOF, a + mid, b + mid, rb, ra, Vector3.UP + side, color, color, light, light)


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
		mb.add_block(ROLE_BODY, _box(pos, h, y, y1), ws.stone_bevel * 0.6, 0.012, c, mortar.lerp(c, 0.35))
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


## Polygone convexe en éventail.
static func _polygon(mb: BastideMeshBuilder, role: StringName, poly: PackedVector3Array, hint: Vector3, color: Color) -> void:
	for i in range(1, poly.size() - 1):
		mb.add_tri(role, poly[0], poly[i], poly[i + 1], hint, color, color, color)


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
