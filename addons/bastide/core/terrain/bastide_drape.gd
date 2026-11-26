@tool
class_name BastideDrape
extends RefCounted
## Pose sur le relief une génération faite à plat (sol à y = 0).
##
## - FOLLOW : chaque sommet monte de la hauteur du sol sous lui. Murets, clôtures,
##   chemins, massifs et forêts épousent la pente (les poteaux restent verticaux :
##   seul y change).
## - RIGID : la structure reste d'aplomb, posée sur le point le plus haut de son
##   assise ; les sommets du pied (y ≈ 0) descendent jusqu'au sol, ce qui étire la
##   première assise en soubassement côté pente. Maisons, terrasses, torii.
##
## Fonctions pures, sur n'importe quel thread.

enum Mode { NONE, FOLLOW, RIGID }

## Sommets considérés comme le pied de la structure.
const FOOT := 0.05
## Le pied s'enfonce un peu sous le sol : jamais de jour entre la pierre et l'herbe.
const SINK := 0.08
## Descente du pied au-delà de laquelle on parle de soubassement (m).
const SOCLE_MARK := 0.2


## `xf` : repère local du nœud → monde. Retourne la hauteur de pose (RIGID) ou 0.
## `min_lift` (RIGID) : hauteur de pose minimale, pour qu'un engawa s'aligne sur sa maison.
static func apply(result: BastideBuildResult, field: BastideHeightField, xf: Transform3D, mode: int, min_lift := -INF) -> float:
	if result == null or field == null or mode == Mode.NONE:
		return 0.0
	var inv := xf.affine_inverse()
	var lift := 0.0
	if mode == Mode.RIGID:
		lift = maxf(_rigid_lift(result, field, xf), min_lift)
	if result.mesh:
		result.mesh = _mesh(result.mesh, field, xf, inv, mode, lift)
	result.collision_faces = _points(result.collision_faces, field, xf, inv, mode, lift)
	# Points de vie (fumées, lumières) : posés comme le reste.
	for key in ["smoke", "lights"]:
		if result.anchors.get(key) is PackedVector3Array:
			result.anchors[key] = _points(result.anchors[key], field, xf, inv, mode, lift)
	for g: Dictionary in result.instances:
		var out: Array = []
		for t: Transform3D in g["transforms"]:
			var w := xf * t.origin
			var dy := lift if mode == Mode.RIGID else field.height(w.x, w.z)
			var nt := t
			nt.origin = inv * (w + Vector3(0, dy, 0))
			out.append(nt)
		g["transforms"] = out
	result.stats["terrain_lift"] = snappedf(lift, 0.01)
	return lift


## Hauteur de pose d'une structure rigide : le plus haut point du sol sous son pied.
static func _rigid_lift(result: BastideBuildResult, field: BastideHeightField, xf: Transform3D) -> float:
	var best := -INF
	var any := false
	if result.mesh:
		for s in result.mesh.get_surface_count():
			var v: PackedVector3Array = result.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for p in v:
				if p.y < FOOT:
					var w := xf * p
					best = maxf(best, field.height(w.x, w.z))
					any = true
	if not any:
		var w := xf.origin
		return field.height(w.x, w.z)
	return best


static func _move(p: Vector3, field: BastideHeightField, xf: Transform3D, inv: Transform3D, mode: int, lift: float) -> Vector3:
	var w := xf * p
	var g := field.height(w.x, w.z)
	if mode == Mode.FOLLOW:
		w.y += g
	else:
		w.y += lift
		if p.y < FOOT:
			# Le pied descend jusqu'au sol (soubassement), sans jamais remonter.
			w.y = minf(w.y, g - SINK + p.y)
	return inv * w


static func _points(pts: PackedVector3Array, field: BastideHeightField, xf: Transform3D, inv: Transform3D, mode: int, lift: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = _move(pts[i], field, xf, inv, mode, lift)
	return out


static func _mesh(src: ArrayMesh, field: BastideHeightField, xf: Transform3D, inv: Transform3D, mode: int, lift: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		# Surface vide ou illisible : on la laisse de côté plutôt que d'échouer.
		if arr.size() <= Mesh.ARRAY_VERTEX or not (arr[Mesh.ARRAY_VERTEX] is PackedVector3Array):
			continue
		var before: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var after := _points(before, field, xf, inv, mode, lift)
		arr[Mesh.ARRAY_VERTEX] = after
		# Soubassement : les sommets du pied descendus jusqu'au sol sont marqués
		# (alpha de couleur à 0) pour que le shader pierre y dessine un appareillage de
		# pierres sèches au lieu d'un pan étiré.
		if mode == Mode.RIGID and arr[Mesh.ARRAY_COLOR] is PackedColorArray:
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			if cols.size() == before.size():
				for i in before.size():
					if before[i].y < FOOT and (before[i].y + lift) - after[i].y > SOCLE_MARK:
						cols[i].a = 0.0
				arr[Mesh.ARRAY_COLOR] = cols
		# Les canaux CUSTOM (vent, ombre…) gardent leur format : sans lui, leurs octets
		# seraient relus de travers et tout le maillage avec.
		var fmt := src.surface_get_format(s)
		var flags := 0
		for c in 4:
			var shift: int = Mesh.ARRAY_FORMAT_CUSTOM_BASE + c * Mesh.ARRAY_FORMAT_CUSTOM_BITS
			flags |= fmt & (Mesh.ARRAY_FORMAT_CUSTOM_MASK << shift)
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arr, [], {}, flags)
		var o := out.get_surface_count() - 1
		out.surface_set_material(o, src.surface_get_material(s))
		out.surface_set_name(o, src.surface_get_name(s))
	out.custom_aabb = AABB()
	return out


## Retire ce qui finirait sous l'eau d'un étang (gravier d'un chemin qui traverse :
## l'étang y pose un pont). Triangles dont les trois sommets sont noyés.
static func clip_water(result: BastideBuildResult, field: BastideHeightField, xf: Transform3D) -> int:
	if result == null or field == null or field.waters.is_empty():
		return 0
	var removed := 0
	if result.mesh:
		var out := ArrayMesh.new()
		for s in result.mesh.get_surface_count():
			var arr := result.mesh.surface_get_arrays(s)
			if arr.size() <= Mesh.ARRAY_VERTEX or not (arr[Mesh.ARRAY_VERTEX] is PackedVector3Array) \
					or arr[Mesh.ARRAY_INDEX] != null or result.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				out.add_surface_from_arrays(result.mesh.surface_get_primitive_type(s), arr)
				out.surface_set_material(out.get_surface_count() - 1, result.mesh.surface_get_material(s))
				out.surface_set_name(out.get_surface_count() - 1, result.mesh.surface_get_name(s))
				continue
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var keep := PackedInt32Array()
			for i in range(0, v.size() - 2, 3):
				if _drowned(xf * v[i], field) and _drowned(xf * v[i + 1], field) and _drowned(xf * v[i + 2], field):
					removed += 1
					continue
				keep.append(i)
			if keep.size() * 3 == v.size():
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			elif keep.is_empty():
				continue
			else:
				var na := []
				na.resize(Mesh.ARRAY_MAX)
				for a in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV]:
					if arr[a] == null:
						continue
					var src = arr[a]
					var dst = src.duplicate()
					dst.resize(keep.size() * 3)
					var k := 0
					for i in keep:
						dst[k] = src[i]; dst[k + 1] = src[i + 1]; dst[k + 2] = src[i + 2]
						k += 3
					na[a] = dst
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
			out.surface_set_material(out.get_surface_count() - 1, result.mesh.surface_get_material(s))
			out.surface_set_name(out.get_surface_count() - 1, result.mesh.surface_get_name(s))
		result.mesh = out
	var faces := result.collision_faces
	if not faces.is_empty():
		var kept := PackedVector3Array()
		for i in range(0, faces.size() - 2, 3):
			if _drowned(xf * faces[i], field) and _drowned(xf * faces[i + 1], field) and _drowned(xf * faces[i + 2], field):
				continue
			kept.append(faces[i]); kept.append(faces[i + 1]); kept.append(faces[i + 2])
		result.collision_faces = kept
	result.stats["under_water"] = removed
	return removed


static func _drowned(w: Vector3, field: BastideHeightField) -> bool:
	var l := field.water_level(w.x, w.z)
	return l > -INF and w.y < l - 0.02
