@tool
class_name BastideOrientationRules
extends RefCounted
## Règles « toujours beau » de l'orientation des structures, en fonctions pures.
##
## - On tourne par crans (15° par défaut) : jamais d'angle de travers par accident.
## - Près d'une maison, l'orientation s'aimante sur ses façades (parallèle ou
##   d'équerre) dès qu'on en est à moins de quelques degrés : les façades voisines
##   restent alignées et les raccords propres.
##
## Tout se passe à plat, sur XZ (les tracés sont enregistrés à y = 0). Les angles
## sont mesurés comme atan2(z, x) : tourner de `a` ajoute `a` à cet angle.

## Cran de rotation (degrés).
const STEP_DEG := 15.0
## Écart (degrés) en dessous duquel on s'aimante sur une façade voisine.
const MAGNET_DEG := 8.0
## Distance (m) jusqu'où une maison voisine attire l'orientation.
const MAGNET_RADIUS := 14.0
## Plus petit côté de façade pris en compte.
const MIN_EDGE := 1.8


## Angle (radians) d'une direction au sol.
static func angle_of(dir: Vector3) -> float:
	return atan2(dir.z, dir.x)


## Direction au sol d'angle `a`.
static func dir_of(a: float) -> Vector3:
	return Vector3(cos(a), 0.0, sin(a))


## Tourne une direction au sol de `a` radians (y remis à 0).
static func turn(dir: Vector3, a: float) -> Vector3:
	var c := cos(a)
	var s := sin(a)
	return Vector3(dir.x * c - dir.z * s, 0.0, dir.x * s + dir.z * c)


## Tourne des points autour de `pivot` (sur XZ), en gardant leur hauteur.
static func rotate_points(points: PackedVector3Array, pivot: Vector3, a: float) -> PackedVector3Array:
	var c := cos(a)
	var s := sin(a)
	var out := PackedVector3Array()
	out.resize(points.size())
	for i in points.size():
		var p := points[i]
		var dx := p.x - pivot.x
		var dz := p.z - pivot.z
		out[i] = Vector3(pivot.x + dx * c - dz * s, p.y, pivot.z + dx * s + dz * c)
	return out


## Ramène un angle dans ]-period/2, period/2].
static func wrap_angle(a: float, period: float) -> float:
	return a - period * roundf(a / period)


## Direction du plus long côté d'un contour (son « axe principal »).
static func main_axis(points: PackedVector3Array, closed := true) -> Vector3:
	var best := Vector3.RIGHT
	var best_len := -1.0
	var n := points.size()
	var last := n if closed else n - 1
	for i in last:
		var d := points[(i + 1) % n] - points[i]
		d.y = 0.0
		if d.length() > best_len:
			best_len = d.length()
			best = d
	return best.normalized() if best_len > 1e-4 else Vector3.RIGHT


## Correction d'angle (radians) qui aligne `axis` sur la façade de la maison la
## plus proche de `p` (parallèle ou d'équerre), ou 0 s'il n'y en a pas assez près
## ou si l'écart dépasse `tol_deg`. `footprints` : contours au sol (PackedVector2Array).
static func magnet(axis: Vector3, p: Vector3, footprints: Array, radius := MAGNET_RADIUS,
		tol_deg := MAGNET_DEG) -> float:
	var q := Vector2(p.x, p.z)
	var nearest: PackedVector2Array
	var nearest_d := radius
	for fp: PackedVector2Array in footprints:
		if fp.size() < 3:
			continue
		var d := 0.0 if Geometry2D.is_point_in_polygon(q, fp) else INF
		if d > 0.0:
			for i in fp.size():
				d = minf(d, q.distance_to(Geometry2D.get_closest_point_to_segment(q, fp[i], fp[(i + 1) % fp.size()])))
		if d < nearest_d:
			nearest_d = d
			nearest = fp
	if nearest.is_empty():
		return 0.0
	var a := angle_of(axis)
	var best := INF
	for i in nearest.size():
		var e := nearest[(i + 1) % nearest.size()] - nearest[i]
		if e.length() < MIN_EDGE:
			continue
		var diff := wrap_angle(atan2(e.y, e.x) - a, PI * 0.5)
		if absf(diff) < absf(best):
			best = diff
	return best if absf(best) <= deg_to_rad(tol_deg) else 0.0


## Axe de tracé : `base` tourné de `steps` crans, puis aimanté sur la maison voisine.
static func placement_axis(base: Vector3, steps: int, p: Vector3, footprints: Array) -> Vector3:
	var axis := turn(Vector3(base.x, 0.0, base.z).normalized(), deg_to_rad(STEP_DEG) * steps)
	return turn(axis, magnet(axis, p, footprints))


## Distance (m) en dessous de laquelle une façade qu'on déplace s'aligne sur celle
## d'une maison voisine (dans le prolongement, ou collée contre elle).
const SLIDE_MAGNET := 0.45


## Décalage (sur XZ) qui aligne le contour `moving` qu'on fait glisser sur les
## façades des maisons voisines : une façade parallèle à moins de `tol` m d'une
## autre (même droite) s'y cale. Au plus deux calages, sur deux directions
## différentes (une façade et son équerre). Vector2.ZERO si rien n'est assez près.
static func slide_magnet(moving: PackedVector2Array, footprints: Array, tol := SLIDE_MAGNET,
		radius := MAGNET_RADIUS) -> Vector2:
	if moving.size() < 2:
		return Vector2.ZERO
	var center := Vector2.ZERO
	for q in moving:
		center += q
	center /= moving.size()
	var cands: Array = []  # [|d|, normale, d]
	for fp: PackedVector2Array in footprints:
		if fp.size() < 3:
			continue
		var near := false
		for q in fp:
			if q.distance_to(center) < radius:
				near = true
				break
		if not near:
			continue
		for i in fp.size():
			var a := fp[i]
			var e := fp[(i + 1) % fp.size()] - a
			if e.length() < MIN_EDGE:
				continue
			var dir := e.normalized()
			var n := Vector2(-dir.y, dir.x)
			for j in moving.size():
				var b := moving[j]
				var f := moving[(j + 1) % moving.size()] - b
				if f.length() < MIN_EDGE or absf(dir.cross(f.normalized())) > 0.035:
					continue
				var d := (a - b).dot(n)
				if absf(d) < tol:
					cands.append([absf(d), n, d])
	if cands.is_empty():
		return Vector2.ZERO
	cands.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var first: Array = cands[0]
	var out: Vector2 = (first[1] as Vector2) * float(first[2])
	for c: Array in cands:
		if absf((c[1] as Vector2).dot(first[1])) < 0.5:
			out += (c[1] as Vector2) * float(c[2])
			break
	return out


## Vrai si deux contours au sol se chevauchent (plus de `min_area` m²).
static func overlaps(a: PackedVector2Array, b: PackedVector2Array, min_area := 0.05) -> bool:
	var area := 0.0
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(a, b):
		area += absf(_area(piece))
	return area > min_area


static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		s += p.x * q.y - q.x * p.y
	return s * 0.5


static func flat(points: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(Vector2(p.x, p.z))
	return out
