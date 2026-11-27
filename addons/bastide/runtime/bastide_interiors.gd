class_name BastideInteriors
extends Node
## Entrer dans les maisons : pendant la promenade (touche P), les maisons proches du
## promeneur reçoivent leur intérieur (parquet, escaliers, portes qui s'ouvrent) et
## le perdent quand il s'éloigne. En vue d'ensemble, aucune maison n'en a : un hameau
## ou un village entier ne coûte rien de plus.
##
## La caméra de promenade en crée un toute seule (BastideOrbitCamera.enter_buildings) ;
## on peut aussi en poser un dans la scène pour régler les distances.

const GROUP := &"bastide_interiors"
## Distance (m) à laquelle une porte s'ouvre devant le promeneur.
const DOOR_DISTANCE := 3.2

@export var camera: BastideOrbitCamera
## Une maison reçoit son intérieur quand le promeneur arrive à cette distance de ses murs…
@export var enter_distance := 14.0
## … et le perd au-delà de celle-ci.
@export var leave_distance := 22.0
## Nombre maximal de maisons ouvertes à la fois (les plus proches).
@export var max_open := 4

var _active: Array = []  # Array[BastideBuilding]
var _scan := 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _process(delta: float) -> void:
	if camera == null:
		return
	var walking := camera.walking
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.25
		_update_set(walking)
	if not walking:
		return
	var p := camera.walker_position()
	for b: BastideBuilding in _active:
		if is_instance_valid(b):
			b.update_interior(p, delta)


func _update_set(walking: bool) -> void:
	var keep: Array = []
	if walking:
		var p := camera.walker_position()
		var near: Array = []
		for n in get_tree().get_nodes_in_group(BastideStructure.GROUP):
			var b := n as BastideBuilding
			if b == null or not b.context_enabled or b.mesh_transparency > 0.01 or not b.is_visible_in_tree():
				continue
			var d := b.walker_distance(p)
			var limit := leave_distance if b.is_interior_active() else enter_distance
			if d < limit:
				near.append([d, b])
		near.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		for i in mini(near.size(), max_open):
			keep.append(near[i][1])
	for b in _active:
		if is_instance_valid(b) and not keep.has(b):
			(b as BastideBuilding).set_interior_active(false)
	for b: BastideBuilding in keep:
		if not b.is_interior_active():
			b.set_interior_active(true)
	_active = keep


## Toutes les maisons ouvertes (pour les tests et l'aide à l'écran).
func open_buildings() -> Array:
	return _active.filter(func(b) -> bool: return is_instance_valid(b))
