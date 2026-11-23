@tool
class_name BastidePolyline
extends RefCounted
## Outils sur les polylignes 3D vues de dessus (plan XZ).
## Les hauteurs (Y) sont conservées mais les angles et longueurs se mesurent à plat.


## Direction horizontale normalisée de a vers b (Vector3.ZERO si confondus).
static func flat_dir(a: Vector3, b: Vector3) -> Vector3:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var l := d.length()
	return d / l if l > 1e-6 else Vector3.ZERO


## Distance horizontale entre deux points.
static func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


## Normale horizontale à droite d'une direction (côté +1 du mur).
static func right_of(dir: Vector3) -> Vector3:
	return Vector3(-dir.z, 0.0, dir.x)


## Angle de virage (en radians, 0 = tout droit, PI = demi-tour) entre deux directions.
static func turn_angle(d_in: Vector3, d_out: Vector3) -> float:
	return acos(clampf(d_in.dot(d_out), -1.0, 1.0))


## Décalage d'onglet : vecteur horizontal à multiplier par la demi-épaisseur
## pour obtenir l'arête d'un mur dont les deux segments ont la même épaisseur.
static func miter(d_in: Vector3, d_out: Vector3, limit: float) -> Vector3:
	var n_in := right_of(d_in)
	var n_out := right_of(d_out)
	var m := n_in + n_out
	if m.length_squared() < 1e-8:
		return n_out
	m = m.normalized()
	var c := m.dot(n_out)
	return m * minf(1.0 / maxf(c, 1e-4), limit)


## Longueurs cumulées le long d'une polyligne (à plat).
static func cumulative(points: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(points.size())
	var acc := 0.0
	for i in points.size():
		if i > 0:
			acc += flat_dist(points[i - 1], points[i])
		out[i] = acc
	return out
