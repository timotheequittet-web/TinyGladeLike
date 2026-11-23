@tool
class_name BastideFootprintSanitizer
extends RefCounted
## Corrige un contour de bâtiment avant génération (« toujours beau »).
##
## - fusionne les points trop proches et supprime les points alignés ;
## - supprime les pointes trop aiguës (un mur en lame de couteau est toujours laid) ;
## - remet le polygone dans le sens direct ;
## - « redresse » les contours presque orthogonaux : si chaque côté est à moins de
##   `square_tolerance` degrés d'une direction commune (ou de sa perpendiculaire),
##   les angles deviennent exactement droits. Un contour franchement irrégulier
##   est laissé tel quel ;
## - en dernier recours, un contour qui se croise lui-même est remplacé par son
##   enveloppe convexe.

const COLLINEAR_ANGLE := deg_to_rad(8.0)
const SPIKE_ANGLE := deg_to_rad(150.0)


## Retourne { "points": PackedVector2Array (direct), "squared": bool, "notes": PackedStringArray }.
## `points` est vide si le contour est inutilisable (moins de 3 sommets, surface nulle).
static func sanitize(points: PackedVector2Array, min_edge: float, square_corners: bool,
		square_tolerance_deg: float) -> Dictionary:
	var notes := PackedStringArray()
	var pts := _merge_close(points, min_edge)
	pts = _remove_flat_and_spikes(pts)
	if pts.size() >= 4 and BastidePolygon.self_intersects(pts):
		pts = _hull(pts)
		notes.append("contour croisé remplacé par son enveloppe")
	if pts.size() < 3 or absf(BastidePolygon.signed_area(pts)) < min_edge * min_edge:
		return {"points": PackedVector2Array(), "squared": false, "notes": PackedStringArray(["contour trop petit"])}
	pts = BastidePolygon.ensure_direct(pts)
	var squared := false
	if square_corners:
		var sq := _square(pts, deg_to_rad(square_tolerance_deg))
		if sq.size() >= 4:
			sq = _merge_close(sq, min_edge * 0.5)
			sq = _remove_flat_and_spikes(sq)
			if sq.size() >= 4 and not BastidePolygon.self_intersects(sq) and BastidePolygon.signed_area(sq) > 0.0:
				pts = sq
				squared = true
				notes.append("angles redressés")
	return {"points": pts, "squared": squared, "notes": notes}


static func _hull(pts: PackedVector2Array) -> PackedVector2Array:
	var h := Geometry2D.convex_hull(pts)
	if h.size() > 1 and h[0] == h[h.size() - 1]:
		h.remove_at(h.size() - 1)
	return BastidePolygon.ensure_direct(h)


static func _merge_close(points: PackedVector2Array, min_edge: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		if out.is_empty() or out[out.size() - 1].distance_to(p) >= min_edge:
			out.append(p)
	while out.size() > 2 and out[out.size() - 1].distance_to(out[0]) < min_edge:
		out.remove_at(out.size() - 1)
	return out


static func _remove_flat_and_spikes(points: PackedVector2Array) -> PackedVector2Array:
	var pts := points.duplicate()
	var changed := true
	while changed and pts.size() >= 3:
		changed = false
		for i in pts.size():
			var a := BastidePolygon.turn_angle(pts, i)
			if a < COLLINEAR_ANGLE or a > SPIKE_ANGLE:
				pts.remove_at(i)
				changed = true
				break
	return pts


## Redressement orthogonal. Retourne un polygone vide si le contour n'est pas presque orthogonal.
static func _square(pts: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	var n := pts.size()
	# Direction dominante, modulo 90° : moyenne des angles ×4, pondérée par la longueur.
	var acc := Vector2.ZERO
	for i in n:
		var d := pts[(i + 1) % n] - pts[i]
		var a := d.angle()
		acc += Vector2(cos(4.0 * a), sin(4.0 * a)) * d.length()
	var theta := acc.angle() / 4.0
	var c := BastidePolygon.centroid(pts)
	# Dans le repère tourné : chaque côté devient horizontal (0) ou vertical (1).
	var local := PackedVector2Array()
	for p in pts:
		local.append((p - c).rotated(-theta))
	var axis := PackedInt32Array()
	for i in n:
		var d := local[(i + 1) % n] - local[i]
		var a := absf(fposmod(d.angle(), PI * 0.5))
		var dev := minf(a, PI * 0.5 - a)
		if dev > tolerance:
			return PackedVector2Array()
		axis.append(0 if absf(d.x) >= absf(d.y) else 1)
	# Deux côtés consécutifs sur le même axe : le sommet du milieu disparaît.
	var keep := PackedVector2Array()
	var keep_axis := PackedInt32Array()
	for i in n:
		if axis[posmod(i - 1, n)] != axis[i]:
			keep.append(local[i])
	if keep.size() < 4 or keep.size() % 2 == 1:
		return PackedVector2Array()
	var m := keep.size()
	for i in m:
		var d := keep[(i + 1) % m] - keep[i]
		keep_axis.append(0 if absf(d.x) >= absf(d.y) else 1)
	for i in m:
		if keep_axis[i] == keep_axis[(i + 1) % m]:
			return PackedVector2Array()
	# Chaque côté prend la coordonnée moyenne de ses deux bouts.
	var coord := PackedFloat32Array()
	for i in m:
		var a := keep[i]
		var b := keep[(i + 1) % m]
		coord.append((a.y + b.y) * 0.5 if keep_axis[i] == 0 else (a.x + b.x) * 0.5)
	var out := PackedVector2Array()
	for i in m:
		var e_in := posmod(i - 1, m)
		var e_out := i
		var p := Vector2.ZERO
		if keep_axis[e_out] == 0:
			p = Vector2(coord[e_in], coord[e_out])
		else:
			p = Vector2(coord[e_out], coord[e_in])
		out.append(p.rotated(theta) + c)
	return out
