@tool
class_name BastideHillShape
extends RefCounted
## Colline tracée à la main : le contour fermé devient une colline douce (pied sur le
## contour, sommet arrondi), un peu irrégulière. Fonction pure : elle décrit le
## relief à monter (BastideTerrain.set_carve, type « hill »).


## `poly` : contour en monde (xz) ; `height` : hauteur au sommet. Hauteurs monde sur
## la grille du relief `base` (NAN : intact).
static func carve(poly: PackedVector2Array, height: float, base: BastideHeightField, seed := 0) -> Dictionary:
	if poly.size() < 3 or base == null:
		return {}
	var box := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		box = box.expand(q)
	# Pente douce : le sommet est atteint à mi-chemin du centre, jamais plus loin que 9 m du bord.
	var reach := clampf(minf(box.size.x, box.size.y) * 0.42, 2.0, 9.0)
	var skirt := 1.5
	var area := box.grow(skirt + base.cell)
	var i0 := maxi(0, floori((area.position.x - base.origin.x) / base.cell))
	var j0 := maxi(0, floori((area.position.y - base.origin.y) / base.cell))
	var i1 := mini(base.width - 1, ceili((area.end.x - base.origin.x) / base.cell))
	var j1 := mini(base.depth - 1, ceili((area.end.y - base.origin.y) / base.cell))
	var w := maxi(0, i1 - i0 + 1)
	var d := maxi(0, j1 - j0 + 1)
	var heights := PackedFloat32Array()
	heights.resize(w * d)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.09
	for jj in d:
		for ii in w:
			var p := base.origin + Vector2(i0 + ii, j0 + jj) * base.cell
			var t := _signed_distance(poly, p)
			var u := clampf((t + skirt) / (reach + skirt), 0.0, 1.0)
			var h := height * u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
			h *= 0.88 + 0.12 * noise.get_noise_2dv(p)
			heights[jj * w + ii] = base.at(i0 + ii, j0 + jj) + h if h > 0.01 else NAN
	var r := Rect2(base.origin + Vector2(i0, j0) * base.cell, Vector2(w, d) * base.cell)
	return {"type": "hill", "i0": i0, "j0": j0, "w": w, "d": d, "heights": heights, "rect": r.grow(base.cell)}


## Distance au contour, positive dedans.
static func _signed_distance(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best if Geometry2D.is_point_in_polygon(p, poly) else -best
