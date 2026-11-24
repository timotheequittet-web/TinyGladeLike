@tool
class_name BastideFenceMesher
extends RefCounted
## Petites clôtures de jardin le long d'un tracé :
## - STONE : muret bas de pierres sèches arrondies, assises décalées, pierres de
##   couronnement plus larges, grandes pierres dressées aux extrémités ;
## - BAMBOO : clôture de bambou à claire-voie (yotsume-gaki) : poteaux réguliers,
##   lisses horizontales, bambous verticaux en quinconce, liens de corde noire.
##
## Règles : la clôture s'ouvre là où un chemin la traverse (deux poteaux de portail
## encadrent le passage) ; poteaux répartis en nombre entier sur chaque tronçon,
## jamais de bout de travée ridicule.

const ROLE_STONE := BastideGardenMesher.ROLE_STONE
const ROLE_WOOD := BastideGardenMesher.ROLE_WOOD


static func build(points: PackedVector3Array, closed: bool, variant: int, seed: int, style: BastideStyle,
		ctx: BastideGardenContext, with_collision := true, height := 0.0) -> BastideBuildResult:
	var result := BastideBuildResult.new()
	if points.size() < 2:
		return result
	var gs := style.get_garden_style()
	var cum := BastidePolyline.cumulative(points)
	var total := cum[cum.size() - 1]
	if closed:
		total += BastidePolyline.flat_dist(points[points.size() - 1], points[0])
	if total < 0.6:
		return result
	var openings := BastideGardenRules.fence_openings(points, closed, ctx)
	var runs := _runs(openings, total, closed)
	var mb := BastideMeshBuilder.new()
	var stone := variant == BastideGardenStyle.FenceKind.STONE
	var h := height if height > 0.0 else (gs.stone_fence_height if stone else gs.bamboo_fence_height)
	for ri in runs.size():
		var run: Dictionary = runs[ri]
		if run["s1"] - run["s0"] < 0.35:
			continue
		if stone:
			_stone_run(mb, result, points, cum, total, closed, run, h, gs, BastideRng.combine(seed, ri), with_collision)
		else:
			_bamboo_run(mb, result, points, cum, total, closed, run, h, gs, BastideRng.combine(seed, ri), with_collision)
	result.mesh = mb.commit(BastideGardenMesher.materials(style))
	result.stats = {"triangles": mb.triangle_count, "openings": openings.size(), "runs": runs.size()}
	return result


## Tronçons pleins entre les ouvertures : {s0, s1, gate0, gate1, loop}.
static func _runs(openings: Array[Vector2], total: float, closed: bool) -> Array:
	var runs: Array = []
	if openings.is_empty():
		return [{"s0": 0.0, "s1": total, "gate0": false, "gate1": false, "loop": closed}]
	if closed:
		for i in openings.size():
			var a: float = openings[i].y
			var b: float = openings[(i + 1) % openings.size()].x
			if i == openings.size() - 1:
				b += total
			runs.append({"s0": a, "s1": b, "gate0": true, "gate1": true, "loop": false})
		return runs
	var s := 0.0
	var gate := false
	for o in openings:
		if o.x > s:
			runs.append({"s0": s, "s1": minf(o.x, total), "gate0": gate, "gate1": true, "loop": false})
		s = maxf(s, o.y)
		gate = true
	if s < total:
		runs.append({"s0": s, "s1": total, "gate0": gate, "gate1": false, "loop": false})
	return runs


## Point et direction à l'abscisse s (enceinte fermée : s modulo le tour).
static func _at(points: PackedVector3Array, cum: PackedFloat32Array, total: float, closed: bool, s: float) -> Array:
	var n := points.size()
	if closed:
		s = fposmod(s, total)
		var last := cum[n - 1]
		if s > last:
			var t := (s - last) / maxf(total - last, 1e-6)
			var a := points[n - 1]
			var b := points[0]
			return [a.lerp(b, t), BastidePolyline.flat_dir(a, b)]
	s = clampf(s, 0.0, cum[n - 1])
	var i := clampi(cum.bsearch(s), 1, n - 1)
	var a := points[i - 1]
	var b := points[i]
	var seg := cum[i] - cum[i - 1]
	var t := (s - cum[i - 1]) / seg if seg > 1e-6 else 0.0
	var dir := BastidePolyline.flat_dir(a, b)
	return [a.lerp(b, t), dir if dir != Vector3.ZERO else Vector3.RIGHT]


# --- Pierres sèches -----------------------------------------------------------------

static func _stone_run(mb: BastideMeshBuilder, result: BastideBuildResult, points: PackedVector3Array,
		cum: PackedFloat32Array, total: float, closed: bool, run: Dictionary, h: float,
		gs: BastideGardenStyle, key: int, with_collision: bool) -> void:
	var s0: float = run["s0"]
	var s1: float = run["s1"]
	var base_t := 0.27  # demi-épaisseur au pied
	var top_t := 0.21
	var mortar := gs.fence_stone_color.darkened(0.45)
	# Grandes pierres dressées aux bouts (portail ou fin de muret).
	var post_len := 0.4
	var inner0 := s0 + (post_len if not run["loop"] else 0.0)
	var inner1 := s1 - (post_len if not run["loop"] else 0.0)
	if not run["loop"]:
		for e in 2:
			var gate: bool = run["gate0"] if e == 0 else run["gate1"]
			var a := s0 if e == 0 else s1 - post_len
			var ph := h + (0.28 if gate else 0.12)
			var pk := BastideRng.combine(key, 900 + e)
			_stone(mb, points, cum, total, closed, a + 0.02, a + post_len - 0.02, 0.0, ph, base_t + 0.03, base_t - 0.02,
					BastideGardenMesher.tint(gs.fence_stone_color, BastideGardenMesher.hs(pk, 1) * 0.06), mortar, 0.05)
	var courses := 2 if h < 0.75 else 3
	var cap_h := minf(0.16, h * 0.25)
	var body_h := h - cap_h
	for c in courses:
		var y0 := body_h * c / courses
		var y1 := body_h * (c + 1) / courses
		var t0 := lerpf(base_t, top_t, y0 / h)
		var t1 := lerpf(base_t, top_t, y1 / h)
		var s := inner0 - (0.0 if c % 2 == 0 else 0.22)
		var k := 0
		while s < inner1 - 0.05:
			var sk := BastideRng.combine(key, c * 1000 + k)
			var length := 0.3 + BastideGardenMesher.h(sk, 1) * 0.26
			var a := maxf(s, inner0)
			var b := minf(s + length, inner1)
			if b - a > 0.08:
				var col := BastideGardenMesher.tint(gs.fence_stone_color, BastideGardenMesher.hs(sk, 2) * 0.09)
				var bulge := BastideGardenMesher.hs(sk, 4) * 0.035
				_stone(mb, points, cum, total, closed, a + 0.025, b - 0.025, y0 + 0.015 + maxf(BastideGardenMesher.hs(sk, 5), 0.0) * 0.03,
						y1 - 0.015 + BastideGardenMesher.hs(sk, 3) * 0.035, t0 + 0.01 + bulge, t1 + bulge, col, mortar, 0.08, 0.05)
			s += length
			k += 1
	# Couronnement : pierres plus longues, un peu plus larges, moussues.
	var s := inner0
	var k := 0
	while s < inner1 - 0.05:
		var sk := BastideRng.combine(key, 5000 + k)
		var length := 0.42 + BastideGardenMesher.h(sk, 1) * 0.3
		var b := minf(s + length, inner1)
		var col := BastideGardenMesher.tint(gs.fence_stone_color.lerp(Color(0.45, 0.5, 0.36), 0.18), BastideGardenMesher.hs(sk, 2) * 0.07)
		_stone(mb, points, cum, total, closed, s + 0.02, b - 0.02, body_h, h + BastideGardenMesher.hs(sk, 3) * 0.04,
				top_t + 0.04 + BastideGardenMesher.hs(sk, 4) * 0.03, top_t + BastideGardenMesher.hs(sk, 5) * 0.03, col, mortar, 0.07, 0.04)
		s += length
		k += 1
	if with_collision:
		_collision(result, points, cum, total, closed, s0, s1, h, base_t)


## Une pierre entre les abscisses a et b, de la hauteur y0 à y1, demi-épaisseurs
## t0 (bas) et t1 (haut).
static func _stone(mb: BastideMeshBuilder, points: PackedVector3Array, cum: PackedFloat32Array, total: float,
		closed: bool, a: float, b: float, y0: float, y1: float, t0: float, t1: float, col: Color, edge: Color, bevel: float,
		bulge := 0.025) -> void:
	var pa: Array = _at(points, cum, total, closed, a)
	var pb: Array = _at(points, cum, total, closed, b)
	var sa := BastidePolyline.right_of(pa[1])
	var sb := BastidePolyline.right_of(pb[1])
	var A: Vector3 = pa[0]
	var B: Vector3 = pb[0]
	var k := [A - sa * t0 + Vector3(0, y0, 0), B - sb * t0 + Vector3(0, y0, 0), B + sb * t0 + Vector3(0, y0, 0), A + sa * t0 + Vector3(0, y0, 0),
		A - sa * t1 + Vector3(0, y1, 0), B - sb * t1 + Vector3(0, y1, 0), B + sb * t1 + Vector3(0, y1, 0), A + sa * t1 + Vector3(0, y1, 0)]
	mb.add_block(ROLE_STONE, k, minf(bevel, minf((b - a) * 0.3, (y1 - y0) * 0.3)), bulge, col, edge)


static func _collision(result: BastideBuildResult, points: PackedVector3Array, cum: PackedFloat32Array, total: float,
		closed: bool, s0: float, s1: float, h: float, t: float) -> void:
	var steps := maxi(1, ceili((s1 - s0) / 1.0))
	for i in steps:
		var a: Array = _at(points, cum, total, closed, lerpf(s0, s1, float(i) / steps))
		var b: Array = _at(points, cum, total, closed, lerpf(s0, s1, float(i + 1) / steps))
		var sa := BastidePolyline.right_of(a[1]) * t
		var sb := BastidePolyline.right_of(b[1]) * t
		var A: Vector3 = a[0]
		var B: Vector3 = b[0]
		var up := Vector3(0, h, 0)
		result.add_box([A - sa, B - sb, B + sb, A + sa, A - sa + up, B - sb + up, B + sb + up, A + sa + up])


# --- Bambou --------------------------------------------------------------------------

static func _bamboo_run(mb: BastideMeshBuilder, result: BastideBuildResult, points: PackedVector3Array,
		cum: PackedFloat32Array, total: float, closed: bool, run: Dictionary, h: float,
		gs: BastideGardenStyle, key: int, with_collision: bool) -> void:
	var s0: float = run["s0"]
	var s1: float = run["s1"]
	var length := s1 - s0
	var bamboo := gs.bamboo_color
	var post_col := bamboo.darkened(0.12)
	var gate_col := gs.trunk_color.darkened(0.1)
	var cord := gs.cord_color
	var count := maxi(1, roundi(length / 1.6))
	var loop: bool = run["loop"]
	var rails := 3 if h > 0.9 else 2
	var rail_y := PackedFloat32Array()
	for r in rails:
		rail_y.append(h * (0.28 + 0.6 * r / maxf(rails - 1, 1)))
	# Poteaux.
	var post_s := PackedFloat32Array()
	for i in (count if loop else count + 1):
		post_s.append(s0 + length * i / count)
	for i in post_s.size():
		var at: Array = _at(points, cum, total, closed, post_s[i])
		var p: Vector3 = at[0]
		var gate: bool = (i == 0 and run["gate0"]) or (i == post_s.size() - 1 and run["gate1"] and not loop)
		if gate:
			# Poteau de portail : bois sombre, plus haut, petit chapeau.
			var side := BastidePolyline.right_of(at[1])
			var gk := BastideRng.combine(key, 700 + i)
			var hp := h + 0.3
			var k := []
			for yy in [-0.05, hp]:
				for c2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					k.append(p + (at[1] as Vector3) * (c2.x * 0.07) + side * (c2.y * 0.07) + Vector3(0, yy, 0))
			mb.add_block(ROLE_WOOD, k, 0.0, 0.0, BastideGardenMesher.tint(gate_col, BastideGardenMesher.hs(gk, 1) * 0.05), gate_col)
			BastideGardenMesher.prism(mb, ROLE_WOOD, p, 0.12, 0.02, hp, hp + 0.1, 4, gate_col.darkened(0.2), atan2((at[1] as Vector3).z, (at[1] as Vector3).x) + PI * 0.25, true, true)
		else:
			BastideGardenMesher.bamboo_pole(mb, p + Vector3(0, -0.05, 0), p + Vector3(0, h + 0.05, 0), 0.042,
					BastideGardenMesher.tint(post_col, BastideGardenMesher.hs(key, 100 + i) * 0.05), BastideRng.combine(key, 100 + i), 0.5)
		# Liens de corde sur chaque lisse.
		for r in rails:
			var y := rail_y[r]
			BastideGardenMesher.tube(mb, ROLE_WOOD, p + Vector3(0, y - 0.03, 0), p + Vector3(0, y + 0.03, 0), 0.058, 0.058, cord, 6, 0.0)
	# Lisses horizontales, une sur deux devant puis derrière les montants.
	var step := 0.5
	var nseg := maxi(1, ceili(length / step))
	for r in rails:
		var off := 0.05 if r % 2 == 0 else -0.05
		for i in nseg:
			var a: Array = _at(points, cum, total, closed, s0 + length * i / nseg)
			var b: Array = _at(points, cum, total, closed, s0 + length * (i + 1) / nseg)
			var pa: Vector3 = (a[0] as Vector3) + BastidePolyline.right_of(a[1]) * off + Vector3(0, rail_y[r], 0)
			var pb: Vector3 = (b[0] as Vector3) + BastidePolyline.right_of(b[1]) * off + Vector3(0, rail_y[r], 0)
			BastideGardenMesher.tube(mb, ROLE_WOOD, pa, pb, 0.022, 0.022,
					BastideGardenMesher.tint(bamboo, BastideGardenMesher.hs(key, 300 + r * 97 + i) * 0.04), 6, 0.0)
	# Bambous verticaux en quinconce (devant / derrière les lisses), entre les poteaux.
	var gap := 0.27
	var nslat := maxi(0, floori(length / gap))
	for i in range(1, nslat):
		var s := s0 + length * i / nslat
		var near_post := false
		for ps in post_s:
			if absf(s - ps) < 0.1:
				near_post = true
		if near_post:
			continue
		var at: Array = _at(points, cum, total, closed, s)
		var sk := BastideRng.combine(key, 2000 + i)
		var off := (0.0 if i % 2 == 0 else 0.0)
		var p: Vector3 = (at[0] as Vector3) + BastidePolyline.right_of(at[1]) * off
		var top := h - 0.04 + BastideGardenMesher.hs(sk, 1) * 0.03
		BastideGardenMesher.bamboo_pole(mb, p + Vector3(0, -0.03, 0), p + Vector3(0, top, 0), 0.02,
				BastideGardenMesher.tint(bamboo, BastideGardenMesher.hs(sk, 2) * 0.06), sk, 0.42)
	if with_collision:
		_collision(result, points, cum, total, closed, s0, s1, h, 0.08)
