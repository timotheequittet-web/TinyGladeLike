@tool
class_name BastideRoofGenerator
extends RefCounted
## Contour + style → BastideRoofLayout. Fonction pure.
##
## Règles « toujours beau » :
## - le toit déborde des murs du même `overhang` partout, et son dessous repose
##   pile sur le haut des murs ;
## - en mode pignons, seuls les bouts étroits d'une aile (deux angles saillants
##   d'environ 90°, côté nettement plus court que l'aile) deviennent des pignons ; un
##   plan carré garde un toit en pavillon ;
## - si un calcul échoue (contour extrême), on se replie sur des croupes, puis
##   sur un toit plat : jamais de trou ni d'erreur.

const ArcKind := BastideRoofLayout.ArcKind


static func generate(footprint: PackedVector2Array, eave_y: float, rs: BastideRoofStyle,
		roof_type: int, seed: int) -> BastideRoofLayout:
	var roof := BastideRoofLayout.new()
	roof.eave_y = eave_y
	roof.pitch_deg = rs.pitch
	roof.tan_pitch = tan(deg_to_rad(rs.pitch))
	roof.thickness = rs.thickness
	roof.overhang = rs.overhang
	if not rs.roof_colors.is_empty():
		var ci := int(BastideRng.randf_at(seed, "roof_color") * rs.roof_colors.size()) % rs.roof_colors.size()
		var tint := BastideRng.signed_at(seed, "roof_tint") * 0.04
		var c := rs.roof_colors[ci]
		roof.color = c.lightened(tint) if tint > 0.0 else c.darkened(-tint)
	if footprint.size() < 3:
		return roof

	var outline := BastidePolygon.offset(footprint, -rs.overhang, 3.0)
	if BastidePolygon.self_intersects(outline) or BastidePolygon.signed_area(outline) <= 0.0:
		outline = footprint
		roof.overhang = 0.0
	roof.outline = outline
	roof.base_y = eave_y + rs.thickness - roof.overhang * roof.tan_pitch

	var n := outline.size()
	var ones := PackedFloat32Array()
	ones.resize(n)
	ones.fill(1.0)
	var weights := ones
	if roof_type == BastideRoofStyle.RoofType.GABLE:
		weights = gable_weights(footprint)
	var sk := BastideStraightSkeleton.compute(outline, weights)
	if not sk.ok and weights != ones:
		weights = ones
		roof.fallback = "croupes"
		sk = BastideStraightSkeleton.compute(outline, weights)
	if not sk.ok:
		_flat(roof, footprint)
		return roof
	roof.weights = weights

	# --- Pans ---------------------------------------------------------------
	for e in n:
		var d := BastidePolygon.edge_dir(outline, e)
		var nin := Vector2(-d.y, d.x)
		var up_dir := Vector3(nin.x, 0.0, nin.y)
		var normal := Vector3.UP if weights[e] > 0.0 else -up_dir
		if weights[e] > 0.0:
			normal = Vector3(-nin.x * roof.tan_pitch, 1.0, -nin.y * roof.tan_pitch).normalized()
		var polys: Array = []
		for s: PackedVector3Array in sk.strips[e]:
			var p3 := PackedVector3Array()
			for p in s:
				p3.append(Vector3(p.x, roof.base_y + p.y * roof.tan_pitch, p.z))
			polys.append(p3)
		roof.faces.append({"weight": weights[e], "normal": normal, "up_dir": up_dir,
			"dir": Vector3(d.x, 0.0, d.y), "polys": polys})
	roof.ridge_y = roof.base_y + sk.max_time * roof.tan_pitch

	# --- Arcs ---------------------------------------------------------------
	var reflex := {}
	for i in n:
		if not BastidePolygon.is_convex_vertex(outline, i):
			reflex[outline[i]] = true
	for arc in sk.arcs:
		var a: Vector3 = arc.a
		var b: Vector3 = arc.b
		var a3 := Vector3(a.x, roof.base_y + a.y * roof.tan_pitch, a.z)
		var b3 := Vector3(b.x, roof.base_y + b.y * roof.tan_pitch, b.z)
		var faces: PackedInt32Array = arc.faces
		var kind := ArcKind.HIP
		var verge := false
		for fc in faces:
			verge = verge or weights[fc] <= 0.0
		if verge:
			kind = ArcKind.VERGE
		elif absf(a3.y - b3.y) < 1e-3:
			kind = ArcKind.RIDGE
		elif (a.y < 1e-6 and reflex.has(Vector2(a.x, a.z))) or (b.y < 1e-6 and reflex.has(Vector2(b.x, b.z))):
			kind = ArcKind.VALLEY
		roof.arcs.append({"a": a3, "b": b3, "kind": kind, "faces": faces})

	roof.bake()
	_place_chimney(roof, rs, seed)
	return roof


## Pignons : bouts étroits d'aile (deux angles saillants proches de 90°, côté plus
## court que l'aile qu'il termine), jamais deux pignons côte à côte.
static func gable_weights(fp: PackedVector2Array) -> PackedFloat32Array:
	var n := fp.size()
	var w := PackedFloat32Array()
	w.resize(n)
	w.fill(1.0)
	var lens := PackedFloat32Array()
	for i in n:
		lens.append(fp[i].distance_to(fp[(i + 1) % n]))
	for i in n:
		var j := (i + 1) % n
		if not BastidePolygon.is_convex_vertex(fp, i) or not BastidePolygon.is_convex_vertex(fp, j):
			continue
		var ai := rad_to_deg(BastidePolygon.turn_angle(fp, i))
		var aj := rad_to_deg(BastidePolygon.turn_angle(fp, j))
		if absf(ai - 90.0) > 25.0 or absf(aj - 90.0) > 25.0:
			continue
		var lp := lens[posmod(i - 1, n)]
		var ln := lens[j]
		# Bout étroit : plus court que le plus long voisin, sans dépasser de beaucoup l'autre.
		if lens[i] > 0.92 * maxf(lp, ln) or lens[i] > 1.25 * minf(lp, ln):
			continue
		if w[posmod(i - 1, n)] <= 0.0 or w[j] <= 0.0:
			continue
		w[i] = 0.0
	return w


static func _flat(roof: BastideRoofLayout, fp: PackedVector2Array) -> void:
	roof.fallback = "plat"
	roof.outline = fp
	roof.overhang = 0.0
	roof.base_y = roof.eave_y + roof.thickness
	roof.ridge_y = roof.base_y
	roof.weights = PackedFloat32Array()
	var idx := BastidePolygon.triangulate(fp)
	var polys: Array = []
	for t in range(0, idx.size(), 3):
		var p3 := PackedVector3Array()
		for k in 3:
			var p := fp[idx[t + k]]
			p3.append(Vector3(p.x, roof.base_y, p.y))
		polys.append(p3)
	roof.weights.append(1.0)
	roof.faces.append({"weight": 1.0, "normal": Vector3.UP, "up_dir": Vector3.ZERO,
		"dir": Vector3.RIGHT, "polys": polys})
	roof.bake()


## Cheminée posée près du plus long faîtage horizontal, d'un côté ou de l'autre.
static func _place_chimney(roof: BastideRoofLayout, rs: BastideRoofStyle, seed: int) -> void:
	if BastideRng.randf_at(seed, "chimney") >= rs.chimney_chance:
		return
	var best := {}
	var best_len := 1.4
	for arc in roof.arcs:
		if arc.kind != ArcKind.RIDGE:
			continue
		var l := Vector2(arc.a.x, arc.a.z).distance_to(Vector2(arc.b.x, arc.b.z))
		if l > best_len:
			best_len = l
			best = arc
	if best.is_empty():
		return
	var a := Vector2(best.a.x, best.a.z)
	var b := Vector2(best.b.x, best.b.z)
	var u := BastideRng.randf_range_at(seed, "chimney_u", 0, 0.22, 0.78)
	var side := 1.0 if BastideRng.randf_at(seed, "chimney_side") < 0.5 else -1.0
	var d := (b - a).normalized()
	var size := 0.72
	var pos := a.lerp(b, u) + Vector2(-d.y, d.x) * side * (size * 0.5 + 0.25)
	roof.chimney = {"pos": pos, "size": size, "y0": roof.eave_y - 0.3, "y1": float(best.a.y) + 0.95}
