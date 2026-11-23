@tool
class_name BastidePolygon
extends RefCounted
## Outils sur les polygones 2D vus de dessus : Vector2(x, z) de l'espace local.
##
## Convention : un polygone « direct » a une aire signée positive (formule du lacet
## sur (x, z)). L'intérieur est alors à gauche de chaque arête, et la normale
## intérieure de l'arête de direction d vaut (-d.y, d.x).


## Aire signée (positive pour un polygone direct).
static func signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## Retourne le polygone dans le sens direct (aire positive).
static func ensure_direct(poly: PackedVector2Array) -> PackedVector2Array:
	if signed_area(poly) >= 0.0:
		return poly
	var out := poly.duplicate()
	out.reverse()
	return out


static func edge_dir(poly: PackedVector2Array, i: int) -> Vector2:
	return (poly[(i + 1) % poly.size()] - poly[i]).normalized()


## Normale intérieure de l'arête i (polygone direct).
static func inward_normal(poly: PackedVector2Array, i: int) -> Vector2:
	var d := edge_dir(poly, i)
	return Vector2(-d.y, d.x)


## Virage au sommet i : > 0 pour un angle saillant (convexe), < 0 pour un angle rentrant.
static func turn_cross(poly: PackedVector2Array, i: int) -> float:
	var n := poly.size()
	var d_in := (poly[i] - poly[posmod(i - 1, n)]).normalized()
	var d_out := (poly[(i + 1) % n] - poly[i]).normalized()
	return d_in.cross(d_out)


static func is_convex_vertex(poly: PackedVector2Array, i: int) -> bool:
	return turn_cross(poly, i) > 1e-6


## Angle de virage absolu au sommet i (0 = tout droit), en radians.
static func turn_angle(poly: PackedVector2Array, i: int) -> float:
	var n := poly.size()
	var d_in := (poly[i] - poly[posmod(i - 1, n)]).normalized()
	var d_out := (poly[(i + 1) % n] - poly[i]).normalized()
	return acos(clampf(d_in.dot(d_out), -1.0, 1.0))


## Décalage d'onglet au sommet i : vecteur à multiplier par une distance `dist`
## pour déplacer les deux arêtes voisines de `dist` vers l'intérieur.
static func miter(poly: PackedVector2Array, i: int, limit := 4.0) -> Vector2:
	var n := poly.size()
	var n_in := inward_normal(poly, posmod(i - 1, n))
	var n_out := inward_normal(poly, i)
	var m := n_in + n_out
	if m.length_squared() < 1e-10:
		return n_out
	m = m.normalized()
	return m * minf(1.0 / maxf(m.dot(n_out), 1e-4), limit)


## Décale toutes les arêtes de `dist` vers l'intérieur (dist < 0 : vers l'extérieur).
## Le nombre de sommets est conservé (onglets bornés).
static func offset(poly: PackedVector2Array, dist: float, limit := 4.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in poly.size():
		out.append(poly[i] + miter(poly, i, limit) * dist)
	return out


static func perimeter(poly: PackedVector2Array) -> float:
	var l := 0.0
	for i in poly.size():
		l += poly[i].distance_to(poly[(i + 1) % poly.size()])
	return l


static func centroid(poly: PackedVector2Array) -> Vector2:
	var a := signed_area(poly)
	if absf(a) < 1e-9:
		var c := Vector2.ZERO
		for p in poly:
			c += p
		return c / maxf(poly.size(), 1)
	var cx := 0.0
	var cy := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		var f := p.x * q.y - q.x * p.y
		cx += (p.x + q.x) * f
		cy += (p.y + q.y) * f
	return Vector2(cx, cy) / (6.0 * a)


## Vrai si deux arêtes non voisines se croisent.
static func self_intersects(poly: PackedVector2Array) -> bool:
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			var c := poly[j]
			var d := poly[(j + 1) % n]
			if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
				return true
	return false


## Triangulation (indices, 3 par triangle). Vide si le polygone est invalide.
static func triangulate(poly: PackedVector2Array) -> PackedInt32Array:
	return Geometry2D.triangulate_polygon(poly)
