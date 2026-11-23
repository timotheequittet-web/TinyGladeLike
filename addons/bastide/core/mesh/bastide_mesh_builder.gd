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
func add_block(role: StringName, k: Array, bevel: float, bulge: float, color: Color, edge_color: Color,
		with_bottom := false) -> void:
	var center := Vector3.ZERO
	for p: Vector3 in k:
		center += p
	center /= 8.0
	var faces := [
		[k[4], k[5], k[6], k[7]],  # dessus
		[k[0], k[1], k[5], k[4]],
		[k[1], k[2], k[6], k[5]],
		[k[2], k[3], k[7], k[6]],
		[k[3], k[0], k[4], k[7]],
	]
	if with_bottom:
		faces.append([k[0], k[3], k[2], k[1]])
	for f in faces:
		var fc: Vector3 = (f[0] + f[1] + f[2] + f[3]) * 0.25
		add_pillow_quad(role, f, fc - center, bevel, bulge, color, edge_color)


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
