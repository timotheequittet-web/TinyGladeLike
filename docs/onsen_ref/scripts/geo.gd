class_name Geo

## Couleur sentinelle : la pièce garde ses propres couleurs de sommets (déjà en linéaire), ex. les rochers moussus.
const OWN := Color(-1, -1, -1, 1)

static var _boulders := {}
static var _glbs := {}


static func glb(name: String) -> Array:
	## Modèle Blender (tools/blender) fusionné en un tableau de surface ; s'assemble avec Geo.OWN.
	if _glbs.has(name):
		return _glbs[name]
	var inst: Node = (load("res://assets/models/%s.glb" % name) as PackedScene).instantiate()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_merge_node(inst, Transform3D.IDENTITY, st)
	inst.free()
	_glbs[name] = st.commit_to_arrays()
	return _glbs[name]


static func glb_mesh(name: String) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glb(name))
	return m


static func _merge_node(n: Node, xf: Transform3D, st: SurfaceTool) -> void:
	var nxf: Transform3D = xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and n.mesh:
		for s in n.mesh.get_surface_count():
			st.append_from(n.mesh, s, nxf)
	for c in n.get_children():
		_merge_node(c, nxf, st)
## Assemblage de modèles low-poly : on fusionne des primitives colorées (couleurs de sommets)
## en un seul mesh, donc un seul draw call par objet. Les modèles Meshy pourront remplacer ces maquettes.


static func merge(parts: Array) -> ArrayMesh:
	## parts : [[PrimitiveMesh ou Array de surface, Transform3D, Color], ...]
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for part in parts:
		var arr: Array = part[0] if part[0] is Array else part[0].get_mesh_arrays()
		var xf: Transform3D = part[1]
		var c: Color = part[2]
		var own: PackedColorArray = arr[Mesh.ARRAY_COLOR] if c.r < 0.0 and arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var cl := c.srgb_to_linear()
		var nb := xf.basis.inverse().transposed()
		var base := v.size()
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in pv.size():
			v.append(xf * pv[i])
			nr.append((nb * pn[i]).normalized())
			col.append(own[i] if not own.is_empty() else cl)   # couleurs écrites en sRGB, stockées en linéaire comme dans les GLB
		var pi = arr[Mesh.ARRAY_INDEX]
		if pi == null or pi.is_empty():
			for i in pv.size():
				idx.append(base + i)
		else:
			for i in pi:
				idx.append(base + i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = nr
	out[Mesh.ARRAY_COLOR] = col
	out[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return m


static func tris(points: PackedVector3Array, inside: Vector3) -> Array:
	## Triangles à facettes plates. Chaque face est orientée pour regarder à l'opposé du point « inside »
	## (Godot affiche les faces dont les sommets tournent dans le sens horaire vus de face).
	var nr := PackedVector3Array()
	for i in range(0, points.size(), 3):
		var c := (points[i + 1] - points[i]).cross(points[i + 2] - points[i])
		if c.dot(points[i] - inside) > 0.0:
			var t := points[i + 1]
			points[i + 1] = points[i + 2]
			points[i + 2] = t
			c = -c
		var n := -c.normalized()
		nr.append_array([n, n, n])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = points
	arr[Mesh.ARRAY_NORMAL] = nr
	return arr


static func roof(w: float, d: float, h: float, ridge := 0.45, sag := 0.18) -> Array:
	## Toit en croupe à la japonaise : faîtage le long de X, rives légèrement relevées aux coins.
	var hw := w * 0.5
	var hd := d * 0.5
	var r := hw * ridge
	var up := h * sag   # coins relevés
	var a := Vector3(-hw, up, -hd)
	var b := Vector3(hw, up, -hd)
	var c := Vector3(hw, up, hd)
	var e := Vector3(-hw, up, hd)
	var ma := Vector3(-hw * 0.5, 0.0, -hd)   # milieu des longs pans, plus bas : courbe douce
	var mc := Vector3(hw * 0.5, 0.0, hd)
	var mb := Vector3(hw * 0.5, 0.0, -hd)
	var me := Vector3(-hw * 0.5, 0.0, hd)
	var r1 := Vector3(-r, h, 0)
	var r2 := Vector3(r, h, 0)
	var p := PackedVector3Array([
		# pan nord (−Z)
		a, r1, ma, ma, r1, mb, mb, r1, r2, mb, r2, b,
		# pan sud (+Z)
		e, me, r1, me, mc, r1, mc, r2, r1, mc, c, r2,
		# croupes
		a, e, r1, b, r2, c,
		# dessous
		a, ma, e, ma, me, e, ma, mb, me, mb, mc, me, mb, b, mc, b, c, mc,
	])
	return tris(p, Vector3(0, h * 0.35, 0))


static func boulder(variant: int) -> Array:
	## Rocher sculpté comme sur le concept : rond et lisse, base aplatie, chapeau de mousse vert vif sur le dessus.
	## Renvoie un tableau de surface (couleurs en linéaire), à utiliser avec Geo.OWN ou tel quel dans un ArrayMesh.
	if _boulders.has(variant):
		return _boulders[variant]
	var sm := SphereMesh.new()
	sm.radial_segments = 22
	sm.rings = 12
	var src := sm.get_mesh_arrays()
	var fn := FastNoiseLite.new()
	fn.seed = 31 + variant * 17
	fn.frequency = 0.9
	var moss_n := FastNoiseLite.new()
	moss_n.seed = 5 + variant
	moss_n.frequency = 2.2
	var stretch: Vector3 = [Vector3(1.3, 0.8, 1.05), Vector3(1.0, 0.95, 0.9), Vector3(1.5, 0.65, 1.2), Vector3(1.1, 1.1, 1.0)][variant % 4]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	var moved := PackedVector3Array()
	for v in pv:
		var p: Vector3 = v * (1.0 + fn.get_noise_3dv(v * 1.3) * 0.22)
		if p.y < -0.25:
			p.y = -0.25 + (p.y + 0.25) * 0.25   # base aplatie, posée au sol
		moved.append(p * stretch)
	for k in idx:
		st.set_color(Color.WHITE)
		st.add_vertex(moved[k])
	st.index()
	st.generate_normals()
	var arr := st.commit_to_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cols := PackedColorArray()
	var stone_a := Color(0.6, 0.6, 0.57).srgb_to_linear()
	var stone_b := Color(0.72, 0.71, 0.66).srgb_to_linear()
	var moss_a := Color(0.34, 0.46, 0.18).srgb_to_linear()
	var moss_b := Color(0.46, 0.56, 0.22).srgb_to_linear()
	for i in verts.size():
		var n := norms[i]
		var mn := moss_n.get_noise_3dv(verts[i])
		var col := stone_a.lerp(stone_b, clampf(0.5 + fn.get_noise_3dv(verts[i] * 2.0), 0.0, 1.0))
		var moss := smoothstep(0.5, 0.75, n.y + mn * 0.35) * 0.9
		cols.append(col.lerp(moss_a.lerp(moss_b, clampf(0.5 + mn, 0.0, 1.0)), moss))
	arr[Mesh.ARRAY_COLOR] = cols
	_boulders[variant] = arr
	return arr


static var _hulls := {}
static var _ia_props := {}
static var _ia_fits := {}


static func arrays_aabb(arr: Array) -> AABB:
	var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bb := AABB(pv[0], Vector3.ZERO)
	for v in pv:
		bb = bb.expand(v)
	return bb


static func ia_fit(name: String, target: AABB) -> Dictionary:
	## Modèle fait par IA (assets/models/ia/<name>.glb) fusionné en un maillage texturé, étiré pour remplir
	## exactement la boîte « target » (celle du modèle Blender qu'il remplace). {} si le fichier est absent.
	## Renvoie {mesh, arrays (pour les collisions), mat}. Mis en cache par boîte.
	var path := "res://assets/models/ia/%s.glb" % name
	if not ResourceLoader.exists(path):
		return {}
	var key := name + str(target)
	if _ia_fits.has(key):
		return _ia_fits[key]
	var inst: Node = (load(path) as PackedScene).instantiate()
	var tex: Texture2D = null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stack := [[inst, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var n: Node = it[0]
		var nxf: Transform3D = it[1] * (n as Node3D).transform if n is Node3D else it[1]
		if n is MeshInstance3D and n.mesh:
			for s in n.mesh.get_surface_count():
				st.append_from(n.mesh, s, nxf)
				var m = n.mesh.surface_get_material(s)
				if tex == null and m is BaseMaterial3D:
					tex = m.albedo_texture
		for c in n.get_children():
			stack.append([c, nxf])
	inst.free()
	var raw := st.commit_to_arrays()
	var bb := arrays_aabb(raw)
	var k := target.size / bb.size
	var fit := Transform3D(Basis.from_scale(k), target.position - bb.position * k)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, raw)
	st2.append_from(tmp, 0, fit)
	st2.generate_normals()
	var arr := st2.commit_to_arrays()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# la pierre peinte du rocher IA sort presque blanche au soleil : ramenée à un gris chaud de granit
	var tint := Color(0.7, 0.68, 0.63) if name == "rocher" else Color.WHITE
	var res := {mesh = mesh, arrays = arr, mat = Mats.toon(tint, {tex = tex, rim = 0.2, tex_glow = 1.0 if name == "toro" else 0.0})}
	_ia_fits[key] = res
	return res


static func cut_tris(arr: Array, keep: Callable) -> ArrayMesh:
	## Copie d'un maillage (tableaux de surface) sans les triangles que keep(a, b, c) refuse.
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
	var out := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if keep.call(v[idx[t]], v[idx[t + 1]], v[idx[t + 2]]):
			out.append_array([idx[t], idx[t + 1], idx[t + 2]])
	var a2 := arr.duplicate()
	a2[Mesh.ARRAY_INDEX] = out
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
	return m


static func ia_swap(name: String, proxy: Array, xf: Transform3D, collide: bool) -> Node3D:
	## Remplace un modèle Blender (son tableau de surface « proxy ») par le modèle IA <name>, à la même place
	## et à la même taille. null si le modèle IA n'existe pas (on garde alors le modèle Blender).
	var bb := arrays_aabb(proxy)
	var fit := ia_fit(name, bb)
	if fit.is_empty():
		return null
	# collision : la forme du modèle Blender remplacé (même boîte) ; le dôme du modèle IA, trop doux à sa base,
	# se laissait gravir comme une rampe
	if not collide:
		return ia_node(fit, xf, "", false)
	var body := hull_body("proxy_%s" % str(bb), proxy, xf)
	var mi := ia_node(fit, Transform3D(xf.basis, Vector3.ZERO), "", false)
	body.add_child(mi)
	return body


static func ia_node(fit: Dictionary, xf: Transform3D, key: String, collide := true) -> Node3D:
	## Instance d'un modèle IA ajusté (ia_fit), avec sa collision à la forme exacte.
	var mi := MeshInstance3D.new()
	mi.mesh = fit.mesh
	mi.material_override = fit.mat
	mi.transform = xf
	if not collide:
		return mi
	var body := hull_body(key, fit.arrays, xf)
	body.add_child(mi)
	mi.transform = Transform3D.IDENTITY
	mi.transform.basis = xf.basis
	return body


static func ia_prop(name: String, xf: Transform3D) -> Node3D:
	## Décor fait par IA (assets/models/ia/<name>.glb) à la place du modèle Blender du même nom :
	## même hauteur, posé au sol, texture peinte passée dans le shader du jeu. null si absent.
	var path := "res://assets/models/ia/%s.glb" % name
	if not ResourceLoader.exists(path):
		return null
	if not _ia_props.has(name):
		var proxy := MeshInstance3D.new()
		proxy.mesh = glb_mesh(name)
		var holder := Node3D.new()
		holder.add_child(proxy)
		_ia_props[name] = Creatures._ia(name, holder)
	var n: Node3D = (_ia_props[name] as Node3D).duplicate()
	n.transform = xf
	return n


static func hull_body(key: String, arr: Array, xf: Transform3D) -> StaticBody3D:
	## Collision qui épouse la forme du modèle (enveloppe convexe simplifiée, mise en cache par modèle),
	## tournée et mise à l'échelle exactement comme le modèle affiché.
	if not _hulls.has(key):
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_hulls[key] = (m.create_convex_shape(true, false) as ConvexPolygonShape3D).points   # sans simplification : flancs fidèles
	var pts := PackedVector3Array()
	for p in _hulls[key]:
		pts.append(xf.basis * p)
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = sh
	var body := StaticBody3D.new()
	body.position = xf.origin
	body.add_child(cs)
	return body


static func stone(variant: int) -> Array:
	## Pierre plate de pas japonais : même forme ronde que les rochers, mais dessus nu et usé,
	## mousse seulement sur les flancs.
	var key := -1 - variant
	if _boulders.has(key):
		return _boulders[key]
	var arr := boulder(variant).duplicate()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cols := PackedColorArray()
	# granit gris chaud, un ton par variante (plus clairs, ils sortaient blancs au soleil du soir), grain moucheté
	var tone: float = [0.0, 0.05, -0.04, 0.02][variant % 4]
	var top_a := Color(0.47 + tone, 0.45 + tone, 0.42 + tone).srgb_to_linear()
	var top_b := Color(0.6 + tone, 0.58 + tone, 0.53 + tone).srgb_to_linear()
	var moss := Color(0.38, 0.52, 0.2).srgb_to_linear()
	for i in verts.size():
		var n := norms[i]
		var v := verts[i]
		var k := 0.5 + 0.5 * sin(v.x * 7.0 + v.z * 5.0) * cos(v.z * 11.0 - v.x * 3.0)
		var c := top_a.lerp(top_b, k)
		c = c.lerp(moss, smoothstep(0.75, 0.35, n.y) * smoothstep(-0.2, 0.2, n.y) * 0.8)
		cols.append(c)
	arr[Mesh.ARRAY_COLOR] = cols
	_boulders[key] = arr
	return arr


static func boulder_mesh(variant: int) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, boulder(variant))
	return m


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cyl(r_top: float, r_bot: float, h: float, seg := 8) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


static func sphere(r: float, seg := 10, rings := 6, hgt := -1.0) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0 if hgt < 0.0 else hgt
	m.radial_segments = seg
	m.rings = rings
	return m


static func at(pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)
