@tool
class_name BastideTreeBody
extends StaticBody3D
## Collisions des troncs d'arbres : un seul corps statique, un cylindre par arbre.
##
## Léger : pas de nœud par arbre (une « shape owner » par tronc sur ce corps), des
## formes partagées entre troncs de même taille, rien sur le feuillage. Les arbres
## restent dessinés par MultiMesh (et leur LOD) : ce corps ne touche pas au rendu.
##
## Prévu pour l'abattage : chaque arbre a un identifiant (son rang dans la liste
## donnée à `set_trunks`), `tree_at` retrouve l'arbre visé et `remove_tree` retire sa
## collision et efface ses instances dans les MultiMesh de la structure.

const GROUP := &"bastide_trees"
## Hauteur des cylindres : de quoi buter dessus en promenade, sans monter dans les couronnes.
const DEFAULT_HEIGHT := 6.0

## Nœud qui porte les MultiMeshInstance3D de l'arbre (instances `parts`).
var host: Node3D
## Indice d'arbre → shape owner (absent : arbre retiré).
var _owners := {}
var _trunks: Array = []
static var _shapes := {}


func _init() -> void:
	add_to_group(GROUP)


## Remplace tous les troncs. `trunks` : voir BastideBuildResult.trunks (repère local de ce corps).
func set_trunks(trunks: Array) -> void:
	for o in get_shape_owners():
		remove_shape_owner(o)
	_owners.clear()
	_trunks = trunks
	for i in trunks.size():
		var t: Dictionary = trunks[i]
		var h := float(t.get("h", DEFAULT_HEIGHT))
		var o := create_shape_owner(self)
		shape_owner_add_shape(o, _shape(float(t["r"]), h))
		shape_owner_set_transform(o, Transform3D(Basis.IDENTITY, (t["pos"] as Vector3) + Vector3(0, h * 0.5, 0)))
		_owners[i] = o


func tree_count() -> int:
	return _owners.size()


## Identifiant de l'arbre le plus proche d'un point (monde) à moins de `max_dist`, ou -1.
func tree_at(world_pos: Vector3, max_dist := 1.5) -> int:
	var p := to_local(world_pos)
	var best := -1
	var best_d := max_dist
	for i: int in _owners:
		var t: Dictionary = _trunks[i]
		var d := Vector2(p.x - t["pos"].x, p.z - t["pos"].z).length() - float(t["r"])
		if d < best_d:
			best_d = d
			best = i
	return best


## Position du pied d'un arbre (monde).
func tree_position(id: int) -> Vector3:
	return to_global(_trunks[id]["pos"]) if _owners.has(id) else Vector3.INF


## Retire un arbre : sa collision et ses instances (tronc, couronnes, ombre).
## Renvoie faux s'il n'existe plus. Une régénération de la structure le fait revenir :
## le jeu devra mémoriser les arbres abattus (identifiants) pour les retirer à nouveau.
func remove_tree(id: int) -> bool:
	if not _owners.has(id):
		return false
	remove_shape_owner(_owners[id])
	_owners.erase(id)
	if host:
		for part: Array in _trunks[id].get("parts", []):
			var mmi := host.get_node_or_null(NodePath("%s%d" % [BastideResultApplier.MULTI_PREFIX, int(part[0])])) as MultiMeshInstance3D
			if mmi and mmi.multimesh and int(part[1]) < mmi.multimesh.instance_count:
				var xf := mmi.multimesh.get_instance_transform(int(part[1]))
				mmi.multimesh.set_instance_transform(int(part[1]), Transform3D(Basis.from_scale(Vector3.ONE * 1e-4), xf.origin))
	return true


## Formes partagées (rayon arrondi au cm près : quelques dizaines de formes au plus).
static func _shape(r: float, h: float) -> CylinderShape3D:
	var key := Vector2i(roundi(r * 100.0), roundi(h * 10.0))
	if not _shapes.has(key):
		var c := CylinderShape3D.new()
		c.radius = key.x / 100.0
		c.height = key.y / 10.0
		_shapes[key] = c
	return _shapes[key]
