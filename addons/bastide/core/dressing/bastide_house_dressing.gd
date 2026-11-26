@tool
class_name BastideHouseDressing
extends RefCounted
## Habillage d'une maison japonaise, pour le rendu « vécu » des niveaux Haut et Ultra :
## lanternes de papier (chōchin) sous l'avant-toit, lierre qui grimpe sur un mur,
## pots et bonsaïs près des portes, jardinières aux fenêtres de l'étage, fougères et
## buissons à baies au pied des murs, caisses, paniers et sandales, bannières de
## couleur. Rien n'a de collision et l'axe des portes reste libre (on y entre).
##
## Calcul pur à partir des ancres de la génération (BastideBuildingMesher.anchors) :
## tout est rendu dans le repère local de la maison, prêt à être posé à côté d'elle.
## Résultat : {props: ArrayMesh (couleurs de sommet), paper: ArrayMesh (lanternes),
## cloth: ArrayMesh, ivy: {mesh, mat}, berries: {mesh, mat}, plants: [{mesh, mat, xf: Array}]}.

## Longueur dégagée devant et derrière chaque seuil (m).
const DOOR_CLEAR := 1.6
## Demi-largeur dégagée de part et d'autre de l'axe d'une porte, en plus de la porte.
const DOOR_SIDE := 0.35

const PAPER := Color(1.0, 0.86, 0.62)
const PAPER_RED := Color(0.86, 0.3, 0.2)
const DARK_WOOD := Color(0.16, 0.1, 0.07)
const WOOD := Color(0.42, 0.29, 0.18)
const TERRACOTTA := Color(0.55, 0.3, 0.2)
const GLAZE := [Color(0.22, 0.3, 0.38), Color(0.34, 0.3, 0.26), Color(0.5, 0.42, 0.3)]
const BANNERS := [Color(0.42, 0.2, 0.55), Color(0.2, 0.5, 0.42), Color(0.85, 0.62, 0.2), Color(0.25, 0.32, 0.6), Color(0.7, 0.22, 0.25)]


static func build(anchors: Dictionary, seed: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed * 92821 + 7
	var fp: PackedVector2Array = anchors.get("footprint", PackedVector2Array())
	if fp.size() < 3:
		return {}
	var base_y: float = anchors.get("base_y", 0.0)
	var eave_y: float = anchors.get("eave_y", base_y + 3.0)
	var floor_h: float = anchors.get("floor_height", 2.9)
	var floors: int = anchors.get("floors", 1)
	var overhang: float = anchors.get("overhang", 0.6)
	var doors: Array = anchors.get("doors", [])
	var windows: Array = anchors.get("windows", [])
	var facades: Array = anchors.get("facades", [])
	if facades.is_empty():
		facades = _facades_from(fp, base_y)
	# Bas de l'avant-toit du rez-de-chaussée (auvent s'il y en a un, sinon le toit).
	var low_eave := minf(eave_y, base_y + floor_h) if floors > 1 else eave_y
	var props := SurfaceTool.new()
	props.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paper := SurfaceTool.new()
	paper.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cloth := SurfaceTool.new()
	cloth.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plants := {}   # clé → {mesh, mat, xf: Array}
	var ivy_pts := []   # [pos, normal, color]
	var berry_pts := []
	var free := func(p: Vector3, margin: float) -> bool:
		for d: Dictionary in doors:
			var dp: Vector3 = d["pos"]
			var out: Vector3 = d["out"]
			var side := Vector3(-out.z, 0, out.x)
			var q := p - dp
			if absf(q.dot(out)) < DOOR_CLEAR + margin and absf(q.dot(side)) < float(d["width"]) * 0.5 + DOOR_SIDE + margin:
				return false
		return true
	var add_plant := func(key: String, item: Dictionary, xf: Transform3D) -> void:
		if item.is_empty() or item.get("mesh") == null:
			return
		if not plants.has(key):
			plants[key] = {"mesh": item["mesh"], "mat": item["mat"], "xf": []}
		(plants[key]["xf"] as Array).append(xf)
		if item.get("trunk") != null:
			if not plants.has(key + "/bois"):
				plants[key + "/bois"] = {"mesh": item["trunk"], "mat": BastideKitNature.trunk_material(), "xf": []}
			(plants[key + "/bois"]["xf"] as Array).append(xf)

	# --- Portes : lanterne à potence, pots, caisses et paniers, sandales ---
	for d: Dictionary in doors:
		var dp: Vector3 = d["pos"]
		var out: Vector3 = d["out"]
		var side := Vector3(-out.z, 0, out.x)
		var hw := float(d["width"]) * 0.5
		var s := 1.0 if r.randf() < 0.5 else -1.0
		# Lanterne suspendue à une potence fixée au mur, à côté de la porte.
		var lp := dp + side * s * (hw + 0.45) + Vector3(0, minf(low_eave - base_y - 0.5, 2.35), 0)
		_bracket(props, lp, out, 0.42)
		_lantern(paper, props, lp + out * 0.42 + Vector3(0, -0.12, 0), 0.17, 0.44, r.randf() < 0.25)
		# Pots de l'autre côté, contre le mur, hors de l'axe.
		var pc := 2 + r.randi_range(0, 2)
		for k in pc:
			var pp := dp + side * -s * (hw + DOOR_SIDE + 0.35 + k * 0.42) + out * r.randf_range(0.25, 0.4)
			if not free.call(pp, 0.0):
				continue
			var pr := r.randf_range(0.13, 0.22)
			var ph := pr * r.randf_range(1.0, 1.6)
			var col: Color = TERRACOTTA if r.randf() < 0.55 else GLAZE[r.randi() % GLAZE.size()]
			_pot(props, pp, pr, ph, col)
			var top := pp + Vector3(0, ph, 0)
			var pick := r.randf()
			var rot := Basis(Vector3.UP, r.randf() * TAU)
			# Les cartes peintes ne suivent pas l'échelle de l'instance : la taille est
			# donnée au kit (arrondie au dixième pour partager le cache).
			if pick < 0.4:
				add_plant.call("bush_s", BastideKitNature.plant("bush_1", 0.4), Transform3D(rot, top))
			elif pick < 0.7 or pr < 0.17:
				add_plant.call("fern_s", BastideKitNature.tuft("fern", Color.WHITE, 0.6), Transform3D(rot, top))
			else:
				# Petit bonsaï : un pin taillé miniature.
				var tr := BastideKitNature.tree("matsu", r.randi_range(0, 1), 0.1)
				add_plant.call("bonsai", {"mesh": tr["crown"], "mat": tr["crown_mat"], "trunk": tr["trunk"]}, Transform3D(rot, top))
		# Caisses, panier : du côté de la lanterne, un peu plus loin.
		if r.randf() < 0.75:
			var cp := dp + side * s * (hw + DOOR_SIDE + 0.75) + out * 0.42
			if free.call(cp, 0.0):
				var cr := Basis(Vector3.UP, r.randf_range(-0.2, 0.2))
				_crate(props, cp, cr, Vector3(0.62, 0.36, 0.42))
				if r.randf() < 0.6:
					_crate(props, cp + Vector3(0, 0.36, 0) + side * 0.04, Basis(Vector3.UP, r.randf_range(-0.3, 0.3)), Vector3(0.5, 0.3, 0.36))
				_basket(props, cp + side * s * 0.6, r.randf_range(0.16, 0.22), r.randf_range(0.18, 0.26))
		# Sandales (geta) posées devant le seuil, sur le côté : on ne bute pas dessus.
		var gp := dp + out * 0.55 + side * s * (hw * 0.6)
		for k in 2:
			var g := gp + side * (k * 0.24) + out * r.randf_range(-0.05, 0.05)
			var gb := Basis(Vector3.UP, atan2(out.x, out.z) + r.randf_range(-0.3, 0.3))
			_geta(props, g, gb)
	# --- Lanternes aux angles de l'avant-toit (maisons à étage surtout) ---
	for f: Dictionary in facades:
		var a: Vector3 = f["a"]
		var out: Vector3 = f["out"]
		if r.randf() < (0.55 if floors > 1 else 0.3):
			var y := eave_y - 0.55
			var lp := Vector3(a.x, y, a.z) + out * overhang * 0.55
			_cord(props, lp + Vector3(0, 0.22, 0), eave_y - 0.05)
			_lantern(paper, props, lp, 0.15, 0.38, r.randf() < 0.2)
	# --- Façades : lierre, plantes au pied, jardinières, bannières ---
	var ivy_done := 0
	var ivy_max := 1 + (1 if r.randf() < 0.45 else 0)
	var order := range(facades.size())
	_shuffle(order, r)
	for fi: int in order:
		var f: Dictionary = facades[fi]
		var a: Vector3 = f["a"]
		var b: Vector3 = f["b"]
		var out: Vector3 = f["out"]
		var flen := Vector2(b.x - a.x, b.z - a.z).length()
		if flen < 1.5:
			continue
		var dir := (b - a) / flen
		dir.y = 0.0
		# Lierre : part d'un pied de mur, près d'un angle, et monte jusqu'à l'avant-toit.
		if ivy_done < ivy_max and flen > 3.0:
			var u := r.randf_range(0.25, 0.9) if r.randf() < 0.5 else flen - r.randf_range(0.25, 0.9)
			var root := a + dir * u + out * 0.04
			if free.call(root, 0.0):
				_ivy(ivy_pts, root, dir, out, base_y, eave_y - 0.15, r)
				ivy_done += 1
				# Un buisson à baies pousse souvent au pied du lierre.
				_berry_bush(berry_pts, add_plant, root + out * 0.5, r)
		# Pied du mur : fougères, petits buissons, de loin en loin (rythme irrégulier).
		var u := r.randf_range(0.3, 1.0)
		while u < flen - 0.3:
			var p := a + dir * u + out * r.randf_range(0.45, 0.7)
			p.y = base_y
			if free.call(p, 0.0):
				var pick := r.randf()
				var rot := Basis(Vector3.UP, r.randf() * TAU)
				if pick < 0.55:
					add_plant.call("fern", BastideKitNature.tuft("fern", Color.WHITE, 1.2), Transform3D(rot, p))
				elif pick < 0.75:
					add_plant.call("bush_m", BastideKitNature.plant("bush_1", 0.6), Transform3D(rot, p))
				elif pick < 0.87:
					_berry_bush(berry_pts, add_plant, p, r)
			u += r.randf_range(0.9, 2.2)
		# Bannières de tissu sous l'auvent du rez-de-chaussée (une façade par maison).
		if floors > 1 and r.randf() < 0.35 and flen > 3.0:
			var n := 3 + r.randi_range(0, 2)
			var u0 := r.randf_range(0.6, maxf(0.7, flen - 0.6 - n * 0.32))
			for k in n:
				var bp := a + dir * (u0 + k * 0.32) + out * (overhang * 0.45)
				var col: Color = BANNERS[(k + r.randi()) % BANNERS.size()]
				if free.call(bp, 0.0):
					_banner(cloth, Vector3(bp.x, low_eave - 0.1, bp.z), dir, out, 0.2, 0.55, col)
	# Jardinières sous les fenêtres de l'étage.
	for w: Dictionary in windows:
		if int(w["floor"]) < 1 or r.randf() > 0.4:
			continue
		var wp: Vector3 = w["pos"]
		var out: Vector3 = w["out"]
		var side := Vector3(-out.z, 0, out.x)
		var bw := float(w["width"]) * 0.9
		var by := wp.y - float(w["height"]) * 0.5 - 0.16
		var c := Vector3(wp.x, by, wp.z) + out * 0.2
		_box(props, c, Basis(side, Vector3.UP, out), Vector3(bw, 0.16, 0.22), WOOD.darkened(0.1))
		for k in int(bw / 0.28):
			var pp := c + side * (-bw * 0.5 + 0.14 + k * 0.28) + Vector3(0, 0.08, 0)
			var rot := Basis(Vector3.UP, r.randf() * TAU)
			if r.randf() < 0.5:
				add_plant.call("flowers", BastideKitNature.tuft("flower", Color(1.0, 0.85, 0.9), 0.5), Transform3D(rot, pp))
			else:
				add_plant.call("fern_s", BastideKitNature.tuft("fern", Color.WHITE, 0.55), Transform3D(rot, pp))
	var res := {"props": props.commit(), "paper": paper.commit(), "cloth": cloth.commit(), "plants": plants.values()}
	if not ivy_pts.is_empty():
		res["ivy"] = _cards("ivy/%d" % seed, ivy_pts, {"kind": "leaf", "green_only": true, "card": 0.3, "cover": 0.55, "depth": 0.03})
	if not berry_pts.is_empty():
		res["berries"] = _cards("berries/%d" % seed, berry_pts, {"kind": "bloom", "palette": [Color(0.5, 0.05, 0.1), Color(0.85, 0.15, 0.25)],
			"card": 0.22, "cover": 0.5, "depth": 0.1})
	return res


## Lierre : quelques tiges qui montent en ondulant et se ramifient ; des feuilles
## tout du long, plus fournies en bas, quelques rameaux qui retombent sous l'avant-toit.
static func _ivy(pts: Array, root: Vector3, dir: Vector3, out: Vector3, y0: float, y1: float, r: RandomNumberGenerator) -> void:
	var leaf := func(q: Vector3, tilt: float) -> void:
		var c := Color(0.07, 0.15, 0.05).lerp(Color(0.24, 0.38, 0.1), r.randf())
		pts.append([q + out * r.randf_range(0.04, 0.12), (out + Vector3(0, tilt, 0) + dir * r.randf_range(-0.4, 0.4)).normalized(), c])
	var stems := 2 + r.randi_range(0, 2)
	for s in stems:
		var p := root + dir * r.randf_range(-0.35, 0.35)
		p.y = y0 + r.randf_range(0.0, 0.2)
		var drift := r.randf_range(-0.4, 0.4)
		var top := lerpf(y0 + (y1 - y0) * 0.55, y1, r.randf())
		var next_shoot := r.randf_range(0.3, 0.7)
		while p.y < top:
			var step := r.randf_range(0.16, 0.24)
			p.y += step
			p += dir * (drift * step + r.randf_range(-0.05, 0.05))
			drift = clampf(drift + r.randf_range(-0.25, 0.25), -0.7, 0.7)
			leaf.call(p + dir * r.randf_range(-0.12, 0.12), 0.3)
			# Rameaux latéraux : la plante s'étale en nappe sur le mur, pas en colonne.
			next_shoot -= step
			if next_shoot <= 0.0:
				next_shoot = r.randf_range(0.35, 0.8)
				var sd := 1.0 if r.randf() < 0.5 else -1.0
				var q := p
				for j in r.randi_range(2, 5):
					q += dir * sd * r.randf_range(0.14, 0.22) + Vector3(0, r.randf_range(-0.1, 0.05), 0)
					leaf.call(q, 0.2)
		# Rameaux qui pendent depuis le haut.
		for i in r.randi_range(0, 2):
			var hp := p + dir * r.randf_range(-0.5, 0.5)
			for j in r.randi_range(2, 5):
				hp += Vector3(0, -0.16, 0) + dir * r.randf_range(-0.04, 0.04)
				leaf.call(hp, -0.1)


## Buisson à baies : un petit buisson de feuillage et des grappes rouges dessus.
static func _berry_bush(berry_pts: Array, add_plant: Callable, p: Vector3, r: RandomNumberGenerator) -> void:
	var sc := 0.7
	add_plant.call("bush_b", BastideKitNature.plant("bush_1", sc), Transform3D(Basis(Vector3.UP, r.randf() * TAU), p))
	for i in 9:
		var a := r.randf() * TAU
		var h := r.randf_range(0.35, 0.95) * sc
		var rad := (0.65 - absf(h / sc - 0.6) * 0.5) * sc
		var q := p + Vector3(cos(a) * rad, h, sin(a) * rad)
		berry_pts.append([q, Vector3(cos(a), 0.5, sin(a)).normalized(), Color(0.7, 0.1, 0.15)])


## Cartes peintes (même style que les arbres) sur une liste de points [pos, normale, couleur].
static func _cards(key: String, pts: Array, opts: Dictionary) -> Dictionary:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	for e: Array in pts:
		var k := v.size()
		v.append(e[0])
		n.append(e[1])
		c.append(e[2])
		idx.append_array([k, k, k])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = idx
	var opt := opts.duplicate()
	opt["all_leafy"] = true
	var b := BastideKitNature.crown(key, arr, opt)
	return {"mesh": b["crown"], "mat": b["crown_mat"]}


# --- Petits objets (couleurs de sommet, faces plates) ---------------------------------

## Lanterne de papier : corps renflé, côtes sombres, chapeau et pied de bois.
static func _lantern(paper: SurfaceTool, props: SurfaceTool, c: Vector3, rad: float, h: float, red: bool) -> void:
	var sides := 10
	var rings := 6
	var col := PAPER_RED if red else PAPER
	var prev := []
	for j in rings + 1:
		var t := float(j) / rings
		var y := c.y - h * 0.5 + t * h
		var rr := rad * (0.62 + 0.38 * sin(t * PI))
		var ring := []
		for i in sides:
			var a := TAU * i / sides
			ring.append(Vector3(c.x + cos(a) * rr, y, c.z + sin(a) * rr))
		if j > 0:
			for i in sides:
				var i2 := (i + 1) % sides
				var shade := 0.85 if j % 2 == 0 else 1.0   # légères côtes
				_quad(paper, prev[i], prev[i2], ring[i2], ring[i], col * shade)
		prev = ring
	_cyl(props, c + Vector3(0, h * 0.5 - 0.01, 0), c + Vector3(0, h * 0.5 + 0.05, 0), rad * 0.66, rad * 0.6, 8, DARK_WOOD)
	_cyl(props, c + Vector3(0, -h * 0.5 - 0.05, 0), c + Vector3(0, -h * 0.5 + 0.01, 0), rad * 0.6, rad * 0.66, 8, DARK_WOOD)


## Potence de bois fixée au mur, d'où pend une lanterne.
static func _bracket(st: SurfaceTool, at: Vector3, out: Vector3, reach: float) -> void:
	var side := Vector3(-out.z, 0, out.x)
	var bs := Basis(side, Vector3.UP, out)
	_box(st, at + out * reach * 0.5 + Vector3(0, 0.22, 0), bs, Vector3(0.05, 0.05, reach), DARK_WOOD)
	_box(st, at + out * 0.03 + Vector3(0, 0.05, 0), bs, Vector3(0.05, 0.4, 0.05), DARK_WOOD)
	_box(st, at + out * (reach - 0.0) + Vector3(0, 0.15, 0), bs, Vector3(0.012, 0.14, 0.012), DARK_WOOD)


static func _cord(st: SurfaceTool, from: Vector3, top_y: float) -> void:
	_box(st, Vector3(from.x, (from.y + top_y) * 0.5, from.z), Basis(), Vector3(0.012, maxf(top_y - from.y, 0.02), 0.012), DARK_WOOD)


## Pot : tronc de cône évasé, lèvre plus claire, terre sombre.
static func _pot(st: SurfaceTool, p: Vector3, rad: float, h: float, col: Color) -> void:
	_cyl(st, p, p + Vector3(0, h, 0), rad * 0.72, rad, 10, col)
	_cyl(st, p + Vector3(0, h - 0.025, 0), p + Vector3(0, h + 0.012, 0), rad * 1.06, rad * 1.06, 10, col.lightened(0.12))
	_cyl(st, p + Vector3(0, h - 0.03, 0), p + Vector3(0, h - 0.005, 0), rad * 0.95, rad * 0.95, 10, Color(0.12, 0.09, 0.06))


## Caisse de planches : un bloc et des lattes plus sombres.
static func _crate(st: SurfaceTool, p: Vector3, b: Basis, size: Vector3) -> void:
	_box(st, p + Vector3(0, size.y * 0.5, 0), b, size, WOOD)
	for k in 3:
		var y := size.y * (0.18 + 0.32 * k)
		_box(st, p + Vector3(0, y, 0), b, size + Vector3(0.015, -size.y + 0.04, 0.015), WOOD.darkened(0.3))


## Panier tressé : cylindre clair qui s'évase, bord sombre.
static func _basket(st: SurfaceTool, p: Vector3, rad: float, h: float) -> void:
	var c := Color(0.62, 0.5, 0.3)
	_cyl(st, p, p + Vector3(0, h, 0), rad * 0.8, rad, 10, c)
	_cyl(st, p + Vector3(0, h - 0.02, 0), p + Vector3(0, h + 0.015, 0), rad * 1.04, rad * 1.04, 10, c.darkened(0.35))


## Paire de sandales de bois (geta).
static func _geta(st: SurfaceTool, p: Vector3, b: Basis) -> void:
	var side := b.x
	for k: float in [-1.0, 1.0]:
		var c: Vector3 = p + side * 0.055 * float(k)
		_box(st, c + Vector3(0, 0.045, 0), b, Vector3(0.09, 0.02, 0.22), Color(0.55, 0.4, 0.26))
		_box(st, c + Vector3(0, 0.018, 0) + b.z * 0.06, b, Vector3(0.08, 0.035, 0.025), DARK_WOOD)
		_box(st, c + Vector3(0, 0.018, 0) - b.z * 0.06, b, Vector3(0.08, 0.035, 0.025), DARK_WOOD)
		_box(st, c + Vector3(0, 0.065, 0) + b.z * 0.05, b, Vector3(0.07, 0.012, 0.012), Color(0.6, 0.12, 0.12))


## Bannière de tissu qui pend d'une baguette (deux faces).
static func _banner(st: SurfaceTool, top: Vector3, dir: Vector3, out: Vector3, w: float, h: float, col: Color) -> void:
	var a := top - dir * w * 0.5
	var b := top + dir * w * 0.5
	var sway := out * 0.04
	_quad(st, a, b, b + Vector3(0, -h, 0) + sway, a + Vector3(0, -h, 0) + sway, col)
	_quad(st, b, a, a + Vector3(0, -h, 0) + sway, b + Vector3(0, -h, 0) + sway, col * 0.85)


static func _box(st: SurfaceTool, c: Vector3, b: Basis, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var x := b.x.normalized() * h.x
	var y := b.y.normalized() * h.y
	var z := b.z.normalized() * h.z
	var faces := [[x, y, z], [-x, y, -z], [z, y, -x], [-z, y, x], [y, -z, x], [-y, z, x]]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var shade := 0.8 + 0.2 * n.normalized().y
		_quad(st, c + n - u - v, c + n - u + v, c + n + u + v, c + n + u - v, col * shade)


static func _cyl(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color) -> void:
	for i in sides:
		var t0 := TAU * i / sides
		var t1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(t0), 0, sin(t0))
		var d1 := Vector3(cos(t1), 0, sin(t1))
		_quad(st, a + d0 * r0, a + d1 * r0, b + d1 * r1, b + d0 * r1, col)
		_tri(st, b, b + d0 * r1, b + d1 * r1, col.lightened(0.05))


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (c - a).cross(b - a).normalized()
	for p in [a, b, c]:
		st.set_color(Color(col.r, col.g, col.b, 1.0))
		st.set_normal(n)
		st.add_vertex(p)


static func _shuffle(arr: Array, r: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## Façades déduites du contour quand la génération ne les donne pas.
static func _facades_from(fp: PackedVector2Array, y: float) -> Array:
	var area := 0.0
	for i in fp.size():
		var a := fp[i]
		var b := fp[(i + 1) % fp.size()]
		area += a.x * b.y - b.x * a.y
	var out: Array = []
	for i in fp.size():
		var a := fp[i]
		var b := fp[(i + 1) % fp.size()]
		var d := (b - a).normalized()
		var n := Vector2(d.y, -d.x) if area > 0.0 else Vector2(-d.y, d.x)
		out.append({"a": Vector3(a.x, y, a.y), "b": Vector3(b.x, y, b.y), "out": Vector3(n.x, 0, n.y)})
	return out
