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


func is_empty() -> bool:
	return mesh == null or mesh.get_surface_count() == 0


## Ajoute les 12 triangles d'un bloc à 8 coins (0-3 dessous, 4-7 dessus).
func add_box(k: Array) -> void:
	for q in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		var a: Vector3 = k[q[0]]
		var b: Vector3 = k[q[1]]
		var c: Vector3 = k[q[2]]
		var d: Vector3 = k[q[3]]
		collision_faces.append(a); collision_faces.append(b); collision_faces.append(c)
		collision_faces.append(a); collision_faces.append(c); collision_faces.append(d)
