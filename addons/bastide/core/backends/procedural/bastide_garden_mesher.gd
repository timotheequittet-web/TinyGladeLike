@tool
class_name BastideGardenMesher
extends RefCounted
## Pièces du décor dessinées en triangles : pierres plates, galets, rochers,
## lanternes de pierre, buissons taillés, hortensias, fougères, herbes, érables,
## cerisiers, pins taillés, bambous. Fonctions pures sur un BastideMeshBuilder.
##
## Chaque pièce tire ses petites variations d'une clé entière (BastideRng) : même
## clé = même plante, au brin près.

const ROLE_STONE := &"stone"
const ROLE_GRAVEL := &"gravel"
const ROLE_FOLIAGE := &"foliage"
const ROLE_PAINT := &"paint"
const ROLE_WOOD := &"wood"
const ROLE_PAPER := &"paper"


## Matériaux par rôle pour BastideMeshBuilder.commit().
static func materials(style: BastideStyle) -> Dictionary:
	return {
		ROLE_STONE: style.get_material(),
		ROLE_GRAVEL: style.get_gravel_material(),
		ROLE_FOLIAGE: style.get_foliage_material(),
		ROLE_PAINT: style.get_paint_material(),
		ROLE_WOOD: style.get_wood_material(),
		ROLE_PAPER: style.get_paper_material(),
	}


static func h(key: int, i: int) -> float:
	return BastideRng.unit(BastideRng.combine(key, i))


static func hs(key: int, i: int) -> float:
	return h(key, i) * 2.0 - 1.0


static func pick(colors: PackedColorArray, key: int, i: int, fallback := Color(0.3, 0.45, 0.22)) -> Color:
	if colors.is_empty():
		return fallback
	return colors[int(h(key, i) * colors.size()) % colors.size()]


static func tint(c: Color, amount: float) -> Color:
	return c.lightened(amount) if amount > 0.0 else c.darkened(-amount)


## Clé stable tirée d'une position (au décimètre) : une plante garde son allure
## quand on modifie une structure ailleurs.
static func key_at(seed: int, p: Vector3, channel := 0) -> int:
	return BastideRng.combine(BastideRng.combine(seed + channel * 7919, roundi(p.x * 10.0)), roundi(p.z * 10.0))


# --- Pierres -------------------------------------------------------------------------

## Pierre plate irrégulière (pas japonais, pierre de seuil) : prisme à `sides`
## côtés, dessus légèrement chanfreiné. `stretch` allonge la pierre selon `rot`.
static func slab(mb: BastideMeshBuilder, center: Vector3, radius: float, top: float, rot: float, key: int,
		col: Color, sides := 7, stretch := 1.0, base := -0.04) -> void:
	var ring := PackedVector3Array()
	var inner := PackedVector3Array()
	var ca := cos(rot)
	var sa := sin(rot)
	for i in sides:
		var a := TAU * (float(i) + hs(key, i) * 0.25) / sides
		var r := radius * (1.0 + hs(key, 40 + i) * 0.16)
		var lx := cos(a) * r * stretch
		var lz := sin(a) * r
		var off := Vector3(lx * ca - lz * sa, 0.0, lx * sa + lz * ca)
		ring.append(center + off + Vector3(0, base, 0))
		inner.append(center + off * (1.0 - minf(0.05 / maxf(r, 0.05), 0.3)) + Vector3(0, top, 0))
	var c_top := tint(col, hs(key, 90) * 0.06 + 0.03)
	var c_side := col.darkened(0.18)
	var apex := center + Vector3(0, top + hs(key, 91) * 0.006, 0)
	for i in sides:
		var j := (i + 1) % sides
		mb.add_tri(ROLE_STONE, apex, inner[i], inner[j], Vector3.UP, c_top, c_top, c_top)
		var out := (ring[i] + ring[j]) * 0.5 - center
		out.y = 0.0
		mb.add_quad(ROLE_STONE, ring[i], ring[j], inner[j], inner[i], out, c_side, c_side, c_top, c_top)


## Galet ou rocher : boule bosselée à facettes, à moitié enterrée.
static func rock(mb: BastideMeshBuilder, center: Vector3, size: Vector3, key: int, col: Color,
		rings := 4, segs := 7, sink := 0.35) -> void:
	var grid: Array = []
	for i in rings + 1:
		var v := float(i) / rings
		var phi := v * PI
		var row := PackedVector3Array()
		for j in segs:
			var th := TAU * (float(j) + (0.5 if i % 2 == 1 else 0.0)) / segs
			var bump := 1.0 + (hs(key, i * 31 + j) * 0.22 if i > 0 and i < rings else 0.0)
			var y := cos(phi) * size.y
			if y < 0.0:
				y *= 0.5
			row.append(center + Vector3(sin(phi) * cos(th) * size.x * bump, y - size.y * sink,
					sin(phi) * sin(th) * size.z * bump))
		grid.append(row)
	for i in rings:
		var r0: PackedVector3Array = grid[i]
		var r1: PackedVector3Array = grid[i + 1]
		for j in segs:
			var a := r0[j]
			var b := r0[(j + 1) % segs]
			var c := r1[(j + 1) % segs]
			var d := r1[j]
			var mid := (a + b + c + d) * 0.25
			var k := 1.0 + hs(key, 500 + i * 17 + j) * 0.06
			var shade := col * k
			shade.a = 1.0
			if i == 0:
				mb.add_tri(ROLE_STONE, a, c, d, mid - center, shade, shade, shade)
			elif i == rings - 1:
				mb.add_tri(ROLE_STONE, a, b, c, mid - center, shade, shade, shade)
			else:
				mb.add_quad(ROLE_STONE, a, b, c, d, mid - center, shade, shade, shade, shade)


## Prisme à `sides` côtés (pièces de lanterne), dessus et côtés.
static func prism(mb: BastideMeshBuilder, role: StringName, c: Vector3, r0: float, r1: float, y0: float, y1: float,
		sides: int, col: Color, rot := 0.0, top := true, bottom := false) -> void:
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	for i in sides:
		var a := rot + TAU * i / sides
		lo.append(c + Vector3(cos(a) * r0, y0, sin(a) * r0))
		hi.append(c + Vector3(cos(a) * r1, y1, sin(a) * r1))
	var side_col := col.darkened(0.08)
	for i in sides:
		var j := (i + 1) % sides
		var out := (lo[i] + lo[j]) * 0.5 - c
		out.y = 0.0
		mb.add_quad(role, lo[i], lo[j], hi[j], hi[i], out, side_col, side_col, side_col, side_col)
	if top:
		var apex := c + Vector3(0, y1, 0)
		for i in sides:
			mb.add_tri(role, apex, hi[i], hi[(i + 1) % sides], Vector3.UP, col, col, col)
	if bottom:
		var apex := c + Vector3(0, y0, 0)
		for i in sides:
			mb.add_tri(role, apex, lo[i], lo[(i + 1) % sides], Vector3.DOWN, col, col, col)


## Lanterne de pierre (tōrō), type kasuga : socle, fût, plateau, foyer aux
## fenêtres de papier allumées, toit à six pans relevés, joyau au sommet.
static func lantern(mb: BastideMeshBuilder, pos: Vector3, rot: float, scale: float, col: Color, key: int) -> void:
	var s := scale
	var c := tint(col, hs(key, 1) * 0.05)
	var r := rot
	prism(mb, ROLE_STONE, pos, 0.3 * s, 0.27 * s, -0.05, 0.14 * s, 6, c.darkened(0.05), r)
	prism(mb, ROLE_STONE, pos, 0.2 * s, 0.17 * s, 0.14 * s, 0.22 * s, 6, c, r)
	prism(mb, ROLE_STONE, pos, 0.1 * s, 0.085 * s, 0.22 * s, 0.78 * s, 8, c, r)
	prism(mb, ROLE_STONE, pos, 0.14 * s, 0.29 * s, 0.78 * s, 0.9 * s, 6, c.lightened(0.02), r, true, true)
	# Foyer : quatre montants autour d'une lumière de papier.
	var y0 := 0.9 * s
	var y1 := 1.2 * s
	prism(mb, ROLE_PAPER, pos, 0.15 * s, 0.15 * s, y0, y1, 6, Color(1.0, 0.86, 0.6), r + PI / 6.0, false)
	for i in 3:
		var a := r + TAU * i / 3.0
		var p := pos + Vector3(cos(a), 0, sin(a)) * 0.17 * s
		prism(mb, ROLE_STONE, p, 0.05 * s, 0.05 * s, y0, y1, 4, c, a)
	# Toit : six pans qui se relèvent un peu aux angles.
	var eave := 0.47 * s
	var ry := y1 + 0.03 * s
	var ring := PackedVector3Array()
	var lip := PackedVector3Array()
	for i in 6:
		var a := r + TAU * i / 6.0
		ring.append(pos + Vector3(cos(a) * eave, ry + 0.08 * s, sin(a) * eave))
		lip.append(pos + Vector3(cos(a) * eave * 0.98, ry, sin(a) * eave * 0.98))
	var apex := pos + Vector3(0, ry + 0.3 * s, 0)
	var roof := c.darkened(0.04)
	for i in 6:
		var j := (i + 1) % 6
		var mid := (ring[i] + ring[j]) * 0.5
		var mid_in := mid.lerp(apex, 0.18) + Vector3(0, -0.035 * s, 0)
		mb.add_tri(ROLE_STONE, apex, ring[i], mid_in, mid_in - pos, roof, roof, roof)
		mb.add_tri(ROLE_STONE, apex, mid_in, ring[j], mid_in - pos, roof, roof, roof)
		var out := mid - pos
		out.y = 0.0
		mb.add_quad(ROLE_STONE, lip[i], lip[j], ring[j], ring[i], out, roof.darkened(0.15), roof.darkened(0.15), roof, roof)
		mb.add_tri(ROLE_STONE, pos + Vector3(0, ry, 0), lip[j], lip[i], Vector3.DOWN, roof.darkened(0.3), roof.darkened(0.3), roof.darkened(0.3))
	prism(mb, ROLE_STONE, pos, 0.07 * s, 0.05 * s, ry + 0.27 * s, ry + 0.33 * s, 6, c, r)
	blob(mb, ROLE_STONE, pos + Vector3(0, ry + 0.4 * s, 0), Vector3(0.07, 0.09, 0.07) * s, c, key, 4, 6, 0.1, 0.0)


# --- Végétal ---------------------------------------------------------------------

## Ellipsoïde bosselé à normales lissées. `dark` assombrit le dessous ; `flower`
## (alpha = proportion) parsème le dessus de fleurs ; `soft` = alpha des sommets
## (souplesse dans le vent, voir le shader de feuillage).
static func blob(mb: BastideMeshBuilder, role: StringName, c: Vector3, r: Vector3, col: Color, key: int,
		rings := 5, segs := 8, dark := 0.3, bumpiness := 0.1, flower := Color(0, 0, 0, 0), soft := 1.0) -> void:
	var verts: Array = []
	var nrms: Array = []
	var cols: Array = []
	for i in rings + 1:
		var v := float(i) / rings
		var phi := v * PI
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for j in segs:
			var th := TAU * (float(j) + (0.5 if i % 2 == 1 else 0.0)) / segs
			var unit := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var bump := 1.0 + (hs(key, i * 37 + j) * bumpiness if i > 0 and i < rings else 0.0)
			row.append(c + unit * r * bump)
			nrow.append(Vector3(unit.x / r.x, unit.y / r.y, unit.z / r.z).normalized())
			var k := lerpf(1.0 - dark, 1.06, (unit.y + 1.0) * 0.5)
			var cc := Color(col.r * k, col.g * k, col.b * k, soft)
			if flower.a > 0.0 and unit.y > -0.15 and h(key, 900 + i * 37 + j) < flower.a:
				cc = Color(flower.r, flower.g, flower.b, soft)
			crow.append(cc)
		verts.append(row)
		nrms.append(nrow)
		cols.append(crow)
	for i in rings:
		var r0: PackedVector3Array = verts[i]
		var r1: PackedVector3Array = verts[i + 1]
		var n0: PackedVector3Array = nrms[i]
		var n1: PackedVector3Array = nrms[i + 1]
		var c0: PackedColorArray = cols[i]
		var c1: PackedColorArray = cols[i + 1]
		for j in segs:
			var j1 := (j + 1) % segs
			if i > 0:
				mb.add_tri_smooth(role, r0[j], r0[j1], r1[j1], n0[j], n0[j1], n1[j1], c0[j], c0[j1], c1[j1])
			if i < rings - 1:
				mb.add_tri_smooth(role, r0[j], r1[j1], r1[j], n0[j], n1[j1], n1[j], c0[j], c1[j1], c1[j])


## Tube effilé (tronc, branche, tige de bambou), normales lissées, sans bouchons.
static func tube(mb: BastideMeshBuilder, role: StringName, a: Vector3, b: Vector3, ra: float, rb: float, col: Color,
		segs := 6, soft := 0.0, col_b := Color(0, 0, 0, 0)) -> void:
	var axis := b - a
	if axis.length() < 1e-5:
		return
	axis = axis.normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(axis)
	var ca := Color(col.r, col.g, col.b, soft)
	var cb := ca if col_b.a <= 0.0 else Color(col_b.r, col_b.g, col_b.b, soft)
	for j in segs:
		var t0 := TAU * j / segs
		var t1 := TAU * (j + 1) / segs
		var o0 := side * cos(t0) + up * sin(t0)
		var o1 := side * cos(t1) + up * sin(t1)
		mb.add_tri_smooth(role, a + o0 * ra, b + o0 * rb, b + o1 * rb, o0, o0, o1, ca, cb, cb)
		mb.add_tri_smooth(role, a + o0 * ra, b + o1 * rb, a + o1 * ra, o0, o1, o1, ca, cb, ca)


## Buisson taillé en boule (karikomi : azalée, buis), parfois fleuri.
static func bush(mb: BastideMeshBuilder, c: Vector3, size: float, gs: BastideGardenStyle, key: int, bloom := false) -> void:
	var leaf := pick(gs.foliage_colors, key, 1)
	var flower := Color(0, 0, 0, 0)
	if bloom:
		var fc := pick(gs.blossom_colors, key, 2, Color(0.95, 0.6, 0.7))
		flower = Color(fc.r, fc.g, fc.b, 0.28)
	var n := 1 + int(h(key, 3) * 2.99)
	for i in n:
		var a := TAU * h(key, 10 + i)
		var off := Vector3(cos(a), 0, sin(a)) * size * (0.0 if i == 0 else 0.55)
		var s := size * (1.0 if i == 0 else 0.7 + h(key, 20 + i) * 0.2)
		blob(mb, ROLE_FOLIAGE, c + off + Vector3(0, s * 0.55, 0), Vector3(s, s * 0.72, s),
				tint(leaf, hs(key, 30 + i) * 0.05), BastideRng.combine(key, i), 5, 9, 0.38, 0.06, flower, 0.4)


## Hortensia : touffe de feuilles et grosses têtes de fleurs.
static func hydrangea(mb: BastideMeshBuilder, c: Vector3, size: float, gs: BastideGardenStyle, key: int) -> void:
	var leaf := pick(gs.foliage_colors, key, 1).darkened(0.05)
	blob(mb, ROLE_FOLIAGE, c + Vector3(0, size * 0.45, 0), Vector3(size, size * 0.62, size), leaf, key, 4, 8, 0.4, 0.12, Color(0, 0, 0, 0), 0.6)
	var fc := pick(gs.flower_colors, key, 2, Color(0.45, 0.55, 0.85))
	var heads := 4 + int(h(key, 3) * 4.0)
	for i in heads:
		var a := TAU * (float(i) / heads + hs(key, 40 + i) * 0.08)
		var rr := size * (0.45 + h(key, 50 + i) * 0.35)
		var p := c + Vector3(cos(a) * rr, size * (0.72 + h(key, 60 + i) * 0.3), sin(a) * rr)
		var hr := size * (0.2 + h(key, 70 + i) * 0.07)
		blob(mb, ROLE_FOLIAGE, p, Vector3(hr, hr * 0.85, hr), tint(fc, hs(key, 80 + i) * 0.08), BastideRng.combine(key, 100 + i),
				3, 6, 0.15, 0.15, Color(0, 0, 0, 0), 1.0)


## Fougère : frondes arquées en éventail.
static func fern(mb: BastideMeshBuilder, c: Vector3, size: float, gs: BastideGardenStyle, key: int) -> void:
	var col := pick(gs.foliage_colors, key, 1).lightened(0.05)
	var n := 7 + int(h(key, 2) * 4.0)
	for i in n:
		var a := TAU * (float(i) + hs(key, 10 + i) * 0.3) / n
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := size * (0.8 + h(key, 20 + i) * 0.4)
		var lift := 0.7 + h(key, 30 + i) * 0.4
		var prev := c + Vector3(0, 0.02, 0)
		var segs := 4
		for k in segs:
			var t := float(k + 1) / segs
			var p := c + dir * length * t + Vector3(0, length * lift * (t - t * t * 0.9), 0)
			var w0 := size * 0.16 * sin(PI * minf(float(k) / segs + 0.15, 1.0))
			var w1 := size * 0.16 * sin(PI * minf(t + 0.15, 1.0))
			var cc := Color(col.r, col.g, col.b, 1.0).darkened(0.12 * (1.0 - t))
			var nrm := (p - prev).cross(side).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			mb.add_tri_2s(ROLE_FOLIAGE, prev - side * w0, prev + side * w0, p + side * w1, nrm, cc, cc, cc)
			mb.add_tri_2s(ROLE_FOLIAGE, prev - side * w0, p + side * w1, p - side * w1, nrm, cc, cc, cc)
			prev = p


## Touffe d'herbe (hakone) : brins fins qui retombent d'un seul côté, au vent.
static func grass(mb: BastideMeshBuilder, c: Vector3, size: float, gs: BastideGardenStyle, key: int) -> void:
	var col := pick(gs.grass_colors, key, 1, Color(0.55, 0.62, 0.27))
	var lean := TAU * h(key, 2)
	var n := 10 + int(h(key, 3) * 8.0)
	for i in n:
		var a := lean + hs(key, 10 + i) * 1.4
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := size * (0.7 + h(key, 20 + i) * 0.5)
		var base := c + side * hs(key, 30 + i) * size * 0.12
		var mid := base + dir * length * 0.35 + Vector3(0, length * 0.75, 0)
		var tip := base + dir * length * 0.95 + Vector3(0, length * 0.45, 0)
		var w := size * 0.045
		var cb := Color(col.r, col.g, col.b, 1.0).darkened(0.25)
		var cm := Color(col.r, col.g, col.b, 1.0)
		var ct := Color(col.r, col.g, col.b, 1.0).lightened(0.15)
		var nrm := (mid - base).cross(side).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		mb.add_tri_2s(ROLE_FOLIAGE, base - side * w, base + side * w, mid + side * w * 0.7, nrm, cb, cb, cm)
		mb.add_tri_2s(ROLE_FOLIAGE, base - side * w, mid + side * w * 0.7, mid - side * w * 0.7, nrm, cb, cm, cm)
		mb.add_tri_2s(ROLE_FOLIAGE, mid - side * w * 0.7, mid + side * w * 0.7, tip, nrm, cm, cm, ct)


## Érable du Japon (momiji) : tronc fin, houppier en étages plats rouges et orangés.
static func maple(mb: BastideMeshBuilder, c: Vector3, height: float, gs: BastideGardenStyle, key: int) -> void:
	var trunk := gs.trunk_color
	var top := c + Vector3(hs(key, 1) * 0.3, height * 0.55, hs(key, 2) * 0.3)
	tube(mb, ROLE_FOLIAGE, c + Vector3(0, -0.05, 0), top, 0.11, 0.06, trunk, 6, 0.0)
	var tiers := 3 + int(h(key, 3) * 2.0)
	for t in tiers:
		var ft := float(t) / maxf(tiers - 1, 1)
		var y := lerpf(height * 0.5, height * 0.95, ft)
		var spread := lerpf(1.25, 0.55, ft) * height * 0.38
		var n := 4 - int(ft * 2.0)
		for k in n:
			var a := TAU * (float(k) / n + h(key, 10 + t * 7 + k) * 0.4)
			var p := Vector3(cos(a), 0, sin(a)) * spread * (0.4 + h(key, 20 + t * 7 + k) * 0.6)
			var col := tint(pick(gs.maple_colors, key, 30 + t * 7 + k, Color(0.8, 0.2, 0.12)), hs(key, 40 + t * 7 + k) * 0.06)
			var r := spread * (0.55 + h(key, 50 + t * 7 + k) * 0.25)
			if t == 0 and k < 2:
				tube(mb, ROLE_FOLIAGE, top.lerp(c, 0.25), Vector3(top.x, y - 0.1, top.z) + p * 0.9, 0.05, 0.025, trunk, 5, 0.2)
			blob(mb, ROLE_FOLIAGE, Vector3(top.x, y, top.z) + p, Vector3(r, r * 0.5, r), col,
					BastideRng.combine(key, 60 + t * 7 + k), 5, 11, 0.35, 0.06, Color(0, 0, 0, 0), 1.0)


## Cerisier : tronc sombre qui se divise, large dôme rose.
static func sakura(mb: BastideMeshBuilder, c: Vector3, height: float, gs: BastideGardenStyle, key: int) -> void:
	var trunk := gs.trunk_color.darkened(0.15)
	var fork := c + Vector3(hs(key, 1) * 0.2, height * 0.42, hs(key, 2) * 0.2)
	tube(mb, ROLE_FOLIAGE, c + Vector3(0, -0.05, 0), fork, 0.17, 0.12, trunk, 7, 0.0)
	var n := 3 + int(h(key, 3) * 2.0)
	for k in n:
		var a := TAU * (float(k) / n + h(key, 10 + k) * 0.3)
		var dir := Vector3(cos(a), 0, sin(a))
		var end := fork + dir * height * (0.25 + h(key, 20 + k) * 0.15) + Vector3(0, height * 0.32, 0)
		tube(mb, ROLE_FOLIAGE, fork, end, 0.09, 0.04, trunk, 5, 0.2)
		var r := height * (0.24 + h(key, 30 + k) * 0.08)
		blob(mb, ROLE_FOLIAGE, end + Vector3(0, r * 0.25, 0), Vector3(r, r * 0.7, r),
				tint(pick(gs.blossom_colors, key, 40 + k, Color(0.97, 0.78, 0.82)), hs(key, 50 + k) * 0.05),
				BastideRng.combine(key, 60 + k), 5, 9, 0.3, 0.12, Color(1.0, 0.92, 0.94, 0.25), 1.0)
	var rr := height * 0.3
	blob(mb, ROLE_FOLIAGE, fork + Vector3(0, height * 0.5, 0), Vector3(rr, rr * 0.65, rr),
			pick(gs.blossom_colors, key, 70, Color(0.97, 0.78, 0.82)), BastideRng.combine(key, 71), 5, 9, 0.3, 0.12,
			Color(1.0, 0.92, 0.94, 0.25), 1.0)


## Pin taillé (niwaki) : tronc tordu, branches qui portent des nuages d'aiguilles plats.
static func pine(mb: BastideMeshBuilder, c: Vector3, height: float, gs: BastideGardenStyle, key: int) -> void:
	var trunk := gs.trunk_color.lerp(Color(0.38, 0.3, 0.26), 0.4)
	var needle := pick(gs.foliage_colors, key, 1).darkened(0.25)
	var pts := PackedVector3Array([c + Vector3(0, -0.05, 0)])
	var lean := Vector3(hs(key, 2), 0, hs(key, 3)).normalized() * height * 0.12
	for k in range(1, 5):
		var t := float(k) / 4.0
		var wig := Vector3(hs(key, 10 + k), 0, hs(key, 20 + k)) * height * 0.06
		pts.append(c + lean * t * t * 3.0 + wig + Vector3(0, height * 0.82 * t, 0))
	for k in range(pts.size() - 1):
		tube(mb, ROLE_FOLIAGE, pts[k], pts[k + 1], lerpf(0.16, 0.06, float(k) / 4.0), lerpf(0.16, 0.06, float(k + 1) / 4.0),
				trunk, 6, 0.0)
	# Nuages : un au sommet, deux à quatre portés par des branches latérales.
	var top := pts[pts.size() - 1]
	blob(mb, ROLE_FOLIAGE, top + Vector3(0, 0.15, 0), Vector3(0.75, 0.3, 0.75) * height * 0.32, needle,
			BastideRng.combine(key, 30), 4, 9, 0.45, 0.1, Color(0, 0, 0, 0), 0.5)
	var n := 2 + int(h(key, 4) * 2.99)
	for k in n:
		var t := 0.4 + 0.45 * float(k) / maxf(n - 1, 1)
		var base := pts[0].lerp(top, t)
		var a := TAU * (float(k) / n + h(key, 40 + k) * 0.3)
		var dir := Vector3(cos(a), 0, sin(a))
		var reach := height * (0.32 - t * 0.12)
		var end := base + dir * reach + Vector3(0, height * 0.08, 0)
		tube(mb, ROLE_FOLIAGE, base, end, 0.06, 0.035, trunk, 5, 0.1)
		var r := height * (0.24 - t * 0.08)
		blob(mb, ROLE_FOLIAGE, end + Vector3(0, r * 0.2, 0), Vector3(r, r * 0.36, r), tint(needle, hs(key, 50 + k) * 0.06),
				BastideRng.combine(key, 60 + k), 4, 9, 0.45, 0.1, Color(0, 0, 0, 0), 0.5)


## Bosquet de bambous : tiges fines aux nœuds plus clairs, plumets de feuilles.
static func bamboo_clump(mb: BastideMeshBuilder, c: Vector3, size: float, gs: BastideGardenStyle, key: int) -> void:
	var n := 5 + int(h(key, 1) * 5.0)
	for i in n:
		var off := Vector3(hs(key, 10 + i), 0, hs(key, 20 + i)) * size * 0.45
		var hgt := size * (3.0 + h(key, 30 + i) * 2.0)
		var lean := Vector3(hs(key, 40 + i), 0, hs(key, 50 + i)) * size * 0.3
		var col := Color(0.42, 0.55, 0.26).lerp(Color(0.55, 0.62, 0.3), h(key, 60 + i))
		var segs := maxi(2, int(hgt / 0.8))
		for k in segs:
			var t0 := float(k) / segs
			var t1 := float(k + 1) / segs
			var a := c + off + lean * t0 * t0 + Vector3(0, hgt * t0, 0)
			var b := c + off + lean * t1 * t1 + Vector3(0, hgt * t1 - 0.03, 0)
			tube(mb, ROLE_FOLIAGE, a, b, 0.04, 0.04, col, 5, t0 * 0.6, col.lightened(0.2))
		var tip := c + off + lean + Vector3(0, hgt, 0)
		for k in 2:
			blob(mb, ROLE_FOLIAGE, tip + Vector3(hs(key, 70 + i * 3 + k) * 0.35, -k * 0.7, hs(key, 80 + i * 3 + k) * 0.35),
					Vector3(0.5, 0.25, 0.5) * size, Color(0.36, 0.5, 0.22).lerp(Color(0.48, 0.58, 0.27), h(key, 90 + i)),
					BastideRng.combine(key, 100 + i * 3 + k), 3, 7, 0.3, 0.15, Color(0, 0, 0, 0), 1.0)


## Petite tige de bambou (clôtures) : cylindre lisse avec un nœud plus clair à
## chaque bout et tous les `node_spacing` mètres.
static func bamboo_pole(mb: BastideMeshBuilder, a: Vector3, b: Vector3, r: float, col: Color, key: int,
		node_spacing := 0.45) -> void:
	var length := a.distance_to(b)
	var n := maxi(1, roundi(length / node_spacing))
	var dir := (b - a) / maxf(length, 1e-5)
	for k in n:
		var p0 := a + dir * (length * k / n)
		var p1 := a + dir * (length * (k + 1) / n)
		var c := tint(col, hs(key, k) * 0.05)
		tube(mb, ROLE_WOOD, p0, p1 - dir * 0.012, r, r * 0.97, c, 6, 0.0)
		tube(mb, ROLE_WOOD, p1 - dir * 0.012, p1 + dir * 0.012, r * 1.12, r * 1.12, c.lightened(0.18), 6, 0.0)
