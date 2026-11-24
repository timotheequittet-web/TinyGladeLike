@tool
class_name BastideTerraceMesher
extends RefCounted
## Terrasses de bois : plancher de planches posé sur des poteaux courts, chacun sur
## sa pierre d'assise.
##
## - Contre une maison (engawa) : galerie collée à la façade, planches dans le sens
##   de la façade, sans garde-corps, une grande pierre de seuil (kutsunugi-ishi)
##   devant, parfois une paire de geta posée dessus.
## - Isolée : garde-corps à lisse haute (boules de bronze aux angles en style
##   japonais), quelques marches de bois du côté d'où l'on vient.
##
## Règles : toujours un rectangle, planches de largeur régulière aux joints
## décalés, poteaux en nombre entier (1,8 m au plus entre deux), marches de hauteur
## égale. Les marches sont déclarées comme une « porte » : un chemin qui arrive
## près d'elles les rejoint tout seul.

const ROLE_STONE := BastideGardenMesher.ROLE_STONE
const ROLE_WOOD := BastideGardenMesher.ROLE_WOOD
const ROLE_GRAVEL := BastideGardenMesher.ROLE_GRAVEL
const ROLE_PAINT := BastideGardenMesher.ROLE_PAINT
const BOARD := 0.04
const POST_SPACING := 1.8
const RAIL_HEIGHT := 0.78


## Plan d'une terrasse (aucune géométrie) : {rect, house_side, entry, engawa, height,
## step_width, step_run, door}.
static func plan(points: PackedVector3Array, gs: BastideGardenStyle, ctx: BastideGardenContext,
		entry := -1, height := 0.0) -> Dictionary:
	var out := {"rect": PackedVector3Array(), "house_side": -1, "entry": 0, "engawa": false}
	var rect := BastideTerraceRules.fit_rect(points)
	if rect.size() != 4:
		return out
	if ctx != null:
		# Retouchée à la main tout près d'une maison : elle s'y recolle.
		rect = BastideTerraceRules.snap_to_house(rect, ctx, 0.5)["points"]
	var hside := BastideTerraceRules.house_side(rect, ctx) if ctx != null else -1
	var esid := BastideTerraceRules.entry_side(rect, ctx, hside, entry)
	var h := height if height > 0.0 else gs.terrace_height
	var side_len := rect[esid].distance_to(rect[(esid + 1) % 4])
	var sw := clampf(side_len - 0.6, 0.8, 1.4)
	var risers := maxi(2, roundi(h / 0.17))
	var run := 0.0 if hside >= 0 else 0.28 * (risers - 1)
	var nrm := BastideTerraceRules.side_normal(rect, esid)
	var mid := (rect[esid] + rect[(esid + 1) % 4]) * 0.5
	var door_pos := mid + nrm * (0.1 if hside >= 0 else run + 0.08)
	out["rect"] = rect
	out["house_side"] = hside
	out["entry"] = esid
	out["engawa"] = hside >= 0
	out["height"] = h
	out["step_width"] = sw
	out["risers"] = risers
	out["step_run"] = run
	out["door"] = {"pos": door_pos, "out": nrm, "width": sw, "stone": false}
	return out


static func build(points: PackedVector3Array, seed: int, style: BastideStyle, ctx: BastideGardenContext,
		with_collision := true, entry := -1, height := 0.0) -> BastideBuildResult:
	var result := BastideBuildResult.new()
	var gs := style.get_garden_style()
	var pl := plan(points, gs, ctx, entry, height)
	var rect: PackedVector3Array = pl["rect"]
	if rect.size() != 4:
		return result
	var mb := BastideMeshBuilder.new()
	var h: float = pl["height"]
	var hside: int = pl["house_side"]
	var esid: int = pl["entry"]
	var o := rect[0]
	var e0 := BastidePolyline.flat_dir(rect[0], rect[1])
	var e3 := BastidePolyline.flat_dir(rect[0], rect[3])
	var l0 := BastidePolyline.flat_dist(rect[0], rect[1])
	var l3 := BastidePolyline.flat_dist(rect[0], rect[3])
	var at := func(u: float, v: float, y: float) -> Vector3: return o + e0 * u + e3 * v + Vector3(0, y, 0)
	var frame := gs.terrace_frame_color
	var deck := gs.terrace_color
	var stone := gs.stepping_stone_color
	var top := h
	var under := top - BOARD

	# --- Ombre sous le plancher -------------------------------------------------
	var shade := gs.pebble_color.darkened(0.55)
	shade.a = 0.5
	mb.add_quad(ROLE_GRAVEL, at.call(0.08, 0.08, 0.012), at.call(l0 - 0.08, 0.08, 0.012), at.call(l0 - 0.08, l3 - 0.08, 0.012),
			at.call(0.08, l3 - 0.08, 0.012), Vector3.UP, shade, shade, shade, shade)

	# --- Poteaux sur pierres, poutres ------------------------------------------------
	var inset := 0.15
	var us := _stations(l0, inset, POST_SPACING)
	var vs := _stations(l3, inset, POST_SPACING)
	var beam_h := 0.15
	var post_top := under - beam_h
	var posts := 0
	for ui in us.size():
		for vi in vs.size():
			var edge := ui == 0 or ui == us.size() - 1 or vi == 0 or vi == vs.size() - 1
			if not edge and (ui + vi) % 2 == 1:
				continue  # à l'intérieur, un poteau sur deux suffit
			var u: float = us[ui]
			var v: float = vs[vi]
			var k := BastideRng.combine(seed, ui * 97 + vi)
			var p: Vector3 = at.call(u, v, 0.0)
			BastideGardenMesher.slab(mb, p, 0.16, 0.08, BastideGardenMesher.h(k, 1) * TAU, k,
					BastideGardenMesher.tint(stone, BastideGardenMesher.hs(k, 2) * 0.06), 6, 1.1)
			var pc := BastideGardenMesher.tint(frame, BastideGardenMesher.hs(k, 3) * 0.05)
			mb.add_block(ROLE_WOOD, _box(at, u - 0.055, u + 0.055, v - 0.055, v + 0.055, 0.06, post_top + 0.01), 0.0, 0.0, pc, pc.darkened(0.1))
			posts += 1
	# Poutres sur chaque file de poteaux, dans les deux sens.
	var beam := frame.darkened(0.05)
	for u: float in us:
		mb.add_block(ROLE_WOOD, _box(at, u - 0.06, u + 0.06, vs[0] - 0.08, vs[vs.size() - 1] + 0.08, post_top, under), 0.0, 0.0, beam, beam)
	for v: float in vs:
		mb.add_block(ROLE_WOOD, _box(at, us[0] - 0.08, us[us.size() - 1] + 0.08, v - 0.06, v + 0.06, post_top, under), 0.0, 0.0, beam, beam)
	# Rive : planche frontale sous le bord du plancher, sur les côtés visibles.
	for si in 4:
		if si == hside:
			continue
		var q := _side_box(at, l0, l3, si, 0.04, 0.0, under - 0.17, under - 0.005)
		mb.add_block(ROLE_WOOD, q, 0.0, 0.0, frame.lightened(0.04), frame)

	# --- Planches -----------------------------------------------------------------------
	# Dans le sens de la façade pour un engawa, du plus long côté sinon.
	var along_u := l0 >= l3
	if hside >= 0:
		along_u = hside == 0 or hside == 2
	var span := l3 if along_u else l0
	var length := l0 if along_u else l3
	var count := maxi(3, roundi(span / 0.165))
	var bw := span / count
	var boards := 0
	for b in count:
		var c0 := b * bw + 0.005
		var c1 := (b + 1) * bw - 0.005
		var first := -1.0
		if length > 3.2:
			first = 0.6 + BastideRng.randf_at(seed, "board_first", b) * 1.8
		var segs := BastideDistributor.split_lengths(seed, "board", b, length, 1.6, 3.2, first)
		var acc := 0.0
		for si in segs.size():
			var a0 := acc + (0.004 if si > 0 else -0.02)
			var a1 := acc + segs[si] - (0.004 if si < segs.size() - 1 else -0.02)
			acc += segs[si]
			var k := BastideRng.combine(BastideRng.combine(seed, b), si)
			var col := BastideGardenMesher.tint(deck, BastideGardenMesher.hs(k, 1) * 0.06)
			var dy := BastideGardenMesher.hs(k, 2) * 0.003
			var box: Array
			if along_u:
				box = _box(at, a0, a1, c0, c1, under, top + dy)
			else:
				box = _box(at, c0, c1, a0, a1, under, top + dy)
			mb.add_block(ROLE_WOOD, box, 0.0, 0.0, col, col.darkened(0.18))
			boards += 1

	# --- Accès -----------------------------------------------------------------------------
	var nrm := BastideTerraceRules.side_normal(rect, esid)
	var sdir := BastidePolyline.flat_dir(rect[esid], rect[(esid + 1) % 4])
	var mid := (rect[esid] + rect[(esid + 1) % 4]) * 0.5
	var sw: float = pl["step_width"]
	if hside >= 0:
		# Engawa : grande pierre de seuil, et parfois une paire de geta dessus.
		var sk := BastideRng.key(seed, "kutsunugi")
		var st_top := minf(0.22, h * 0.5)
		var sp := mid + nrm * 0.46
		BastideGardenMesher.slab(mb, sp, 0.36, st_top, atan2(sdir.z, sdir.x), sk, stone.lightened(0.05), 8, 1.65)
		if with_collision:
			result.add_box(_oriented(sp, sdir, nrm, 0.55, 0.32, 0.0, st_top))
		if gs.terrace_details and BastideRng.unit(BastideRng.combine(sk, 7)) < 0.7:
			for e in [-1.0, 1.0]:
				var gp: Vector3 = sp + sdir * (e * 0.11 + BastideGardenMesher.hs(sk, 8) * 0.04)
				var yaw := BastideGardenMesher.hs(sk, 9 + int(e > 0.0)) * 0.2
				var fwd := nrm.rotated(Vector3.UP, yaw)
				var side := sdir.rotated(Vector3.UP, yaw)
				_geta(mb, gp + Vector3(0, st_top, 0), fwd, side, gs)
	else:
		# Terrasse isolée : marches de bois entre deux limons.
		var risers: int = pl["risers"]
		var run := 0.28
		var rise := h / risers
		for j in range(1, risers):
			var y := h - j * rise
			var a := (j - 1) * run - 0.02
			var b := j * run + 0.03
			var col := BastideGardenMesher.tint(deck, BastideRng.signed_at(seed, "tread", j) * 0.05)
			mb.add_block(ROLE_WOOD, _oriented(mid + nrm * ((a + b) * 0.5), sdir, nrm, sw * 0.5 - 0.06, (b - a) * 0.5, y - 0.045, y), 0.0, 0.0,
					col, col.darkened(0.18))
		var foot := (risers - 1) * run + 0.04
		for e in [-1.0, 1.0]:
			var c: Vector3 = mid + sdir * (e * (sw * 0.5 - 0.02))
			var k := []
			for t in [-0.035, 0.035]:
				var q: Vector3 = c + sdir * t
				k.append_array([q + Vector3(0, under + 0.01, 0), q + nrm * foot + Vector3(0, 0.1, 0),
					q + nrm * (foot - 0.24) + Vector3(0, -0.02, 0), q + Vector3(0, under - 0.26, 0)])
			mb.add_block(ROLE_WOOD, k, 0.0, 0.0, frame, frame.darkened(0.1))
		# Une pierre plate au pied des marches.
		var fk := BastideRng.key(seed, "step_foot")
		BastideGardenMesher.slab(mb, mid + nrm * (foot + 0.32), 0.3, 0.06, atan2(sdir.z, sdir.x), fk, stone, 7, 1.6)
		if with_collision:
			result.add_box(_oriented(mid + nrm * (foot * 0.5), sdir, nrm, sw * 0.5, foot * 0.5, 0.0, h * 0.5))
		if gs.terrace_railing:
			_railing(mb, result, rect, at, l0, l3, hside, esid, sw, h, gs, seed, with_collision)

	if with_collision:
		result.add_box([rect[0], rect[1], rect[2], rect[3],
			rect[0] + Vector3(0, top, 0), rect[1] + Vector3(0, top, 0), rect[2] + Vector3(0, top, 0), rect[3] + Vector3(0, top, 0)])
	result.mesh = mb.commit(BastideGardenMesher.materials(style))
	result.anchors = {"rect": rect, "doors": [pl["door"]], "engawa": hside >= 0, "height": h}
	result.stats = {"triangles": mb.triangle_count, "boards": boards, "posts": posts, "engawa": hside >= 0,
		"entry": esid, "length": snappedf(maxf(l0, l3), 0.01), "depth": snappedf(minf(l0, l3), 0.01)}
	return result


## Abscisses régulières de `inset` à `length - inset`, espacées de `spacing` au plus.
static func _stations(length: float, inset: float, spacing: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var usable := maxf(length - inset * 2.0, 0.0)
	var n := maxi(1, ceili(usable / spacing))
	for i in n + 1:
		out.append(inset + usable * i / n)
	return out


## Bloc droit dans le repère de la terrasse.
static func _box(at: Callable, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float) -> Array:
	return [at.call(u0, v0, y0), at.call(u1, v0, y0), at.call(u1, v1, y0), at.call(u0, v1, y0),
		at.call(u0, v0, y1), at.call(u1, v0, y1), at.call(u1, v1, y1), at.call(u0, v1, y1)]


## Planche le long du côté si, épaisseur `t`, en retrait `back` du bord.
static func _side_box(at: Callable, l0: float, l3: float, si: int, t: float, back: float, y0: float, y1: float) -> Array:
	match si:
		0:
			return _box(at, 0.0, l0, back, back + t, y0, y1)
		1:
			return _box(at, l0 - back - t, l0 - back, 0.0, l3, y0, y1)
		2:
			return _box(at, 0.0, l0, l3 - back - t, l3 - back, y0, y1)
	return _box(at, back, back + t, 0.0, l3, y0, y1)


## Bloc centré en c, demi-largeurs hu (selon `along`) et hv (selon `across`).
static func _oriented(c: Vector3, along: Vector3, across: Vector3, hu: float, hv: float, y0: float, y1: float) -> Array:
	var k := []
	for y in [y0, y1]:
		for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			k.append(c + along * (q.x * hu) + across * (q.y * hv) + Vector3(0, y, 0))
	return k


## Une geta (socque de bois) posée à plat, la pointe vers `fwd`.
static func _geta(mb: BastideMeshBuilder, p: Vector3, fwd: Vector3, side: Vector3, gs: BastideGardenStyle) -> void:
	var wood := gs.terrace_color.lightened(0.1)
	for t in [-0.06, 0.06]:
		mb.add_block(ROLE_WOOD, _oriented(p + fwd * t, side, fwd, 0.045, 0.012, 0.0, 0.035), 0.0, 0.0, wood.darkened(0.2), wood.darkened(0.3))
	mb.add_block(ROLE_WOOD, _oriented(p, side, fwd, 0.05, 0.11, 0.035, 0.058), 0.0, 0.0, wood, wood.darkened(0.15))
	var cord := Color(0.55, 0.12, 0.1)
	mb.add_block(ROLE_PAINT, _oriented(p - fwd * 0.01, side, fwd, 0.04, 0.012, 0.058, 0.075), 0.0, 0.0, cord, cord)
	mb.add_block(ROLE_PAINT, _oriented(p + fwd * 0.055, side, fwd, 0.01, 0.03, 0.058, 0.072), 0.0, 0.0, cord, cord)


## Garde-corps : poteaux réguliers, lisse haute (kasagi) et lisse basse, ouvert au
## droit des marches ; boules de bronze sur les poteaux d'angle et de passage.
static func _railing(mb: BastideMeshBuilder, result: BastideBuildResult, rect: PackedVector3Array, at: Callable,
		l0: float, l3: float, hside: int, esid: int, sw: float, h: float, gs: BastideGardenStyle, seed: int,
		with_collision: bool) -> void:
	var frame := gs.terrace_frame_color
	var rail := frame.lightened(0.05)
	var ins := 0.07
	var y_top := h + RAIL_HEIGHT
	# Côtés dans le repère (u, v) : début, fin.
	var ends := [[Vector2(ins, ins), Vector2(l0 - ins, ins)], [Vector2(l0 - ins, ins), Vector2(l0 - ins, l3 - ins)],
		[Vector2(l0 - ins, l3 - ins), Vector2(ins, l3 - ins)], [Vector2(ins, l3 - ins), Vector2(ins, ins)]]
	var knobs: Array[Vector2] = []
	var posts: Array[Vector2] = []
	for si in 4:
		if si == hside:
			continue
		var a: Vector2 = ends[si][0]
		var b: Vector2 = ends[si][1]
		var length := a.distance_to(b)
		var segs: Array = [[0.0, length]]
		if si == esid:
			var g0 := length * 0.5 - sw * 0.5 - 0.06
			var g1 := length * 0.5 + sw * 0.5 + 0.06
			segs = [[0.0, g0], [g1, length]]
		for sg: Array in segs:
			var s0: float = sg[0]
			var s1: float = sg[1]
			if s1 - s0 < 0.2:
				continue
			var pa := a.lerp(b, s0 / length)
			var pb := a.lerp(b, s1 / length)
			var n := maxi(1, ceili((s1 - s0) / 1.5))
			for i in n + 1:
				var pp := pa.lerp(pb, float(i) / n)
				var dup := false
				for q in posts:
					if q.distance_to(pp) < 0.05:
						dup = true
				if not dup:
					posts.append(pp)
			knobs.append(pa)
			knobs.append(pb)
			# Lisses.
			var d3: Vector3 = (at.call(pb.x, pb.y, 0.0) as Vector3) - (at.call(pa.x, pa.y, 0.0) as Vector3)
			var dir := d3.normalized()
			var across := Vector3(-dir.z, 0, dir.x)
			var c3: Vector3 = ((at.call(pa.x, pa.y, 0.0) as Vector3) + (at.call(pb.x, pb.y, 0.0) as Vector3)) * 0.5
			var half := d3.length() * 0.5
			mb.add_block(ROLE_WOOD, _oriented(c3, dir, across, half + 0.06, 0.055, y_top - 0.02, y_top + 0.035), 0.0, 0.0,
					rail.lightened(0.04), rail.darkened(0.1))
			mb.add_block(ROLE_WOOD, _oriented(c3, dir, across, half, 0.028, h + 0.3, h + 0.36), 0.0, 0.0, rail, rail.darkened(0.1))
			if with_collision:
				result.add_box(_oriented(c3, dir, across, half, 0.06, h, y_top + 0.04))
	for pp in posts:
		var k := BastideRng.combine(seed, roundi(pp.x * 31.0) * 1009 + roundi(pp.y * 31.0))
		var c := BastideGardenMesher.tint(frame, BastideGardenMesher.hs(k, 1) * 0.05)
		mb.add_block(ROLE_WOOD, _box(at, pp.x - 0.045, pp.x + 0.045, pp.y - 0.045, pp.y + 0.045, h - 0.02, y_top - 0.02), 0.0, 0.0,
				c, c.darkened(0.1))
	if gs.giboshi:
		var bronze := gs.giboshi_color
		var done: Array[Vector2] = []
		for pp in knobs:
			var dup := false
			for q in done:
				if q.distance_to(pp) < 0.05:
					dup = true
			if dup:
				continue
			done.append(pp)
			var p: Vector3 = at.call(pp.x, pp.y, 0.0)
			var k := BastideRng.combine(seed, roundi(pp.x * 17.0) * 7919 + roundi(pp.y * 17.0))
			BastideGardenMesher.prism(mb, ROLE_PAINT, p, 0.06, 0.05, y_top + 0.035, y_top + 0.1, 8, bronze.darkened(0.1))
			BastideGardenMesher.blob(mb, ROLE_PAINT, p + Vector3(0, y_top + 0.16, 0), Vector3(0.075, 0.07, 0.075), bronze, k, 4, 8, 0.25, 0.0)
			BastideGardenMesher.prism(mb, ROLE_PAINT, p, 0.035, 0.0, y_top + 0.215, y_top + 0.3, 8, bronze.lightened(0.05))
