@tool
class_name BastideWallMesher
extends RefCounted
## Backend procédural : WallLayout → BuildResult (mesh + collisions).
## Ne prend aucune décision de « quoi » construire : tout vient du plan.

const EndKind := BastideWallLayout.EndKind
const ROLE_BODY := &"body"
const ROLE_ROOF := &"roof"
const ROLE_WOOD := &"wood"
const SINK := 0.03


static func build(layout: BastideWallLayout, style: BastideStyle, with_collision := true) -> BastideBuildResult:
	var result := BastideBuildResult.new()
	var ws := style.get_wall_style()
	var mb := BastideMeshBuilder.new()
	var col := result

	var mortar := ws.mortar_color
	var _t := Time.get_ticks_usec()
	var timings := {}
	var runs_by_index := {}
	for run in layout.runs:
		runs_by_index[run.index] = run

	timings["setup"] = Time.get_ticks_usec() - _t; _t = Time.get_ticks_usec()
	# --- Fond de mur (joints) : caché derrière les pierres, il bouche tout interstice ---
	for run in layout.runs:
		_add_backing(mb, layout, run, mortar)
		if with_collision:
			_add_run_collision(col, layout, run)

	timings["backing"] = Time.get_ticks_usec() - _t; _t = Time.get_ticks_usec()
	# --- Pierres des parements ---
	var js := ws.stone_bevel * 0.6   # retrait aléatoire maximal des coins (joints irréguliers)
	for si in layout.stones.size():
		var st: Dictionary = layout.stones[si]
		var run: BastideWallLayout.Run = runs_by_index[st.run]
		var side: float = st.side
		var s0: float = st.s0
		var s1: float = st.s1
		var y0: float = st.y0
		var sk := BastideRng.key(layout.seed, "stone_shape", si)
		# Repères aux deux bouts de la pierre, calculés une seule fois.
		var pa := run.pos_at(s0)
		var pb := run.pos_at(s1)
		var oa := run.off_at(s0) * side
		var ob := run.off_at(s1) * side
		var inv := js / maxf(s1 - s0, 1e-4)
		var u0 := BastideRng.unit(sk + 0) * inv
		var u1 := 1.0 - BastideRng.unit(sk + 2) * inv
		var u2 := 1.0 - BastideRng.unit(sk + 4) * inv
		var u3 := BastideRng.unit(sk + 6) * inv
		var c := [
			_fp(layout, pa, pb, oa, ob, u0, y0 + js * BastideRng.unit(sk + 1)),
			_fp(layout, pa, pb, oa, ob, u1, y0 + js * BastideRng.unit(sk + 3)),
			_fp(layout, pa, pb, oa, ob, u2, float(st.y1b) - js * BastideRng.unit(sk + 5)),
			_fp(layout, pa, pb, oa, ob, u3, float(st.y1a) - js * BastideRng.unit(sk + 7)),
		]
		var relief := Vector4(0.55 + BastideRng.unit(sk + 8) * 0.9, 0.55 + BastideRng.unit(sk + 9) * 0.9,
			0.55 + BastideRng.unit(sk + 10) * 0.9, 0.55 + BastideRng.unit(sk + 11) * 0.9)
		var hint := oa + ob
		var color := _stone_color(ws, st.tint, st.alt, st.quoin)
		var bevel := ws.stone_bevel * (0.8 + BastideRng.unit(sk + 12) * 0.6)
		mb.add_pillow_quad(ROLE_BODY, c, hint, bevel, st.bulge, color, mortar.lerp(color, 0.3), relief)

	timings["stones"] = Time.get_ticks_usec() - _t; _t = Time.get_ticks_usec()
	# --- Bouts de murs ouverts sans pilier ---
	for run in layout.runs:
		if run.start_kind == EndKind.OPEN:
			_add_end_cap(mb, layout, run, run.s0, -run.dir_at(run.s0), ws)
		if run.end_kind == EndKind.OPEN:
			_add_end_cap(mb, layout, run, run.s1, run.dir_at(run.s1), ws)

	timings["caps"] = Time.get_ticks_usec() - _t; _t = Time.get_ticks_usec()
	# --- Chaperon ---
	for cp in layout.coping:
		var run: BastideWallLayout.Run = runs_by_index[cp.run]
		var s0: float = cp.s0
		var s1: float = cp.s1
		var hw := layout.half_top + layout.coping_overhang
		var b0 := layout.height_at(s0) - SINK
		var b1 := layout.height_at(s1) - SINK
		var t: float = cp.thickness + SINK
		var dy: float = cp.dy
		var k := [
			layout.lateral_point(run, s0, b0, -hw), layout.lateral_point(run, s1, b1, -hw),
			layout.lateral_point(run, s1, b1, hw), layout.lateral_point(run, s0, b0, hw),
			layout.lateral_point(run, s0, b0 + t + dy, -hw), layout.lateral_point(run, s1, b1 + t + dy, -hw),
			layout.lateral_point(run, s1, b1 + t + dy, hw), layout.lateral_point(run, s0, b0 + t + dy, hw),
		]
		var color := ws.quoin_color.darkened(0.04 + absf(dy) * 4.0)
		mb.add_block(ROLE_BODY, k, 0.035, 0.008, color, mortar.lerp(color, 0.45), true)

	timings["coping"] = Time.get_ticks_usec() - _t; _t = Time.get_ticks_usec()
	# --- Merlons (deux pierres empilées chacun) ---
	var crown_base := layout.coping_thickness - 0.02
	for i in layout.merlons.size():
		var me: Dictionary = layout.merlons[i]
		var run: BastideWallLayout.Run = runs_by_index[me.run]
		var s0: float = me.s0
		var s1: float = me.s1
		var b0 := layout.height_at(s0) + crown_base
		var b1 := layout.height_at(s1) + crown_base
		var top := maxf(b0, b1) + float(me.height)
		var mid := lerpf(minf(b0, b1), top, 0.5 + BastideRng.signed_at(layout.seed, "merlon_split", i) * 0.08)
		var d: float = me.depth
		for part in 2:
			var ya0 := b0 if part == 0 else mid
			var ya1 := b1 if part == 0 else mid
			var yb := mid if part == 0 else top
			var dd := d * (1.0 + BastideRng.signed_at(layout.seed, "merlon_d", i * 2 + part) * 0.03)
			var k := [
				layout.lateral_point(run, s0, ya0, -dd), layout.lateral_point(run, s1, ya1, -dd),
				layout.lateral_point(run, s1, ya1, dd), layout.lateral_point(run, s0, ya0, dd),
				layout.lateral_point(run, s0, yb, -dd), layout.lateral_point(run, s1, yb, -dd),
				layout.lateral_point(run, s1, yb, dd), layout.lateral_point(run, s0, yb, dd),
			]
			var color := _stone_color(ws, BastideRng.signed_at(layout.seed, "merlon_tint", i * 2 + part),
				BastideRng.randf_at(layout.seed, "merlon_alt", i * 2 + part), false)
			mb.add_block(ROLE_BODY, k, 0.045, 0.018, color, mortar.lerp(color, 0.3))
		if with_collision:
			_box_faces(col, [
				layout.lateral_point(run, s0, b0, -d), layout.lateral_point(run, s1, b1, -d),
				layout.lateral_point(run, s1, b1, d), layout.lateral_point(run, s0, b0, d),
				layout.lateral_point(run, s0, top, -d), layout.lateral_point(run, s1, top, -d),
				layout.lateral_point(run, s1, top, d), layout.lateral_point(run, s0, top, d),
			])

	timings["merlons"] = Time.get_ticks_usec() - _t; _t = Time.get_ticks_usec()
	# --- Piliers ---
	for pi in layout.pillars.size():
		_add_pillar(mb, col, layout, layout.pillars[pi], pi, ws, with_collision)

	timings["pillars"] = Time.get_ticks_usec() - _t; _t = Time.get_ticks_usec()
	# --- Petit toit de tuiles ---
	if layout.cap_roof:
		for run in layout.runs:
			_cap_roof(mb, layout, run, ws)
	timings["cap"] = Time.get_ticks_usec() - _t; _t = Time.get_ticks_usec()
	result.mesh = mb.commit({
		ROLE_BODY: style.get_material(),
		ROLE_ROOF: style.get_roof_material(),
		ROLE_WOOD: style.get_wood_material(),
	})
	timings["commit"] = Time.get_ticks_usec() - _t
	result.stats = {
		"stones": layout.stones.size(),
		"merlons": layout.merlons.size(),
		"pillars": layout.pillars.size(),
		"runs": layout.runs.size(),
		"triangles": mb.triangle_count,
		"length_m": snappedf(layout.length, 0.01),
		"timings_us": timings,
	}
	return result


## Petit toit de tuiles rondes à deux pentes le long d'un tronçon : côtes en
## travers de chaque pente, faîtage maçonné, dessous et planches de rive en bois.
static func _cap_roof(mb: BastideMeshBuilder, layout: BastideWallLayout, run: BastideWallLayout.Run,
		ws: BastideWallStyle) -> void:
	var ho := layout.half_top + layout.cap_overhang
	var rise := ho * layout.cap_tan
	var under := ws.cap_wood_color
	var tile := ws.cap_color
	var channel := tile.darkened(0.22)
	var lift := 0.05
	# Points du toit à l'abscisse s : faîte, et égout de chaque côté.
	var ridge := func(sv: float) -> Vector3:
		return layout.lateral_point(run, sv, layout.height_at(sv) + lift + rise, 0.0)
	var eave := func(sv: float, side: float) -> Vector3:
		return layout.lateral_point(run, sv, layout.height_at(sv) + lift, side * ho)
	for i in run.s.size() - 1:
		var sa := run.s[i]
		var sb := run.s[i + 1]
		var ra: Vector3 = ridge.call(sa)
		var rb: Vector3 = ridge.call(sb)
		for side in [-1.0, 1.0]:
			var ea: Vector3 = eave.call(sa, side)
			var eb: Vector3 = eave.call(sb, side)
			var hint: Vector3 = run.off[i] * side + Vector3.UP
			mb.add_quad(ROLE_ROOF, ra, rb, eb, ea, hint, channel, channel, channel.darkened(0.1), channel.darkened(0.1))
			# Dessous (planche horizontale jusqu'au mur) et planche d'égout.
			var da := ea - Vector3(0, 0.07, 0)
			var db := eb - Vector3(0, 0.07, 0)
			var wa := layout.lateral_point(run, sa, layout.height_at(sa) + lift - 0.07, side * layout.half_top * 0.9)
			var wb := layout.lateral_point(run, sb, layout.height_at(sb) + lift - 0.07, side * layout.half_top * 0.9)
			mb.add_quad(ROLE_WOOD, da, db, wb, wa, Vector3.DOWN, under, under, under.darkened(0.2), under.darkened(0.2))
			mb.add_quad(ROLE_WOOD, ea, eb, db, da, run.off[i] * side, under, under, under, under)
		BastideRoofMesher.stacked_ridge(mb, ra, rb, layout.cap_tan, tile.darkened(0.08), 0.13, 0.11, false)
	# Côtes de tuiles rondes en travers des pentes (même profil que les toits).
	var w := ws.cap_tile_width
	var count := maxi(1, floori(run.length() / w))
	var rw := w * BastideRoofMesher.RIB_HALF
	var h := w * BastideRoofMesher.RIB_HEIGHT
	var s_start := run.s0 + (run.length() - count * w) * 0.5 + w * 0.5
	var knots := [-rw, -rw * BastideRoofMesher.RIB_TOP, rw * BastideRoofMesher.RIB_TOP, rw]
	for k in count:
		var sc := s_start + k * w
		var tint := BastideRng.signed_at(layout.seed, "cap_tile", BastideRng.combine(run.index, k)) * 0.06
		var c := tile.lightened(tint) if tint > 0.0 else tile.darkened(-tint)
		var dark := c.darkened(0.12)
		for side in [-1.0, 1.0]:
			var rc: Vector3 = ridge.call(sc)
			var ec: Vector3 = eave.call(sc, side)
			var along := ((ridge.call(sc + rw) as Vector3) - (ridge.call(sc - rw) as Vector3)).normalized()
			var nrm := along.cross(ec - rc).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			var rs: Array = []
			var es: Array = []
			for kn: float in knots:
				var u := BastideRoofMesher.rib_profile(absf(kn), rw)
				rs.append((ridge.call(sc + kn) as Vector3) + nrm * h * u)
				es.append((eave.call(sc + kn, side) as Vector3) + nrm * h * u)
			for part in 3:
				var col := c if part == 1 else dark
				mb.add_quad(ROLE_ROOF, rs[part], es[part], es[part + 1], rs[part + 1], nrm + along * float(part - 1),
					col, col, col, col)
			var cap := c.lightened(0.1)
			mb.add_quad(ROLE_ROOF, es[0], es[1], es[2], es[3], ec - rc, cap, cap, cap, cap)
	# Pignons du petit toit aux bouts ouverts.
	for end in 2:
		var kind: int = run.start_kind if end == 0 else run.end_kind
		if kind != EndKind.OPEN:
			continue
		var sv: float = run.s0 if end == 0 else run.s1
		var outward: Vector3 = -run.dir_at(sv) if end == 0 else run.dir_at(sv)
		var r: Vector3 = ridge.call(sv)
		var l: Vector3 = eave.call(sv, -1.0)
		var rr: Vector3 = eave.call(sv, 1.0)
		mb.add_tri(ROLE_WOOD, l - Vector3(0, 0.07, 0), rr - Vector3(0, 0.07, 0), r, outward, under, under, under.lightened(0.1))


## Point d'une face entre deux repères (u = 0 → début de la pierre, 1 → fin).
static func _fp(layout: BastideWallLayout, pa: Vector3, pb: Vector3, oa: Vector3, ob: Vector3, u: float, y: float) -> Vector3:
	return pa.lerp(pb, u) + oa.lerp(ob, u) * layout.half_thickness_at(y) + Vector3(0.0, y, 0.0)


static func _stone_color(ws: BastideWallStyle, tint: float, alt: float, quoin: bool) -> Color:
	var base := ws.quoin_color if quoin else ws.stone_color.lerp(ws.stone_color_alt, alt)
	var v := tint * ws.color_variance * (0.6 if quoin else 1.0)
	return base.lightened(v) if v > 0.0 else base.darkened(-v)


static func _add_backing(mb: BastideMeshBuilder, layout: BastideWallLayout, run: BastideWallLayout.Run, mortar: Color) -> void:
	var y0 := layout.footing
	var py := layout.plaster_from
	var plaster := layout.plaster_color
	for i in run.s.size() - 1:
		var sa := run.s[i]
		var sb := run.s[i + 1]
		var ha := layout.height_at(sa) - 0.02
		var hb := layout.height_at(sb) - 0.02
		for side in [-1.0, 1.0]:
			var hint: Vector3 = run.off[i] * side
			if is_finite(py):
				# Joints du soubassement, puis enduit affleurant jusqu'au sommet.
				mb.add_quad(ROLE_BODY,
					layout.face_point(run, sa, y0, side, -0.03), layout.face_point(run, sb, y0, side, -0.03),
					layout.face_point(run, sb, py, side, -0.03), layout.face_point(run, sa, py, side, -0.03),
					hint, mortar, mortar, mortar, mortar)
				var low := plaster.darkened(0.12)
				mb.add_quad(ROLE_BODY,
					layout.face_point(run, sa, py, side), layout.face_point(run, sb, py, side),
					layout.face_point(run, sb, hb, side), layout.face_point(run, sa, ha, side),
					hint, low, low, plaster, plaster)
				continue
			mb.add_quad(ROLE_BODY,
				layout.face_point(run, sa, y0, side, -0.03), layout.face_point(run, sb, y0, side, -0.03),
				layout.face_point(run, sb, hb, side, -0.03), layout.face_point(run, sa, ha, side, -0.03),
				hint, mortar, mortar, mortar, mortar)
		var extra := 0.0 if is_finite(py) else -0.03
		var top := plaster if is_finite(py) else mortar
		mb.add_quad(ROLE_BODY,
			layout.face_point(run, sa, ha, -1.0, extra), layout.face_point(run, sb, hb, -1.0, extra),
			layout.face_point(run, sb, hb, 1.0, extra), layout.face_point(run, sa, ha, 1.0, extra),
			Vector3.UP, top, top, top, top)


static func _add_end_cap(mb: BastideMeshBuilder, layout: BastideWallLayout, run: BastideWallLayout.Run,
		sv: float, outward: Vector3, ws: BastideWallStyle) -> void:
	var h := layout.height_at(sv)
	for row in layout.courses.size() - 1:
		var y0: float = layout.courses[row]
		if y0 >= h - 0.05:
			break
		var y1 := minf(layout.courses[row + 1], h)
		var c := [
			layout.face_point(run, sv, y0, -1.0), layout.face_point(run, sv, y0, 1.0),
			layout.face_point(run, sv, y1, 1.0), layout.face_point(run, sv, y1, -1.0),
		]
		var color := ws.quoin_color.darkened(BastideRng.randf_at(layout.seed, "cap", row) * 0.08)
		mb.add_pillow_quad(ROLE_BODY, c, outward, ws.stone_bevel, 0.03, color, ws.mortar_color.lerp(color, 0.3))
	# Corps enduit : le bout est enduit au-dessus du soubassement.
	var py := layout.plaster_from
	if is_finite(py) and h > py:
		var p := layout.plaster_color
		mb.add_quad(ROLE_BODY, layout.face_point(run, sv, py, -1.0), layout.face_point(run, sv, py, 1.0),
			layout.face_point(run, sv, h - 0.02, 1.0), layout.face_point(run, sv, h - 0.02, -1.0),
			outward, p.darkened(0.12), p.darkened(0.12), p, p)


static func _add_pillar(mb: BastideMeshBuilder, col: BastideBuildResult, layout: BastideWallLayout,
		p: Dictionary, pi: int, ws: BastideWallStyle, with_collision: bool) -> void:
	var base: Vector3 = p.pos
	var fwd: Vector3 = p.dir
	var right := BastidePolyline.right_of(fwd)
	var w: float = p.width
	var top: float = p.top
	var cap_t := 0.16
	var body_top := top - cap_t
	var mortar := ws.mortar_color
	var y := layout.footing
	var row := 0
	var corners_at := func(half: float, ya: float, yb: float, shift: Vector3) -> Array:
		var o := base + shift
		return [
			o + (-fwd - right) * half + Vector3(0, ya, 0), o + (fwd - right) * half + Vector3(0, ya, 0),
			o + (fwd + right) * half + Vector3(0, ya, 0), o + (-fwd + right) * half + Vector3(0, ya, 0),
			o + (-fwd - right) * half + Vector3(0, yb, 0), o + (fwd - right) * half + Vector3(0, yb, 0),
			o + (fwd + right) * half + Vector3(0, yb, 0), o + (-fwd + right) * half + Vector3(0, yb, 0),
		]
	while y < body_top - 0.05:
		var key := BastideRng.combine(pi, row)
		var hgt := ws.course_height * 1.35 * BastideRng.randf_range_at(layout.seed, "pillar_course", key, 0.85, 1.15)
		var y1 := minf(y + hgt, body_top)
		if body_top - y1 < 0.12:
			y1 = body_top
		var half := w * 0.5 * (1.0 + BastideRng.signed_at(layout.seed, "pillar_w", key) * 0.025)
		var shift := (fwd * BastideRng.signed_at(layout.seed, "pillar_x", key) + right * BastideRng.signed_at(layout.seed, "pillar_z", key)) * 0.012
		var color := _stone_color(ws, BastideRng.signed_at(layout.seed, "pillar_tint", key), 0.0, true)
		mb.add_block(ROLE_BODY, corners_at.call(half, y, y1, shift), ws.stone_bevel, 0.02, color, mortar.lerp(color, 0.35))
		y = y1
		row += 1
	# Couronnement : dalle débordante puis petite pyramide.
	var slab_half := w * 0.5 + 0.08
	var cap_color := ws.quoin_color.lightened(0.04)
	mb.add_block(ROLE_BODY, corners_at.call(slab_half, body_top, top, Vector3.ZERO), 0.035, 0.008, cap_color, mortar.lerp(cap_color, 0.45), true)
	var apex := base + Vector3(0, top + w * 0.32, 0)
	var ring: Array = (corners_at.call(slab_half - 0.04, top, top, Vector3.ZERO) as Array).slice(0, 4)
	for i in 4:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		var mid := (a + b) * 0.5
		var hint := (mid - base) * Vector3(1, 0, 1) + Vector3.UP * 0.5
		mb.add_tri(ROLE_BODY, a, b, apex, hint, cap_color.darkened(0.1), cap_color.darkened(0.1), cap_color)
	if with_collision:
		_box_faces(col, corners_at.call(w * 0.5, layout.footing, top, Vector3.ZERO))


static func _add_run_collision(col: BastideBuildResult, layout: BastideWallLayout, run: BastideWallLayout.Run) -> void:
	var y0 := layout.footing
	var hw := layout.half_top + layout.coping_overhang
	for i in run.s.size() - 1:
		var sa := run.s[i]
		var sb := run.s[i + 1]
		var ta := layout.height_at(sa) + layout.coping_thickness
		var tb := layout.height_at(sb) + layout.coping_thickness
		_box_faces(col, [
			layout.lateral_point(run, sa, y0, -hw), layout.lateral_point(run, sb, y0, -hw),
			layout.lateral_point(run, sb, y0, hw), layout.lateral_point(run, sa, y0, hw),
			layout.lateral_point(run, sa, ta, -hw), layout.lateral_point(run, sb, tb, -hw),
			layout.lateral_point(run, sb, tb, hw), layout.lateral_point(run, sa, ta, hw),
		])


## Ajoute un bloc à 8 coins aux faces de collision.
static func _box_faces(col: BastideBuildResult, k: Array) -> void:
	col.add_box(k)
