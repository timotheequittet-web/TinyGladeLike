@tool
class_name BastidePathMesher
extends RefCounted
## Chemin de jardin : bande de gravier ratissé aux bords irréguliers, pas japonais
## (grandes pierres plates en quinconce), bordure de petites pierres rondes, pierre
## de seuil devant les portes, lanternes de pierre aux extrémités.
##
## plan() applique les règles (raccord aux portes et aux autres chemins, léger
## serpentement) et place les pièces ; build() les dessine.

const ROLE_GRAVEL := BastideGardenMesher.ROLE_GRAVEL


## Plan du chemin : {center, width, stones, edging, lanterns, step_stones, door_start, door_end}.
static func plan(points: PackedVector3Array, seed: int, gs: BastideGardenStyle, ctx: BastideGardenContext,
		width := 0.0) -> Dictionary:
	var w := width if width > 0.0 else gs.path_width
	var out := {"center": PackedVector3Array(), "width": w, "stones": [], "edging": [], "lanterns": [],
		"step_stones": [], "door_start": {}, "door_end": {}}
	if points.size() < 2:
		return out
	if ctx == null:
		ctx = BastideGardenContext.new()
	var snap := BastideGardenRules.snap_path_ends(points, ctx)
	var pts: PackedVector3Array = snap["points"]
	out["door_start"] = snap["door_start"]
	out["door_end"] = snap["door_end"]
	var fixed_s := BastideGardenRules.DOOR_APPROACH - BastideGardenRules.DOOR_GAP + 0.3 if not (snap["door_start"] as Dictionary).is_empty() else 0.0
	var fixed_e := BastideGardenRules.DOOR_APPROACH - BastideGardenRules.DOOR_GAP + 0.3 if not (snap["door_end"] as Dictionary).is_empty() else 0.0
	pts = BastideGardenRules.meander(pts, seed, 0.22 * w / 1.5, fixed_s, fixed_e)
	if pts.size() > 2:
		pts = BastideStroke.smooth(pts, false, 2, 0.25, 0.5)
	var center := BastideStroke.resample(pts, 0.35)
	if center.size() < 2 or BastideStroke.length(center) < 0.6:
		return out
	out["center"] = center
	var cum := BastidePolyline.cumulative(center)
	var total := cum[cum.size() - 1]

	# Pas japonais : pierres en quinconce, espacées d'un pas tranquille.
	if gs.stepping_stones:
		var stride := 0.8 * pow(w / 1.5, 0.3)
		var s := 0.55
		var k := 0
		while s < total - 0.35:
			var at := _at(center, cum, s)
			var p: Vector3 = at[0]
			var dir: Vector3 = at[1]
			var side := BastidePolyline.right_of(dir)
			var zig := (0.07 if k % 2 == 0 else -0.07) * w + BastideRng.signed_at(seed, "stone_off", k) * 0.04
			var q := p + side * zig
			if ctx.path_clearance(Vector2(q.x, q.z)) > 0.15 and ctx.house_clearance(Vector2(q.x, q.z)) > 0.3:
				out["stones"].append({"pos": q, "radius": w * 0.22 * (1.0 + BastideRng.signed_at(seed, "stone_r", k) * 0.12),
					"rot": atan2(dir.z, dir.x) + BastideRng.signed_at(seed, "stone_rot", k) * 0.35, "key": BastideRng.key(seed, "stone", k)})
			s += stride * (1.0 + BastideRng.signed_at(seed, "stride", k) * 0.1)
			k += 1

	# Pierres de seuil devant les portes rejointes (kutsunugi-ishi).
	for key in ["door_start", "door_end"]:
		var door: Dictionary = out[key]
		if door.is_empty():
			continue
		var dpos: Vector3 = door["pos"]
		var dout: Vector3 = door["out"]
		var sp := dpos + dout * 0.82
		sp.y = center[0].y
		out["step_stones"].append({"pos": sp, "rot": atan2(dout.z, dout.x) + PI * 0.5, "key": BastideRng.key(seed, key)})

	# Bordure : petites pierres rondes de chaque côté.
	if gs.path_edging:
		for side_sign: float in [-1.0, 1.0]:
			var s := 0.15
			var k := 0
			while s < total - 0.1:
				var at := _at(center, cum, s)
				var p: Vector3 = at[0]
				var side := BastidePolyline.right_of(at[1]) * side_sign
				var hw := _half_width(seed, w, s, side_sign)
				var q := p + side * (hw + 0.05)
				var q2 := Vector2(q.x, q.z)
				var ok := ctx.path_clearance(q2) > 0.08 and ctx.house_clearance(q2) > 0.15 and ctx.wall_clearance(q2) > 0.05
				# Pas de bordure en travers de l'arrivée sur une porte.
				for key in ["door_start", "door_end"]:
					var door: Dictionary = out[key]
					if not door.is_empty() and q.distance_to(door["pos"]) < 1.25:
						ok = false
				if ok:
					out["edging"].append({"pos": q, "key": BastideRng.key(seed, "edge%d" % int(side_sign), k)})
				s += 0.26 + BastideRng.randf_at(seed, "edge_gap", k) * 0.08
				k += 1

	# Lanternes : une à chaque arrivée sur une porte ; à défaut, une au départ.
	if gs.lanterns and total > 4.0:
		var ends: Array = []
		if not (out["door_start"] as Dictionary).is_empty():
			ends.append(0)
		if not (out["door_end"] as Dictionary).is_empty():
			ends.append(1)
		if ends.is_empty() and not snap["join_start"]:
			ends.append(0)
		elif ends.is_empty() and not snap["join_end"]:
			ends.append(1)
		for e: int in ends:
			var s := 0.7 if e == 0 else total - 0.7
			var at := _at(center, cum, s)
			var p: Vector3 = at[0]
			var dir: Vector3 = at[1]
			var first := 1.0 if BastideRng.randf_at(seed, "lantern_side", e) > 0.5 else -1.0
			for side_sign: float in [first, -first]:
				var q: Vector3 = p + BastidePolyline.right_of(dir) * side_sign * (w * 0.5 + 0.75)
				var q2 := Vector2(q.x, q.z)
				if ctx.house_clearance(q2) > 0.5 and ctx.path_clearance(q2) > 0.45 and ctx.wall_clearance(q2) > 0.4 \
						and ctx.gate_clearance(q2) > 0.8:
					out["lanterns"].append({"pos": q, "rot": atan2(dir.z, dir.x), "key": BastideRng.key(seed, "lantern", e)})
					break
	return out


## Demi-largeur au point s : les bords ondulent un peu, chaque côté à sa façon.
static func _half_width(seed: int, w: float, s: float, side_sign: float) -> float:
	var n := BastideRng.noise1(seed, "edge_l" if side_sign < 0.0 else "edge_r", s / 1.4)
	return w * 0.5 * (1.0 + (n * 2.0 - 1.0) * 0.08)


## Point et direction à l'abscisse s.
static func _at(pts: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Array:
	s = clampf(s, 0.0, cum[cum.size() - 1])
	var i := cum.bsearch(s)
	i = clampi(i, 1, pts.size() - 1)
	var a := pts[i - 1]
	var b := pts[i]
	var seg := cum[i] - cum[i - 1]
	var t := (s - cum[i - 1]) / seg if seg > 1e-6 else 0.0
	var dir := BastidePolyline.flat_dir(a, b)
	if dir == Vector3.ZERO:
		dir = Vector3.RIGHT
	return [a.lerp(b, t), dir]


static func build(points: PackedVector3Array, seed: int, style: BastideStyle, ctx: BastideGardenContext,
		with_collision := true, width := 0.0) -> BastideBuildResult:
	var result := BastideBuildResult.new()
	var gs := style.get_garden_style()
	var pl := plan(points, seed, gs, ctx, width)
	var center: PackedVector3Array = pl["center"]
	if center.size() < 2:
		return result
	var w: float = pl["width"]
	var mb := BastideMeshBuilder.new()
	var cum := BastidePolyline.cumulative(center)
	# Chaque chemin a sa propre hauteur (au demi-centimètre) : deux chemins qui se
	# croisent ne se disputent jamais le même plan.
	var y := 0.022 + float(posmod(seed, 6)) * 0.005
	var gravel := gs.path_color
	var lefts := PackedVector3Array()
	var rights := PackedVector3Array()
	for i in center.size():
		var a := center[maxi(i - 1, 0)]
		var b := center[mini(i + 1, center.size() - 1)]
		var side := BastidePolyline.right_of(BastidePolyline.flat_dir(a, b))
		var p := center[i] + Vector3(0, y, 0)
		lefts.append(p - side * _half_width(seed, w, cum[i], -1.0))
		rights.append(p + side * _half_width(seed, w, cum[i], 1.0))
	for i in center.size() - 1:
		var tone := 1.0 + (BastideRng.noise1(seed, "gravel_tone", cum[i] / 3.0) - 0.5) * 0.08
		var col := Color(gravel.r * tone, gravel.g * tone, gravel.b * tone, 0.0)
		var col_r := Color(col.r, col.g, col.b, 1.0)
		mb.add_quad(ROLE_GRAVEL, lefts[i], lefts[i + 1], rights[i + 1], rights[i], Vector3.UP, col, col, col_r, col_r)
		if with_collision:
			result.add_box([lefts[i] - Vector3(0, y, 0), lefts[i + 1] - Vector3(0, y, 0), rights[i + 1] - Vector3(0, y, 0),
				rights[i] - Vector3(0, y, 0), lefts[i] + Vector3(0, 0.05, 0), lefts[i + 1] + Vector3(0, 0.05, 0),
				rights[i + 1] + Vector3(0, 0.05, 0), rights[i] + Vector3(0, 0.05, 0)])
	# Bouts arrondis.
	for e in 2:
		var i := 0 if e == 0 else center.size() - 1
		var p := center[i] + Vector3(0, y, 0)
		var l := lefts[i]
		var r := rights[i]
		var dir := BastidePolyline.flat_dir(center[1], center[0]) if e == 0 \
				else BastidePolyline.flat_dir(center[center.size() - 2], center[center.size() - 1])
		var col := Color(gravel.r, gravel.g, gravel.b, 0.0)
		var steps := 6
		var prev := l if e == 0 else r
		for k in range(1, steps + 1):
			var t := PI * k / steps
			var radius := (l - p).length()
			var q: Vector3
			if e == 0:
				q = p + ((l - p) * cos(t) + dir * radius * sin(t))
			else:
				q = p + ((r - p) * cos(t) + dir * radius * sin(t))
			mb.add_tri(ROLE_GRAVEL, p, prev, q, Vector3.UP, col, col, col)
			prev = q
	for st: Dictionary in pl["stones"]:
		BastideGardenMesher.slab(mb, st["pos"], st["radius"], 0.075, st["rot"], st["key"],
				BastideGardenMesher.tint(gs.stepping_stone_color, BastideGardenMesher.hs(st["key"], 3) * 0.06), 7, 1.25)
	for st: Dictionary in pl["step_stones"]:
		BastideGardenMesher.slab(mb, st["pos"], 0.4, 0.2, st["rot"], st["key"], gs.stepping_stone_color.lightened(0.04), 8, 1.7)
	for e: Dictionary in pl["edging"]:
		var k: int = e["key"]
		var sz := Vector3(0.11 + BastideGardenMesher.h(k, 1) * 0.06, 0.07 + BastideGardenMesher.h(k, 2) * 0.04,
				0.09 + BastideGardenMesher.h(k, 3) * 0.04)
		BastideGardenMesher.rock(mb, e["pos"], sz, k, BastideGardenMesher.tint(gs.edging_color, BastideGardenMesher.hs(k, 4) * 0.08), 3, 6, 0.25)
	for l: Dictionary in pl["lanterns"]:
		BastideGardenMesher.lantern(mb, l["pos"], l["rot"], 1.0, gs.lantern_color, l["key"])
		if with_collision:
			var p: Vector3 = l["pos"]
			result.add_box([p + Vector3(-0.3, 0, -0.3), p + Vector3(0.3, 0, -0.3), p + Vector3(0.3, 0, 0.3), p + Vector3(-0.3, 0, 0.3),
				p + Vector3(-0.3, 1.6, -0.3), p + Vector3(0.3, 1.6, -0.3), p + Vector3(0.3, 1.6, 0.3), p + Vector3(-0.3, 1.6, 0.3)])
	result.mesh = mb.commit(BastideGardenMesher.materials(style))
	result.anchors = {"center": center, "width": w}
	result.stats = {"triangles": mb.triangle_count, "length": snappedf(cum[cum.size() - 1], 0.01),
		"stones": (pl["stones"] as Array).size(), "lanterns": (pl["lanterns"] as Array).size(),
		"doors": int(not (pl["door_start"] as Dictionary).is_empty()) + int(not (pl["door_end"] as Dictionary).is_empty())}
	return result
