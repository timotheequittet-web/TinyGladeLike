@tool
class_name BastideWildScatter
extends RefCounted
## Lisière sauvage : où poussent les fleurs des champs, fougères et hautes herbes
## qui rendent le sol moins « tondu ». Calcul pur, à partir du voisinage des
## constructions (BastideGardenContext, en coordonnées du chantier).
##
## - edges() : le long des chemins (les fleurs débordent un peu sur les dalles),
##   au pied des murets et des clôtures ;
## - meadow() : quelques touffes éparses dans la prairie autour d'un point (la
##   caméra), tirées par case de la grille : elles ne bougent pas quand on se déplace.
##
## Chaque plante : [sorte (KINDS), position xz (Vector2), angle, teinte (Color)].
## La hauteur du sol est posée par le nœud (BastideWildEdge).

enum { MEADOW, MEADOW_SMALL, FERN, TALL, FLOWER }
const KINDS := [MEADOW, MEADOW_SMALL, FERN, TALL, FLOWER]

## Teintes des touffes fleuries (la texture « meadow » a déjà ses marguerites) :
## blanc, chaud, rosé, mauve, jaune.
const BLOOM_TINTS := [Color(1, 1, 1), Color(1.0, 0.88, 0.72), Color(1.0, 0.82, 0.86), Color(0.86, 0.84, 1.0),
	Color(1.0, 0.96, 0.7)]
const FLOWER_TINTS := [Color(1.0, 0.75, 0.82), Color(0.82, 0.72, 1.0), Color(1.0, 0.95, 0.85), Color(1.0, 0.8, 0.5)]


static func _h(a: int, b: int, c: int) -> float:
	var n := a * 73856093 ^ b * 19349663 ^ c * 83492791
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0


static func _tint(kind: int, roll: float) -> Color:
	match kind:
		MEADOW, MEADOW_SMALL:
			return BLOOM_TINTS[int(roll * BLOOM_TINTS.size()) % BLOOM_TINTS.size()]
		FLOWER:
			return FLOWER_TINTS[int(roll * FLOWER_TINTS.size()) % FLOWER_TINTS.size()]
		TALL:
			return Color(1.0, 1.0, 0.85).lerp(Color(1.08, 0.98, 0.72), roll)
		_:
			return Color(1.0, 1.0, 1.0).lerp(Color(0.9, 1.0, 0.82), roll)


## Plantes au bord des chemins, des murets et des clôtures.
static func edges(ctx: BastideGardenContext, seed: int, density := 1.0) -> Array:
	var out: Array = []
	var r := RandomNumberGenerator.new()
	r.seed = seed * 4441 + 3
	for pi in ctx.paths.size():
		var e: Dictionary = ctx.paths[pi]
		var w := float(e.get("width", 1.5))
		_along(out, e["points"], false, r, density, func(side: float, rr: RandomNumberGenerator) -> Array:
			# Bord du chemin : surtout des fleurs, qui mordent un peu sur les dalles.
			var roll := rr.randf()
			var kind := MEADOW if roll < 0.42 else (MEADOW_SMALL if roll < 0.62 else (FLOWER if roll < 0.74 else (FERN if roll < 0.84 else TALL)))
			var off := w * 0.5 + rr.randf_range(-0.28, 0.3)
			if kind == FERN or kind == TALL:
				off = w * 0.5 + rr.randf_range(0.25, 0.7)
			return [kind, off * side], 0.42, ctx, pi)
	for e: Dictionary in ctx.walls:
		var t := float(e.get("thickness", 0.6))
		_along(out, e["points"], bool(e.get("closed", false)), r, density, func(side: float, rr: RandomNumberGenerator) -> Array:
			var roll := rr.randf()
			var kind := FERN if roll < 0.35 else (TALL if roll < 0.65 else (MEADOW if roll < 0.9 else FLOWER))
			return [kind, (t * 0.5 + rr.randf_range(0.08, 0.4)) * side], 0.6, ctx, -1)
	for e: Dictionary in ctx.fences:
		_along(out, e["points"], bool(e.get("closed", false)), r, density, func(side: float, rr: RandomNumberGenerator) -> Array:
			var roll := rr.randf()
			var kind := TALL if roll < 0.45 else (MEADOW if roll < 0.8 else FERN)
			return [kind, rr.randf_range(0.12, 0.45) * side], 0.9, ctx, -1)
	return out


## Parcourt une polyligne et pose des plantes des deux côtés, tous les `step` m
## environ. `pick(side, rng) -> [sorte, décalage signé]`.
static func _along(out: Array, pts: PackedVector3Array, closed: bool, r: RandomNumberGenerator, density: float,
		pick: Callable, step: float, ctx: BastideGardenContext, own_path: int) -> void:
	var n := pts.size()
	if n < 2:
		return
	var segs := n if closed else n - 1
	var carry := r.randf() * step
	for i in segs:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[(i + 1) % n].x, pts[(i + 1) % n].z)
		var seg_len := a.distance_to(b)
		if seg_len < 0.01:
			continue
		var d := (b - a) / seg_len
		var nrm := Vector2(-d.y, d.x)
		var u := carry
		while u < seg_len:
			for side: float in [-1.0, 1.0]:
				if r.randf() > density:
					continue
				var res: Array = pick.call(side, r)
				var p := a + d * (u + r.randf_range(-0.15, 0.15)) + nrm * float(res[1])
				if not _free(ctx, p, own_path, res[0] == FLOWER or res[0] == MEADOW or res[0] == MEADOW_SMALL):
					continue
				out.append([res[0], p, r.randf() * TAU, _tint(res[0], r.randf())])
			u += step * r.randf_range(0.6, 1.4) / maxf(density, 0.2)
		carry = u - seg_len


## Touffes éparses de prairie autour de `center` (xz), dans un rayon `radius`.
## Tirage par case de `cell` m : stable quand le centre bouge.
static func meadow(ctx: BastideGardenContext, center: Vector2, radius: float, seed: int, density := 1.0, cell := 2.5) -> Array:
	var out: Array = []
	var c0 := Vector2i(floori((center.x - radius) / cell), floori((center.y - radius) / cell))
	var c1 := Vector2i(floori((center.x + radius) / cell), floori((center.y + radius) / cell))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for k in 3:
				var roll := _h(cx, cz, seed * 31 + k)
				if roll > 0.42 * density:
					continue
				var p := Vector2((cx + _h(cx, cz, seed + 11 + k)) * cell, (cz + _h(cx, cz, seed + 23 + k)) * cell)
				if p.distance_to(center) > radius:
					continue
				# Plages fleuries et plages plus sauvages : la sorte suit une « humeur » par zone.
				var mood := _h(floori(p.x / 9.0), floori(p.y / 9.0), seed + 5)
				var pick := _h(cx, cz, seed + 41 + k)
				var kind: int
				if mood < 0.45:
					kind = MEADOW if pick < 0.5 else (MEADOW_SMALL if pick < 0.75 else (FLOWER if pick < 0.88 else TALL))
				else:
					kind = TALL if pick < 0.45 else (FERN if pick < 0.62 else (MEADOW_SMALL if pick < 0.85 else MEADOW))
				if not _free(ctx, p, -2, false):
					continue
				out.append([kind, p, _h(cx, cz, seed + 59 + k) * TAU, _tint(kind, _h(cx, cz, seed + 71 + k))])
	return out


## Le point est-il libre ? Hors des maisons, terrasses, étangs, champs et du cœur
## des chemins (les fleurs du bord, `overflow`, peuvent mordre sur les dalles du
## chemin qui les porte, mais pas sur celles d'un autre ni au milieu).
static func _free(ctx: BastideGardenContext, p: Vector2, own_path: int, overflow: bool) -> bool:
	for h: Dictionary in ctx.houses:
		if _near_poly(h["footprint"], p, 0.35):
			return false
	for t: Dictionary in ctx.terraces:
		if _near_poly(t["footprint"], p, 0.2):
			return false
	for t: Dictionary in ctx.ponds:
		if _near_poly(t["footprint"], p, 0.4):
			return false
	for t: Dictionary in ctx.farms:
		if _near_poly(t["footprint"], p, 0.3):
			return false
	for i in ctx.paths.size():
		var e: Dictionary = ctx.paths[i]
		var half := float(e.get("width", 1.5)) * 0.5
		var keep := half - (0.3 if overflow and i == own_path else 0.0)
		if own_path == -2:
			keep = half + 0.45
		elif i != own_path:
			keep = half + 0.1
		if _dist_line(e["points"], false, p) < keep:
			return false
	if own_path == -2:
		for e: Dictionary in ctx.walls:
			if _dist_line(e["points"], bool(e.get("closed", false)), p) < float(e.get("thickness", 0.6)) * 0.5 + 0.5:
				return false
	return true


static func _near_poly(fp: PackedVector2Array, p: Vector2, margin: float) -> bool:
	if fp.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(p, fp):
		return true
	for i in fp.size():
		var q := Geometry2D.get_closest_point_to_segment(p, fp[i], fp[(i + 1) % fp.size()])
		if q.distance_squared_to(p) < margin * margin:
			return true
	return false


static func _dist_line(pts: PackedVector3Array, closed: bool, p: Vector2) -> float:
	var best := INF
	var n := pts.size()
	var segs := n if closed else n - 1
	for i in segs:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[(i + 1) % n].x, pts[(i + 1) % n].z)
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p))
	return best
