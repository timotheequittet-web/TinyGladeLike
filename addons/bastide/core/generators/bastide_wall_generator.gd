@tool
class_name BastideWallGenerator
extends RefCounted
## WallSpec + style → WallLayout. Fonction pure : aucun nœud, aucun état global.
##
## Étapes : assainir le tracé, repérer les angles, découper en tronçons, poser les
## piliers, puis répartir assises, pierres, chaperon et merlons selon les règles du style.

const EndKind := BastideWallLayout.EndKind


static func generate(spec: BastideWallSpec, style: BastideStyle) -> BastideWallLayout:
	var ws := style.get_wall_style()
	var layout := BastideWallLayout.new()
	layout.seed = spec.seed
	layout.height = spec.height if spec.height > 0.0 else ws.height
	layout.top_amplitude = minf(ws.top_amplitude, layout.height * 0.4)
	layout.top_wavelength = ws.top_wavelength
	layout.half_top = ws.thickness * 0.5
	layout.half_base = ws.thickness * 0.5 + ws.batter
	layout.coping_thickness = ws.coping_thickness
	layout.coping_overhang = ws.coping_overhang
	if ws.body_kind == BastideWallStyle.BodyKind.PLASTER:
		layout.plaster_from = minf(ws.plinth_height, layout.height - 0.2)
		layout.plaster_color = ws.plaster_color.lerp(ws.plaster_color_alt, BastideRng.randf_at(spec.seed, "plaster"))
	if ws.cap_roof:
		layout.cap_roof = true
		layout.cap_overhang = ws.cap_overhang
		layout.cap_tan = tan(deg_to_rad(ws.cap_pitch))
		# Pour les collisions et les piliers : le petit toit tient lieu de chaperon.
		layout.coping_overhang = ws.cap_overhang
		layout.coping_thickness = (layout.half_top + ws.cap_overhang) * layout.cap_tan + 0.2

	var clean := BastidePathSanitizer.sanitize(spec.points, spec.closed, ws.min_segment)
	var pts: PackedVector3Array = clean.points
	var closed: bool = clean.closed
	layout.closed = closed
	if pts.size() < 2:
		return layout

	# --- Angles ------------------------------------------------------------
	var n := pts.size()
	var turns := PackedFloat32Array()
	turns.resize(n)
	for i in n:
		if not closed and (i == 0 or i == n - 1):
			turns[i] = 0.0
			continue
		var a := pts[posmod(i - 1, n)]
		var b := pts[i]
		var c := pts[posmod(i + 1, n)]
		turns[i] = BastidePolyline.turn_angle(BastidePolyline.flat_dir(a, b), BastidePolyline.flat_dir(b, c))

	var corner_rad := deg_to_rad(ws.corner_angle)
	var pillar_rad := deg_to_rad(ws.pillar_angle)

	if closed:
		# On fait commencer la boucle sur son angle le plus marqué : les tronçons
		# tombent alors naturellement entre deux angles, sans cas particulier.
		var best := 0
		for i in n:
			if turns[i] > turns[best]:
				best = i
		if best > 0 and turns[best] >= corner_rad:
			var rp := PackedVector3Array()
			var rt := PackedFloat32Array()
			for i in n:
				rp.append(pts[(best + i) % n])
				rt.append(turns[(best + i) % n])
			pts = rp
			turns = rt
		pts.append(pts[0])
		turns.append(turns[0])

	var m := pts.size()
	var cum := BastidePolyline.cumulative(pts)
	layout.length = cum[m - 1]
	if layout.length < 0.05:
		return layout
	if closed:
		layout.noise_period = maxi(1, roundi(layout.length / ws.top_wavelength))
	layout.bake_heights()

	var is_loop := closed and turns[0] < corner_rad
	var breaks: Array[int] = []
	if is_loop:
		breaks = [0, m - 1]
	else:
		for i in m:
			var is_end := (not closed) and (i == 0 or i == m - 1)
			if is_end or turns[i] >= corner_rad:
				breaks.append(i)

	var kind_of := func(i: int) -> int:
		if is_loop:
			return EndKind.LOOP
		if not closed and (i == 0 or i == m - 1):
			return EndKind.PILLAR if ws.end_pillars else EndKind.OPEN
		return EndKind.PILLAR if turns[i] >= pillar_rad else EndKind.CORNER

	# Directions de segments, avec bouclage pour les murs fermés.
	var seg_dir := func(j: int) -> Vector3:
		if closed:
			j = posmod(j, m - 1)
		j = clampi(j, 0, m - 2)
		return BastidePolyline.flat_dir(pts[j], pts[j + 1])

	# --- Piliers et angles -------------------------------------------------
	var pillar_w := ws.thickness * ws.pillar_width_factor + ws.batter * 2.0
	var trim := pillar_w * 0.42
	for bi in breaks.size():
		var i: int = breaks[bi]
		if closed and i == m - 1:
			continue  # même sommet que l'indice 0
		var k: int = kind_of.call(i)
		if k == EndKind.LOOP:
			continue
		var d: Vector3
		if not closed and i == 0:
			d = seg_dir.call(0)
		elif not closed and i == m - 1:
			d = seg_dir.call(m - 2)
		else:
			d = (seg_dir.call(i - 1) + seg_dir.call(i)).normalized()
			if d.length_squared() < 0.5:
				d = seg_dir.call(i)
		if k == EndKind.PILLAR:
			layout.pillars.append({"pos": pts[i], "dir": d, "width": pillar_w, "s": cum[i], "top": 0.0})
		if turns[i] > 0.0:
			layout.corners.append({"pos": pts[i], "s": cum[i], "angle_deg": rad_to_deg(turns[i]), "pillar": k == EndKind.PILLAR})

	# --- Tronçons ----------------------------------------------------------
	for bi in breaks.size() - 1:
		var a: int = breaks[bi]
		var b: int = breaks[bi + 1]
		var ka: int = kind_of.call(a)
		var kb: int = kind_of.call(b)
		var sa: float = cum[a] + (trim if ka == EndKind.PILLAR else 0.0)
		var sb: float = cum[b] - (trim if kb == EndKind.PILLAR else 0.0)
		if sb - sa < 0.15:
			continue
		var run := BastideWallLayout.Run.new()
		run.index = layout.runs.size()
		run.s0 = sa
		run.s1 = sb
		run.start_kind = ka
		run.end_kind = kb

		# Abscisses des stations : bouts, sommets intermédiaires, puis subdivision régulière.
		var marks: Array = [[sa, -3]]
		for j in range(a + 1, b):
			if cum[j] > sa + 1e-3 and cum[j] < sb - 1e-3:
				marks.append([cum[j], j])
		marks.append([sb, -2])
		var stations: Array = []
		for mi in marks.size():
			stations.append(marks[mi])
			if mi == marks.size() - 1:
				break
			var d0: float = marks[mi][0]
			var d1: float = marks[mi + 1][0]
			var steps := ceili((d1 - d0) / ws.station_spacing)
			for st in range(1, steps):
				stations.append([lerpf(d0, d1, float(st) / steps), -1])

		var seg := a
		for st in stations:
			var d: float = st[0]
			var tag: int = st[1]
			while seg < b - 1 and cum[seg + 1] < d:
				seg += 1
			var span := cum[seg + 1] - cum[seg]
			var t := (d - cum[seg]) / span if span > 1e-6 else 0.0
			var p := pts[seg].lerp(pts[seg + 1], clampf(t, 0.0, 1.0))
			var o: Vector3
			if tag >= 0:
				o = BastidePolyline.miter(seg_dir.call(tag - 1), seg_dir.call(tag), ws.miter_limit)
			elif tag == -3 and (ka == EndKind.CORNER or ka == EndKind.LOOP):
				o = BastidePolyline.miter(seg_dir.call(a - 1), seg_dir.call(a), ws.miter_limit)
			elif tag == -2 and (kb == EndKind.CORNER or kb == EndKind.LOOP):
				o = BastidePolyline.miter(seg_dir.call(b - 1), seg_dir.call(b), ws.miter_limit)
			else:
				o = BastidePolyline.right_of(seg_dir.call(seg))
			run.s.append(d)
			run.pos.append(p)
			run.off.append(o)
		layout.runs.append(run)

	# --- Assises (communes à tout le mur pour qu'elles se raccordent aux angles) ---
	var y := layout.footing
	var y_max := layout.height + layout.top_amplitude + 0.05
	var ci := 0
	layout.courses.append(y)
	if is_finite(layout.plaster_from):
		# Corps enduit : assises de pierre seulement dans le soubassement, la dernière
		# s'arrêtant pile sous l'enduit.
		var count := maxi(1, roundi((layout.plaster_from - y) / ws.course_height))
		for k in count:
			var t := float(k + 1) / count
			var jitter := BastideRng.signed_at(spec.seed, "course", k) * 0.12 / count if k < count - 1 else 0.0
			layout.courses.append(lerpf(layout.footing, layout.plaster_from, clampf(t + jitter, 0.0, 1.0)))
		y_max = -INF
	while y < y_max:
		y += ws.course_height * BastideRng.randf_range_at(spec.seed, "course", ci, 0.78, 1.28)
		layout.courses.append(y)
		ci += 1

	# --- Pierres -------------------------------------------------------------
	for run in layout.runs:
		for side in [-1.0, 1.0]:
			var side_i := 0 if side < 0.0 else 1
			for row in layout.courses.size() - 1:
				var y0: float = layout.courses[row]
				var y1: float = layout.courses[row + 1]
				var visible_start: bool = run.start_kind == EndKind.OPEN or run.start_kind == EndKind.CORNER
				var visible_end: bool = run.end_kind == EndKind.OPEN or run.end_kind == EndKind.CORNER
				var first := -1.0
				if visible_start:
					# Chaînage d'angle : pierres alternativement longues et courtes.
					first = ws.stone_length_max * 1.05 if (row + side_i) % 2 == 0 else ws.stone_length_min * 1.1
				var key := BastideRng.combine(BastideRng.combine(run.index, side_i), row)
				var lengths := BastideDistributor.split_lengths(spec.seed, "stone", key, run.length(),
					ws.stone_length_min, ws.stone_length_max, first)
				var acc: float = run.s0
				for li in lengths.size():
					var sa: float = acc
					var sb: float = acc + lengths[li]
					acc = sb
					var top_a := minf(y1, layout.height_at(sa))
					var top_b := minf(y1, layout.height_at(sb))
					if maxf(top_a, top_b) - y0 < 0.05:
						continue
					var quoin: bool = (li == 0 and visible_start) or (li == lengths.size() - 1 and visible_end)
					var sk := BastideRng.combine(key, li)
					layout.stones.append({
						"run": run.index, "side": side, "s0": sa, "s1": sb,
						"y0": y0, "y1a": maxf(top_a, y0 + 0.02), "y1b": maxf(top_b, y0 + 0.02),
						"quoin": quoin,
						"tint": BastideRng.signed_at(spec.seed, "tint", sk),
						"alt": BastideRng.randf_at(spec.seed, "alt", sk),
						"bulge": BastideRng.randf_range_at(spec.seed, "bulge", sk, ws.stone_bulge_min, ws.stone_bulge_max) * (1.4 if quoin else 1.0),
					})

	# --- Chaperon ----------------------------------------------------------------
	if ws.coping_thickness > 0.0 and not ws.cap_roof:
		for run in layout.runs:
			var lengths := BastideDistributor.split_lengths(spec.seed, "coping", run.index, run.length(), 0.55, 0.95)
			var acc: float = run.s0
			for li in lengths.size():
				var k := BastideRng.combine(run.index, li)
				layout.coping.append({
					"run": run.index, "s0": acc, "s1": acc + lengths[li],
					"dy": BastideRng.signed_at(spec.seed, "coping_dy", k) * 0.012,
					"thickness": ws.coping_thickness * (1.0 + BastideRng.signed_at(spec.seed, "coping_t", k) * 0.08),
				})
				acc += lengths[li]

	# --- Merlons ---------------------------------------------------------------------
	if ws.crenellations and not ws.cap_roof:
		for run in layout.runs:
			var a: float = run.s0
			var b: float = run.s1
			var fit: Dictionary
			if run.start_kind == EndKind.LOOP:
				fit = BastideDistributor.fit_loop(b - a, ws.merlon_width, ws.merlon_gap)
			else:
				if run.start_kind == EndKind.PILLAR:
					a += ws.merlon_gap * 0.6
				if run.end_kind == EndKind.PILLAR:
					b -= ws.merlon_gap * 0.6
				fit = BastideDistributor.fit_with_full_ends(b - a, ws.merlon_width, ws.merlon_gap, ws.distribution_tolerance)
			var acc := a
			for i in fit.count:
				var k := BastideRng.combine(run.index, i)
				layout.merlons.append({
					"run": run.index, "s0": acc, "s1": acc + fit.item,
					"height": ws.merlon_height * (1.0 + BastideRng.signed_at(spec.seed, "merlon_h", k) * 0.07),
					"depth": layout.half_top * ws.merlon_depth_ratio,
				})
				acc += fit.item + fit.gap

	# --- Hauteur des piliers -----------------------------------------------------------
	var crown := ws.coping_thickness + (ws.merlon_height if ws.crenellations else 0.0)
	if ws.cap_roof:
		crown = layout.coping_thickness
	for p in layout.pillars:
		var s: float = p.s
		var h := maxf(layout.height_at(s), maxf(layout.height_at(s - pillar_w), layout.height_at(s + pillar_w)))
		p.top = h + crown + 0.25

	return layout
