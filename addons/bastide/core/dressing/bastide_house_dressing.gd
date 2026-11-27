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
## cloth: ArrayMesh, ivy: {mesh, mat}, berries: {mesh, mat}, plants: [{mesh, mat, xf: Array}],
## lights: PackedVector3Array (centres des lanternes, pour leurs lumières)}.

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
	var ivy_pts := []   # [pos, normale, taille, angle, couleur]
	var lights := PackedVector3Array()   # centres des lanternes de papier
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
		lights.append(lp + out * 0.42 + Vector3(0, -0.12, 0))
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
			lights.append(lp)
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
			# Le pied du lierre est contre le poteau d'angle : il monte le long du bois.
			var from_start := r.randf() < 0.5
			var u := r.randf_range(0.06, 0.16) if from_start else flen - r.randf_range(0.06, 0.16)
			var root := a + dir * u
			if free.call(root + out * 0.3, 0.0):
				var wall := {"a": a, "dir": dir, "out": out, "len": flen, "posts": f.get("posts", PackedFloat32Array()),
					"timber": bool(anchors.get("timber", true)), "base_y": base_y, "eave_y": eave_y,
					"floor_h": floor_h, "floors": floors, "windows": windows, "inward": 1.0 if from_start else -1.0}
				var ivy_top := (low_eave if bool(anchors.get("pent", false)) and floors > 1 else eave_y) - 0.12
				_ivy(ivy_pts, props, root, wall, ivy_top, free, r)
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
	var res := {"props": props.commit(), "paper": paper.commit(), "cloth": cloth.commit(), "plants": plants.values(),
		"lights": lights}
	if not ivy_pts.is_empty():
		res["ivy"] = {"mesh": _ivy_leaves(ivy_pts), "mat": ivy_material()}
	if not berry_pts.is_empty():
		res["berries"] = _cards("berries/%d" % seed, berry_pts, {"kind": "bloom", "palette": [Color(0.5, 0.05, 0.1), Color(0.85, 0.15, 0.25)],
			"card": 0.22, "cover": 0.5, "depth": 0.1})
	return res


## Lierre plaqué : une tige principale monte le long du poteau d'angle, des rameaux
## partent à l'horizontale en éventail sur l'enduit (en contournant fenêtres et
## portes), un rameau court sous la poutre d'égout et laisse pendre quelques brins.
## Les tiges sont de fins cylindres brun-vert (props) ; les feuilles, de petites
## cartes à plat contre le mur, à 1-3 cm du bois ou de l'enduit.
## `leaves` reçoit [pos, normale, taille, angle, couleur].
static func _ivy(leaves: Array, props: SurfaceTool, root: Vector3, wall: Dictionary, top: float,
		free: Callable, r: RandomNumberGenerator) -> void:
	var dir: Vector3 = wall["dir"]
	var out: Vector3 = wall["out"]
	var a: Vector3 = wall["a"]
	var flen: float = wall["len"]
	var inward: float = wall["inward"]
	var y0: float = wall["base_y"]
	var u_root := (root - a).dot(dir)
	# Distance au nu de l'enduit à (u, y) : le bois (poteaux, poutres, bardage) avance.
	var relief := func(u: float, y: float) -> float:
		var d := 0.0
		if bool(wall["timber"]):
			if u < 0.24 or u > flen - 0.24:
				d = 0.05
			for pu: float in wall["posts"]:
				if absf(u - pu) < 0.12:
					d = 0.045
			if y > float(wall["eave_y"]) - 0.4 or y < y0 + 0.85:
				d = maxf(d, 0.062)
			for k in range(1, int(wall["floors"])):
				if absf(y - (y0 + k * float(wall["floor_h"]))) < 0.12:
					d = maxf(d, 0.06)
		return d
	var at := func(u: float, y: float, lift: float) -> Vector3:
		return a + dir * u + Vector3(0, y - a.y, 0) + out * (relief.call(u, y) + lift)
	var blocked := func(u: float, y: float) -> bool:
		if u < 0.03 or u > flen - 0.03 or y > top + 0.05:
			return true
		var p := a + dir * u + Vector3(0, y - a.y, 0)
		for w: Dictionary in wall["windows"]:
			if (w["out"] as Vector3).dot(out) < 0.9:
				continue
			var q := p - (w["pos"] as Vector3)
			if absf(q.dot(dir)) < float(w["width"]) * 0.5 + 0.12 and absf(q.y) < float(w["height"]) * 0.5 + 0.12 \
					and absf(q.dot(out)) < 0.5:
				return true
		return not free.call(p + out * 0.3, 0.0)
	var leaf := func(u: float, y: float, size: float, young: float) -> void:
		var c := Color(0.045, 0.11, 0.03).lerp(Color(0.1, 0.2, 0.04), r.randf())
		c = c.lerp(Color(0.2, 0.3, 0.06), young * r.randf())
		var n := (out + dir * r.randf_range(-0.25, 0.25) + Vector3(0, r.randf_range(0.0, 0.3), 0)).normalized()
		leaves.append([at.call(u, y, r.randf_range(0.012, 0.03)), n, size * r.randf_range(0.8, 1.2), r.randf() * TAU, c])
	var old_c := Color(0.15, 0.1, 0.065)
	var young_c := Color(0.2, 0.24, 0.09)
	# Tige principale : verticale, collée au poteau, quelques ondulations.
	var main := PackedVector3Array()
	var u := u_root
	var y := y0 + 0.02
	var stem_top := top - r.randf_range(0.0, 0.25)
	var next_run := r.randf_range(0.2, 0.45)
	var runners: Array = []   # [u, y, longueur]
	while y < stem_top:
		main.append(at.call(u, y, 0.008))
		var step := r.randf_range(0.06, 0.09)
		y += step
		u = clampf(u + r.randf_range(-0.015, 0.015), 0.05, flen - 0.05)
		var k := clampf((y - y0) / maxf(stem_top - y0, 0.5), 0.0, 1.0)
		# Feuilles en quinconce, plus grandes et serrées en bas.
		leaf.call(u + inward * r.randf_range(0.02, 0.1), y, lerpf(0.3, 0.22, k), k)
		leaf.call(u - inward * r.randf_range(0.0, 0.07), y + step * 0.5, lerpf(0.28, 0.2, k), k)
		if r.randf() < 0.6 - k * 0.3:
			leaf.call(u + inward * r.randf_range(0.1, 0.2), y + step * 0.3, 0.24, k)
		next_run -= step
		if next_run <= 0.0:
			next_run = r.randf_range(0.2, 0.42)
			runners.append([u, y, lerpf(2.2, 0.7, k) * r.randf_range(0.6, 1.1)])
	main.append(at.call(u, y, 0.008))
	_stem(props, main, 0.014, 0.007, old_c, young_c)
	# Rameaux horizontaux en éventail sur l'enduit (et le long des poutres basses).
	for run: Array in runners:
		var pts := PackedVector3Array()
		var ru: float = run[0]
		var ry: float = run[1]
		var length: float = run[2]
		var rise := r.randf_range(-0.12, 0.35)
		var went := 0.0
		pts.append(at.call(ru, ry, 0.008))
		while went < length:
			var step := r.randf_range(0.06, 0.09)
			var nu := ru + inward * step
			var ny := ry + step * rise + r.randf_range(-0.02, 0.02)
			rise = clampf(rise + r.randf_range(-0.15, 0.15), -0.3, 0.5)
			if blocked.call(nu, ny):
				break
			ru = nu
			ry = ny
			went += step
			pts.append(at.call(ru, ry, 0.008))
			var k := went / maxf(length, 0.1)
			leaf.call(ru, ry + r.randf_range(-0.05, 0.05), lerpf(0.26, 0.18, k), 0.4 + k * 0.6)
			if r.randf() < 0.7:
				leaf.call(ru - inward * 0.03, ry + r.randf_range(0.04, 0.1), lerpf(0.22, 0.16, k), k)
		if pts.size() > 1:
			_stem(props, pts, 0.008, 0.004, old_c.lerp(young_c, 0.4), young_c)
	# Sous l'égout : un rameau suit la poutre, des brins pendent.
	if y > top - 0.4:
		var pts := PackedVector3Array()
		var ru := u
		var ry := top - r.randf_range(0.05, 0.15)
		var length := r.randf_range(0.8, 2.4)
		var went := 0.0
		pts.append(at.call(ru, ry, 0.008))
		var next_hang := r.randf_range(0.15, 0.4)
		while went < length:
			var step := r.randf_range(0.06, 0.09)
			var nu := ru + inward * step
			if nu < 0.05 or nu > flen - 0.05:
				break
			ru = nu
			ry += r.randf_range(-0.012, 0.012)
			went += step
			pts.append(at.call(ru, ry, 0.008))
			leaf.call(ru, ry + r.randf_range(-0.06, 0.03), 0.22, 0.7)
			next_hang -= step
			if next_hang <= 0.0:
				next_hang = r.randf_range(0.25, 0.55)
				var hang := PackedVector3Array([at.call(ru, ry, 0.012)])
				var hy := ry
				for j in r.randi_range(2, 6):
					hy -= r.randf_range(0.07, 0.1)
					if blocked.call(ru, hy):
						break
					hang.append(at.call(ru + r.randf_range(-0.01, 0.01), hy, 0.016))
					leaf.call(ru + r.randf_range(-0.03, 0.03), hy, 0.18, 1.0)
				if hang.size() > 1:
					_stem(props, hang, 0.004, 0.003, young_c, young_c)
		if pts.size() > 1:
			_stem(props, pts, 0.008, 0.004, old_c.lerp(young_c, 0.3), young_c)


## Tige : prisme fin à trois pans qui suit une polyligne, du rayon r0 au rayon r1.
static func _stem(st: SurfaceTool, pts: PackedVector3Array, r0: float, r1: float, c0: Color, c1: Color) -> void:
	var n := pts.size()
	if n < 2:
		return
	var prev: Array = []
	for i in n:
		var t := float(i) / (n - 1)
		var fwd := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := fwd.cross(Vector3.UP if absf(fwd.y) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(fwd).normalized()
		var rr := lerpf(r0, r1, t)
		var ring := []
		for k in 3:
			var ang := TAU * k / 3.0
			ring.append(pts[i] + (side * cos(ang) + up * sin(ang)) * rr)
		if not prev.is_empty():
			var col := c0.lerp(c1, t)
			for k in 3:
				_quad(st, prev[k], prev[(k + 1) % 3], ring[(k + 1) % 3], ring[k], col)
		prev = ring


## Feuilles de lierre : petites cartes à plat contre le mur, texture de feuilles à
## trois lobes (BastideKitNature.clump_tex("ivy")).
static func _ivy_leaves(leaves: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e: Array in leaves:
		var p: Vector3 = e[0]
		var n: Vector3 = e[1]
		var hs := float(e[2]) * 0.5
		var ang: float = e[3]
		var col: Color = e[4]
		var t := n.cross(Vector3.UP).normalized()
		if t.length_squared() < 0.5:
			t = Vector3.RIGHT
		var b := t.cross(n).normalized()
		var tx := (t * cos(ang) + b * sin(ang)) * hs
		var bx := (b * cos(ang) - t * sin(ang)) * hs
		var cs := [p - tx - bx, p + tx - bx, p + tx + bx, p - tx + bx]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(uvs[k])
			st.add_vertex(cs[k])
	return st.commit()


static var _ivy_mat: StandardMaterial3D

static func ivy_material() -> StandardMaterial3D:
	if _ivy_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_texture = BastideKitNature.clump_tex("ivy")
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.55
		m.metallic_specular = 0.35
		m.backlight_enabled = true
		m.backlight = Color(0.12, 0.2, 0.05)
		_ivy_mat = m
	return _ivy_mat


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
