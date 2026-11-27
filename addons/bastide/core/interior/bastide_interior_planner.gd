@tool
class_name BastideInteriorPlanner
extends RefCounted
## BuildingLayout → InteriorLayout. Fonction pure : aucun nœud, aucun état global.
##
## Règles « toujours juste » :
## - le plancher du rez-de-chaussée est surélevé (à la japonaise, au niveau du
##   soubassement), avec une entrée en contrebas (genkan) derrière la porte et une
##   pierre de marche si la hauteur l'exige ; une maison de pierre a un plancher bas ;
## - un escalier droit par étage, appuyé contre un mur, raide comme dans les vraies
##   maisons (environ 41°), jamais devant la porte, jamais sur la trémie ni sur
##   l'arrivée de l'escalier du dessous (les volées d'une tour changent donc de mur) ;
## - on doit pouvoir s'y tenir debout : la hauteur libre au-dessus des marches et de
##   l'arrivée est vérifiée, sous le plancher suivant comme sous le toit ;
## - entre deux emplacements possibles, celui qui cache le moins de fenêtres et se
##   range dans un angle l'emporte ; le choix est stable (même maison, même escalier).

const Kind := BastideBuildingLayout.OpeningKind
const RISER_MAX := 0.215
const HEADROOM := 1.95
## Place libre au pied de la volée et à son arrivée.
const APPROACH := 0.7
const ARRIVAL := 0.6
## Réglages essayés dans l'ordre : [largeur, giron, place au pied, place à l'arrivée].
## Les suivants, plus raides et plus serrés, pour les tours et les petites bases.
const FLIGHT_TRIES := [[0.8, 0.24, APPROACH, ARRIVAL], [0.72, 0.21, APPROACH, ARRIVAL], [0.7, 0.19, 0.5, 0.5]]


## Le terrain monte au plus à cet endroit, sous la maison (marge pour les sols) ;
## sans terrain, la marge vient du socle seul.
const GROUND_CLEAR := 0.07


## `ground_top` : point le plus haut du terrain sous la maison (repère local), ou -INF.
static func plan(layout: BastideBuildingLayout, style: BastideStyle, ground_top := -INF) -> BastideInteriorLayout:
	var bs := style.get_building_style()
	var il := BastideInteriorLayout.new()
	if layout == null or layout.is_empty():
		return il
	il.timber = layout.timber
	il.base_y = layout.base_y
	il.wall_thickness = layout.wall_thickness
	il.inner = BastidePolygon.ensure_direct(BastidePolygon.offset(layout.footprint, layout.wall_thickness))
	if il.inner.size() < 3 or BastidePolygon.self_intersects(il.inner) or BastidePolygon.signed_area(il.inner) < 2.0:
		il.notes.append("trop petit pour un intérieur")
		return il

	var raise := clampf(bs.plinth_height, 0.25, 0.42) if layout.timber else 0.12
	var ground_y := maxf(layout.base_y + raise, ground_top + GROUND_CLEAR + 0.12)
	# L'entrée en terre battue ne doit jamais passer sous le terrain : on verrait l'herbe.
	var genkan_y := maxf(layout.base_y + 0.03, ground_top + GROUND_CLEAR)

	# --- Porte et entrée -------------------------------------------------------------
	var door_zone := PackedVector2Array()
	for f: BastideBuildingLayout.Facade in layout.facades:
		for o in f.openings:
			if o.kind != Kind.DOOR or o.floor != 0:
				continue
			var c: float = (o.u0 + o.u1) * 0.5
			var th := layout.wall_thickness
			il.door = {"facade": f.index, "u0": o.u0, "u1": o.u1, "y0": o.y0, "y1": o.y1, "arch": o.arch,
				"pos": _fp(f, c, -th), "inward": -f.out}
			var span := _inner_span(f, il.inner)
			var gw := minf(float(o.u1 - o.u0) + 0.6, span.y - span.x - 0.3)
			var gd := minf(1.2, _depth_inside(f, c, il.inner, th) * 0.4)
			var lo := clampf(c - gw * 0.5, span.x + 0.05, span.y - 0.05)
			var hi := clampf(c + gw * 0.5, span.x + 0.05, span.y - 0.05)
			if layout.timber and hi - lo > 0.9 and gd > 0.7:
				il.genkan = BastidePolygon.ensure_direct(PackedVector2Array([
					_fp(f, lo, -th + 0.05), _fp(f, hi, -th + 0.05), _fp(f, hi, -th - gd), _fp(f, lo, -th - gd)]))
				il.genkan_y = genkan_y
				if ground_y - il.genkan_y > 0.3:
					il.step_stone = BastidePolygon.ensure_direct(PackedVector2Array([
						_fp(f, c - 0.38, -th - gd + 0.04), _fp(f, c + 0.38, -th - gd + 0.04),
						_fp(f, c + 0.38, -th - gd + 0.42), _fp(f, c - 0.38, -th - gd + 0.42)]))
					il.step_stone_y = lerpf(il.genkan_y, ground_y, 0.5)
			door_zone = BastidePolygon.ensure_direct(PackedVector2Array([
				_fp(f, c - gw * 0.5 - 0.35, -th + 0.05), _fp(f, c + gw * 0.5 + 0.35, -th + 0.05),
				_fp(f, c + gw * 0.5 + 0.35, -th - gd - 1.0), _fp(f, c - gw * 0.5 - 0.35, -th - gd - 1.0)]))
			break
		if not il.door.is_empty():
			break

	# --- Niveaux ---------------------------------------------------------------------
	for k in layout.floors:
		var lv := BastideInteriorLayout.Level.new()
		lv.index = k
		lv.y = ground_y if k == 0 else layout.base_y + k * layout.floor_height
		lv.rooms.append({"poly": il.inner, "kind": "open"})
		il.levels.append(lv)
	for k in layout.floors - 1:
		(il.levels[k] as BastideInteriorLayout.Level).ceiling_y = (il.levels[k + 1] as BastideInteriorLayout.Level).y - il.slab_thickness

	# --- Escaliers -------------------------------------------------------------------
	var forbidden: Array = [door_zone] if not door_zone.is_empty() else []
	for k in layout.floors - 1:
		var fl := _place_flight(layout, il, k, forbidden)
		if fl == null:
			il.notes.append("pas de place pour l'escalier du niveau %d" % k)
			break
		il.flights.append(fl)
		var up: BastideInteriorLayout.Level = il.levels[k + 1]
		up.holes.append(fl.rect(0.0, 0.0, 0.08))
		up.railings.append([fl.at(0.0, fl.width), fl.at(fl.run(), fl.width)])
		up.railings.append([fl.at(0.0, 0.0), fl.at(0.0, fl.width)])
		# À l'étage suivant, on évite la trémie et l'arrivée de cette volée.
		forbidden = [fl.rect(0.15, ARRIVAL + 0.2, 0.0)]

	# --- Planchers découpés ------------------------------------------------------------
	for lv: BastideInteriorLayout.Level in il.levels:
		var cuts: Array = lv.holes.duplicate()
		if lv.index == 0 and not il.genkan.is_empty():
			cuts.append(il.genkan)
		lv.pieces = subtract(il.inner, cuts)
	return il


## Point du plan : u le long de la façade, d vers l'extérieur (négatif = vers l'intérieur).
static func _fp(f: BastideBuildingLayout.Facade, u: float, d: float) -> Vector2:
	return f.a + f.dir * u + f.out * d


## Étendue [u0, u1] de la face intérieure d'une façade.
static func _inner_span(f: BastideBuildingLayout.Facade, inner: PackedVector2Array) -> Vector2:
	var i := f.index
	var a := inner[i]
	var b := inner[(i + 1) % inner.size()]
	return Vector2((a - f.a).dot(f.dir), (b - f.a).dot(f.dir))


## Profondeur libre vers l'intérieur depuis le milieu d'une façade (jusqu'au mur d'en face).
static func _depth_inside(f: BastideBuildingLayout.Facade, u: float, inner: PackedVector2Array, th: float) -> float:
	var o := _fp(f, u, -th - 0.01)
	var far := o - f.out * 200.0
	var best := 200.0
	var n := inner.size()
	for i in n:
		var hit: Variant = Geometry2D.segment_intersects_segment(o, far, inner[i], inner[(i + 1) % n])
		if hit != null:
			best = minf(best, o.distance_to(hit))
	return best


static func _place_flight(layout: BastideBuildingLayout, il: BastideInteriorLayout, k: int,
		forbidden: Array) -> BastideInteriorLayout.Flight:
	var from: BastideInteriorLayout.Level = il.levels[k]
	var to: BastideInteriorLayout.Level = il.levels[k + 1]
	var grown := BastidePolygon.offset(il.inner, -0.02)
	var top := k + 1 == il.levels.size() - 1
	var ceiling_above := INF if top else (il.levels[k + 2] as BastideInteriorLayout.Level).y - il.slab_thickness
	for tries: Array in FLIGHT_TRIES:
		var width: float = tries[0]
		var tread: float = tries[1]
		var approach: float = tries[2]
		var arrival: float = tries[3]
		var steps := ceili((to.y - from.y) / RISER_MAX - 1e-4)
		var run := steps * tread
		var best: BastideInteriorLayout.Flight = null
		var best_score := INF
		var cand := 0
		for f: BastideBuildingLayout.Facade in layout.facades:
			var i := f.index
			var ea := il.inner[i]
			var eb := il.inner[(i + 1) % il.inner.size()]
			var edge := eb - ea
			var length := edge.length()
			var total := approach + run + arrival
			if length < total:
				continue
			var d := edge / length
			var side := Vector2(-d.y, d.x)
			for s in [1, -1]:
				var lo := 0.0
				while lo + total <= length + 1e-4:
					cand += 1
					var fl := BastideInteriorLayout.Flight.new()
					fl.from_level = k
					fl.width = width
					fl.tread = tread
					fl.steps = steps
					fl.y0 = from.y
					fl.y1 = to.y
					fl.facade = i
					fl.side = side
					if s == 1:
						fl.dir = d
						fl.start = ea + d * (lo + approach)
					else:
						fl.dir = -d
						fl.start = ea + d * (lo + run + arrival)
					var score := _score(layout, il, fl, f, lo, length - lo - total, grown, forbidden, ceiling_above, top, approach, arrival)
					score += BastideRng.randf_at(layout.seed, "stair", BastideRng.combine(k, cand)) * 0.05
					if score < best_score:
						best_score = score
						best = fl
					lo += 0.2
		if best != null:
			return best
	return null


## Coût d'un emplacement (INF s'il ne va pas).
static func _score(layout: BastideBuildingLayout, il: BastideInteriorLayout, fl: BastideInteriorLayout.Flight,
		f: BastideBuildingLayout.Facade, gap_start: float, gap_end: float, grown: PackedVector2Array,
		forbidden: Array, ceiling_above: float, top: bool, approach: float, arrival: float) -> float:
	var whole := fl.rect(approach, arrival, 0.0)
	if not inside(whole, grown):
		return INF
	for z: PackedVector2Array in forbidden:
		if overlaps(whole, z):
			return INF
	# Hauteur libre au-dessus des marches et de l'arrivée.
	var along := 0.3
	while along <= fl.run() + arrival:
		for across in [0.15, fl.width - 0.15]:
			var p := fl.at(along, across)
			var head := fl.height_at(along) + HEADROOM
			var ceil := ceiling_above
			if top:
				var h := layout.roof.height_at(p) - layout.roof.thickness if layout.roof else INF
				ceil = h if is_finite(h) else -INF
			if head > ceil:
				return INF
		along += 0.4
	var score := 0.0
	# Fenêtres masquées par la volée (de ce niveau et du suivant).
	var ua := (fl.start - f.a).dot(f.dir)
	var ub := (fl.at(fl.run(), 0.0) - f.a).dot(f.dir)
	var u0 := minf(ua, ub)
	var u1 := maxf(ua, ub)
	for o in f.openings:
		if o.kind == Kind.ATTIC or (o.floor != fl.from_level and o.floor != fl.from_level + 1):
			continue
		var ov := minf(u1, o.u1 + 0.1) - maxf(u0, o.u0 - 0.1)
		if ov > 0.0:
			score += ov * (3.0 if o.kind == Kind.WINDOW else 10.0)
	if not il.door.is_empty() and int(il.door["facade"]) == f.index:
		score += 1.5
	# Rangée dans un angle.
	score += 0.15 * minf(gap_start, gap_end)
	return score


## Vrai si `a` est entièrement dans `b`.
static func inside(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for piece in Geometry2D.clip_polygons(a, b):
		if absf(BastidePolygon.signed_area(piece)) > 1e-3:
			return false
	return true


static func overlaps(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for piece in Geometry2D.intersect_polygons(a, b):
		if absf(BastidePolygon.signed_area(piece)) > 1e-3:
			return true
	return false


## Polygone moins des découpes (qui traversent son bord) : morceaux dans le sens direct.
static func subtract(poly: PackedVector2Array, cuts: Array) -> Array:
	var pieces: Array = [poly]
	for c: PackedVector2Array in cuts:
		var next: Array = []
		for p: PackedVector2Array in pieces:
			var res := Geometry2D.clip_polygons(p, c)
			# Un trou fermé (découpe entièrement intérieure) serait rendu plein : on le garde
			# tel quel plutôt que de perdre le plancher.
			var cw := 0
			for q: PackedVector2Array in res:
				cw += 1 if Geometry2D.is_polygon_clockwise(q) else 0
			if cw != 0 and cw != res.size():
				next.append(p)
				continue
			for q: PackedVector2Array in res:
				if absf(BastidePolygon.signed_area(q)) > 1e-3:
					next.append(BastidePolygon.ensure_direct(q))
		pieces = next
	return pieces
