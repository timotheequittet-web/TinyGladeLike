@tool
class_name BastideGardenContext
extends RefCounted
## Le voisinage d'une structure de décor : maisons (contour, portes), murs, chemins,
## clôtures, torii, massifs. Uniquement des données, dans l'espace local du nœud
## qui génère : utilisable sur n'importe quel thread.
##
## Les nœuds remplissent ce contexte (BastideStructure.gather_context) ; les tests
## et le code de jeu peuvent aussi le remplir à la main avec from_entries().

## {footprint: PackedVector2Array, doors: [{pos, out, width}], overhang, rect}
var houses: Array = []
## {points: PackedVector3Array, thickness, closed, rect}
var walls: Array = []
## {points: PackedVector3Array (axe), width, rect}
var paths: Array = []
## {points, thickness, closed, rect}
var fences: Array = []
## {a: Vector3, b: Vector3, rect} : pieds des deux piliers d'un torii.
var gates: Array = []
## {points, rect}
var plantings: Array = []
## {footprint: PackedVector2Array, doors: [{pos, out, width, stone}], height, rect} : terrasses de bois.
var terraces: Array = []


## Ramène une description (coordonnées monde) dans un autre repère.
static func transform_entry(d: Dictionary, xf: Transform3D) -> Dictionary:
	var out := d.duplicate()
	for key in ["points", "footprint"]:
		if d.has(key):
			var pts := PackedVector3Array()
			for p: Vector3 in d[key]:
				pts.append(xf * p)
			out[key] = pts
	if d.has("doors"):
		var doors: Array = []
		for door: Dictionary in d["doors"]:
			var nd := (door as Dictionary).duplicate()
			nd["pos"] = xf * (door["pos"] as Vector3)
			nd["out"] = (xf.basis * (door["out"] as Vector3)).normalized()
			nd["width"] = door.get("width", 1.5)
			doors.append(nd)
		out["doors"] = doors
	return out


## Construit le contexte à partir de descriptions (voir BastideStructure.describe).
static func from_entries(entries: Array) -> BastideGardenContext:
	var c := BastideGardenContext.new()
	for d: Dictionary in entries:
		match String(d.get("kind", "")):
			"house":
				var fp := PackedVector2Array()
				for p: Vector3 in d.get("footprint", PackedVector3Array()):
					fp.append(Vector2(p.x, p.z))
				if fp.size() >= 3:
					fp = BastidePolygon.ensure_direct(fp)
					c.houses.append({"footprint": fp, "doors": d.get("doors", []),
						"overhang": float(d.get("overhang", 0.6)), "rect": _rect2(fp, 1.0)})
			"wall":
				c.walls.append(_line(d, float(d.get("thickness", 0.6))))
			"fence":
				c.fences.append(_line(d, float(d.get("thickness", 0.5))))
			"path":
				var e := _line(d, 0.0)
				e["width"] = float(d.get("width", 1.5))
				e["rect"] = (e["rect"] as Rect2).grow(e["width"] * 0.5)
				c.paths.append(e)
			"gate":
				var pts: PackedVector3Array = d.get("points", PackedVector3Array())
				if pts.size() >= 2:
					c.gates.append({"a": pts[0], "b": pts[1], "rect": _rect3(pts, 0.8)})
			"plants":
				c.plantings.append(_line(d, 1.2))
			"terrace":
				var tp := PackedVector2Array()
				for p: Vector3 in d.get("footprint", PackedVector3Array()):
					tp.append(Vector2(p.x, p.z))
				if tp.size() >= 3:
					tp = BastidePolygon.ensure_direct(tp)
					c.terraces.append({"footprint": tp, "doors": d.get("doors", []),
						"height": float(d.get("height", 0.45)), "rect": _rect2(tp, 0.6)})
	return c


static func _line(d: Dictionary, thickness: float) -> Dictionary:
	var pts: PackedVector3Array = d.get("points", PackedVector3Array())
	# Les longues polylignes sont allégées (1 point tous les ~0,8 m suffit pour les
	# distances) : le jardin interroge le voisinage des milliers de fois.
	if pts.size() > 8:
		pts = BastideStroke.resample(pts, 0.8, bool(d.get("closed", false)))
	return {"points": pts, "thickness": thickness, "closed": bool(d.get("closed", false)),
		"variant": int(d.get("variant", 0)), "rect": _rect3(pts, thickness * 0.5 + 0.5)}


static func _rect2(pts: PackedVector2Array, grow: float) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r.grow(grow)


static func _rect3(pts: PackedVector3Array, grow: float) -> Rect2:
	var flat := PackedVector2Array()
	for p in pts:
		flat.append(Vector2(p.x, p.z))
	return _rect2(flat, grow)


# --- Requêtes ----------------------------------------------------------------------

## Toutes les portes : [{pos, out, width}], marches des terrasses comprises
## (celles-ci portent `stone: false` : elles ont déjà leur pierre de seuil).
func doors() -> Array:
	var out: Array = []
	for h: Dictionary in houses:
		out.append_array(h["doors"])
	for t: Dictionary in terraces:
		out.append_array(t["doors"])
	return out


## Point le plus proche d'une polyligne (à plat) : {dist, pos, tangent, s}.
static func nearest_on_polyline(p: Vector2, pts: PackedVector3Array, closed := false) -> Dictionary:
	var best := {"dist": INF, "pos": Vector3.ZERO, "tangent": Vector3.RIGHT, "s": 0.0}
	var n := pts.size()
	if n == 0:
		return best
	if n == 1:
		best["dist"] = p.distance_to(Vector2(pts[0].x, pts[0].z))
		best["pos"] = pts[0]
		return best
	var acc := 0.0
	var last := n if closed else n - 1
	for i in last:
		var a3 := pts[i]
		var b3 := pts[(i + 1) % n]
		var a := Vector2(a3.x, a3.z)
		var b := Vector2(b3.x, b3.z)
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 1e-10 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_to(q)
		if d < best["dist"]:
			var tan := Vector3(ab.x, 0.0, ab.y)
			best = {"dist": d, "pos": a3.lerp(b3, t), "tangent": tan.normalized() if l2 > 1e-10 else Vector3.RIGHT,
				"s": acc + sqrt(l2) * t}
		acc += sqrt(l2)
	return best


## Chemin le plus proche : {dist (à l'axe), clearance (au bord), pos, tangent, width, index}.
func nearest_path(p: Vector2, skip := -1) -> Dictionary:
	var best := {"dist": INF, "clearance": INF, "index": -1}
	for i in paths.size():
		if i == skip:
			continue
		var e: Dictionary = paths[i]
		var r: Rect2 = e["rect"]
		if not r.grow(best["clearance"] if best["clearance"] < 50.0 else 50.0).has_point(p):
			continue
		var q := nearest_on_polyline(p, e["points"])
		var clear: float = q["dist"] - e["width"] * 0.5
		if clear < best["clearance"]:
			best = q
			best["clearance"] = clear
			best["width"] = e["width"]
			best["index"] = i
	return best


## Distance au bord du chemin le plus proche (négative à l'intérieur d'un chemin).
func path_clearance(p: Vector2) -> float:
	var best := INF
	for e: Dictionary in paths:
		if not (e["rect"] as Rect2).grow(2.0).has_point(p):
			continue
		best = minf(best, nearest_on_polyline(p, e["points"])["dist"] - e["width"] * 0.5)
	return best


## Distance à la face du mur ou de la clôture la plus proche (négative dedans).
func wall_clearance(p: Vector2) -> float:
	var best := INF
	for list: Array in [walls, fences]:
		for e: Dictionary in list:
			if not (e["rect"] as Rect2).grow(2.0).has_point(p):
				continue
			best = minf(best, nearest_on_polyline(p, e["points"], e["closed"])["dist"] - e["thickness"] * 0.5)
	return best


## Distance au contour de la maison la plus proche (négative à l'intérieur).
func house_clearance(p: Vector2) -> float:
	var best := INF
	for h: Dictionary in houses:
		if not (h["rect"] as Rect2).grow(2.0).has_point(p):
			continue
		var fp: PackedVector2Array = h["footprint"]
		var d := INF
		for i in fp.size():
			var q := Geometry2D.get_closest_point_to_segment(p, fp[i], fp[(i + 1) % fp.size()])
			d = minf(d, p.distance_to(q))
		if Geometry2D.is_point_in_polygon(p, fp):
			d = -d
		best = minf(best, d)
	return best


## Distance au bord de la terrasse la plus proche (négative dessous).
func terrace_clearance(p: Vector2) -> float:
	var best := INF
	for t: Dictionary in terraces:
		if not (t["rect"] as Rect2).grow(2.0).has_point(p):
			continue
		var fp: PackedVector2Array = t["footprint"]
		var d := INF
		for i in fp.size():
			var q := Geometry2D.get_closest_point_to_segment(p, fp[i], fp[(i + 1) % fp.size()])
			d = minf(d, p.distance_to(q))
		if Geometry2D.is_point_in_polygon(p, fp):
			d = -d
		best = minf(best, d)
	return best


## Vrai si p est devant une porte (dans un demi-disque de rayon `radius`).
func near_door(p: Vector2, radius := 2.0) -> bool:
	for d: Dictionary in doors():
		var pos: Vector3 = d["pos"]
		var out: Vector3 = d["out"]
		var rel := p - Vector2(pos.x, pos.z)
		if rel.length() < radius and rel.dot(Vector2(out.x, out.z)) > -0.3:
			return true
	return false


## Distance au pilier de torii le plus proche.
func gate_clearance(p: Vector2) -> float:
	var best := INF
	for g: Dictionary in gates:
		var a: Vector3 = g["a"]
		var b: Vector3 = g["b"]
		best = minf(best, minf(p.distance_to(Vector2(a.x, a.z)), p.distance_to(Vector2(b.x, b.z))))
		# Le passage sous le torii reste libre.
		var q := Geometry2D.get_closest_point_to_segment(p, Vector2(a.x, a.z), Vector2(b.x, b.z))
		best = minf(best, p.distance_to(q) + 0.2)
	return best


## Vrai si une plante de rayon `r` posée en p gênerait quelque chose : chemin,
## maison, mur, clôture, seuil de porte, torii, terrasse.
func blocked(p: Vector2, r: float) -> bool:
	if path_clearance(p) < r + 0.1:
		return true
	if house_clearance(p) < r + 0.05:
		return true
	if wall_clearance(p) < r * 0.6 + 0.05:
		return true
	if near_door(p, 1.9 + r):
		return true
	if gate_clearance(p) < r + 0.4:
		return true
	if not terraces.is_empty() and terrace_clearance(p) < r * 0.5 + 0.1:
		return true
	return false

