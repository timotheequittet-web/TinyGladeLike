@tool
class_name BastideBurrowBuilder
extends RefCounted
## Maisons-terriers : des habitations creusées dans des buttes herbeuses.
##
## Le contour au sol ne donne pas des murs et un toit mais une ou plusieurs buttes
## arrondies (une par porte : un long tracé en aligne plusieurs, séparées par de
## petits cols). La façade de chaque butte est taillée dans l'herbe, abritée sous
## une avancée de gazon : porte ronde peinte avec son bouton au centre, couronne de
## pierres, fenêtres rondes à croisillons et leurs jardinières, cheminée de pierre
## qui sort de l'herbe, muret de pierres sèches en arc devant la porte, lanterne,
## bûches, tonneaux, meules de foin et potagers en caisses. Fleurs, touffes d'herbe
## et buissons couvrent les flancs.
##
## Règles « toujours beau » : la porte est au milieu de la façade choisie (le côté
## de la porte du tracé, sinon le plus long) ; les fenêtres ne sont posées que là où
## la butte est assez haute pour les abriter ; tout le décor laisse le seuil libre.
##
## Calcul pur (aucun nœud), sur n'importe quel thread. Les ancres reprennent celles
## d'une maison (portes, contour, fumée, lumières) : chemins, jardin et vie du
## hameau s'y raccordent sans rien savoir des terriers.

const ROLE_BODY := BastideBuildingMesher.ROLE_BODY
const ROLE_WOOD := BastideBuildingMesher.ROLE_WOOD
const ROLE_GLASS := BastideBuildingMesher.ROLE_GLASS
const ROLE_PAPER := BastideBuildingMesher.ROLE_PAPER
const ROLE_TURF := &"turf"
const ROLE_EARTH := &"earth"

## Débord de la butte au-delà du tracé (m).
const SKIRT := 2.3
## Avancée de l'herbe au-dessus de la façade.
const LIP := 0.26
## Épaisseur de l'avancée (la façade s'arrête dessous).
const LIP_DROP := 0.24
## Pente de l'herbe qui monte du haut de la façade vers le sommet de la butte.
const BROW_SLOPE := 0.85
## Hors du front d'herbe, la butte maillée s'enfonce de ça sous le relief.
const SINK := 0.3
## Pas du maillage de la butte.
const STEP := 0.38
## Les flancs de la façade avancent en arc autour de la porte.
const WING := 1.1

const STRAW := Color(0.84, 0.68, 0.34)
const LOG := Color(0.36, 0.25, 0.16)
const LOG_END := Color(0.72, 0.56, 0.36)
const IRON := Color(0.12, 0.11, 0.1)
const BRASS := Color(0.86, 0.66, 0.26)
const SOIL := Color(0.24, 0.17, 0.11)
const SOFFIT := Color(0.3, 0.2, 0.12)
const BRICK := Color(0.62, 0.33, 0.24)
const BRICK_ALT := Color(0.52, 0.27, 0.2)


## Une butte : un dôme, sa façade et sa porte.
class Mound:
	var cx := 0.0       ## centre, le long de la façade
	var w := 8.0        ## largeur de la part du tracé
	var h := 3.0        ## hauteur au sommet
	var ax := 5.0       ## demi-largeur du dôme (avec son débord)
	var zc := 1.2       ## ligne de crête (au-delà, le dôme redescend vers l'arrière)
	var az := 6.0       ## portée du dôme derrière la crête
	var dz := 0.0       ## recul de la façade (buttes voisines un peu décalées)
	var seed := 0
	var door_color := Color.WHITE
	var cap := 2.5      ## haut de la façade (au-dessus de la porte)
	var face_half := 3.3  ## demi-largeur de la façade : au-delà, l'herbe descend au sol
	## Pièce creusée dans la butte (repère de façade : x, z, largeur, profondeur).
	var room := Rect2()
	## Profil de la voûte de la pièce : hauteur au milieu et au pied des murs.
	var vault_h := 2.3
	var wall_h := 1.25

	## Haut de la voûte à l'abscisse x (repère de façade).
	func ceil_at(x: float) -> float:
		var u := clampf((x - cx) / (room.size.x * 0.5), -1.0, 1.0)
		return wall_h + (vault_h - wall_h) * sqrt(maxf(1.0 - u * u, 0.0))

	## Zone sans relief autour de la pièce (le sol du terrain n'y monte pas).
	func hollow(margin := 1.2) -> Rect2:
		return Rect2(room.position - Vector2(margin, 2.5), room.size + Vector2(margin * 2.0, margin + 2.5))

	func height(x: float, z: float) -> float:
		var dx := (x - cx) / ax
		var dzz := maxf(z - zc - dz, 0.0) / az
		var r2 := dx * dx + dzz * dzz
		if r2 >= 1.0:
			return 0.0
		return h * pow(1.0 - r2, 1.4)

	## Position de la façade (z) devant la colonne x : les flancs avancent un peu.
	func face_z(x: float) -> float:
		var dx := absf(x - cx) / ax
		return dz - WING * smoothstep(0.3, 0.95, dx)


## Repère de la façade : origine au milieu du côté de la porte, X le long de la
## façade, Z vers l'intérieur de la butte. y = hauteur (sol à base_y).
class Frame:
	var o := Vector2.ZERO
	var x := Vector2.RIGHT
	var z := Vector2.DOWN
	var y0 := 0.0
	var mounds: Array = []

	func p(px: float, py: float, pz: float) -> Vector3:
		var q := o + x * px + z * pz
		return Vector3(q.x, y0 + py, q.y)

	func dir(px: float, pz: float) -> Vector3:
		var q := x * px + z * pz
		return Vector3(q.x, 0.0, q.y)

	func height(px: float, pz: float) -> float:
		var best := 0.0
		for m: Mound in mounds:
			best = maxf(best, m.height(px, pz))
		return best

	## Butte qui domine la colonne x (celle dont la façade passe là).
	func owner(px: float) -> Mound:
		var best: Mound = mounds[0]
		var bh := -1.0
		for m: Mound in mounds:
			var hh := m.height(px, m.zc + m.dz)
			if hh > bh:
				bh = hh
				best = m
		return best

	func face_z(px: float) -> float:
		return owner(px).face_z(px)

	## Haut de l'herbe au-dessus de la façade : la façade ne monte qu'un peu
	## au-dessus de la porte, et s'efface sur les côtés où l'herbe descend au sol.
	func brow(px: float) -> float:
		var m := owner(px)
		var d := absf(px - m.cx)
		var u := clampf(d / m.face_half, 0.0, 1.0)
		var c := m.cap * (1.0 - 0.25 * u * u) * sqrt(1.0 - smoothstep(0.86, 1.0, u))
		return c + LIP_DROP * smoothstep(0.0, 0.5, c)

	## Hauteur de l'herbe au bord de l'avancée, au-dessus de la façade.
	func face_top(px: float) -> float:
		return surface(px, face_z(px))

	## Hauteur du sol de la butte : le dôme, rabattu au-dessus de la façade en un
	## front d'herbe qui descend jusqu'à elle.
	func surface(px: float, pz: float) -> float:
		var zf := face_z(px)
		var hh := height(px, maxf(pz, zf))
		return minf(hh, brow(px) + BROW_SLOPE * maxf(pz - zf, 0.0))


## `open` : variante « on peut entrer » (vantail à part, passage dans la collision,
## pièce voûtée dans anchors.interior_result / interior_layout).
static func build(spec: BastideBuildingSpec, style: BastideStyle, with_collision: bool, open := false) -> BastideBuildResult:
	var result := BastideBuildResult.new()
	var bs := style.get_building_style()
	var ws := style.get_wall_style()
	var clean := BastideFootprintSanitizer.sanitize(spec.footprint, bs.min_edge, bs.square_corners, bs.square_tolerance)
	var fp: PackedVector2Array = clean.points
	if fp.size() < 3:
		return result
	var t0 := Time.get_ticks_usec()
	var fr := _frame(fp, spec, bs)
	var width: float = fr.get_meta("width")
	var depth: float = fr.get_meta("depth")

	var mb := BastideMeshBuilder.new()
	var groups := {}   # clé → {mesh, mat, xf: Array, shadow}
	var lights := PackedVector3Array()
	var smoke := PackedVector3Array()
	var doors: Array = []
	var windows: Array = []
	var holes: Array = []   # [x, y, r] dans le plan de façade

	# --- Portes, fenêtres (avant la façade : elle se perce autour) ---
	var door_r := clampf(bs.door_width * 0.5, 0.7, 1.3)
	var win_r := clampf(bs.window_width * 0.5, 0.3, 0.75)
	for m: Mound in fr.mounds:
		m.cap = minf(door_r * 1.97 + 0.55, m.h * 0.72)
		m.face_half = minf(door_r + 0.95 + win_r * 2.0 + 0.95, m.w * 0.5 + 0.3)
		_plan_room(fr, m, depth)
	var leaves: Array = []
	for m: Mound in fr.mounds:
		var mz := m.face_z(m.cx)
		var dyc := door_r * 0.97
		holes.append([m.cx, dyc, door_r])
		_door(mb, fr, m, door_r, dyc, mz, bs, ws, leaves if open else null, style)
		doors.append({"pos": fr.p(m.cx, 0.0, mz), "out": -fr.dir(0.0, 1.0), "width": door_r * 2.0})
		for s in [-1.0, 1.0]:
			var wx: float = m.cx + s * (door_r + 0.95 + win_r + BastideRng.randf_at(m.seed, "fenetre", int(s)) * 0.12)
			if absf(wx - m.cx) > m.w * 0.5 - 0.15:
				continue
			var wy := 1.05
			var wr := win_r
			var room := fr.face_top(wx) - LIP_DROP - 0.16
			if room < wy + wr + 0.12:
				wr = room - wy - 0.12
				if wr < 0.28:
					continue
			var wz := fr.face_z(wx)
			holes.append([wx, wy, wr])
			_window(mb, fr, wx, wy, wr, wz, bs, m.seed + int(s), open)
			windows.append({"pos": fr.p(wx, wy, wz), "out": -fr.dir(0.0, 1.0), "width": wr * 2.0, "height": wr * 2.0, "floor": 0})
			if BastideRng.randf_at(m.seed, "jardiniere", int(s)) < maxf(bs.flower_box_chance, 0.55):
				_flower_box(mb, fr, groups, wx, wy - wr - 0.2, wz, bs, m.seed + int(s) * 7)

	# --- Butte, avancée d'herbe et façade ---
	var x_lo := -width * 0.5 - SKIRT - 0.2
	var x_hi := width * 0.5 + SKIRT + 0.2
	_mound(mb, fr, x_lo, x_hi, depth + SKIRT, result if with_collision else null)
	_facade(mb, fr, x_lo, x_hi, holes, bs, result if with_collision else null, door_r if open else 0.0)
	for m: Mound in fr.mounds:
		_timber(mb, fr, m, door_r, holes, bs)

	# --- Cheminées, abords, végétation ---
	for i in fr.mounds.size():
		var m: Mound = fr.mounds[i]
		var side := -1.0 if BastideRng.randf_at(m.seed, "cote") < 0.5 else 1.0
		var top := _chimney(mb, fr, m, side, ws, result if with_collision else null)
		smoke.append(top)
		_forecourt(mb, fr, m, door_r, ws, result if with_collision else null)
		lights.append(_lantern(mb, fr, m, -side, door_r))
		_props(mb, fr, groups, m, side, door_r, i == 0, i == fr.mounds.size() - 1, result if with_collision else null)
		_greenery(fr, groups, m, bs, door_r)

	mb.set_height_frame(ROLE_BODY, 0.0, 3.0, 0.0, 3.0)
	result.mesh = mb.commit({
		ROLE_BODY: style.get_material(),
		ROLE_WOOD: style.get_wood_material(),
		ROLE_GLASS: style.get_glass_material(),
		ROLE_PAPER: style.get_paper_material(),
		ROLE_TURF: style.get_turf_material(),
		ROLE_EARTH: style.get_earth_material(),
	})
	for key: String in groups:
		var g: Dictionary = groups[key]
		result.add_instances(g["mesh"], g["mat"], g["xf"], g.get("shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_OFF), 0.0, g.get("range", 90.0))

	# Contour pour les voisins : la façade et sa petite cour seulement. Le reste de
	# la butte est porté par le relief (voir carve()) : l'herbe y pousse.
	var outline := PackedVector2Array()
	var first: Mound = fr.mounds[0]
	var last: Mound = fr.mounds[fr.mounds.size() - 1]
	var xa := first.cx - first.face_half - 0.4
	var xb := last.cx + last.face_half + 0.4
	var zf := minf(first.dz, last.dz) - 2.4
	var zb := maxf(first.dz, last.dz) + 0.9
	for m: Mound in fr.mounds:
		if m.room.size.x > 0.0:
			var hol := m.hollow(1.0)
			xa = minf(xa, hol.position.x)
			xb = maxf(xb, hol.end.x)
			zb = maxf(zb, hol.end.y)
	for c in [Vector2(xa, zf), Vector2(xb, zf), Vector2(xb, zb), Vector2(xa, zb)]:
		var q: Vector3 = fr.p(c.x, 0.0, c.y)
		outline.append(Vector2(q.x, q.z))
	if BastidePolygon.signed_area(outline) * BastidePolygon.signed_area(fp) < 0.0:
		outline.reverse()
	var top_h := 0.0
	for m: Mound in fr.mounds:
		top_h = maxf(top_h, m.h)
	result.anchors = {"doors": doors, "windows": windows, "footprint": outline, "base_y": spec.base_y,
		"eave_y": spec.base_y + top_h, "floors": 1, "floor_height": top_h, "overhang": 0.3,
		"smoke": smoke, "lights": lights, "burrow": true, "mound_data": _terrain_data(fr, spec.seed)}
	if open:
		result.anchors["door_leaves"] = leaves
		var inner := _interior(fr, fr.mounds[0], door_r, holes, style, with_collision)
		result.anchors["interior_result"] = inner[0]
		result.anchors["interior_layout"] = inner[1]
	result.stats = {"buttes": fr.mounds.size(), "doors": doors.size(), "windows": windows.size(),
		"triangles": mb.triangle_count, "notes": ", ".join(clean.notes),
		"timings_us": {"total": Time.get_ticks_usec() - t0}}
	return result


## Repère de façade et découpage du tracé en buttes.
static func _frame(fp: PackedVector2Array, spec: BastideBuildingSpec, bs: BastideBuildingStyle) -> Frame:
	var n := fp.size()
	var fi := spec.door_facade
	if fi < 0 or fi >= n:
		fi = 0
		var best := -1.0
		for i in n:
			var l := fp[i].distance_to(fp[(i + 1) % n])
			if l > best + 0.01:
				best = l
				fi = i
	var a := fp[fi]
	var b := fp[(fi + 1) % n]
	var fx := (b - a).normalized()
	var fz := Vector2(-fx.y, fx.x)
	var c := BastidePolygon.centroid(fp)
	if (c - a).dot(fz) < 0.0:
		fz = -fz
	var x0 := INF
	var x1 := -INF
	var z1 := 0.0
	for p in fp:
		x0 = minf(x0, (p - a).dot(fx))
		x1 = maxf(x1, (p - a).dot(fx))
		z1 = maxf(z1, (p - a).dot(fz))
	var fr := Frame.new()
	fr.x = fx
	fr.z = fz
	fr.o = a + fx * (x0 + x1) * 0.5
	fr.y0 = spec.base_y
	# Un terrier par tracé, de taille bornée : un grand tracé ne fait pas une rangée
	# de maisons, juste une maison un peu plus large, centrée.
	var width := clampf(x1 - x0, 3.0, bs.burrow_width * 1.3)
	var depth := clampf(z1, 3.0, 9.0)
	fr.set_meta("width", width)
	fr.set_meta("depth", depth)
	var count := 1
	var w := width / count
	for i in count:
		var m := Mound.new()
		m.seed = BastideRng.key(spec.seed, "butte", i)
		m.w = w
		m.cx = -width * 0.5 + w * (i + 0.5)
		var size := clampf(minf(w, depth + 1.0) / 7.0, 0.85, 1.18)
		m.h = 3.2 * size * (0.93 + 0.14 * BastideRng.randf_at(m.seed, "haut"))
		m.ax = w * 0.5 + (SKIRT if count == 1 else 0.95)
		if count > 1 and (i == 0 or i == count - 1):
			m.ax = w * 0.5 + 1.3
		m.zc = clampf(depth * 0.28, 0.8, 2.0)
		m.az = maxf(depth - m.zc, 1.5) + SKIRT
		if count > 1:
			m.dz = BastideRng.randf_range_at(m.seed, "recul", 0, -0.25, 0.4)
		m.h *= bs.mound_height / 3.2
		m.door_color = bs.door_color
		if not bs.door_colors.is_empty():
			var k := int(BastideRng.randf_at(m.seed, "porte") * bs.door_colors.size()) % bs.door_colors.size()
			m.door_color = bs.door_colors[k]
		fr.mounds.append(m)
	return fr


# --- Butte -------------------------------------------------------------------------

## Le dôme d'herbe : une grille par colonnes, qui part du bord de l'avancée (devant
## la façade) et file vers l'arrière ; normales lissées tirées de la pente.
static func _mound(mb: BastideMeshBuilder, fr: Frame, x_lo: float, x_hi: float, z_end: float, coll: BastideBuildResult) -> void:
	var cols := maxi(4, ceili((x_hi - x_lo) / STEP))
	const ROWS := 30
	var grid: Array = []   # [col] -> Array de [pos, normale, couleur]
	for i in cols + 1:
		var x := lerpf(x_lo, x_hi, float(i) / cols)
		var zf := fr.face_z(x)
		var z0 := zf - LIP
		var mo := fr.owner(x)
		var near := 1.0 - smoothstep(mo.face_half + 0.6, mo.face_half + 2.4, absf(x - mo.cx))
		var col: Array = []
		for j in ROWS + 1:
			# Rangées serrées près de la façade (le bord de l'avancée se lit net).
			var z := z0 if j == 0 else zf + (z_end - zf) * pow(float(j - 1) / (ROWS - 1), 1.35)
			# Hors du front d'herbe de la façade, la butte maillée passe juste sous le
			# relief (voir terrain_height) : c'est l'herbe du terrain qu'on voit.
			var hol := mo.hollow()
			var gap := maxf(maxf(hol.position.x - x, x - hol.end.x), z - hol.end.y)
			var sink := SINK * maxf(1.0 - near, smoothstep(zf + 0.9, zf + 1.9, z)) * smoothstep(0.0, 1.0, gap)
			var y := maxf(fr.surface(x, z) - sink, 0.0)
			var n := _normal(fr, x, z)
			col.append([fr.p(x, y, z), n, Color(0.0, 0.0, 1.0, 0.0)])
		grid.append(col)
	for i in cols:
		for j in ROWS:
			var a: Array = grid[i][j]
			var b: Array = grid[i + 1][j]
			var c: Array = grid[i + 1][j + 1]
			var d: Array = grid[i][j + 1]
			if (a[0] as Vector3).y < fr.y0 + 0.01 and (b[0] as Vector3).y < fr.y0 + 0.01 \
					and (c[0] as Vector3).y < fr.y0 + 0.01 and (d[0] as Vector3).y < fr.y0 + 0.01:
				continue
			mb.add_tri_smooth(ROLE_TURF, a[0], b[0], c[0], a[1], b[1], c[1], a[2], b[2], c[2])
			mb.add_tri_smooth(ROLE_TURF, a[0], c[0], d[0], a[1], c[1], d[1], a[2], c[2], d[2])
	# Dessous de l'avancée : une bande de terre et de racines, du bord de l'herbe
	# jusqu'au haut de la façade.
	var out := -fr.dir(0.0, 1.0)
	for i in cols:
		var xa := lerpf(x_lo, x_hi, float(i) / cols)
		var xb := lerpf(x_lo, x_hi, float(i + 1) / cols)
		var ta := fr.face_top(xa)
		var tb := fr.face_top(xb)
		if ta < 0.02 and tb < 0.02:
			continue
		var za := fr.face_z(xa)
		var zb := fr.face_z(xb)
		var ba := maxf(ta - LIP_DROP, 0.0)
		var bb := maxf(tb - LIP_DROP, 0.0)
		var soil_a := SOFFIT
		var soil_b := SOFFIT.darkened(0.06)
		var dn := (out + Vector3.DOWN).normalized()
		mb.add_tri_smooth(ROLE_WOOD, fr.p(xa, ta, za - LIP), fr.p(xb, tb, zb - LIP), fr.p(xb, bb, zb), dn, dn, dn,
				soil_a, soil_b, soil_b)
		mb.add_tri_smooth(ROLE_WOOD, fr.p(xa, ta, za - LIP), fr.p(xb, bb, zb), fr.p(xa, ba, za), dn, dn, dn,
				soil_a, soil_b, soil_a)
	if coll:
		var ci := maxi(2, cols / 3)
		for i in ci:
			for j in 10:
				var xa := lerpf(x_lo, x_hi, float(i) / ci)
				var xb := lerpf(x_lo, x_hi, float(i + 1) / ci)
				var p := func(x: float, t: float) -> Vector3:
					var zf := fr.face_z(x)
					var z := zf + (z_end - zf) * t
					return fr.p(x, fr.surface(x, z), z)
				var a: Vector3 = p.call(xa, j / 10.0)
				var b: Vector3 = p.call(xb, j / 10.0)
				var c: Vector3 = p.call(xb, (j + 1) / 10.0)
				var d: Vector3 = p.call(xa, (j + 1) / 10.0)
				coll.collision_faces.append_array(PackedVector3Array([a, b, c, a, c, d]))


static func _normal(fr: Frame, x: float, z: float) -> Vector3:
	var e := 0.15
	var hx := fr.surface(x + e, z) - fr.surface(x - e, z)
	var hz := fr.surface(x, z + e) - fr.surface(x, z - e)
	# Pente dans le repère de façade, ramenée dans le repère du nœud.
	var n := fr.dir(-hx / (2.0 * e), -hz / (2.0 * e)) + Vector3.UP
	return n.normalized()


## Façade enduite sous l'avancée, percée de la porte et des fenêtres ; pied de
## pierres (le shader dessine les moellons sous l'enduit, COLOR.a < 1).
static func _facade(mb: BastideMeshBuilder, fr: Frame, x_lo: float, x_hi: float, holes: Array,
		bs: BastideBuildingStyle, coll: BastideBuildResult, door_gap := 0.0) -> void:
	var out := -fr.dir(0.0, 1.0)
	var plaster := bs.plaster_color
	var alt := bs.plaster_color_alt
	var dx := 0.18
	var cols := ceili((x_hi - x_lo) / dx)
	for i in cols:
		var xa := x_lo + i * dx
		var xb := xa + dx
		var ta := fr.face_top(xa) - LIP_DROP + 0.02
		var tb := fr.face_top(xb) - LIP_DROP + 0.02
		if ta < 0.05 and tb < 0.05:
			continue
		ta = maxf(ta, 0.0)
		tb = maxf(tb, 0.0)
		var za := fr.face_z(xa)
		var zb := fr.face_z(xb)
		var top := maxf(ta, tb)
		var rows := maxi(1, ceili(top / 0.2))
		for j in rows:
			var y0 := j * 0.2
			var y1 := (j + 1) * 0.2
			var ya0 := minf(y0, ta)
			var ya1 := minf(y1, ta)
			var yb0 := minf(y0, tb)
			var yb1 := minf(y1, tb)
			if ya1 - ya0 < 0.001 and yb1 - yb0 < 0.001:
				continue
			var cx := (xa + xb) * 0.5
			var cy := (y0 + minf(y1, top)) * 0.5
			var skip := false
			for hole: Array in holes:
				if Vector2(cx - float(hole[0]), cy - float(hole[1])).length() < float(hole[2]) + 0.1:
					skip = true
					break
			if skip:
				continue
			var tint := BastideRng.noise1(7, "enduit", (xa + cy * 3.0) * 0.6) * 0.5 + 0.5
			var col := plaster.lerp(alt, tint)
			var ca := col
			var cb := col
			# Pied de pierres sèches.
			var stone_a := 0.9 if y0 < 0.42 else 1.0
			ca.a = stone_a
			cb.a = stone_a
			mb.add_quad(ROLE_BODY, fr.p(xa, ya0, za), fr.p(xb, yb0, zb), fr.p(xb, yb1, zb), fr.p(xa, ya1, za), out,
					ca, cb, cb, ca)
	if coll and door_gap > 0.0:
		# Variante ouverte : la collision se perce à la porte.
		var step := 0.25
		var x := x_lo
		while x < x_hi - 0.01:
			var xb := minf(x + step, x_hi)
			var top := maxf(fr.face_top(x), fr.face_top(xb))
			var m := fr.owner((x + xb) * 0.5)
			var dcy := door_gap * 0.97
			var y := 0.0
			while top > 0.1 and y < top:
				var y1 := minf(y + step, top)
				var mid := Vector2((x + xb) * 0.5 - m.cx, (y + y1) * 0.5 - dcy)
				if mid.length() > door_gap - 0.05 and not (absf(mid.x) < door_gap - 0.05 and y < dcy):
					var za := fr.face_z(x)
					var zb := fr.face_z(xb)
					coll.collision_faces.append_array(PackedVector3Array([fr.p(x, y, za), fr.p(xb, y, zb), fr.p(xb, y1, zb),
						fr.p(x, y, za), fr.p(xb, y1, zb), fr.p(x, y1, za)]))
				y = y1
			x = xb
	elif coll:
		var n := 16
		for i in n:
			var xa := lerpf(x_lo, x_hi, float(i) / n)
			var xb := lerpf(x_lo, x_hi, float(i + 1) / n)
			var ta := fr.face_top(xa)
			var tb := fr.face_top(xb)
			if ta < 0.1 and tb < 0.1:
				continue
			var a := fr.p(xa, 0.0, fr.face_z(xa))
			var b := fr.p(xb, 0.0, fr.face_z(xb))
			var c := fr.p(xb, tb, fr.face_z(xb))
			var d := fr.p(xa, ta, fr.face_z(xa))
			coll.collision_faces.append_array(PackedVector3Array([a, b, c, a, c, d]))


# --- Porte et fenêtres -------------------------------------------------------------

## Couronne de blocs dans le plan de façade (centre cx, cy), de r0 à r1, épaisseur
## de z0 à z1 (z vers l'intérieur). Les segments sous le sol sont omis.
static func _ring(mb: BastideMeshBuilder, fr: Frame, role: StringName, cx: float, cy: float, r0: float, r1: float,
		z0: float, z1: float, segs: int, color: Color, edge: Color, seed: int, gap := 0.0, jitter := 0.0) -> void:
	for k in segs:
		var a0 := TAU * k / segs + gap * 0.5
		var a1 := TAU * (k + 1) / segs - gap * 0.5
		var c0 := Vector2(cos(a0), sin(a0))
		var c1 := Vector2(cos(a1), sin(a1))
		var rr1 := r1 + jitter * BastideRng.signed_at(seed, "couronne", k)
		var pts := [Vector2(cx, cy) + c0 * r0, Vector2(cx, cy) + c1 * r0, Vector2(cx, cy) + c1 * rr1, Vector2(cx, cy) + c0 * rr1]
		var low := INF
		for q: Vector2 in pts:
			low = minf(low, q.y)
		if low < -0.02 and (pts[0] as Vector2).y < 0.0 and (pts[1] as Vector2).y < 0.0:
			continue
		var kk: Array = []
		# Le dessus d'un bloc (4 derniers coins) est sa face dessinée : ici l'avant.
		for zz in [z1, z0]:
			for q: Vector2 in pts:
				kk.append(fr.p(q.x, maxf(q.y, -0.05), zz))
		var t := BastideRng.signed_at(seed, "teinte", k) * 0.06
		mb.add_block(role, kk, 0.02, 0.008, color.lightened(t) if t > 0.0 else color.darkened(-t), edge)


static func _door(main: BastideMeshBuilder, fr: Frame, m: Mound, r: float, cy: float, fz: float,
		bs: BastideBuildingStyle, ws: BastideWallStyle, leaves: Variant = null, style: BastideStyle = null) -> void:
	var col := m.door_color
	var wood := bs.wood_color
	var mb := main
	if leaves == null:
		# Fond sombre derrière le trou (on ne voit jamais l'intérieur de la butte).
		_disc(mb, fr, ROLE_BODY, m.cx, cy, r + 0.32, fz + 0.32, bs.interior_color, 0.0)
	else:
		mb = BastideMeshBuilder.new()
	# Vantail : planches verticales peintes, un peu en retrait.
	var n := maxi(5, roundi(r * 2.0 / 0.24))
	var pw := r * 2.0 / n
	for k in n:
		var x0 := -r + k * pw
		var x1 := x0 + pw
		var xm := absf(x0 + pw * 0.5)
		var half := sqrt(maxf(r * r - xm * xm, 0.0))
		var yb := maxf(cy - half, 0.0)
		var yt := cy + half
		if yt - yb < 0.05:
			continue
		var tint := BastideRng.signed_at(m.seed, "planche", k) * 0.05
		var pc := col.lightened(tint) if tint > 0.0 else col.darkened(-tint)
		var edge := pc.darkened(0.12)
		mb.add_quad(ROLE_WOOD, fr.p(m.cx + x0, yb, fz + 0.12), fr.p(m.cx + x1, yb, fz + 0.12), fr.p(m.cx + x1, yt, fz + 0.12),
				fr.p(m.cx + x0, yt, fz + 0.12), -fr.dir(0.0, 1.0), edge, pc, pc, edge)
	# Bouton de laiton au centre, et son anneau.
	_knob(mb, fr, m.cx, cy, fz + 0.12, 0.075)
	if leaves != null:
		# Dos du vantail, vu de l'intérieur ; il pivote sur son bord gauche, vers l'intérieur.
		_disc(mb, fr, ROLE_WOOD, m.cx, cy, r - 0.01, fz + 0.15, col.darkened(0.2), 0.0, -1.0)
		var pivot := fr.p(m.cx - r, 0.0, fz + 0.13)
		var d3 := fr.dir(1.0, 0.0)
		var inward := fr.dir(0.0, 1.0)
		var angle := atan2(d3.cross(inward).y, d3.dot(inward)) * 0.92
		(leaves as Array).append({"mesh": mb.commit({ROLE_WOOD: style.get_wood_material(), ROLE_BODY: style.get_material()}),
			"kind": "hinge", "pivot": pivot, "angle": angle})
		mb = main
	# Huisserie de bois, puis couronne de pierres taillées.
	_ring(mb, fr, ROLE_WOOD, m.cx, cy, r - 0.03, r + 0.15, fz - 0.06, fz + 0.18, 28, wood, wood.darkened(0.3), m.seed)
	var stone := ws.stone_color
	var dark := stone.lightened(0.14)
	_ring(mb, fr, ROLE_BODY, m.cx, cy, r + 0.15, r + 0.5, fz - 0.12, fz + 0.12, 15, Color(dark.r, dark.g, dark.b, 1.0),
			ws.mortar_color, m.seed + 3, 0.05, 0.06)
	# Seuil de pierre et dalles de pas.
	var slab: Array = []
	for yy in [-0.25, 0.06]:
		for q: Vector2 in [Vector2(m.cx - r * 0.8, fz - 0.02), Vector2(m.cx + r * 0.8, fz - 0.02),
				Vector2(m.cx + r * 0.8, fz - 0.62), Vector2(m.cx - r * 0.8, fz - 0.62)]:
			slab.append(fr.p(q.x, yy, q.y))
	mb.add_block(ROLE_BODY, slab, 0.03, 0.01, Color(stone.r, stone.g, stone.b, 0.9).darkened(0.05), ws.mortar_color)
	for k in 3:
		var sx := m.cx + BastideRng.signed_at(m.seed, "pas", k) * 0.25
		var sz := fz - 1.05 - k * 0.68
		var sr := 0.3 + BastideRng.randf_at(m.seed, "pas_r", k) * 0.08
		var st: Array = []
		for yy in [-0.2, 0.035]:
			for q: Vector2 in [Vector2(sx - sr, sz - sr * 0.8), Vector2(sx + sr, sz - sr * 0.7),
					Vector2(sx + sr * 0.9, sz + sr * 0.8), Vector2(sx - sr * 0.85, sz + sr * 0.75)]:
				st.append(fr.p(q.x, yy, q.y))
		mb.add_block(ROLE_BODY, st, 0.04, 0.012, Color(stone.r, stone.g, stone.b, 0.9).darkened(0.08), ws.mortar_color)


static func _knob(mb: BastideMeshBuilder, fr: Frame, cx: float, cy: float, fz: float, s: float) -> void:
	var kk: Array = []
	for zz in [fz - 0.0, fz - 0.07]:
		for q: Vector2 in [Vector2(cx - s, cy - s), Vector2(cx + s, cy - s), Vector2(cx + s, cy + s), Vector2(cx - s, cy + s)]:
			kk.append(fr.p(q.x, q.y, zz))
	mb.add_block(ROLE_WOOD, kk, s * 0.45, s * 0.2, BRASS, BRASS.darkened(0.3))


## Disque plein dans le plan de façade (fond, vitre).
static func _disc(mb: BastideMeshBuilder, fr: Frame, role: StringName, cx: float, cy: float, r: float, fz: float,
		color: Color, clip_y: float, facing := 1.0) -> void:
	var out := -fr.dir(0.0, 1.0) * facing
	var segs := 24
	var c := fr.p(cx, maxf(cy, clip_y), fz)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var p0 := fr.p(cx + cos(a0) * r, maxf(cy + sin(a0) * r, clip_y), fz)
		var p1 := fr.p(cx + cos(a1) * r, maxf(cy + sin(a1) * r, clip_y), fz)
		mb.add_tri(role, c, p0, p1, out, color, color, color)


static func _window(mb: BastideMeshBuilder, fr: Frame, cx: float, cy: float, r: float, fz: float,
		bs: BastideBuildingStyle, seed: int, open := false) -> void:
	var wood := bs.wood_color
	if not open:
		_disc(mb, fr, ROLE_BODY, cx, cy, r + 0.25, fz + 0.3, bs.interior_color, -10.0)
	_disc(mb, fr, ROLE_GLASS, cx, cy, r + 0.02, fz + 0.1, bs.glass_color, -10.0)
	if open:
		_disc(mb, fr, ROLE_GLASS, cx, cy, r + 0.02, fz + 0.1, bs.glass_color.lightened(0.25), -10.0, -1.0)
	# Croisillons : une croix et un petit cercle intérieur.
	var t := 0.035
	for bar in [[Vector2(cx - r, cy - t), Vector2(cx + r, cy + t)], [Vector2(cx - t, cy - r), Vector2(cx + t, cy + r)]]:
		var a: Vector2 = bar[0]
		var b: Vector2 = bar[1]
		var kk: Array = []
		for zz in [fz + 0.09, fz + 0.04]:
			for q: Vector2 in [Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(a.x, b.y)]:
				kk.append(fr.p(q.x, q.y, zz))
		mb.add_block(ROLE_WOOD, kk, 0.008, 0.0, wood, wood.darkened(0.3))
	_ring(mb, fr, ROLE_WOOD, cx, cy, r - 0.02, r + 0.13, fz - 0.05, fz + 0.16, 20, wood, wood.darkened(0.3), seed + 1)


static func _flower_box(mb: BastideMeshBuilder, fr: Frame, groups: Dictionary, cx: float, y: float, fz: float,
		bs: BastideBuildingStyle, seed: int) -> void:
	var wood := bs.wood_color.lightened(0.05)
	var hw := 0.5
	var kk: Array = []
	for yy in [y - 0.2, y]:
		for q: Vector2 in [Vector2(cx - hw, fz - 0.02), Vector2(cx + hw, fz - 0.02), Vector2(cx + hw, fz - 0.3), Vector2(cx - hw, fz - 0.3)]:
			kk.append(fr.p(q.x, yy, q.y))
	mb.add_block(ROLE_WOOD, kk, 0.015, 0.004, wood, wood.darkened(0.35))
	var cols := bs.flower_colors
	for k in 5:
		var fx := cx - hw + 0.12 + k * (hw * 2.0 - 0.24) / 4.0
		var c: Color = cols[(seed + k) % cols.size()] if not cols.is_empty() else Color(0.9, 0.4, 0.5)
		_plant(groups, "flower", Color(0.75 + c.r * 0.4, 0.75 + c.g * 0.4, 0.75 + c.b * 0.4), 0.3,
				fr.p(fx, y - 0.02, fz - 0.16), float(seed + k))


# --- Cheminée, muret, lanterne -----------------------------------------------------

static func _chimney(mb: BastideMeshBuilder, fr: Frame, m: Mound, side: float, ws: BastideWallStyle,
		coll: BastideBuildResult) -> Vector3:
	var x := m.cx + side * m.w * 0.18
	var z := m.zc + m.dz + 1.1
	var g := fr.surface(x, z)
	var y := g - 0.4
	var s := 0.3
	var stone := ws.stone_color
	for k in 5:
		var hh := 0.34 if k < 4 else 0.1
		var ss := s if k < 4 else s + 0.08
		var jx := BastideRng.signed_at(m.seed, "chem", k) * 0.02
		var kk: Array = []
		for yy in [y, y + hh]:
			for q: Vector2 in [Vector2(x - ss + jx, z - ss), Vector2(x + ss + jx, z - ss), Vector2(x + ss + jx, z + ss), Vector2(x - ss + jx, z + ss)]:
				kk.append(fr.p(q.x, yy, q.y))
		var t := BastideRng.signed_at(m.seed, "chem_t", k) * 0.07
		var c := BRICK.lerp(BRICK_ALT, t * 5.0 + 0.5) if k < 4 else Color(0.5, 0.47, 0.42)
		mb.add_block(ROLE_BODY, kk, 0.02, 0.008, Color(c.r, c.g, c.b, 1.0), c.darkened(0.35))
		y += hh
	# Petit pot de terre cuite.
	var pot: Array = []
	for yy in [y, y + 0.22]:
		for q: Vector2 in [Vector2(x - 0.11, z - 0.11), Vector2(x + 0.11, z - 0.11), Vector2(x + 0.11, z + 0.11), Vector2(x - 0.11, z + 0.11)]:
			pot.append(fr.p(q.x, yy, q.y))
	mb.add_block(ROLE_EARTH, pot, 0.03, 0.01, Color(0.6, 0.33, 0.22), Color(0.3, 0.16, 0.1))
	if coll:
		var kk: Array = []
		for yy in [g - 0.4, y]:
			for q: Vector2 in [Vector2(x - s, z - s), Vector2(x + s, z - s), Vector2(x + s, z + s), Vector2(x - s, z + s)]:
				kk.append(fr.p(q.x, yy, q.y))
		coll.add_box(kk)
	return fr.p(x, y + 0.3, z)


## Muret de pierres sèches en arc de chaque côté du seuil : il enserre une petite
## cour devant la porte et s'appuie sur le flanc de la butte.
static func _forecourt(mb: BastideMeshBuilder, fr: Frame, m: Mound, door_r: float, ws: BastideWallStyle,
		coll: BastideBuildResult) -> void:
	if BastideRng.randf_at(m.seed, "muret") > 0.8:
		return
	var stone := ws.stone_color
	var alt := ws.stone_color_alt
	for s in [-1.0, 1.0]:
		var x0: float = m.cx + s * (m.w * 0.5 - 0.35)
		var p0 := Vector2(x0, fr.face_z(x0) + 0.25)
		var p2 := Vector2(m.cx + s * (door_r + 0.75), m.dz - 2.15)
		var p1 := Vector2(x0, m.dz - 1.9)
		var pts: Array = []
		var n := 24
		for k in n + 1:
			var t := float(k) / n
			pts.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
		var length := 0.0
		for k in n:
			length += (pts[k] as Vector2).distance_to(pts[k + 1])
		var hgt := 0.66 + BastideRng.randf_at(m.seed, "muret_h", int(s)) * 0.12
		for course in 3:
			var y0 := -0.12 + course * hgt / 3.0
			var y1 := -0.12 + (course + 1) * hgt / 3.0
			var u: float = [0.0, 0.17, 0.08][course]
			var k := 0
			while u < length - 0.05:
				var l := 0.26 + BastideRng.randf_at(m.seed + course, "pierre", k + int(s * 50)) * 0.24
				var u1 := minf(u + l, length)
				var a := _at(pts, u + 0.015)
				var b := _at(pts, u1 - 0.015)
				var d := (b - a).normalized()
				var nn := Vector2(-d.y, d.x) * (0.2 - course * 0.025)
				var t := BastideRng.signed_at(m.seed + course, "pierre_t", k + int(s * 50))
				var c := stone.lerp(alt, t * 0.5 + 0.5)
				var kk: Array = []
				var top := y1 + BastideRng.signed_at(m.seed + course, "pierre_y", k) * 0.03
				for yy in [y0, top]:
					for q: Vector2 in [a - nn, b - nn, b + nn, a + nn]:
						kk.append(fr.p(q.x, yy, q.y))
				mb.add_block(ROLE_BODY, kk, 0.06, 0.03, Color(c.r, c.g, c.b, 1.0), c.darkened(0.3))
				if coll and course == 2:
					coll.add_box(kk)
				u = u1
				k += 1


static func _at(pts: Array, u: float) -> Vector2:
	var acc := 0.0
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var l := a.distance_to(b)
		if acc + l >= u:
			return a.lerp(b, (u - acc) / maxf(l, 1e-5))
		acc += l
	return pts[pts.size() - 1]


## Lanterne accrochée au poteau de la porte. Retourne le centre de sa lumière.
static func _lantern(mb: BastideMeshBuilder, fr: Frame, m: Mound, side: float, door_r: float) -> Vector3:
	var x := m.cx + side * (door_r + 0.66)
	var zf := fr.face_z(x)
	var top := fr.face_top(x) - LIP_DROP - 0.18
	var y := clampf(top - 0.55, 1.2, 1.95)
	var z := zf - 0.36
	# Potence fixée au poteau.
	_box(mb, fr, ROLE_WOOD, x - 0.025, x + 0.025, y + 0.36, y + 0.42, z - 0.02, zf - 0.1, IRON, IRON, 0.005)
	var s := 0.1
	_box(mb, fr, ROLE_PAPER, x - s, x + s, y, y + 0.27, z - s, z + s, Color(1.0, 0.86, 0.6), Color(0.3, 0.2, 0.1), 0.01)
	_box(mb, fr, ROLE_WOOD, x - s - 0.03, x + s + 0.03, y + 0.27, y + 0.34, z - s - 0.03, z + s + 0.03, IRON, IRON, 0.01)
	_box(mb, fr, ROLE_WOOD, x - s - 0.01, x + s + 0.01, y - 0.04, y, z - s - 0.01, z + s + 0.01, IRON, IRON, 0.005)
	return fr.p(x, y + 0.13, z)


# --- Abords : bûches, tonneau, foin, potager en caisse --------------------------------

static func _props(mb: BastideMeshBuilder, fr: Frame, groups: Dictionary, m: Mound, side: float, door_r: float,
		first: bool, last: bool, coll: BastideBuildResult) -> void:
	# Tas de bûches contre la façade, sous une fenêtre.
	if BastideRng.randf_at(m.seed, "buches") < 0.7:
		var x := m.cx + side * (door_r + 1.35)
		var z := fr.face_z(x) - 0.42
		var rows := [4, 3, 2]
		for row in rows.size():
			var count: int = rows[row]
			for k in count:
				var lx := x + (k - (count - 1) * 0.5) * 0.27
				var ly := 0.13 + row * 0.23
				_log(mb, fr, Vector2(lx, z), ly, 0.13, 0.8, m.seed + row * 10 + k)
	# Banc de bois contre la façade et tonneau de pluie, de l'autre côté.
	var bx := m.cx - side * (door_r + 1.55)
	_bench(mb, fr, bx, fr.face_z(bx) - 0.5, coll)
	if BastideRng.randf_at(m.seed, "tonneau") < 0.7:
		var x := m.cx - side * (door_r + 0.75)
		var z := fr.face_z(x) - 0.75
		_barrel(mb, fr, Vector2(x, z), 0.25, 0.72, m.seed)
	# Hors du muret : meule de foin et potager en caisse, sur les côtés extérieurs.
	var outer_left := first
	var outer_right := last
	var hay_side := -side
	if (hay_side < 0.0 and outer_left) or (hay_side > 0.0 and outer_right) or fr.mounds.size() == 1:
		if BastideRng.randf_at(m.seed, "foin") < 0.65:
			var x := m.cx + hay_side * (m.w * 0.5 + 0.7)
			_hay(mb, fr, Vector2(x, m.dz - 3.0), 0.75 + BastideRng.randf_at(m.seed, "foin_r") * 0.2, m.seed)
			if BastideRng.randf_at(m.seed, "foin2") < 0.5:
				_hay(mb, fr, Vector2(x + hay_side * 1.3, m.dz - 2.2), 0.6, m.seed + 1)
	if (side < 0.0 and outer_left) or (side > 0.0 and outer_right) or fr.mounds.size() == 1:
		if BastideRng.randf_at(m.seed, "potager") < 0.7:
			var x := m.cx + side * (m.w * 0.5 + 0.2)
			_crate_garden(mb, fr, groups, Vector2(x, m.dz - 3.3), side, m.seed, coll)


static func _log(mb: BastideMeshBuilder, fr: Frame, c: Vector2, y: float, r: float, length: float, seed: int) -> void:
	# Bûche couchée dans l'axe de la façade (vers l'avant), six pans.
	var sides := 6
	var z0 := c.y - length * 0.5
	var z1 := c.y + length * 0.5
	var rr := r * (0.85 + BastideRng.randf_at(seed, "buche") * 0.3)
	var rot := BastideRng.randf_at(seed, "buche_a") * TAU
	var ring0: Array = []
	var ring1: Array = []
	for k in sides:
		var a := rot + TAU * k / sides
		var q := Vector2(c.x + cos(a) * rr, y + sin(a) * rr)
		ring0.append(fr.p(q.x, q.y, z0))
		ring1.append(fr.p(q.x, q.y, z1 + BastideRng.signed_at(seed, "bout", k) * 0.02))
	var mid := fr.p(c.x, y, c.y)
	for k in sides:
		var a: Vector3 = ring0[k]
		var b: Vector3 = ring0[(k + 1) % sides]
		var cc: Vector3 = ring1[(k + 1) % sides]
		var d: Vector3 = ring1[k]
		mb.add_quad(ROLE_WOOD, a, b, cc, d, (a + b + cc + d) * 0.25 - mid, LOG, LOG, LOG.darkened(0.1), LOG.darkened(0.1))
	var e0 := fr.p(c.x, y, z0)
	var e1 := fr.p(c.x, y, z1)
	for k in sides:
		mb.add_tri(ROLE_WOOD, e0, ring0[k], ring0[(k + 1) % sides], e0 - mid, LOG_END, LOG_END.darkened(0.15), LOG_END.darkened(0.15))
		mb.add_tri(ROLE_WOOD, e1, ring1[k], ring1[(k + 1) % sides], e1 - mid, LOG_END, LOG_END.darkened(0.15), LOG_END.darkened(0.15))


static func _barrel(mb: BastideMeshBuilder, fr: Frame, c: Vector2, r: float, h: float, seed: int) -> void:
	var sides := 10
	var prof := [[0.0, 0.86], [0.5, 1.0], [1.0, 0.86]]
	var wood := Color(0.45, 0.3, 0.18)
	var mid := fr.p(c.x, h * 0.5, c.y)
	for seg in prof.size() - 1:
		var y0: float = prof[seg][0] * h
		var y1: float = prof[seg + 1][0] * h
		var r0: float = prof[seg][1] * r
		var r1: float = prof[seg + 1][1] * r
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var p0 := fr.p(c.x + cos(a0) * r0, y0, c.y + sin(a0) * r0)
			var p1 := fr.p(c.x + cos(a1) * r0, y0, c.y + sin(a1) * r0)
			var p2 := fr.p(c.x + cos(a1) * r1, y1, c.y + sin(a1) * r1)
			var p3 := fr.p(c.x + cos(a0) * r1, y1, c.y + sin(a0) * r1)
			var t := BastideRng.signed_at(seed, "douve", k) * 0.06
			var wc := wood.lightened(t) if t > 0.0 else wood.darkened(-t)
			mb.add_quad(ROLE_WOOD, p0, p1, p2, p3, (p0 + p1 + p2 + p3) * 0.25 - mid, wc, wc, wc, wc)
	# Cercles de fer et couvercle.
	for hy in [0.18, 0.82]:
		var rr := r * (0.86 + 0.14 * (1.0 - absf(hy - 0.5) * 2.0)) + 0.012
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var p0 := fr.p(c.x + cos(a0) * rr, h * hy - 0.03, c.y + sin(a0) * rr)
			var p1 := fr.p(c.x + cos(a1) * rr, h * hy - 0.03, c.y + sin(a1) * rr)
			var p2 := fr.p(c.x + cos(a1) * rr, h * hy + 0.03, c.y + sin(a1) * rr)
			var p3 := fr.p(c.x + cos(a0) * rr, h * hy + 0.03, c.y + sin(a0) * rr)
			mb.add_quad(ROLE_WOOD, p0, p1, p2, p3, (p0 + p1 + p2 + p3) * 0.25 - mid, IRON, IRON, IRON, IRON)
	var top := fr.p(c.x, h, c.y)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var rr := r * 0.86
		mb.add_tri(ROLE_WOOD, top, fr.p(c.x + cos(a0) * rr, h, c.y + sin(a0) * rr), fr.p(c.x + cos(a1) * rr, h, c.y + sin(a1) * rr),
				Vector3.UP, wood.darkened(0.15), wood.darkened(0.15), wood.darkened(0.15))


## Meule de foin : un dôme de paille un peu affaissé.
static func _hay(mb: BastideMeshBuilder, fr: Frame, c: Vector2, r: float, seed: int) -> void:
	var sides := 18
	var rings := 9
	var h := r * 1.05
	var prev: Array = []
	var cen := fr.p(c.x, h * 0.35, c.y)
	for j in rings + 1:
		var t := float(j) / rings
		var ang := t * PI * 0.5
		var rr := r * cos(ang) * (1.0 if j > 0 else 1.06)
		var y := h * sin(ang) - 0.05
		var cur: Array = []
		for k in sides:
			var a := TAU * k / sides
			var wob := 1.0 + BastideRng.signed_at(seed, "foin_w", k + j * 17) * 0.05
			cur.append(fr.p(c.x + cos(a) * rr * wob, y, c.y + sin(a) * rr * wob))
		if j > 0:
			for k in sides:
				var a: Vector3 = prev[k]
				var b: Vector3 = prev[(k + 1) % sides]
				var cc: Vector3 = cur[(k + 1) % sides]
				var d: Vector3 = cur[k]
				var shade := (0.8 + 0.2 * t) * (0.95 + 0.08 * sin(float(j) * 2.7 + float(seed % 7)))
				var col := Color(STRAW.r * shade, STRAW.g * shade, STRAW.b * shade, 0.0)
				mb.add_tri_smooth(ROLE_EARTH, a, b, cc, (a - cen).normalized(), (b - cen).normalized(), (cc - cen).normalized(), col, col, col)
				mb.add_tri_smooth(ROLE_EARTH, a, cc, d, (a - cen).normalized(), (cc - cen).normalized(), (d - cen).normalized(), col, col, col)
		prev = cur


## Potager en caisse : un bac de planches rempli de terre, des légumes dedans.
static func _crate_garden(mb: BastideMeshBuilder, fr: Frame, groups: Dictionary, c: Vector2, side: float, seed: int,
		coll: BastideBuildResult) -> void:
	var hx := 0.95
	var hz := 0.5
	var h := 0.38
	var wood := Color(0.5, 0.36, 0.22)
	# Quatre planches de bord, la terre entre elles.
	for e in [[Vector2(-hx, -hz), Vector2(hx, -hz + 0.08)], [Vector2(-hx, hz - 0.08), Vector2(hx, hz)],
			[Vector2(-hx, -hz), Vector2(-hx + 0.08, hz)], [Vector2(hx - 0.08, -hz), Vector2(hx, hz)]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var kk: Array = []
		for yy in [-0.1, h]:
			for q: Vector2 in [Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(a.x, b.y)]:
				kk.append(fr.p(c.x + q.x, yy, c.y + q.y))
		mb.add_block(ROLE_WOOD, kk, 0.012, 0.003, wood, wood.darkened(0.35))
	var soil: Array = []
	for yy in [-0.1, h - 0.06]:
		for q: Vector2 in [Vector2(-hx + 0.08, -hz + 0.08), Vector2(hx - 0.08, -hz + 0.08), Vector2(hx - 0.08, hz - 0.08), Vector2(-hx + 0.08, hz - 0.08)]:
			soil.append(fr.p(c.x + q.x, yy, c.y + q.y))
	mb.add_block(ROLE_EARTH, soil, 0.02, 0.01, SOIL, SOIL.darkened(0.2))
	for k in 6:
		var px := c.x - hx + 0.3 + (k % 3) * (hx * 2.0 - 0.6) / 2.0
		var pz := c.y + (-0.2 if k < 3 else 0.2)
		var kind := "fern" if (seed + k) % 3 != 0 else "meadow"
		_plant(groups, kind, Color(0.8, 1.0, 0.75), 0.55, fr.p(px, h - 0.06, pz), float(seed * 3 + k))
	if coll:
		var kk: Array = []
		for yy in [-0.1, h]:
			for q: Vector2 in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]:
				kk.append(fr.p(c.x + q.x, yy, c.y + q.y))
		coll.add_box(kk)


# --- Végétation (instances) ----------------------------------------------------------

## Touffes et fleurs posées en instances (cartes peintes du kit nature).
static func _plant(groups: Dictionary, kind: String, tint: Color, scale: float, pos: Vector3, rot: float) -> void:
	var t := Color(snappedf(tint.r, 0.05), snappedf(tint.g, 0.05), snappedf(tint.b, 0.05))
	var key := "%s/%s" % [kind, str(t)]
	if not groups.has(key):
		var item := BastideKitNature.tuft(kind, t, 1.0)
		if item.is_empty():
			return
		groups[key] = {"mesh": item["mesh"], "mat": item["mat"], "xf": [], "range": 70.0}
	var b := Basis(Vector3.UP, rot * 2.399).scaled(Vector3.ONE * scale)
	(groups[key]["xf"] as Array).append(Transform3D(b, pos))


static func _bush(groups: Dictionary, model: String, scale: float, pos: Vector3, rot: float) -> void:
	var item := BastideKitNature.plant(model, scale)
	if item.is_empty() or item.get("mesh") == null:
		return
	var xf := Transform3D(Basis(Vector3.UP, rot), pos)
	var key := "bush/%s/%.1f" % [model, snappedf(scale, 0.1)]
	if not groups.has(key):
		groups[key] = {"mesh": item["mesh"], "mat": item["mat"], "xf": [], "shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "range": 110.0}
	(groups[key]["xf"] as Array).append(xf)
	if item.get("trunk") != null:
		if not groups.has(key + "/bois"):
			groups[key + "/bois"] = {"mesh": item["trunk"], "mat": BastideKitNature.trunk_material(), "xf": [], "range": 110.0}
		(groups[key + "/bois"]["xf"] as Array).append(xf)


static func _greenery(fr: Frame, groups: Dictionary, m: Mound, bs: BastideBuildingStyle, door_r: float) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = m.seed * 7919 + 3
	var fz := m.dz
	var flowers := bs.flower_colors
	# Au-dessus de la pièce creusée, le relief ne monte pas : l'herbe du terrain n'y
	# pousse pas. Des touffes serrées la remplacent sur la butte maillée.
	if m.room.size.x > 0.0:
		var hol := m.hollow()
		if BastideGrass.mound_material:
			_grass_cards(fr, groups, m, hol, r)
			hol = Rect2()
		var step := 0.5
		var gx := hol.position.x
		while hol.size.x > 0.0 and gx < hol.end.x:
			var gz := hol.position.y
			while gz < hol.end.y:
				var x := gx + r.randf_range(0.0, step)
				var z := gz + r.randf_range(0.0, step)
				gz += step
				if z < fr.face_z(x) + 0.35 or fr.owner(x) != m:
					continue
				var y := fr.surface(x, z)
				if y < 0.15:
					continue
				# Teinte verte : les fleurs du motif se fondent dans l'herbe.
				_plant(groups, "meadow", Color(0.5, 0.8, 0.36).lerp(Color(0.62, 0.86, 0.42), r.randf()), r.randf_range(0.85, 1.2),
						fr.p(x, y - 0.05, z), r.randf() * 10.0)
			gx += step
	# Touffes d'herbe et fleurs sur les flancs et au pied de la butte.
	for k in 12:
		var x := m.cx + r.randf_range(-m.ax, m.ax)
		var z := r.randf_range(fz - 0.2, m.zc + m.dz + m.az)
		var zf := fr.face_z(x)
		if z < zf + 0.15:
			continue
		var y := fr.surface(x, z)
		var dxn := (x - m.cx) / m.ax
		var dzn := maxf(z - m.zc - m.dz, 0.0) / m.az
		var rr := sqrt(dxn * dxn + dzn * dzn)
		if rr > 1.02 or (rr < 0.5 and r.randf() < 0.75):
			continue
		if fr.owner(x) != m:
			continue
		var roll := r.randf()
		if roll < 0.08 and not flowers.is_empty():
			var c: Color = flowers[r.randi() % flowers.size()]
			_plant(groups, "flower", Color(0.7 + c.r * 0.45, 0.7 + c.g * 0.45, 0.7 + c.b * 0.45), r.randf_range(0.3, 0.42),
					fr.p(x, y - 0.03, z), r.randf() * 10.0)
		else:
			_plant(groups, "meadow", Color(1.0, 1.0, 0.9).lerp(Color(0.9, 1.0, 0.8), r.randf()), r.randf_range(0.8, 1.25),
					fr.p(x, y - 0.04, z), r.randf() * 10.0)
	# Fleurs qui débordent de l'avancée d'herbe, au-dessus de la façade.
	for k in 6:
		var x := m.cx + r.randf_range(-m.face_half, m.face_half)
		if absf(x - m.cx) < door_r * 0.6 and r.randf() < 0.6:
			continue
		var zf := fr.face_z(x)
		var y := fr.face_top(x)
		if y < 0.6:
			continue
		var c: Color = flowers[r.randi() % flowers.size()] if not flowers.is_empty() else Color(0.9, 0.5, 0.6)
		_plant(groups, "meadow", Color(0.72 + c.r * 0.4, 0.72 + c.g * 0.4, 0.72 + c.b * 0.4),
				r.randf_range(0.35, 0.5), fr.p(x, y - 0.04, zf - LIP + 0.08), r.randf() * 10.0)
	# Buissons et massifs fleuris au pied des flancs, de part et d'autre de la façade.
	var shrubs := ["bush_1", "hydrangea_blue", "azalea_pink", "hydrangea_pink", "bush_1"]
	for s in [-1.0, 1.0]:
		var x: float = m.cx + s * (m.w * 0.5 - 0.6 + r.randf_range(-0.3, 0.2))
		var zf := fr.face_z(x)
		if fr.face_top(x) > 2.2:
			x += s * 0.6
		_bush(groups, shrubs[r.randi() % shrubs.size()], r.randf_range(0.7, 0.95), fr.p(x, 0.0, zf - 0.35), r.randf() * TAU)
	# Fleurs au pied de la façade, entre la porte et les flancs (jamais devant le seuil).
	for k in 10:
		var x := m.cx + r.randf_range(-m.w * 0.5, m.w * 0.5)
		if absf(x - m.cx) < door_r + 0.35:
			continue
		var zf := fr.face_z(x)
		var c: Color = flowers[r.randi() % flowers.size()] if not flowers.is_empty() else Color(0.9, 0.5, 0.6)
		_plant(groups, "flower", Color(0.7 + c.r * 0.45, 0.7 + c.g * 0.45, 0.7 + c.b * 0.45), r.randf_range(0.45, 0.7),
				fr.p(x, 0.0, zf - r.randf_range(0.15, 0.5)), r.randf() * 10.0)


# --- Relief ----------------------------------------------------------------------------
# La butte maillée porte la façade et son front d'herbe. Sous elle, le relief monte
# lui aussi (un peu en retrait) et s'étale bien au-delà en une large colline douce,
# avec quelques petites collines autour : l'herbe du terrain pousse dessus, et la
# butte se fond dans la prairie.

## Données du relief (dans les ancres) : repère, buttes, petites collines.
static func _terrain_data(fr: Frame, seed: int) -> Dictionary:
	var mounds: Array = []
	var knolls: Array = []
	for i in fr.mounds.size():
		var m: Mound = fr.mounds[i]
		mounds.append([m.cx, m.w, m.h, m.ax, m.zc, m.az, m.dz, m.cap, m.face_half, m.room])
		# Deux ou trois petites collines sur les côtés et à l'arrière.
		var n := 2 + int(BastideRng.randf_at(m.seed, "collines") * 2.0)
		for k in n:
			var ang := lerpf(-1.35, 1.35, BastideRng.randf_at(m.seed, "colline_a", k))
			var dist := lerpf(1.1, 1.45, BastideRng.randf_at(m.seed, "colline_d", k))
			var dir := Vector2(sin(ang), cos(ang))
			var c := Vector2(m.cx + dir.x * m.ax * dist, m.zc + m.dz + dir.y * m.az * dist * 0.9)
			var kr := lerpf(2.6, 4.4, BastideRng.randf_at(m.seed, "colline_r", k))
			# Jamais devant une façade : la cour et le chemin restent à plat.
			if c.y - kr < m.dz + 0.5 and absf(c.x - m.cx) - kr < m.face_half + 2.0:
				continue
			knolls.append([c.x, c.y, kr,
					lerpf(0.6, 1.5, BastideRng.randf_at(m.seed, "colline_h", k))])
	return {"o": fr.o, "x": fr.x, "z": fr.z, "y0": fr.y0, "mounds": mounds, "knolls": knolls}


static func _frame_from(data: Dictionary) -> Frame:
	var fr := Frame.new()
	fr.o = data["o"]
	fr.x = data["x"]
	fr.z = data["z"]
	fr.y0 = data["y0"]
	for a: Array in data["mounds"]:
		var m := Mound.new()
		m.cx = a[0]; m.w = a[1]; m.h = a[2]; m.ax = a[3]; m.zc = a[4]; m.az = a[5]; m.dz = a[6]
		m.cap = a[7]; m.face_half = a[8]
		if a.size() > 9:
			m.room = a[9]
		fr.mounds.append(m)
	return fr


## Hauteur du relief (au-dessus du sol de la maison) au point (px, pz) du repère de
## façade : sous la butte, juste en retrait de son herbe ; autour, une colline large
## et basse ; devant la façade, rien (la cour et le seuil restent à plat).
static func terrain_height(fr: Frame, knolls: Array, px: float, pz: float) -> float:
	var m := fr.owner(px)
	var zf := fr.face_z(px)
	var near_face := 1.0 - smoothstep(m.face_half + 0.6, m.face_half + 2.4, absf(px - m.cx))
	var fade := lerpf(1.0, smoothstep(zf + 0.3, zf + 1.3, pz), near_face)
	# Au-dessus de la pièce creusée, le relief reste au sol : seule la butte maillée
	# couvre la voûte (sinon le sol du terrain traverserait la pièce).
	for o: Mound in fr.mounds:
		if o.room.size.x > 0.0 and o.hollow().has_point(Vector2(px, pz)):
			return 0.0
	var h := maxf(fr.surface(px, pz) - 0.08, 0.0)
	# Grande colline douce : la butte s'étale dans la prairie.
	for o: Mound in fr.mounds:
		var dx := (px - o.cx) / (o.ax * 1.75)
		var dz := (pz - o.zc - o.dz) / (o.az * 1.6 if pz > o.zc + o.dz else o.zc + 2.2)
		var r2 := dx * dx + dz * dz
		if r2 < 1.0:
			h = maxf(h, o.h * 0.42 * (1.0 - r2) * (1.0 - r2))
	for k: Array in knolls:
		var d := Vector2(px - float(k[0]), pz - float(k[1])).length() / float(k[2])
		if d < 1.0:
			var u := 1.0 - d * d
			h = maxf(h, float(k[3]) * u * u)
	return h * fade


## Description pour BastideTerrain.set_carve (type « mound ») : hauteurs monde sur la
## grille du relief (NAN : intact). `xf` : repère local → monde, hauteur de pose comprise.
static func carve(data: Dictionary, xf: Transform3D, base: BastideHeightField) -> Dictionary:
	var fr := _frame_from(data)
	var knolls: Array = data["knolls"]
	var reach := 0.0
	for m: Mound in fr.mounds:
		reach = maxf(reach, maxf(m.ax, m.az) * 1.8)
	for k: Array in knolls:
		reach = maxf(reach, Vector2(k[0], k[1]).length() + float(k[2]))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var c0: Vector3 = xf * Vector3(fr.o.x, fr.y0, fr.o.y)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var w := c0 + xf.basis * fr.dir(corner.x * reach, corner.y * reach)
		lo = lo.min(Vector2(w.x, w.z))
		hi = hi.max(Vector2(w.x, w.z))
	var i0 := maxi(0, floori((lo.x - base.origin.x) / base.cell))
	var j0 := maxi(0, floori((lo.y - base.origin.y) / base.cell))
	var i1 := mini(base.width - 1, ceili((hi.x - base.origin.x) / base.cell))
	var j1 := mini(base.depth - 1, ceili((hi.y - base.origin.y) / base.cell))
	var w := maxi(0, i1 - i0 + 1)
	var d := maxi(0, j1 - j0 + 1)
	var heights := PackedFloat32Array()
	heights.resize(w * d)
	var inv := xf.affine_inverse()
	for jj in d:
		for ii in w:
			var wx := base.origin.x + (i0 + ii) * base.cell
			var wz := base.origin.y + (j0 + jj) * base.cell
			var l := inv * Vector3(wx, 0.0, wz)
			var q := Vector2(l.x, l.z) - fr.o
			var h := terrain_height(fr, knolls, q.dot(fr.x), q.dot(fr.z))
			heights[jj * w + ii] = (xf * Vector3(l.x, fr.y0 + h, l.z)).y if h > 0.01 else NAN
	var r := Rect2(base.origin + Vector2(i0, j0) * base.cell, Vector2(w, d) * base.cell)
	return {"type": "mound", "i0": i0, "j0": j0, "w": w, "d": d, "heights": heights, "rect": r.grow(base.cell)}


# --- Charpente de façade et mobilier ------------------------------------------------

static func _box(mb: BastideMeshBuilder, fr: Frame, role: StringName, x0: float, x1: float, y0: float, y1: float,
		z0: float, z1: float, col: Color, edge: Color, bevel := 0.015) -> Array:
	var kk: Array = []
	for yy in [y0, y1]:
		for q: Vector2 in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]:
			kk.append(fr.p(q.x, yy, q.y))
	mb.add_block(role, kk, bevel, 0.004, col, edge)
	return kk


## Charpente de bois de la façade : sablière sous l'avancée d'herbe, bandeau au bord
## de l'herbe, poteaux aux extrémités et de part et d'autre de la porte.
static func _timber(mb: BastideMeshBuilder, fr: Frame, m: Mound, door_r: float, holes: Array,
		bs: BastideBuildingStyle) -> void:
	var wood := bs.wood_color
	var edge := wood.darkened(0.35)
	var xa := m.cx - m.face_half
	var xb := m.cx + m.face_half
	# Sablière et bandeau, par tronçons qui suivent la courbe du haut de la façade.
	var n := maxi(6, ceili((xb - xa) / 0.32))
	for k in n:
		var x0 := lerpf(xa, xb, float(k) / n)
		var x1 := lerpf(xa, xb, float(k + 1) / n)
		var xm := (x0 + x1) * 0.5
		var ft := fr.face_top(xm)
		if ft < 0.6 or fr.owner(xm) != m:
			continue
		var top := ft - LIP_DROP
		var zf := fr.face_z(xm)
		var tint := BastideRng.signed_at(m.seed, "poutre", k) * 0.04
		var c := wood.lightened(tint) if tint > 0.0 else wood.darkened(-tint)
		_box(mb, fr, ROLE_WOOD, x0 - 0.01, x1 + 0.01, top - 0.2, top + 0.01, zf - 0.1, zf + 0.06, c, edge)
		_box(mb, fr, ROLE_WOOD, x0 - 0.01, x1 + 0.01, ft - 0.15, ft + 0.03, zf - LIP - 0.07, zf - LIP + 0.05,
				c.darkened(0.08), edge)
	# Poteaux : aux deux bouts, et encadrant la porte (sans couper une fenêtre).
	var posts := [m.face_half * 0.86 - 0.12, -(m.face_half * 0.86 - 0.12), door_r + 0.66, -(door_r + 0.66)]
	for dx: float in posts:
		var x := m.cx + dx
		var ok := true
		for hole: Array in holes:
			if absf(x - float(hole[0])) < float(hole[2]) + 0.22 and absf(float(hole[0]) - m.cx) > 0.1:
				ok = false
		if not ok:
			continue
		var top := fr.face_top(x) - LIP_DROP - 0.18
		if top < 0.8:
			continue
		var zf := fr.face_z(x)
		_box(mb, fr, ROLE_WOOD, x - 0.11, x + 0.11, -0.1, top, zf - 0.13, zf + 0.06, wood.darkened(0.05), edge)


## Banc de planches sur deux pieds, contre la façade.
static func _bench(mb: BastideMeshBuilder, fr: Frame, x: float, z: float, coll: BastideBuildResult) -> void:
	var wood := Color(0.46, 0.32, 0.2)
	var edge := wood.darkened(0.35)
	var hw := 0.62
	for s in [-1.0, 1.0]:
		_box(mb, fr, ROLE_WOOD, x + s * (hw - 0.1) - 0.05, x + s * (hw - 0.1) + 0.05, -0.05, 0.42, z - 0.17, z + 0.17,
				wood.darkened(0.12), edge)
	var seat := _box(mb, fr, ROLE_WOOD, x - hw, x + hw, 0.42, 0.48, z - 0.21, z + 0.21, wood, edge)
	# Dossier : deux planches sur montants.
	for s in [-1.0, 1.0]:
		_box(mb, fr, ROLE_WOOD, x + s * (hw - 0.1) - 0.04, x + s * (hw - 0.1) + 0.04, 0.48, 0.95, z + 0.14, z + 0.22,
				wood.darkened(0.1), edge)
	for yy in [0.62, 0.82]:
		_box(mb, fr, ROLE_WOOD, x - hw, x + hw, yy, yy + 0.11, z + 0.16, z + 0.23, wood.lightened(0.04), edge)
	if coll:
		coll.add_box(seat)


# --- Intérieur ------------------------------------------------------------------------
# Une pièce voûtée creusée derrière la façade : plancher de bois, murs et voûte
# enduits, arcs de bois, âtre de briques au fond, table et tabourets.

## Pièce de la butte : sous la voûte, il reste toujours de l'herbe au-dessus.
static func _plan_room(fr: Frame, m: Mound, depth: float) -> void:
	var zi := m.face_z(m.cx) + 0.24
	var rw := m.face_half * 0.8 - 0.15
	var rd := clampf(depth * 0.75, 3.2, 5.0)
	m.room = Rect2(m.cx - rw, zi, rw * 2.0, rd)
	# Voûte : sous la façade près de l'entrée, et sous la butte (marge d'herbe) partout.
	var top := fr.face_top(m.cx) - LIP_DROP - 0.12
	var low := INF
	for k in 9:
		var x := lerpf(m.room.position.x, m.room.end.x, k / 8.0)
		for j in 6:
			var z := lerpf(zi, m.room.end.y, j / 5.0)
			low = minf(low, fr.surface(x, z) - 0.55)
	m.vault_h = clampf(minf(top, 2.45), 2.0, 2.6)
	m.wall_h = clampf(minf(low, 1.35), 1.0, 1.35)
	# Les côtés de la voûte restent sous l'herbe : on les abaisse s'il le faut.
	for k in 9:
		var x := lerpf(m.room.position.x, m.room.end.x, k / 8.0)
		var room_top := INF
		for j in 6:
			room_top = minf(room_top, fr.surface(x, lerpf(zi, m.room.end.y, j / 5.0)) - 0.4)
		if m.ceil_at(x) > room_top and absf(x - m.cx) > 0.3:
			m.vault_h = maxf(m.wall_h + 0.4, m.vault_h - (m.ceil_at(x) - room_top))


static func _interior(fr: Frame, m: Mound, door_r: float, holes: Array, style: BastideStyle,
		with_collision: bool) -> Array:
	var bs := style.get_building_style()
	var res := BastideBuildResult.new()
	var mb := BastideMeshBuilder.new()
	var coll: BastideBuildResult = res if with_collision else null
	var x0 := m.room.position.x
	var x1 := m.room.end.x
	var zi := m.room.position.y
	var zb := m.room.end.y
	var fy := 0.07
	var fwd := fr.dir(0.0, 1.0)
	var plaster := bs.plaster_color.lightened(0.04)
	var alt := bs.plaster_color_alt
	var wood := bs.wood_color
	var floor_c := Color(0.55, 0.38, 0.24)
	var cols := maxi(6, ceili((x1 - x0) / 0.26))
	for i in cols:
		var xa := lerpf(x0, x1, float(i) / cols)
		var xb := lerpf(x0, x1, float(i + 1) / cols)
		# Plancher : une lame par colonne.
		var t := BastideRng.signed_at(m.seed, "lame", i) * 0.07
		var pc := floor_c.lightened(t) if t > 0.0 else floor_c.darkened(-t)
		mb.add_quad(ROLE_WOOD, fr.p(xa, fy, zi - 0.3), fr.p(xb, fy, zi - 0.3), fr.p(xb, fy, zb), fr.p(xa, fy, zb), Vector3.UP,
				pc.darkened(0.1), pc, pc, pc.darkened(0.1))
		# Voûte enduite.
		var ya := m.ceil_at(xa)
		var yb := m.ceil_at(xb)
		var mid := fr.p((xa + xb) * 0.5, 0.0, 0.0)
		var hint := Vector3.DOWN + (fr.p(m.cx, 0.0, 0.0) - mid) * 0.3
		var ca := plaster.lerp(alt, BastideRng.noise1(m.seed, "voute", xa) * 0.5 + 0.5)
		mb.add_quad(ROLE_BODY, fr.p(xa, ya, zi), fr.p(xb, yb, zi), fr.p(xb, yb, zb), fr.p(xa, ya, zb), hint, ca, ca, ca, ca)
		# Mur du fond.
		mb.add_quad(ROLE_BODY, fr.p(xa, 0.0, zb), fr.p(xb, 0.0, zb), fr.p(xb, yb, zb), fr.p(xa, ya, zb), -fwd, ca, ca, ca, ca)
		# Mur de façade, côté intérieur, percé de la porte et des fenêtres.
		var rows := ceili(maxf(ya, yb) / 0.16)
		for j in rows:
			var y0 := j * 0.16
			var y1 := minf((j + 1) * 0.16, minf(ya, yb))
			if y1 <= y0:
				continue
			var c := Vector2((xa + xb) * 0.5, (y0 + y1) * 0.5)
			var skip := false
			for hole: Array in holes:
				if c.distance_to(Vector2(hole[0], hole[1])) < float(hole[2]) + 0.02:
					skip = true
			if not skip:
				mb.add_quad(ROLE_BODY, fr.p(xa, y0, zi), fr.p(xb, y0, zi), fr.p(xb, y1, zi), fr.p(xa, y1, zi), fwd, ca, ca, ca, ca)
	# Murs des côtés.
	for s in [-1.0, 1.0]:
		var x: float = x1 if s > 0.0 else x0
		var hh := m.ceil_at(x)
		mb.add_quad(ROLE_BODY, fr.p(x, 0.0, zi), fr.p(x, 0.0, zb), fr.p(x, hh, zb), fr.p(x, hh, zi), fr.dir(-s, 0.0), plaster, plaster, plaster, plaster)
	# Embrasures : de la façade au mur intérieur, autour de chaque trou.
	for hole: Array in holes:
		var hx: float = hole[0]
		var hy: float = hole[1]
		var hr: float = float(hole[2]) + 0.02
		var z0 := fr.face_z(hx) + 0.12
		for k in 24:
			var a0 := TAU * k / 24.0
			var a1 := TAU * (k + 1) / 24.0
			var p0 := Vector2(hx + cos(a0) * hr, maxf(hy + sin(a0) * hr, 0.0))
			var p1 := Vector2(hx + cos(a1) * hr, maxf(hy + sin(a1) * hr, 0.0))
			var inward := fr.p(hx, hy, z0) - fr.p((p0.x + p1.x) * 0.5, (p0.y + p1.y) * 0.5, z0)
			mb.add_quad(ROLE_WOOD, fr.p(p0.x, p0.y, z0), fr.p(p1.x, p1.y, z0), fr.p(p1.x, p1.y, zi + 0.01), fr.p(p0.x, p0.y, zi + 0.01),
					inward, wood.darkened(0.1), wood.darkened(0.1), wood, wood)
	# Arcs de bois sous la voûte, et leurs poteaux.
	var n_ribs := maxi(2, roundi((zb - zi) / 1.4))
	for r in n_ribs:
		var z := lerpf(zi + 0.5, zb - 0.45, float(r) / maxf(n_ribs - 1, 1))
		for i in cols:
			var xa := lerpf(x0, x1, float(i) / cols)
			var xb := lerpf(x0, x1, float(i + 1) / cols)
			var ya := m.ceil_at(xa) - 0.06
			var yb := m.ceil_at(xb) - 0.06
			mb.add_quad(ROLE_WOOD, fr.p(xa, ya, z - 0.08), fr.p(xb, yb, z - 0.08), fr.p(xb, yb, z + 0.08), fr.p(xa, ya, z + 0.08),
					Vector3.DOWN, wood, wood, wood, wood)
			mb.add_quad(ROLE_WOOD, fr.p(xa, ya, z - 0.08), fr.p(xb, yb, z - 0.08), fr.p(xb, yb + 0.06, z - 0.08), fr.p(xa, ya + 0.06, z - 0.08),
					-fwd, wood.darkened(0.15), wood.darkened(0.15), wood.darkened(0.15), wood.darkened(0.15))
		for s in [-1.0, 1.0]:
			var x: float = (x1 - 0.09) if s > 0.0 else (x0 + 0.09)
			_box(mb, fr, ROLE_WOOD, x - 0.09, x + 0.09, 0.0, m.ceil_at(x) - 0.05, z - 0.08, z + 0.08, wood, wood.darkened(0.3))
	# Âtre de briques au fond, linteau de bois, braises.
	var hx := m.cx + (x1 - x0) * 0.18
	_box(mb, fr, ROLE_BODY, hx - 0.75, hx - 0.45, 0.0, 1.05, zb - 0.45, zb, Color(BRICK, 1.0), BRICK.darkened(0.3), 0.02)
	_box(mb, fr, ROLE_BODY, hx + 0.45, hx + 0.75, 0.0, 1.05, zb - 0.45, zb, Color(BRICK_ALT, 1.0), BRICK.darkened(0.3), 0.02)
	_box(mb, fr, ROLE_BODY, hx - 0.45, hx + 0.45, 0.78, 1.05, zb - 0.45, zb, Color(BRICK, 1.0), BRICK.darkened(0.3), 0.02)
	_box(mb, fr, ROLE_BODY, hx - 0.45, hx + 0.45, 0.0, 0.78, zb - 0.06, zb, Color(0.08, 0.06, 0.05, 1.0), Color(0.05, 0.04, 0.03), 0.0)
	_box(mb, fr, ROLE_WOOD, hx - 0.85, hx + 0.85, 1.05, 1.17, zb - 0.55, zb, wood.darkened(0.1), wood.darkened(0.4))
	_box(mb, fr, ROLE_PAPER, hx - 0.25, hx + 0.25, 0.0, 0.12, zb - 0.35, zb - 0.12, Color(1.0, 0.55, 0.2), Color(0.6, 0.2, 0.05), 0.02)
	# Table ronde et tabourets.
	var tc := Vector2(m.cx - (x1 - x0) * 0.12, (zi + zb) * 0.5 + 0.2)
	var tw := Color(0.5, 0.34, 0.2)
	_box(mb, fr, ROLE_WOOD, tc.x - 0.07, tc.x + 0.07, 0.0, 0.7, tc.y - 0.07, tc.y + 0.07, tw.darkened(0.15), tw.darkened(0.4))
	var top: Array = []
	for yy in [0.7, 0.76]:
		for k in 8:
			var a := TAU * k / 8.0 + 0.39
			top.append(fr.p(tc.x + cos(a) * 0.55, yy, tc.y + sin(a) * 0.55))
	for k in 8:
		var a0 := TAU * k / 8.0 + 0.39
		var a1 := TAU * (k + 1) / 8.0 + 0.39
		var c := fr.p(tc.x, 0.76, tc.y)
		mb.add_tri(ROLE_WOOD, c, fr.p(tc.x + cos(a0) * 0.55, 0.76, tc.y + sin(a0) * 0.55),
				fr.p(tc.x + cos(a1) * 0.55, 0.76, tc.y + sin(a1) * 0.55), Vector3.UP, tw, tw, tw)
		mb.add_quad(ROLE_WOOD, fr.p(tc.x + cos(a0) * 0.55, 0.7, tc.y + sin(a0) * 0.55), fr.p(tc.x + cos(a1) * 0.55, 0.7, tc.y + sin(a1) * 0.55),
				fr.p(tc.x + cos(a1) * 0.55, 0.76, tc.y + sin(a1) * 0.55), fr.p(tc.x + cos(a0) * 0.55, 0.76, tc.y + sin(a0) * 0.55),
				fr.dir(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5)), tw.darkened(0.2), tw.darkened(0.2), tw.darkened(0.2), tw.darkened(0.2))
	for k in 2:
		var a := 0.6 + k * 2.6
		var sc := tc + Vector2(cos(a), sin(a)) * 0.85
		_box(mb, fr, ROLE_WOOD, sc.x - 0.17, sc.x + 0.17, 0.0, 0.44, sc.y - 0.17, sc.y + 0.17, tw.lightened(0.05), tw.darkened(0.35))
	# Collision : plancher, murs.
	if coll:
		var e := 0.2
		var q := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
			coll.collision_faces.append_array(PackedVector3Array([a, b, c, a, c, d]))
		q.call(fr.p(x0, fy, zi - 0.3), fr.p(x1, fy, zi - 0.3), fr.p(x1, fy, zb), fr.p(x0, fy, zb))
		q.call(fr.p(x0, 0.0, zb), fr.p(x1, 0.0, zb), fr.p(x1, 2.6, zb), fr.p(x0, 2.6, zb))
		for s in [-1.0, 1.0]:
			var x: float = (x1 - e) if s > 0.0 else (x0 + e)
			q.call(fr.p(x, 0.0, zi), fr.p(x, 0.0, zb), fr.p(x, 2.6, zb), fr.p(x, 2.6, zi))
		coll.add_box([fr.p(tc.x - 0.5, 0.0, tc.y - 0.5), fr.p(tc.x + 0.5, 0.0, tc.y - 0.5), fr.p(tc.x + 0.5, 0.0, tc.y + 0.5),
			fr.p(tc.x - 0.5, 0.0, tc.y + 0.5), fr.p(tc.x - 0.5, 0.76, tc.y - 0.5), fr.p(tc.x + 0.5, 0.76, tc.y - 0.5),
			fr.p(tc.x + 0.5, 0.76, tc.y + 0.5), fr.p(tc.x - 0.5, 0.76, tc.y + 0.5)])
	res.mesh = mb.commit({
		ROLE_BODY: style.get_material(),
		ROLE_WOOD: style.get_wood_material(),
		ROLE_PAPER: style.get_paper_material(),
	})
	res.anchors["lights"] = PackedVector3Array([fr.p(m.cx, m.vault_h - 0.5, (zi + zb) * 0.5), fr.p(hx, 0.45, zb - 0.7)])
	# Plan : une pièce, un niveau (les lumières s'allument quand on y entre).
	var il := BastideInteriorLayout.new()
	var poly := PackedVector2Array()
	for c in [Vector2(x0, zi - 0.3), Vector2(x1, zi - 0.3), Vector2(x1, zb), Vector2(x0, zb)]:
		var w: Vector2 = fr.o + fr.x * c.x + fr.z * c.y
		poly.append(w)
	il.inner = BastidePolygon.ensure_direct(poly)
	il.base_y = fr.y0
	var lvl := BastideInteriorLayout.Level.new()
	lvl.y = fr.y0 + fy
	lvl.ceiling_y = fr.y0 + m.vault_h
	lvl.pieces = [il.inner]
	lvl.rooms = [{"poly": il.inner, "kind": "terrier"}]
	il.levels = [lvl]
	var dp := fr.o + fr.x * m.cx + fr.z * zi
	il.door = {"pos": dp, "inward": fr.z}
	return [res, il]


## Herbe peinte sur la butte, au-dessus de la pièce (là où le relief ne monte pas) :
## les mêmes cartes que la prairie, pieds posés sur le maillage de la butte.
static func _grass_cards(fr: Frame, groups: Dictionary, m: Mound, hol: Rect2, r: RandomNumberGenerator) -> void:
	var density := 22.0
	var count := int(hol.size.x * hol.size.y * density)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var corners := [Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)]
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for c in count:
		var x := hol.position.x + r.randf() * hol.size.x
		var z := hol.position.y + r.randf() * hol.size.y
		if z < fr.face_z(x) + 0.3 or fr.owner(x) != m:
			continue
		var y := fr.surface(x, z)
		if y < 0.1:
			continue
		var q := fr.p(x, y - 0.02, z)
		lo = lo.min(q)
		hi = hi.max(q)
		var col := Color(r.randf(), r.randf(), r.randf(), r.randf())
		var v := verts.size()
		for k in 4:
			var cu: Vector2 = corners[k]
			verts.append(Vector3(q.x + cu.x * 0.2, q.y, q.z))
			uvs.append(cu)
			uv2s.append(Vector2(q.x, q.z))
			cols.append(col)
		idx.append_array(PackedInt32Array([v, v + 1, v + 2, v + 1, v + 3, v + 2]))
	if verts.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = AABB(lo - Vector3(1, 1, 1), hi - lo + Vector3(2, 2, 2))
	groups["herbe_butte_%d" % m.seed] = {"mesh": mesh, "mat": BastideGrass.mound_material, "xf": [Transform3D.IDENTITY], "range": 60.0}
