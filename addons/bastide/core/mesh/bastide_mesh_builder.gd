@tool
class_name BastideMeshBuilder
extends RefCounted
## Accumule des triangles par rôle de matériau (body, trim, roof…), puis produit un
## ArrayMesh multi-surfaces. Normales plates : chaque face garde ses propres sommets,
## ce qui donne l'aspect taillé des pierres.
##
## Toutes les primitives prennent un « indice » de normale (hint) qui indique de
## quel côté la face doit être visible ; l'ordre des sommets est corrigé en conséquence.

## Tampon d'une surface. Les ajouts passent par ses propres méthodes pour que les
## Packed*Array soient modifiés sur place (pas de copie à chaque triangle).
class Surface:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()

	func push(a: Vector3, b: Vector3, cc: Vector3, nrm: Vector3, ca: Color, cb: Color, ccol: Color) -> void:
		v.append(a); v.append(b); v.append(cc)
		n.append(nrm); n.append(nrm); n.append(nrm)
		c.append(ca); c.append(cb); c.append(ccol)


## En dessous de ce biseau, une face « bombée » est dessinée plate : le biseau
## ferait moins d'un pixel à distance normale de jeu.
const FLAT_BEVEL := 0.013
## Faces d'un bloc (add_block), pour `skip` : on n'émet pas les faces cachées.
const FACE_TOP := 1
const FACE_FRONT_01 := 2   # face k0-k1
const FACE_SIDE_12 := 4    # face k1-k2
const FACE_BACK_23 := 8    # face k2-k3
const FACE_SIDE_30 := 16   # face k3-k0

var _surfaces := {}  # role -> Surface
var triangle_count := 0


func _surface(role: StringName) -> Surface:
	var s: Surface = _surfaces.get(role)
	if s == null:
		s = Surface.new()
		_surfaces[role] = s
	return s


func roles() -> Array:
	return _surfaces.keys()


## Triangle visible du côté de `hint`.
func add_tri(role: StringName, a: Vector3, b: Vector3, c: Vector3, hint: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.length_squared() < 1e-14:
		return
	var surf := _surface(role)
	# Godot considère comme faces avant les triangles vus dans le sens horaire.
	if nrm.dot(hint) >= 0.0:
		surf.push(a, c, b, nrm.normalized(), ca, cc, cb)
	else:
		surf.push(a, b, c, -nrm.normalized(), ca, cb, cc)
	triangle_count += 1


## Quadrilatère a-b-c-d (dans l'ordre du contour).
func add_quad(role: StringName, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	add_tri(role, a, b, c, hint, ca, cb, cc)
	add_tri(role, a, c, d, hint, ca, cc, cd)


## Quadrilatère « bombé » : une face centrale décalée vers l'extérieur et un biseau
## qui rejoint le contour. Le contour reçoit `edge_color` (joint sombre), le centre `color`.
## `relief` module le bombé coin par coin (1 = uniforme) pour des faces un peu de travers.
## Chemin optimisé : orientation décidée une fois, triangles poussés directement.
func add_pillow_quad(role: StringName, corners: Array, hint: Vector3, bevel: float, bulge: float,
		color: Color, edge_color: Color, relief := Vector4.ONE) -> void:
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	var d: Vector3 = corners[3]
	if bevel < FLAT_BEVEL:
		# Biseau invisible à l'œil : un simple quadrilatère (2 triangles au lieu de 10).
		add_quad(role, a, b, c, d, hint, color, color, color, color)
		return
	var nrm := (c - a).cross(d - b)
	if nrm.length_squared() < 1e-12:
		return
	if nrm.dot(hint) < 0.0:
		# Contour inversé : on le parcourt dans l'autre sens pour qu'il tourne
		# dans le sens trigonométrique vu de devant.
		var tmp := b
		b = d
		d = tmp
		nrm = -nrm
		relief = Vector4(relief.x, relief.w, relief.z, relief.y)
	nrm = nrm.normalized()
	var center := (a + b + c + d) * 0.25
	var ia := _inset(a, center, bevel) + nrm * (bulge * relief.x)
	var ib := _inset(b, center, bevel) + nrm * (bulge * relief.y)
	var ic := _inset(c, center, bevel) + nrm * (bulge * relief.z)
	var id := _inset(d, center, bevel) + nrm * (bulge * relief.w)
	var surf := _surface(role)
	# Face centrale (vue de devant dans le sens trigo → émise dans le sens horaire).
	var fn := (ic - ia).cross(id - ib).normalized()
	surf.push(ia, ic, ib, fn, color, color, color)
	surf.push(ia, id, ic, fn, color, color, color)
	_ring(surf, a, b, ib, ia, color, edge_color)
	_ring(surf, b, c, ic, ib, color, edge_color)
	_ring(surf, c, d, id, ic, color, edge_color)
	_ring(surf, d, a, ia, id, color, edge_color)
	triangle_count += 10


static func _inset(p: Vector3, center: Vector3, bevel: float) -> Vector3:
	var to_c := center - p
	var dist := to_c.length()
	if dist < 1e-6:
		return p
	return p + to_c * (minf(bevel, dist * 0.45) / dist)


## Facette de biseau p0-p1 (contour) → q1-q0 (face centrale).
static func _ring(surf: Surface, p0: Vector3, p1: Vector3, q1: Vector3, q0: Vector3, color: Color, edge: Color) -> void:
	var n := (p1 - p0).cross(q1 - p0)
	if n.length_squared() < 1e-14:
		n = (q1 - p0).cross(q0 - p0)
		if n.length_squared() < 1e-14:
			return
	n = n.normalized()
	surf.push(p0, q1, p1, n, edge, color, edge)
	surf.push(p0, q0, q1, n, edge, color, color)


## Bloc à 8 coins (pas forcément parallélépipédique), chaque face bombée.
## Ordre des coins : 0-3 dessous (contour), 4-7 dessus (même ordre).
## `skip` : masque de faces cachées à ne pas émettre (FACE_*), par exemple la face
## collée contre un mur.
func add_block(role: StringName, k: Array, bevel: float, bulge: float, color: Color, edge_color: Color,
		with_bottom := false, skip := 0) -> void:
	var center := Vector3.ZERO
	for p: Vector3 in k:
		center += p
	center /= 8.0
	var faces := []
	if not skip & FACE_TOP:
		faces.append([k[4], k[5], k[6], k[7]])
	if not skip & FACE_FRONT_01:
		faces.append([k[0], k[1], k[5], k[4]])
	if not skip & FACE_SIDE_12:
		faces.append([k[1], k[2], k[6], k[5]])
	if not skip & FACE_BACK_23:
		faces.append([k[2], k[3], k[7], k[6]])
	if not skip & FACE_SIDE_30:
		faces.append([k[3], k[0], k[4], k[7]])
	if with_bottom:
		faces.append([k[0], k[3], k[2], k[1]])
	for f in faces:
		var fc: Vector3 = (f[0] + f[1] + f[2] + f[3]) * 0.25
		add_pillow_quad(role, f, fc - center, bevel, bulge, color, edge_color)


## Repère le nombre de sommets de chaque surface (voir warp_since).
func mark() -> Dictionary:
	var m := {}
	for role in _surfaces:
		m[role] = (_surfaces[role] as Surface).v.size()
	return m


## Déforme tous les sommets ajoutés depuis `since` (résultat de mark()) avec
## `fn(Vector3) -> Vector3`, puis recalcule leurs normales plates. Sert aux bords
## de toit relevés : la déformation ne dépend que de la position, donc deux pans
## qui partagent une arête restent jointifs.
func warp_since(since: Dictionary, fn: Callable) -> void:
	for role in _surfaces:
		var surf: Surface = _surfaces[role]
		var start: int = since.get(role, 0)
		var i := start
		while i + 2 < surf.v.size():
			var a: Vector3 = fn.call(surf.v[i])
			var b: Vector3 = fn.call(surf.v[i + 1])
			var c: Vector3 = fn.call(surf.v[i + 2])
			surf.v[i] = a
			surf.v[i + 1] = b
			surf.v[i + 2] = c
			# Sommets émis dans le sens horaire vu de devant : normale = (c - a) × (b - a).
			var nrm := (c - a).cross(b - a)
			if nrm.length_squared() > 1e-14:
				nrm = nrm.normalized()
				if nrm.dot(surf.n[i]) < 0.0:
					nrm = -nrm
				surf.n[i] = nrm
				surf.n[i + 1] = nrm
				surf.n[i + 2] = nrm
			i += 3


## Construit l'ArrayMesh final. `materials` associe un rôle à un Material (optionnel).
func commit(materials := {}) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for role in _surfaces:
		var surf: Surface = _surfaces[role]
		if surf.v.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surf.v
		arrays[Mesh.ARRAY_NORMAL] = surf.n
		arrays[Mesh.ARRAY_COLOR] = surf.c
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var idx := mesh.get_surface_count() - 1
		mesh.surface_set_name(idx, String(role))
		if materials.has(role):
			mesh.surface_set_material(idx, materials[role])
	return mesh
