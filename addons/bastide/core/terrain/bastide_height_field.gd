@tool
class_name BastideHeightField
extends RefCounted
## Relief du sol : une grille régulière de hauteurs (monde, en mètres), lue par
## interpolation bilinéaire. Uniquement des données : utilisable sur n'importe quel
## thread une fois construite (les générations la lisent en parallèle).
##
## Hors de la grille, la hauteur est celle du bord le plus proche.

## Coin (x, z) de la grille, en monde.
var origin := Vector2.ZERO
## Taille d'une case, en mètres.
var cell := 1.0
## Nombre de points sur x et sur z.
var width := 0
var depth := 0
var heights := PackedFloat32Array()
## Plans d'eau posés sur ce relief (étangs) : [{poly: PackedVector2Array, level, rect}],
## en monde. Lus par les structures qui ne doivent pas finir sous l'eau.
var waters: Array = []


static func flat(origin_: Vector2, cell_: float, width_: int, depth_: int, h := 0.0) -> BastideHeightField:
	var f := BastideHeightField.new()
	f.origin = origin_
	f.cell = cell_
	f.width = width_
	f.depth = depth_
	f.heights.resize(width_ * depth_)
	f.heights.fill(h)
	return f


func size() -> Vector2:
	return Vector2((width - 1) * cell, (depth - 1) * cell)


func rect() -> Rect2:
	return Rect2(origin, size())


func at(ix: int, iz: int) -> float:
	ix = clampi(ix, 0, width - 1)
	iz = clampi(iz, 0, depth - 1)
	return heights[iz * width + ix]


func set_at(ix: int, iz: int, h: float) -> void:
	heights[iz * width + ix] = h


## Hauteur du sol en (x, z), monde.
func height(x: float, z: float) -> float:
	if width < 2 or depth < 2:
		return heights[0] if heights.size() > 0 else 0.0
	var fx := clampf((x - origin.x) / cell, 0.0, width - 1.0)
	var fz := clampf((z - origin.y) / cell, 0.0, depth - 1.0)
	var ix := mini(int(fx), width - 2)
	var iz := mini(int(fz), depth - 2)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * width + ix
	var a := heights[i]
	var b := heights[i + 1]
	var c := heights[i + width]
	var d := heights[i + width + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func height_v(p: Vector3) -> float:
	return height(p.x, p.z)


## Niveau de l'eau en (x, z) s'il y a un étang à cet endroit, sinon -INF.
func water_level(x: float, z: float) -> float:
	var p := Vector2(x, z)
	for w: Dictionary in waters:
		if (w["rect"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, w["poly"]):
			return w["level"]
	return -INF


## Profondeur d'eau en (x, z) (0 hors de l'eau).
func water_depth(x: float, z: float) -> float:
	var l := water_level(x, z)
	return maxf(l - height(x, z), 0.0) if l > -INF else 0.0


## Normale du sol (différences centrées).
func normal(x: float, z: float) -> Vector3:
	var e := cell
	var dx := height(x + e, z) - height(x - e, z)
	var dz := height(x, z + e) - height(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## Pente (0 = plat, 1 = 45°).
func slope(x: float, z: float) -> float:
	var n := normal(x, z)
	return sqrt(maxf(0.0, 1.0 - n.y * n.y)) / maxf(n.y, 0.01)


## Hauteurs extrêmes sous un contour (échantillonné tous les `step` mètres, contour
## et intérieur) : {min, max, mean}.
func range_under(poly: PackedVector2Array, step := 1.0) -> Dictionary:
	if poly.is_empty():
		return {"min": 0.0, "max": 0.0, "mean": 0.0}
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	# [min, max, somme, nombre] : les lambdas capturent les variables par copie.
	var acc := [INF, -INF, 0.0, 0]
	var take := func(q: Vector2) -> void:
		var h := height(q.x, q.y)
		acc[0] = minf(acc[0], h)
		acc[1] = maxf(acc[1], h)
		acc[2] += h
		acc[3] += 1
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var k := maxi(1, ceili(a.distance_to(b) / step))
		for j in k:
			take.call(a.lerp(b, float(j) / k))
	var x := box.position.x + step * 0.5
	while x < box.end.x:
		var z := box.position.y + step * 0.5
		while z < box.end.y:
			if Geometry2D.is_point_in_polygon(Vector2(x, z), poly):
				take.call(Vector2(x, z))
			z += step
		x += step
	return {"min": acc[0], "max": acc[1], "mean": acc[2] / maxf(acc[3], 1)}



## Intersection d'un rayon avec le sol (marche puis dichotomie). null si rien.
func raycast(from: Vector3, dir: Vector3, max_dist := 600.0) -> Variant:
	dir = dir.normalized()
	var step := cell * 0.5
	var t := 0.0
	var prev := from
	var prev_above := from.y - height_v(from)
	while t < max_dist:
		t += step
		var p := from + dir * t
		var above := p.y - height_v(p)
		if above <= 0.0:
			var lo := t - step
			var hi := t
			for i in 18:
				var mid := (lo + hi) * 0.5
				var q := from + dir * mid
				if q.y - height_v(q) > 0.0:
					lo = mid
				else:
					hi = mid
			var hit := from + dir * hi
			return Vector3(hit.x, height_v(hit), hit.z)
		prev = p
		prev_above = above
		# Plus on est haut au-dessus du sol, plus on peut avancer vite.
		step = clampf(above * 0.5, cell * 0.25, cell * 4.0)
	return null


## Une image (32 bits flottants) des hauteurs, pour les shaders (herbe…).
func to_image() -> Image:
	var bytes := heights.to_byte_array()
	return Image.create_from_data(width, depth, false, Image.FORMAT_RF, bytes)
