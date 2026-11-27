@tool
class_name BastideBuildResult
extends RefCounted
## Sortie d'une génération : uniquement des données, aucun nœud.
## Le BastideResultApplier se charge de la poser dans la scène.

## Mesh visuel (une surface par rôle de matériau).
var mesh: ArrayMesh
## Triangles de collision simplifiés (3 sommets par triangle), indépendants du détail des pierres.
var collision_faces := PackedVector3Array()
## Informations de debug : nombre de pierres, triangles, temps de génération…
var stats := {}
## Points remarquables pour les autres structures (portes d'une maison, axe d'un
## chemin…), dans l'espace local du nœud. Lus par le décor (chemins qui rejoignent
## les portes, plantes qui évitent les seuils…).
var anchors := {}
## Maillages posés en grand nombre (arbres et plantes d'une forêt) : chaque entrée
## {mesh, material, transforms: Array[Transform3D], shadow (ShadowCastingSetting),
## vis_begin, vis_end (m, 0 = sans limite), custom (facultatif : Array[Color], une
## donnée par instance pour le shader)} devient un MultiMeshInstance3D.
var instances: Array = []
## Troncs d'arbres : une collision légère (cylindre) par arbre, et de quoi retirer
## l'arbre plus tard (abattage). Chaque entrée : {pos: Vector3 (pied, local),
## r: float, h: float, parts: Array de [groupe d'instances, rang dans le groupe]}.
## L'indice dans ce tableau sert d'identifiant de l'arbre dans sa structure.
var trunks: Array = []


func is_empty() -> bool:
	return (mesh == null or mesh.get_surface_count() == 0) and instances.is_empty()


## Ajoute un groupe d'instances (voir `instances`).
func add_instances(m: Mesh, material: Material, transforms: Array, shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		vis_begin := 0.0, vis_end := 0.0) -> void:
	if m == null or transforms.is_empty():
		return
	instances.append({"mesh": m, "material": material, "transforms": transforms, "shadow": shadow,
		"vis_begin": vis_begin, "vis_end": vis_end})


## Ajoute le tronc d'un arbre (voir `trunks`) ; renvoie son identifiant.
## `parts` : les instances qui dessinent cet arbre, [indice du groupe dans
## `instances`, rang de la transformation], pour pouvoir l'effacer un jour.
func add_trunk(pos: Vector3, radius: float, height: float, parts: Array = []) -> int:
	trunks.append({"pos": pos, "r": clampf(radius, 0.08, 1.5), "h": height, "parts": parts})
	return trunks.size() - 1


## Ajoute un prisme vertical à `sides` pans (tronc d'arbre) aux triangles de collision.
func add_prism(center: Vector3, radius: float, height: float, sides := 8) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := center + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := center + Vector3(cos(a1), 0, sin(a1)) * radius
		var up := Vector3(0, height, 0)
		collision_faces.append(p0); collision_faces.append(p1); collision_faces.append(p1 + up)
		collision_faces.append(p0); collision_faces.append(p1 + up); collision_faces.append(p0 + up)


## Ajoute les 12 triangles d'un bloc à 8 coins (0-3 dessous, 4-7 dessus).
func add_box(k: Array) -> void:
	for q in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		var a: Vector3 = k[q[0]]
		var b: Vector3 = k[q[1]]
		var c: Vector3 = k[q[2]]
		var d: Vector3 = k[q[3]]
		collision_faces.append(a); collision_faces.append(b); collision_faces.append(c)
		collision_faces.append(a); collision_faces.append(c); collision_faces.append(d)
