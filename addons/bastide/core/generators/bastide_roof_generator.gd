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
	if roof_type == BastideRoofStyle.RoofType.IRIMOYA:
		if _irimoya(roof, footprint, rs):
			roof.bake()
			_place_chimney(roof, rs, seed)
			return roof
		roof.fallback = "croupes"
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
		var entry := {"a": a3, "b": b3, "kind": kind, "faces": faces}
		for fc in faces:
			if weights[fc] <= 0.0:
				entry["gable"] = fc
		roof.arcs.append(entry)

	roof.bake()
	_place_chimney(roof, rs, seed)
	return roof


## Irimoya : une croupe basse tout autour (bande entre le contour et le contour
## rentré de `d`), puis, au-dessus, un toit à pignons calculé sur le contour rentré.
## Les bouts étroits gardent donc un pan en bas et un petit pignon vertical en haut.
## Renvoie false si le contour ne s'y prête pas (le toit retombe alors en croupes).
static func _irimoya(roof: BastideRoofLayout, footprint: PackedVector2Array, rs: BastideRoofStyle) -> bool:
	var outline := roof.outline
	var n := outline.size()
	var gw := gable_weights(footprint)
	if not gw.has(0.0):
		return false  # aucun bout étroit (plan carré…) : une croupe suffit
	var ones := PackedFloat32Array()
	ones.resize(n)
	ones.fill(1.0)
	var hip := BastideStraightSkeleton.compute(outline, ones)
	if not hip.ok:
		return false
	# Hauteur de la croupe : part de la hauteur du toit, réduite tant que le contour
	# rentré n'est pas propre (une aile étroite disparaîtrait avant).
	var d := hip.max_time * rs.irimoya_ratio
	var inner := PackedVector2Array()
	var upper: BastideStraightSkeleton.Result = null
	for attempt in 5:
		inner = BastidePolygon.offset(outline, d, 6.0)
		if _offset_ok(outline, inner):
			upper = BastideStraightSkeleton.compute(inner, gw)
			if upper.ok:
				break
		upper = null
		d *= 0.7
	if upper == null or d < 0.3:
		return false

	var y_c := roof.base_y + d * roof.tan_pitch
	roof.weights = ones
	roof.irimoya_y = y_c
	for e in n:
		var dir := BastidePolygon.edge_dir(outline, e)
		var nin := Vector2(-dir.y, dir.x)
		var up_dir := Vector3(nin.x, 0.0, nin.y)
		var normal := Vector3(-nin.x * roof.tan_pitch, 1.0, -nin.y * roof.tan_pitch).normalized()
		var j := (e + 1) % n
		var band := PackedVector3Array([
			Vector3(outline[e].x, roof.base_y, outline[e].y), Vector3(outline[j].x, roof.base_y, outline[j].y),
			Vector3(inner[j].x, y_c, inner[j].y), Vector3(inner[e].x, y_c, inner[e].y)])
		var polys: Array = [band]
		var up_polys: Array = []
		for st: PackedVector3Array in upper.strips[e]:
			var p3 := PackedVector3Array()
			for p in st:
				p3.append(Vector3(p.x, y_c + p.y * roof.tan_pitch, p.z))
			up_polys.append(p3)
		if gw[e] > 0.0:
			polys.append_array(up_polys)
		else:
			roof.gable_panels.append({"face": e, "out": -up_dir, "polys": up_polys})
		roof.faces.append({"weight": 1.0, "normal": normal, "up_dir": up_dir,
			"dir": Vector3(dir.x, 0.0, dir.y), "polys": polys})
	roof.ridge_y = y_c + upper.max_time * roof.tan_pitch

	# Arcs de la croupe basse : arêtiers (angles saillants) et noues (angles rentrants).
	for i in n:
		var a3 := Vector3(outline[i].x, roof.base_y, outline[i].y)
		var b3 := Vector3(inner[i].x, y_c, inner[i].y)
		var kind := ArcKind.HIP if BastidePolygon.is_convex_vertex(outline, i) else ArcKind.VALLEY
		roof.arcs.append({"a": a3, "b": b3, "kind": kind, "faces": PackedInt32Array([posmod(i - 1, n), i])})
	# Arcs du toit du haut.
	var reflex := {}
	for i in n:
		if not BastidePolygon.is_convex_vertex(inner, i):
			reflex[inner[i]] = true
	for arc in upper.arcs:
		var a: Vector3 = arc.a
		var b: Vector3 = arc.b
		var a3 := Vector3(a.x, y_c + a.y * roof.tan_pitch, a.z)
		var b3 := Vector3(b.x, y_c + b.y * roof.tan_pitch, b.z)
		var faces: PackedInt32Array = arc.faces
		var kind := ArcKind.HIP
		var gable := -1
		for fc in faces:
			if gw[fc] <= 0.0:
				gable = fc
		if gable >= 0:
			kind = ArcKind.VERGE
		elif absf(a3.y - b3.y) < 1e-3:
			kind = ArcKind.RIDGE
		elif (a.y < 1e-6 and reflex.has(Vector2(a.x, a.z))) or (b.y < 1e-6 and reflex.has(Vector2(b.x, b.z))):
			kind = ArcKind.VALLEY
		var entry := {"a": a3, "b": b3, "kind": kind, "faces": faces}
		if gable >= 0:
			entry["gable"] = gable
		roof.arcs.append(entry)
	return true


## Le contour rentré garde le même nombre de côtés, chacun dans le même sens et
## d'une longueur raisonnable, sans se recouper.
static func _offset_ok(outline: PackedVector2Array, inner: PackedVector2Array) -> bool:
	var n := outline.size()
	if inner.size() != n or BastidePolygon.signed_area(inner) <= 0.0 or BastidePolygon.self_intersects(inner):
		return false
	for i in n:
		var j := (i + 1) % n
		var a := outline[j] - outline[i]
		var b := inner[j] - inner[i]
		if b.length() < 0.25 or a.dot(b) <= 0.0:
			return false
	return true


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
