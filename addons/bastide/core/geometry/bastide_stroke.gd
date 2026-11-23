@tool
class_name BastideStroke
extends RefCounted
## Traits dessinés à la main : on simplifie, on lisse, on rééchantillonne.
##
## Fonctions pures (aucun nœud) utilisées par la construction en jeu : un tracé
## tremblant à la souris devient une courbe douce, quelques points de contrôle
## restent éditables. Les calculs se font sur le plan XZ ; Y est conservé.


## Supprime les points d'un tracé qui ne changent presque rien à sa forme
## (Ramer-Douglas-Peucker). `tolerance` : écart maximal toléré, en mètres.
static func simplify(points: PackedVector3Array, tolerance: float) -> PackedVector3Array:
	if points.size() < 3:
		return points
	var keep := PackedByteArray()
	keep.resize(points.size())
	keep.fill(0)
	keep[0] = 1
	keep[points.size() - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, points.size() - 1)]
	while not stack.is_empty():
		var seg: Vector2i = stack.pop_back()
		var a := _xz(points[seg.x])
		var b := _xz(points[seg.y])
		var best := -1.0
		var best_i := -1
		for i in range(seg.x + 1, seg.y):
			var d := _dist_to_segment(_xz(points[i]), a, b)
			if d > best:
				best = d
				best_i = i
		if best > tolerance and best_i > 0:
			keep[best_i] = 1
			stack.append(Vector2i(seg.x, best_i))
			stack.append(Vector2i(best_i, seg.y))
	var out := PackedVector3Array()
	for i in points.size():
		if keep[i] == 1:
			out.append(points[i])
	return out


## Lissage de Chaikin : chaque itération coupe les angles. Un tracé ouvert garde
## ses extrémités. `cut` (0 à 0,5) : plus petit = angles plus nets. `max_cut` :
## longueur maximale coupée de chaque côté d'un angle (un long mur garde un angle
## franc au lieu d'un grand arrondi).
static func smooth(points: PackedVector3Array, closed: bool, iterations := 3, cut := 0.25,
		max_cut := 1.2) -> PackedVector3Array:
	var pts := points
	if pts.size() < 3:
		return pts
	for _it in iterations:
		var out := PackedVector3Array()
		var n := pts.size()
		if not closed:
			out.append(pts[0])
		var last := n if closed else n - 1
		for i in last:
			var p := pts[i]
			var q := pts[(i + 1) % n]
			var c := minf(cut, max_cut / maxf(p.distance_to(q), 1e-4))
			out.append(p.lerp(q, c))
			out.append(p.lerp(q, 1.0 - c))
		if not closed:
			out.append(pts[n - 1])
		pts = out
	return pts


## Points régulièrement espacés le long d'une polyligne (le dernier point est gardé).
static func resample(points: PackedVector3Array, spacing: float, closed := false) -> PackedVector3Array:
	if points.size() < 2 or spacing <= 0.0:
		return points
	var src := points.duplicate()
	if closed:
		src.append(points[0])
	var out := PackedVector3Array([src[0]])
	var carry := 0.0
	for i in range(1, src.size()):
		var a := src[i - 1]
		var b := src[i]
		var seg := a.distance_to(b)
		if seg < 1e-6:
			continue
		var t := spacing - carry
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += spacing
		carry = seg - (t - spacing)
	if closed:
		# La boucle se referme d'elle-même : on retire un dernier point collé au premier.
		if out.size() > 2 and out[out.size() - 1].distance_to(out[0]) < spacing * 0.5:
			out.remove_at(out.size() - 1)
	elif out[out.size() - 1].distance_to(src[src.size() - 1]) > spacing * 0.25:
		out.append(src[src.size() - 1])
	else:
		out[out.size() - 1] = src[src.size() - 1]
	return out


## Tracé de mur prêt à générer : points de contrôle lissés puis rééchantillonnés.
static func wall_path(control: PackedVector3Array, closed: bool, spacing: float) -> PackedVector3Array:
	if control.size() < 2:
		return control
	var smoothed := smooth(control, closed, 3, 0.22) if control.size() > 2 else control
	return resample(smoothed, spacing, closed)


static func length(points: PackedVector3Array, closed := false) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	if closed and points.size() > 2:
		total += points[points.size() - 1].distance_to(points[0])
	return total


## Rectangle au sol de diagonale a → b, orienté selon `right` (direction horizontale,
## en général la droite de la caméra) et arrondi au pas `snap`. Côtés ≥ `min_side`.
## Renvoie 4 coins dans le sens direct (vu du dessus, X vers la droite, Z vers soi).
static func rectangle(a: Vector3, b: Vector3, right: Vector3, snap := 0.5, min_side := 3.0) -> PackedVector3Array:
	var r := Vector3(right.x, 0.0, right.z)
	r = r.normalized() if r.length() > 1e-4 else Vector3.RIGHT
	var f := Vector3(-r.z, 0.0, r.x)  # perpendiculaire au sol
	var d := b - a
	var w := d.dot(r)
	var h := d.dot(f)
	var sw := signf(w) if absf(w) > 1e-4 else 1.0
	var sh := signf(h) if absf(h) > 1e-4 else 1.0
	w = maxf(snappedf(absf(w), snap), min_side) * sw
	h = maxf(snappedf(absf(h), snap), min_side) * sh
	var pts := PackedVector3Array([a, a + r * w, a + r * w + f * h, a + f * h])
	for i in pts.size():
		pts[i].y = a.y
	return ensure_direct(pts)


## Remet un contour au sol dans le sens direct (aire signée positive sur XZ).
static func ensure_direct(points: PackedVector3Array) -> PackedVector3Array:
	if signed_area(points) < 0.0:
		var out := points.duplicate()
		out.reverse()
		return out
	return points


static func signed_area(points: PackedVector3Array) -> float:
	var a := 0.0
	for i in points.size():
		var p := points[i]
		var q := points[(i + 1) % points.size()]
		a += p.x * q.z - q.x * p.z
	return a * 0.5


## Union de deux contours au sol. Vide si l'union n'est pas un seul contour sans trou
## (les deux formes ne se touchent pas, ou elles enferment une cour).
static func union(a: PackedVector3Array, b: PackedVector3Array) -> PackedVector3Array:
	var merged := Geometry2D.merge_polygons(_to_2d(a), _to_2d(b))
	if merged.size() != 1:
		return PackedVector3Array()
	var poly: PackedVector2Array = merged[0]
	var y := a[0].y if a.size() > 0 else 0.0
	var out := PackedVector3Array()
	for p in poly:
		out.append(Vector3(p.x, y, p.y))
	return ensure_direct(out)


## Vrai si les deux contours se chevauchent (pas seulement se touchent).
static func overlaps(a: PackedVector3Array, b: PackedVector3Array, min_area := 0.5) -> bool:
	for poly in Geometry2D.intersect_polygons(_to_2d(a), _to_2d(b)):
		if absf(_area_2d(poly)) >= min_area:
			return true
	return false


static func centroid(points: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in points:
		c += p
	return c / maxf(points.size(), 1)


static func _to_2d(points: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(Vector2(p.x, p.z))
	return out


static func _area_2d(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return a * 0.5


static func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-12:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
