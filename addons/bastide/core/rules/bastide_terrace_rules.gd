@tool
class_name BastideTerraceRules
extends RefCounted
## Règles « toujours beau » des terrasses de bois, en fonctions pures.
##
## - Une terrasse est toujours un rectangle (on redresse ce qu'on a tracé).
## - Tirée contre une maison, elle devient un engawa : collée à la façade, de la
##   profondeur d'une galerie (0,9 à 2,4 m), sans dépasser les angles, et jamais
##   devant la porte (elle s'arrête avant, du côté le plus long).
## - Ses marches (ou sa pierre de seuil) donnent du côté opposé à la maison ; sur
##   une terrasse isolée, du côté de la porte la plus proche.

## Distance façade ↔ bord de la terrasse en dessous de laquelle elle s'y colle.
const HOUSE_SNAP := 1.4
## Jour laissé entre la façade et le plancher (le soubassement dépasse un peu).
const HOUSE_GAP := 0.06
const ENGAWA_MIN_DEPTH := 0.9
const ENGAWA_MAX_DEPTH := 2.4
## Espace laissé libre de part et d'autre d'une porte.
const DOOR_CLEAR := 0.55


## Rectangle orienté qui épouse un tracé : axe du premier côté, emprise de tous
## les points. Toujours dans le sens direct (aire signée positive sur XZ).
static func fit_rect(points: PackedVector3Array) -> PackedVector3Array:
	if points.size() < 2:
		return PackedVector3Array()
	var u := Vector3(points[1].x - points[0].x, 0.0, points[1].z - points[0].z)
	if u.length() < 1e-4:
		u = Vector3.RIGHT
	u = u.normalized()
	var v := Vector3(-u.z, 0.0, u.x)
	var o := points[0]
	var umin := INF
	var umax := -INF
	var vmin := INF
	var vmax := -INF
	for p in points:
		var d := p - o
		umin = minf(umin, d.dot(u))
		umax = maxf(umax, d.dot(u))
		vmin = minf(vmin, d.dot(v))
		vmax = maxf(vmax, d.dot(v))
	if vmax - vmin < 0.5:
		vmax = vmin + 0.5
	if umax - umin < 0.5:
		umax = umin + 0.5
	var pts := PackedVector3Array([o + u * umin + v * vmin, o + u * umax + v * vmin, o + u * umax + v * vmax, o + u * umin + v * vmax])
	for i in 4:
		pts[i].y = o.y
	return BastideStroke.ensure_direct(pts)


## Normale sortante du côté i d'un rectangle direct.
static func side_normal(rect: PackedVector3Array, i: int) -> Vector3:
	var d := BastidePolyline.flat_dir(rect[i], rect[(i + 1) % rect.size()])
	return Vector3(d.z, 0.0, -d.x)


## Façade de maison contre laquelle le rectangle est tiré : {house, edge, side, p, t, n, len}
## (side = côté du rectangle qui touche), ou {} s'il n'y en a pas.
static func find_facade(rect: PackedVector3Array, ctx: BastideGardenContext, snap := HOUSE_SNAP) -> Dictionary:
	if ctx == null or rect.size() != 4:
		return {}
	var c := BastideStroke.centroid(rect)
	var c2 := Vector2(c.x, c.z)
	var best := {}
	var best_score := INF
	for hi in ctx.houses.size():
		var h: Dictionary = ctx.houses[hi]
		var fp: PackedVector2Array = h["footprint"]
		if Geometry2D.is_point_in_polygon(c2, fp):
			continue
		for ei in fp.size():
			var p := fp[ei]
			var q := fp[(ei + 1) % fp.size()]
			var length := p.distance_to(q)
			if length < 1.8:
				continue
			var t := (q - p) / length
			var n := Vector2(t.y, -t.x)  # sortante (contour direct)
			if (c2 - p).dot(n) < 0.3:
				continue
			for si in 4:
				var a3 := rect[si]
				var b3 := rect[(si + 1) % 4]
				var a := Vector2(a3.x, a3.z)
				var b := Vector2(b3.x, b3.z)
				var sd := (b - a).normalized()
				if absf(sd.dot(t)) < 0.96:
					continue
				var m := (a + b) * 0.5
				var dist := (m - p).dot(n)
				if dist < -1.0 or dist > snap:
					continue
				# Recouvrement le long de la façade.
				var ua := (a - p).dot(t)
				var ub := (b - p).dot(t)
				var overlap := minf(maxf(ua, ub), length) - maxf(minf(ua, ub), 0.0)
				if overlap < 0.9:
					continue
				var score := absf(dist - HOUSE_GAP) + (1.0 - absf(sd.dot(t))) * 10.0
				if score < best_score:
					best_score = score
					best = {"house": hi, "edge": ei, "side": si, "p": p, "t": t, "n": n, "len": length}
	return best


## Direction de la façade de maison la plus proche de p (à moins de `radius` m),
## pour aligner une terrasse qu'on commence à tirer. Vector3.ZERO s'il n'y en a pas.
static func facade_axis(p: Vector3, ctx: BastideGardenContext, radius := 3.0) -> Vector3:
	if ctx == null:
		return Vector3.ZERO
	var q := Vector2(p.x, p.z)
	var best := Vector3.ZERO
	var best_d := radius
	for h: Dictionary in ctx.houses:
		var fp: PackedVector2Array = h["footprint"]
		for i in fp.size():
			var a := fp[i]
			var b := fp[(i + 1) % fp.size()]
			var d := q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b))
			if d < best_d:
				best_d = d
				var t := (b - a).normalized()
				best = Vector3(t.x, 0.0, t.y)
	return best


## Colle un rectangle tiré près d'une maison contre sa façade (engawa).
## Renvoie {points, engawa (bool)}.
static func snap_to_house(rect: PackedVector3Array, ctx: BastideGardenContext, snap := HOUSE_SNAP) -> Dictionary:
	var f := find_facade(rect, ctx, snap)
	if f.is_empty():
		return {"points": rect, "engawa": false}
	var p: Vector2 = f["p"]
	var t: Vector2 = f["t"]
	var n: Vector2 = f["n"]
	var length: float = f["len"]
	var umin := INF
	var umax := -INF
	var depth := 0.0
	for q3 in rect:
		var q := Vector2(q3.x, q3.z)
		umin = minf(umin, (q - p).dot(t))
		umax = maxf(umax, (q - p).dot(t))
		depth = maxf(depth, (q - p).dot(n))
	var margin := 0.2
	umin = clampf(snappedf(umin, 0.25), margin, length - margin)
	umax = clampf(snappedf(umax, 0.25), margin, length - margin)
	depth = clampf(snappedf(depth - HOUSE_GAP, 0.15), ENGAWA_MIN_DEPTH, ENGAWA_MAX_DEPTH)
	# Jamais devant une porte de cette façade : on garde le plus long côté.
	var h: Dictionary = ctx.houses[f["house"]]
	for door: Dictionary in h["doors"]:
		var dp: Vector3 = door["pos"]
		var d2 := Vector2(dp.x, dp.z)
		if absf((d2 - p).dot(n)) > 0.4:
			continue
		var du := (d2 - p).dot(t)
		var hw: float = float(door.get("width", 1.5)) * 0.5 + DOOR_CLEAR
		if umax <= du - hw or umin >= du + hw:
			continue
		var left := (du - hw) - umin
		var right := umax - (du + hw)
		if maxf(left, right) < 1.2:
			return {"points": rect, "engawa": false}
		if left >= right:
			umax = du - hw
		else:
			umin = du + hw
	if umax - umin < 1.2:
		return {"points": rect, "engawa": false}
	var y := rect[0].y
	var g := HOUSE_GAP
	var corners: Array[Vector2] = [p + t * umin + n * g, p + t * umax + n * g, p + t * umax + n * (g + depth), p + t * umin + n * (g + depth)]
	var out := PackedVector3Array()
	for cc in corners:
		out.append(Vector3(cc.x, y, cc.y))
	out = BastideStroke.ensure_direct(out)
	# Même ordre d'angles que le rectangle tiré : les numéros de côtés (marches)
	# gardent leur sens.
	var first := 0
	for i in 4:
		if out[i].distance_to(rect[0]) < out[first].distance_to(rect[0]):
			first = i
	var rot := PackedVector3Array()
	for i in 4:
		rot.append(out[(first + i) % 4])
	return {"points": rot, "engawa": true}


## Côté du rectangle collé à une façade (-1 s'il n'y en a pas), à 0,35 m près.
static func house_side(rect: PackedVector3Array, ctx: BastideGardenContext) -> int:
	var f := find_facade(rect, ctx, HOUSE_GAP + 0.35)
	return int(f["side"]) if not f.is_empty() else -1


## Côté des marches : `wanted` s'il est valable, sinon à l'opposé de la maison
## (engawa), sinon face à la porte la plus proche, sinon le premier grand côté.
static func entry_side(rect: PackedVector3Array, ctx: BastideGardenContext, hside: int, wanted := -1) -> int:
	if wanted >= 0 and wanted < 4 and wanted != hside:
		return wanted
	if hside >= 0:
		return (hside + 2) % 4
	var c := BastideStroke.centroid(rect)
	var best_door := {}
	var best_d := 30.0
	if ctx != null:
		for d: Dictionary in ctx.doors():
			var dp: Vector3 = d["pos"]
			var dd := Vector2(dp.x - c.x, dp.z - c.z).length()
			if dd < best_d:
				best_d = dd
				best_door = d
	if not best_door.is_empty():
		var to := (best_door["pos"] as Vector3) - c
		to.y = 0.0
		var best := 0
		var best_dot := -INF
		for i in 4:
			var dot := side_normal(rect, i).dot(to.normalized())
			if dot > best_dot:
				best_dot = dot
				best = i
		return best
	# Le plus long côté (le premier en cas d'égalité).
	return 0 if rect[0].distance_to(rect[1]) >= rect[1].distance_to(rect[2]) - 0.01 else 1
