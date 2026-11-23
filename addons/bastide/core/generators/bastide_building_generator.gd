@tool
class_name BastideBuildingGenerator
extends RefCounted
## BuildingSpec + style → BuildingLayout. Fonction pure : aucun nœud, aucun état global.
##
## Règles « toujours beau » :
## - contour assaini et redressé (BastideFootprintSanitizer) ;
## - fenêtres en travées régulières, centrées, à bonne distance des angles,
##   alignées d'un étage à l'autre ;
## - une seule porte, au milieu de la plus longue façade sous égout : la travée
##   de porte est toujours centrale (nombre de travées impair) ;
## - volets seulement s'ils ont la place de s'ouvrir ; petite fenêtre dans les
##   pignons assez hauts ;
## - le haut de chaque mur suit exactement le dessous du toit.

const Kind := BastideBuildingLayout.OpeningKind
const MIN_PIER := 0.7


static func generate(spec: BastideBuildingSpec, style: BastideStyle) -> BastideBuildingLayout:
	var bs := style.get_building_style()
	var rs := style.get_roof_style()
	var layout := BastideBuildingLayout.new()
	layout.seed = spec.seed
	layout.base_y = spec.base_y
	layout.floors = spec.floors if spec.floors > 0 else bs.floors
	layout.floor_height = bs.floor_height
	layout.wall_thickness = bs.wall_thickness
	layout.eave_y = spec.base_y + layout.floors * bs.floor_height + bs.knee_height

	var clean := BastideFootprintSanitizer.sanitize(spec.footprint, bs.min_edge, bs.square_corners, bs.square_tolerance)
	layout.notes = clean.notes
	var fp: PackedVector2Array = clean.points
	if fp.size() < 3:
		return layout
	layout.footprint = fp

	var roof_type := spec.roof_type if spec.roof_type >= 0 else int(rs.roof_type)
	layout.roof = BastideRoofGenerator.generate(fp, layout.eave_y, rs, roof_type, spec.seed)
	if layout.roof.fallback != "":
		layout.notes.append("toit de repli : " + layout.roof.fallback)

	# --- Couleurs tirées une fois par bâtiment ---------------------------------
	var plaster := bs.plaster_color.lerp(bs.plaster_color_alt, BastideRng.randf_at(spec.seed, "plaster"))
	if not bs.shutter_colors.is_empty():
		var si := int(BastideRng.randf_at(spec.seed, "shutter_color") * bs.shutter_colors.size()) % bs.shutter_colors.size()
		layout.shutter_color = bs.shutter_colors[si]
	var has_shutters := BastideRng.randf_at(spec.seed, "shutters") < bs.shutter_chance
	if not bs.noren_colors.is_empty():
		var ni := int(BastideRng.randf_at(spec.seed, "noren") * bs.noren_colors.size()) % bs.noren_colors.size()
		layout.noren_color = bs.noren_colors[ni]
	layout.timber = bs.facade_kind == BastideBuildingStyle.FacadeKind.TIMBER
	layout.pent_roof = bs.pent_roof and layout.floors >= 2

	# --- Façades -------------------------------------------------------------------
	var n := fp.size()
	for i in n:
		var f := BastideBuildingLayout.Facade.new()
		f.index = i
		f.a = fp[i]
		f.b = fp[(i + 1) % n]
		f.length = f.a.distance_to(f.b)
		f.dir = (f.b - f.a) / maxf(f.length, 1e-6)
		f.out = Vector2(f.dir.y, -f.dir.x)
		f.convex_start = BastidePolygon.is_convex_vertex(fp, i)
		f.convex_end = BastidePolygon.is_convex_vertex(fp, (i + 1) % n)
		f.profile = _wall_profile(layout.roof, f, layout.eave_y)
		for p in f.profile:
			f.gable = f.gable or p.y > layout.eave_y + 0.05
		var shade := BastideRng.signed_at(spec.seed, "facade_shade", i) * 0.025
		f.plaster = plaster.lightened(shade) if shade > 0.0 else plaster.darkened(-shade)
		layout.facades.append(f)

	# --- Porte -----------------------------------------------------------------------
	var door_facade := -1
	var src := spec.footprint
	if spec.door_facade >= 0 and spec.door_facade < src.size():
		# Le côté choisi sur le tracé d'origine : on retrouve la façade la plus proche
		# (le contour a pu être redressé, simplifié ou retourné).
		var mid := (src[spec.door_facade] + src[(spec.door_facade + 1) % src.size()]) * 0.5
		var best_d := INF
		for f: BastideBuildingLayout.Facade in layout.facades:
			var d := mid.distance_to(Geometry2D.get_closest_point_to_segment(mid, f.a, f.b))
			if d < best_d:
				best_d = d
				door_facade = f.index
	if door_facade < 0:
		var best := -1.0
		for f: BastideBuildingLayout.Facade in layout.facades:
			if f.length < bs.door_width + 2.0 * 0.5:
				continue
			# Une façade sous égout (pas un pignon) est préférée à longueur égale.
			var score := f.length + (0.0 if f.gable else 3.0)
			if score > best + 1e-3:
				best = score
				door_facade = f.index

	# --- Ouvertures ----------------------------------------------------------------
	for f: BastideBuildingLayout.Facade in layout.facades:
		_place_openings(f, layout, bs, f.index == door_facade, has_shutters, spec.seed)
		if layout.timber:
			_place_posts(f, bs)
	return layout


## Ossature bois : un poteau entre deux travées, et des poteaux réguliers (environ
## un « ken », 1,8 m) sur les façades aveugles. Jamais à travers une ouverture ni
## collé à un angle.
static func _place_posts(f: BastideBuildingLayout.Facade, bs: BastideBuildingStyle) -> void:
	var cand := PackedFloat32Array()
	var windows: Array = f.openings.filter(func(o): return o.kind != Kind.ATTIC)
	if windows.is_empty():
		var count := maxi(1, roundi(f.length / 1.8))
		for i in range(1, count):
			cand.append(f.length * i / count)
	else:
		var spans: Array = []
		for o in windows:
			spans.append(Vector2(o.u0, o.u1))
		spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		# Entre deux ouvertures voisines, et entre l'angle et la première/dernière.
		var prev := 0.0
		for sp: Vector2 in spans:
			if sp.x - prev > 0.9:
				cand.append((prev + sp.x) * 0.5 if prev > 0.0 else sp.x - bs.post_width * 0.5 - 0.12)
			prev = maxf(prev, sp.y)
		if f.length - prev > 0.9:
			cand.append(prev + bs.post_width * 0.5 + 0.12)
	var half := bs.post_width * 0.5
	for u in cand:
		if u < half + 0.45 or u > f.length - half - 0.45:
			continue
		var clear := true
		for o in f.openings:
			if u + half > o.u0 - 0.03 and u - half < o.u1 + 0.03:
				clear = false
		if clear and (f.posts.is_empty() or u - f.posts[f.posts.size() - 1] > bs.post_width * 2.0):
			f.posts.append(u)


## Haut du mur le long d'une façade : le dessous du toit, jamais sous l'égout.
static func _wall_profile(roof: BastideRoofLayout, f: BastideBuildingLayout.Facade, eave_y: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ts := roof.crossings(f.a, f.b)
	var last := -1.0
	for t in ts:
		if t - last < 1e-4:
			continue
		last = t
		var h := roof.height_at(f.a.lerp(f.b, t)) - roof.thickness
		out.append(Vector2(t * f.length, maxf(eave_y, h) if is_finite(h) else eave_y))
	# Points alignés retirés : un mur sous égout n'a que ses deux bouts.
	var i := 1
	while i < out.size() - 1:
		var a := out[i - 1]
		var b := out[i]
		var c := out[i + 1]
		if absf((b - a).cross(c - a)) < 1e-4 * maxf((c - a).length(), 1e-3):
			out.remove_at(i)
		else:
			i += 1
	return out


## Hauteur du profil à l'abscisse u.
static func profile_at(f: BastideBuildingLayout.Facade, u: float) -> float:
	var p := f.profile
	for i in p.size() - 1:
		if u <= p[i + 1].x or i == p.size() - 2:
			var span := p[i + 1].x - p[i].x
			var t := clampf((u - p[i].x) / span, 0.0, 1.0) if span > 1e-6 else 0.0
			return lerpf(p[i].y, p[i + 1].y, t)
	return p[0].y if not p.is_empty() else 0.0


static func _place_openings(f: BastideBuildingLayout.Facade, layout: BastideBuildingLayout,
		bs: BastideBuildingStyle, has_door: bool, has_shutters: bool, seed: int) -> void:
	var margin := bs.corner_margin
	var usable := f.length - 2.0 * margin
	var ww := bs.window_width
	var count := 0
	if usable >= ww:
		count = maxi(1, roundi(usable / bs.bay_width))
		while count > 1 and count * ww + (count - 1) * MIN_PIER > usable:
			count -= 1
	if has_door:
		if count == 0 and f.length >= bs.door_width + 1.0:
			count = 1
			usable = 0.0
		elif count % 2 == 0:
			count = count + 1 if (count + 1) * ww + count * MIN_PIER <= usable else count - 1
	if count == 0:
		_place_attic(f, layout, bs)
		return
	var centers := PackedFloat32Array()
	for k in count:
		centers.append(margin + usable * (k + 0.5) / count if usable > 0.0 else f.length * 0.5)
	var door_k := count / 2 if has_door else -1

	# Volets : il faut la place de les ouvrir des deux côtés.
	var spacing := usable / count if count > 0 else 0.0
	var shutters := has_shutters and spacing - ww >= ww + 0.3 and margin + spacing * 0.5 - ww * 0.5 >= ww * 0.5 + 0.3

	for fl in layout.floors:
		var y_floor := layout.base_y + fl * layout.floor_height
		for k in count:
			var c := centers[k]
			if fl == 0 and k == door_k:
				var dw := bs.door_width
				var r := dw * 0.5 if bs.arched_door else 0.0
				# La porte et son arc restent sous le bandeau de l'étage.
				var limit := minf(layout.floor_height - 0.35, layout.eave_y - layout.base_y - 0.3)
				var dh := minf(bs.door_height, limit - r - 0.2)
				f.openings.append({"kind": Kind.DOOR, "u0": c - dw * 0.5, "u1": c + dw * 0.5,
					"y0": layout.base_y, "y1": layout.base_y + dh, "arch": r, "floor": 0,
					"shutters": false, "flowers": false})
				continue
			var y0 := y_floor + bs.sill_height
			var y1 := y0 + bs.window_height
			if y1 > layout.eave_y - 0.3 or y0 < layout.base_y + bs.plinth_height + 0.1:
				continue
			var key := BastideRng.combine(BastideRng.combine(f.index, fl), k)
			f.openings.append({"kind": Kind.WINDOW, "u0": c - ww * 0.5, "u1": c + ww * 0.5,
				"y0": y0, "y1": y1, "arch": 0.0, "floor": fl, "shutters": shutters,
				"flowers": BastideRng.randf_at(seed, "flowers", key) < bs.flower_box_chance})
	_place_attic(f, layout, bs)


## Petite fenêtre au milieu d'un pignon, s'il est assez haut.
static func _place_attic(f: BastideBuildingLayout.Facade, layout: BastideBuildingLayout, bs: BastideBuildingStyle) -> void:
	if not bs.attic_windows or not f.gable:
		return
	var peak := f.profile[0]
	for p in f.profile:
		if p.y > peak.y:
			peak = p
	var rise := peak.y - layout.eave_y
	if rise < 1.7:
		return
	var w := 0.55
	var h := 0.7
	var c := peak.x
	var y0 := layout.eave_y + rise * 0.3
	var y1 := y0 + h
	if c - w < 0.6 or c + w > f.length - 0.6:
		return
	if profile_at(f, c - w * 0.5 - 0.2) < y1 + 0.3 or profile_at(f, c + w * 0.5 + 0.2) < y1 + 0.3:
		return
	f.openings.append({"kind": Kind.ATTIC, "u0": c - w * 0.5, "u1": c + w * 0.5, "y0": y0, "y1": y1,
		"arch": 0.0, "floor": layout.floors, "shutters": false, "flowers": false})
