@tool
class_name BastideToriiMesher
extends RefCounted
## Torii (type myōjin) entre deux pieds de piliers : piliers laqués légèrement
## inclinés vers l'intérieur, socles de pierre et bagues noires, traverse basse
## (nuki) qui dépasse, poteau central et plaque (gaku), linteau (shimaki) et grande
## poutre noire (kasagi) aux bouts relevés.
##
## Proportions tirées de la largeur : un torii étroit est plus trapu, jamais
## disproportionné. Couleurs du volet Garden du style.

const ROLE_PAINT := BastideGardenMesher.ROLE_PAINT
const ROLE_STONE := BastideGardenMesher.ROLE_STONE


static func build(a: Vector3, b: Vector3, seed: int, style: BastideStyle, with_collision := true) -> BastideBuildResult:
	var result := BastideBuildResult.new()
	var fit := BastideGardenRules.fit_torii(a, b)
	a = fit[0]
	b = fit[1]
	var gs := style.get_garden_style()
	var mb := BastideMeshBuilder.new()
	var x := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var w := x.length()
	x /= w
	var f := x.cross(Vector3.UP)
	var c := (a + b) * 0.5
	var base_y := a.y
	var hgt := clampf(w * 1.12, 2.9, 6.6)
	var d := clampf(w * 0.085, 0.22, 0.46)
	var r := d * 0.5
	var paint := BastideGardenMesher.tint(gs.gate_color, BastideRng.signed_at(seed, "torii_paint") * 0.04)
	var black := gs.gate_top_color
	var stone := gs.lantern_color

	# --- Piliers -----------------------------------------------------------------------
	var y_shimaki := base_y + hgt * 0.84
	var lean := hgt * 0.022
	for side: float in [-1.0, 1.0]:
		var foot := c + x * (w * 0.5 * side)
		foot.y = base_y
		var top := foot - x * (lean * side)
		top.y = y_shimaki + d * 0.3
		BastideGardenMesher.prism(mb, ROLE_STONE, foot, r * 1.95, r * 1.7, -0.05, 0.16, 8, stone, 0.2)
		BastideGardenMesher.tube(mb, ROLE_PAINT, foot + Vector3(0, 0.12, 0), top, r, r * 0.9, paint, 14, 0.0)
		# Bague noire au pied (nemaki).
		var ring_top := foot.lerp(top, 0.5 / hgt) + Vector3(0, 0.12, 0)
		BastideGardenMesher.tube(mb, ROLE_PAINT, foot + Vector3(0, 0.12, 0), ring_top, r * 1.1, r * 1.08, black, 14, 0.0)
		_cap(mb, ring_top, r * 1.08, black)
		if with_collision:
			_box_collision(result, foot + Vector3(0, hgt * 0.45, 0), x, f, Vector3(r, hgt * 0.45, r))

	# --- Traverse basse (nuki) ---------------------------------------------------------
	var y_nuki := base_y + hgt * 0.66
	var ext := d * 1.7
	_beam(mb, c + Vector3(0, y_nuki - base_y, 0), x, f, w * 0.5 + ext, d * 0.38, d * 0.72, 0.0, paint, 1)
	# Poteau central (gakuzuka) et plaque (gaku).
	var y_mid := (y_nuki + d * 0.36 + y_shimaki) * 0.5
	var strut_h := (y_shimaki - (y_nuki + d * 0.36)) * 0.5
	_box(mb, ROLE_PAINT, Vector3(c.x, y_mid, c.z), x, f, Vector3(d * 0.28, strut_h, d * 0.22), paint)
	var plaque := Vector3(minf(w * 0.09, 0.42), minf(strut_h * 0.85, 0.5), d * 0.12)
	_box(mb, ROLE_PAINT, Vector3(c.x, y_mid, c.z), x, f, plaque, black)
	_box(mb, ROLE_PAINT, Vector3(c.x, y_mid, c.z), x, f, Vector3(plaque.x * 0.78, plaque.y * 0.82, d * 0.14),
			Color(0.82, 0.66, 0.32))

	# --- Linteau (shimaki) et grande poutre (kasagi) -----------------------------------------
	var lift := hgt * 0.05
	var shimaki_h := d * 0.55
	_beam(mb, c + Vector3(0, y_shimaki - base_y, 0), x, f, w * 0.5 + w * 0.24, d * 0.5, shimaki_h, lift * 0.7, paint, 10)
	var y_kasagi := y_shimaki + shimaki_h
	_beam(mb, c + Vector3(0, y_kasagi - base_y, 0), x, f, w * 0.5 + w * 0.3, d * 0.7, d * 0.62, lift, black, 10, 0.12)
	if with_collision:
		_box_collision(result, Vector3(c.x, y_shimaki + d * 0.6, c.z), x, f, Vector3(w * 0.5 + w * 0.3, d * 0.7, d * 0.4))
		_box_collision(result, Vector3(c.x, y_nuki, c.z), x, f, Vector3(w * 0.5 + ext, d * 0.36, d * 0.2))

	result.mesh = mb.commit(BastideGardenMesher.materials(style))
	result.anchors = {"points": PackedVector3Array([a, b]), "height": hgt}
	result.stats = {"triangles": mb.triangle_count, "width": snappedf(w, 0.01), "height": snappedf(hgt, 0.01)}
	return result


## Bouchon plat d'un tube vertical.
static func _cap(mb: BastideMeshBuilder, c: Vector3, r: float, col: Color) -> void:
	var n := 14
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		mb.add_tri(ROLE_PAINT, c, c + Vector3(cos(a0) * r, 0, sin(a0) * r), c + Vector3(cos(a1) * r, 0, sin(a1) * r),
				Vector3.UP, col, col, col)


## Pavé orienté (x, haut, f), demi-dimensions `he`.
static func _box(mb: BastideMeshBuilder, role: StringName, c: Vector3, x: Vector3, f: Vector3, he: Vector3, col: Color) -> void:
	var k := []
	for yy in [-1.0, 1.0]:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			k.append(c + x * (corner.x * he.x) + f * (corner.y * he.z) + Vector3.UP * (yy * he.y))
	mb.add_block(role, k, 0.0, 0.0, col, col, true)


## Poutre horizontale de demi-longueur `half`, épaisseur `depth` (selon f), hauteur
## `height`, dont le dessous monte de `lift` aux bouts (courbe douce). `flare` :
## les bouts s'évasent vers le haut (coupe biaise du kasagi).
static func _beam(mb: BastideMeshBuilder, c: Vector3, x: Vector3, f: Vector3, half: float, depth: float, height: float,
		lift: float, col: Color, segs: int, flare := 0.0) -> void:
	var under := col.darkened(0.25)
	var prev_lo := Vector3.ZERO
	var prev_hi := Vector3.ZERO
	var rows: Array = []
	for i in segs + 1:
		var t := -1.0 + 2.0 * i / segs
		var y := lift * pow(absf(t), 2.4)
		var top_ext := flare * pow(absf(t), 6.0)
		var p := c + x * (t * half) + Vector3(0, y, 0)
		rows.append([p - f * depth * 0.5, p + f * depth * 0.5,
			p + f * depth * 0.5 + Vector3(0, height + top_ext * 0.5, 0) + x * (signf(t) * top_ext),
			p - f * depth * 0.5 + Vector3(0, height + top_ext * 0.5, 0) + x * (signf(t) * top_ext)])
	for i in segs:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		# Dessous, avant, dessus, arrière.
		mb.add_quad(ROLE_PAINT, r0[0], r1[0], r1[1], r0[1], Vector3.DOWN, under, under, under, under)
		mb.add_quad(ROLE_PAINT, r0[1], r1[1], r1[2], r0[2], f, col, col, col, col)
		mb.add_quad(ROLE_PAINT, r0[2], r1[2], r1[3], r0[3], Vector3.UP, col.lightened(0.04), col.lightened(0.04), col.lightened(0.04), col.lightened(0.04))
		mb.add_quad(ROLE_PAINT, r0[3], r1[3], r1[0], r0[0], -f, col, col, col, col)
	var first: Array = rows[0]
	var last: Array = rows[segs]
	mb.add_quad(ROLE_PAINT, first[0], first[1], first[2], first[3], -x, col.darkened(0.1), col.darkened(0.1), col.darkened(0.1), col.darkened(0.1))
	mb.add_quad(ROLE_PAINT, last[0], last[1], last[2], last[3], x, col.darkened(0.1), col.darkened(0.1), col.darkened(0.1), col.darkened(0.1))


static func _box_collision(result: BastideBuildResult, c: Vector3, x: Vector3, f: Vector3, he: Vector3) -> void:
	var k := []
	for yy in [-1.0, 1.0]:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			k.append(c + x * (corner.x * he.x) + f * (corner.y * he.z) + Vector3.UP * (yy * he.y))
	result.add_box(k)
