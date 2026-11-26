@tool
class_name BastidePondShape
extends RefCounted
## Règles de forme d'un étang : d'un contour tracé grossièrement à la souris, une
## rive naturelle (douce, sans angle, légèrement ondulée), un niveau d'eau toujours
## à plat même sur une pente, et le profil du fond creusé dans le relief.
##
## Fonctions pures, sur n'importe quel thread. Coordonnées à plat (x, z).

## Plus petite et plus grande dimension d'un étang (m).
const MIN_AREA := 6.0
const MAX_SIDE := 48.0
## Hauteur de la rive au-dessus de l'eau (m) : la berge affleure, l'eau ne déborde jamais.
const FREEBOARD := 0.2
## Pas de la rive finale (m).
const SPACING := 0.5


## Contour de rive à partir d'un tracé fermé : lissé, rééchantillonné, avec une
## ondulation douce bornée (deux étangs tracés pareil ne sont jamais identiques).
## Sens direct (aire positive en x, z). Vide si le tracé est trop petit.
static func outline(points: PackedVector3Array, seed: int, wobble := 1.0) -> PackedVector2Array:
	var pts := PackedVector3Array()
	for p in points:
		pts.append(Vector3(p.x, 0.0, p.z))
	if pts.size() < 3:
		return PackedVector2Array()
	pts = BastideStroke.ensure_direct(pts)
	# Un tracé main levée a des à-coups : on le simplifie avant de l'arrondir.
	pts = BastideStroke.resample(pts, 0.6, true)
	pts = _clamp_extent(pts)
	if pts.size() >= 8:
		pts = BastideStroke.simplify(pts, 0.35)
	pts = BastideStroke.smooth(pts, true, 4, 0.25, 3.0)
	pts = BastideStroke.resample(pts, SPACING, true)
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(Vector2(p.x, p.z))
	if poly.size() < 6 or absf(BastidePolygon.signed_area(poly)) < MIN_AREA:
		return PackedVector2Array()
	poly = BastidePolygon.ensure_direct(poly)
	# Ondulation : un bruit bouclé le long du périmètre pousse la rive dedans ou dehors.
	var per := BastidePolygon.perimeter(poly)
	var amp := clampf(sqrt(absf(BastidePolygon.signed_area(poly))) * 0.045, 0.12, 0.7) * wobble
	var waves := maxi(3, int(per / 6.0))
	var out := PackedVector2Array()
	var n := poly.size()
	var acc := 0.0
	for i in n:
		if i > 0:
			acc += poly[i].distance_to(poly[i - 1])
		var x := acc / per * waves
		var off := (BastideRng.noise1(seed, "pond_shore", x, waves) - 0.5) * 2.0 * amp
		off += (BastideRng.noise1(seed, "pond_shore_fine", x * 3.0, waves * 3) - 0.5) * amp * 0.35
		out.append(poly[i] + _normal(poly, i) * off)
	# Une ondulation trop forte sur un étang étroit pourrait croiser la rive : on y renonce.
	if BastidePolygon.self_intersects(out):
		return poly
	return out


## Normale sortante (polygone direct) au sommet i.
static func _normal(poly: PackedVector2Array, i: int) -> Vector2:
	var n := poly.size()
	var t := poly[(i + 1) % n] - poly[(i - 1 + n) % n]
	if t.length_squared() < 1e-10:
		return Vector2.ZERO
	t = t.normalized()
	# Polygone direct : l'intérieur est à gauche (-t.y, t.x), l'extérieur à droite.
	return Vector2(t.y, -t.x)


## Normale sortante publique (polygone direct).
static func outward(poly: PackedVector2Array, i: int) -> Vector2:
	return _normal(poly, i)


## Les côtés sont bornés : un étang trop grand est ramené vers son centre.
static func _clamp_extent(pts: PackedVector3Array) -> PackedVector3Array:
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	var side := maxf(box.size.x, box.size.z)
	if side <= MAX_SIDE:
		return pts
	var c := box.get_center()
	var k := MAX_SIDE / side
	var out := PackedVector3Array()
	for p in pts:
		out.append(c + (p - c) * k)
	return out


## Distance signée au contour : négative dans l'eau, positive sur la berge.
static func signed_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var d := INF
	var n := poly.size()
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % n])
		d = minf(d, p.distance_squared_to(q))
	d = sqrt(d)
	return -d if Geometry2D.is_point_in_polygon(p, poly) else d


static func rect_of(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


## Niveau de l'eau (monde) pour une rive posée sur `field` : un peu sous la rive
## la plus basse, remonté vers la moyenne pour ne pas creuser tout le côté haut.
## Le côté bas reçoit une petite digue (voir carve_height).
static func water_level(field: BastideHeightField, world_poly: PackedVector2Array) -> float:
	if field == null or world_poly.is_empty():
		return -FREEBOARD
	var lo := INF
	var sum := 0.0
	for p in world_poly:
		var h := field.height(p.x, p.y)
		lo = minf(lo, h)
		sum += h
	var mean := sum / world_poly.size()
	return lerpf(lo, mean, 0.4) - FREEBOARD


## Profondeur au centre et largeur de la pente du bord, selon la taille.
static func depth_for(poly: PackedVector2Array) -> float:
	return clampf(0.14 * sqrt(absf(BastidePolygon.signed_area(poly))), 0.55, 1.5)


static func shelf_for(poly: PackedVector2Array) -> float:
	var r := rect_of(poly)
	return clampf(minf(r.size.x, r.size.y) * 0.22, 0.9, 3.2)


## Description du creusement (monde) : {poly, level, depth, shelf, bank, rect}.
static func carve_info(world_poly: PackedVector2Array, level: float) -> Dictionary:
	var bank := 2.6
	return {"poly": world_poly, "level": level, "depth": depth_for(world_poly), "shelf": shelf_for(world_poly),
		"bank": bank, "rect": rect_of(world_poly).grow(bank + 4.0)}


## Hauteur du sol creusé en un point : `base` = sol d'origine, `d` = distance signée.
## Dans l'eau : une cuvette douce, du ras de la rive jusqu'au fond (jamais
## remontée au-dessus du sol d'origine au centre). Sur la berge : le sol rejoint
## le ras de la rive, ce qui creuse le côté haut et fait une digue côté bas.
static func carve_height(base: float, d: float, c: Dictionary) -> float:
	var level: float = c["level"]
	var rim := level + FREEBOARD
	if d < 0.0:
		var t := smoothstep(0.0, float(c["shelf"]), -d)
		var bowl := lerpf(rim, level - float(c["depth"]), t)
		return lerpf(bowl, minf(bowl, base), t)
	var bank: float = c["bank"]
	# Plus la berge diffère du sol d'origine, plus elle s'étale (pas de marche).
	var reach := clampf(bank + absf(base - rim) * 1.8, bank, bank + 6.0)
	if d >= reach:
		return base
	var u := smoothstep(0.0, reach, d)
	return lerpf(rim, base, u)


## Couleur de sol (r = berge mouillée, g = lit sous l'eau) au même point.
static func carve_paint(d: float, c: Dictionary) -> Vector2:
	var bed := smoothstep(0.1, -0.6, d)
	var bank := 1.0 - smoothstep(0.0, 1.4, absf(d - 0.15))
	return Vector2(bank, bed)


## Creuse `field` (sol d'origine `base`) et peint `paint` (r = berge, g = lit) sur
## la zone d'un étang. Retourne le rectangle de grille touché (en cases).
static func apply(field: BastideHeightField, base: BastideHeightField, paint: PackedColorArray, c: Dictionary) -> Rect2i:
	var poly: PackedVector2Array = c["poly"]
	var r: Rect2 = c["rect"]
	var i0 := maxi(0, int(floor((r.position.x - field.origin.x) / field.cell)))
	var i1 := mini(field.width - 1, int(ceil((r.end.x - field.origin.x) / field.cell)))
	var j0 := maxi(0, int(floor((r.position.y - field.origin.y) / field.cell)))
	var j1 := mini(field.depth - 1, int(ceil((r.end.y - field.origin.y) / field.cell)))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := field.origin + Vector2(i, j) * field.cell
			var d := signed_distance(p, poly)
			var b := base.at(i, j)
			var h := carve_height(b, d, c)
			# Plusieurs étangs voisins : chacun ne fait que creuser ou combler vers sa
			# rive ; on garde le plus bas des deux dans l'eau.
			var k := j * field.width + i
			var cur := field.heights[k]
			if d < 0.0:
				field.heights[k] = minf(cur, h) if cur != b else h
			elif absf(h - b) > 1e-4:
				field.heights[k] = h if cur == b else (cur + h) * 0.5
			if not paint.is_empty():
				var pc := carve_paint(d, c)
				var col := paint[k]
				paint[k] = Color(maxf(col.r, pc.x), maxf(col.g, pc.y), col.b, col.a)
	return Rect2i(i0, j0, i1 - i0 + 1, j1 - j0 + 1)
