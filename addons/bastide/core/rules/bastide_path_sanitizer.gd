@tool
class_name BastidePathSanitizer
extends RefCounted
## Corrige un tracé de mur avant génération (« toujours beau », famille 1).
##
## - fusionne les points trop proches (clics doublés, tracé à la souris) ;
## - supprime le point final d'une boucle s'il recouvre le premier ;
## - supprime les « épines » (demi-tours quasi complets) qui feraient un mur plié sur lui-même ;
## - dégrade proprement : une boucle de moins de 3 points devient un mur ouvert.

const SPIKE_ANGLE := deg_to_rad(176.0)


## Retourne { "points": PackedVector3Array, "closed": bool }.
static func sanitize(points: PackedVector3Array, closed: bool, min_segment: float) -> Dictionary:
	var pts := _merge_close(points, closed, min_segment)
	pts = _remove_spikes(pts, closed)
	if closed and pts.size() < 3:
		closed = false
	if pts.size() < 2:
		pts = PackedVector3Array()
	return {"points": pts, "closed": closed}


static func _merge_close(points: PackedVector3Array, closed: bool, min_segment: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in points:
		if out.is_empty() or BastidePolyline.flat_dist(out[out.size() - 1], p) >= min_segment:
			out.append(p)
	# Garder le vrai dernier point d'un mur ouvert : on remplace l'avant-dernier trop proche.
	if not closed and points.size() >= 2 and out.size() >= 2:
		var last := points[points.size() - 1]
		if out[out.size() - 1] != last:
			out[out.size() - 1] = last
	if closed:
		while out.size() > 2 and BastidePolyline.flat_dist(out[out.size() - 1], out[0]) < min_segment:
			out.remove_at(out.size() - 1)
	return out


static func _remove_spikes(points: PackedVector3Array, closed: bool) -> PackedVector3Array:
	var pts := points.duplicate()
	var changed := true
	while changed and pts.size() >= 3:
		changed = false
		var n := pts.size()
		var first := 0 if closed else 1
		var last := n if closed else n - 1
		for i in range(first, last):
			var a := pts[posmod(i - 1, n)]
			var b := pts[i]
			var c := pts[posmod(i + 1, n)]
			var d_in := BastidePolyline.flat_dir(a, b)
			var d_out := BastidePolyline.flat_dir(b, c)
			if BastidePolyline.turn_angle(d_in, d_out) > SPIKE_ANGLE:
				pts.remove_at(i)
				changed = true
				break
	return pts
