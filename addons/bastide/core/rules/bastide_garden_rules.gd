@tool
class_name BastideGardenRules
extends RefCounted
## Règles « toujours beau » du décor, en fonctions pures (testables sans nœud).
##
## - Un chemin qui finit près d'une porte la rejoint de face, sur une pierre de seuil.
## - Un chemin qui finit près d'un autre chemin s'y raccorde.
## - Un chemin serpente doucement (jamais au ras des portes).
## - Une clôture s'ouvre là où un chemin la traverse.
## - Un torii posé près d'un chemin se centre dessus, en travers, à la bonne largeur.

## Distance d'une extrémité de chemin à une porte en dessous de laquelle il la rejoint.
const DOOR_SNAP := 3.6
## Distance à un autre chemin en dessous de laquelle une extrémité s'y raccorde.
const JOIN_SNAP := 2.2
## Le chemin arrive droit sur la porte sur cette longueur.
const DOOR_APPROACH := 2.6
## Distance porte → bout du chemin (la pierre de seuil occupe l'entre-deux).
const DOOR_GAP := 1.15


## Raccorde les extrémités d'un chemin aux portes et aux autres chemins.
## Renvoie {points, door_start, door_end} (door_* : la porte rejointe, ou {}).
static func snap_path_ends(points: PackedVector3Array, ctx: BastideGardenContext) -> Dictionary:
	var out := {"points": points, "door_start": {}, "door_end": {}, "join_start": false, "join_end": false}
	if points.size() < 2 or ctx == null:
		return out
	var pts := points.duplicate()
	for end in 2:
		if end == 1:
			pts.reverse()
		var res := _snap_start(pts, ctx)
		pts = res["points"]
		out["door_start" if end == 0 else "door_end"] = res["door"]
		out["join_start" if end == 0 else "join_end"] = res["join"]
		if end == 1:
			pts.reverse()
	out["points"] = pts
	return out


static func _snap_start(pts: PackedVector3Array, ctx: BastideGardenContext) -> Dictionary:
	var p := pts[0]
	var best := {}
	var best_d := DOOR_SNAP
	for d: Dictionary in ctx.doors():
		var front: Vector3 = (d["pos"] as Vector3) + (d["out"] as Vector3) * DOOR_GAP
		var dd := Vector2(p.x - front.x, p.z - front.z).length()
		if dd < best_d:
			best_d = dd
			best = d
	if not best.is_empty():
		var pos: Vector3 = best["pos"]
		var out: Vector3 = best["out"]
		var t := pos + out * DOOR_GAP
		var a := pos + out * DOOR_APPROACH
		# Retire les points qui tombent dans l'approche (ou derrière, contre la façade).
		while pts.size() > 1:
			var q := pts[0]
			var rel := Vector2(q.x - pos.x, q.z - pos.z)
			var ahead := rel.dot(Vector2(out.x, out.z))
			if ahead < DOOR_APPROACH + 0.4 and rel.length() < DOOR_APPROACH + 1.6:
				pts.remove_at(0)
			else:
				break
		t.y = p.y
		a.y = p.y
		var head := PackedVector3Array([t, a])
		head.append_array(pts)
		return {"points": head, "door": best, "join": false}
	var near := ctx.nearest_path(Vector2(p.x, p.z))
	if near["index"] >= 0 and near["dist"] < JOIN_SNAP:
		var q: Vector3 = near["pos"]
		q.y = p.y
		# Le bout s'enfonce jusqu'à l'axe du chemin rejoint : les deux se fondent.
		if pts.size() > 1 and Vector2(pts[1].x - q.x, pts[1].z - q.z).length() < 0.3:
			pts.remove_at(0)
		pts[0] = q
		return {"points": pts, "door": {}, "join": true}
	return {"points": pts, "door": {}, "join": false}


## Fait serpenter doucement un chemin : léger décalage latéral, nul aux extrémités
## sur `fixed_start` / `fixed_end` mètres (approche des portes bien droite).
static func meander(points: PackedVector3Array, seed: int, amplitude: float,
		fixed_start := 0.0, fixed_end := 0.0) -> PackedVector3Array:
	if points.size() < 2 or amplitude <= 0.0:
		return points
	var pts := BastideStroke.resample(points, 0.5)
	var cum := BastidePolyline.cumulative(pts)
	var total := cum[cum.size() - 1]
	if total < 3.0:
		return points
	var out := PackedVector3Array()
	for i in pts.size():
		var s := cum[i]
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var dir := BastidePolyline.flat_dir(a, b)
		var side := BastidePolyline.right_of(dir)
		var env := smoothstep(0.0, 2.5, s - fixed_start) * smoothstep(0.0, 2.5, total - s - fixed_end)
		var wob := (BastideRng.noise1(seed, "meander", s / 4.5) * 2.0 - 1.0) * amplitude * env
		out.append(pts[i] + side * wob)
	return out


## Ouvertures d'une clôture : intervalles [début, fin] (abscisse le long de la
## clôture) là où un chemin la traverse, assez larges pour le chemin.
static func fence_openings(points: PackedVector3Array, closed: bool, ctx: BastideGardenContext,
		margin := 0.45) -> Array[Vector2]:
	var spans: Array[Vector2] = []
	if ctx == null or points.size() < 2:
		return spans
	var n := points.size()
	var last := n if closed else n - 1
	var acc := 0.0
	for i in last:
		var a3 := points[i]
		var b3 := points[(i + 1) % n]
		var a := Vector2(a3.x, a3.z)
		var b := Vector2(b3.x, b3.z)
		var seg := a.distance_to(b)
		if seg < 1e-5:
			continue
		var fdir := (b - a) / seg
		for e: Dictionary in ctx.paths:
			var pp: PackedVector3Array = e["points"]
			for j in range(pp.size() - 1):
				var c := Vector2(pp[j].x, pp[j].z)
				var d := Vector2(pp[j + 1].x, pp[j + 1].z)
				var hit: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
				if hit == null:
					continue
				var pdir := (d - c).normalized()
				var sin_t := absf(fdir.cross(pdir))
				var half: float = e["width"] * 0.5 / maxf(sin_t, 0.45) + margin
				var s := acc + a.distance_to(hit as Vector2)
				spans.append(Vector2(s - half, s + half))
		acc += seg
	spans.sort_custom(func(u: Vector2, v: Vector2) -> bool: return u.x < v.x)
	var merged: Array[Vector2] = []
	for sp in spans:
		if not merged.is_empty() and sp.x <= merged[merged.size() - 1].y + 0.6:
			merged[merged.size() - 1].y = maxf(merged[merged.size() - 1].y, sp.y)
		else:
			merged.append(sp)
	return merged


## Largeur d'un torii pour un chemin de largeur `path_width`.
static func torii_width(path_width: float) -> float:
	return clampf(path_width + 1.6, 2.6, 6.5)


## Pose d'un torii près de `center` : s'il y a un chemin à moins de `snap` mètres,
## le torii se centre sur son axe, en travers, à sa largeur. Sinon il est posé tel
## quel, piliers alignés sur `fallback_axis`. Renvoie {points: [pied gauche, pied droit], snapped}.
static func place_torii(center: Vector3, ctx: BastideGardenContext, default_path_width: float,
		fallback_axis := Vector3.RIGHT, snap := 3.5) -> Dictionary:
	var c := center
	var axis := Vector3(fallback_axis.x, 0.0, fallback_axis.z)
	axis = axis.normalized() if axis.length() > 1e-4 else Vector3.RIGHT
	var width := torii_width(default_path_width)
	var snapped := false
	if ctx != null:
		var near := ctx.nearest_path(Vector2(center.x, center.z))
		if near["index"] >= 0 and near["dist"] < snap:
			var t: Vector3 = near["tangent"]
			c = near["pos"]
			c.y = center.y
			axis = Vector3(-t.z, 0.0, t.x)
			# Toujours le même sens de lecture : le pilier « gauche » vu de la caméra.
			if axis.dot(fallback_axis) < 0.0:
				axis = -axis
			width = torii_width(near["width"])
			snapped = true
	return {"points": PackedVector3Array([c - axis * width * 0.5, c + axis * width * 0.5]), "snapped": snapped}


## Écartement des piliers borné (2,2 à 7 m), autour du milieu.
static func fit_torii(a: Vector3, b: Vector3) -> PackedVector3Array:
	var c := (a + b) * 0.5
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var w := d.length()
	var axis := d / w if w > 1e-4 else Vector3.RIGHT
	w = clampf(w, 2.2, 7.0)
	var pa := c - axis * w * 0.5
	var pb := c + axis * w * 0.5
	pa.y = minf(a.y, b.y)
	pb.y = pa.y
	return PackedVector3Array([pa, pb])
