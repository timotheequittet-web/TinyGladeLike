@tool
@icon("res://addons/bastide/editor/icons/bastide_wall.svg")
class_name BastideWall
extends BastideStructure
## Mur procédural qui suit sa propre courbe.
##
## Dans l'éditeur : ajoute un nœud BastideWall, puis place des points avec les outils
## de Path3D (barre d'outils du viewport). Le mur se régénère à chaque modification.
## Un point sans poignées fait un angle net ; tire les poignées pour courber le mur.
## Coche « closed » sur la Curve3D pour fermer une enceinte.
## Là où un chemin (BastidePath) le traverse, le mur s'ouvre tout seul : petit
## portail couvert de tuiles en style japonais, piliers et arc de pierre en médiéval.
##
## En jeu : appelle set_points() pour construire un mur à partir de points calculés.

## Hauteur du mur. 0 = hauteur du style.
@export_range(0.0, 20.0, 0.05, "or_greater", "suffix:m") var height := 0.0:
	set(value):
		height = value
		queue_rebuild()

## Ouvre le mur là où un chemin le traverse (portail).
@export var open_for_paths := true:
	set(value):
		open_for_paths = value
		queue_rebuild()

var _points_override := PackedVector3Array()
var _closed_override := false
var _use_override := false


## Construit le mur à partir de points (espace local), sans passer par la courbe.
## Prévu pour la construction en jeu ; appeler clear_points() pour revenir à la courbe.
func set_points(points: PackedVector3Array, closed := false) -> void:
	_points_override = points
	_closed_override = closed
	_use_override = true
	queue_rebuild()


func clear_points() -> void:
	_use_override = false
	queue_rebuild()


func context_level() -> int:
	return LEVEL_WALL


func uses_context() -> bool:
	return open_for_paths


func _make_job() -> Callable:
	var spec := build_spec()
	if open_for_paths:
		spec.context = gather_context()
	var st := get_effective_style()
	var with_collision := generate_collision
	return func() -> BastideBuildResult: return compute(spec, st, with_collision)


## Calcul pur (aucun accès à l'arbre de scène) : peut tourner sur n'importe quel thread.
static func compute(spec: BastideWallSpec, st: BastideStyle, with_collision: bool) -> BastideBuildResult:
	var layout := BastideWallGenerator.generate(spec, st)
	if layout.is_empty():
		return BastideBuildResult.new()
	return BastideWallMesher.build(layout, st, with_collision)


func describe() -> Dictionary:
	var spec := build_spec()
	if spec.points.size() < 2:
		return {}
	return {"kind": "wall", "points": _to_world(spec.points), "closed": spec.closed,
		"thickness": get_effective_style().get_wall_style().thickness}


func build_spec() -> BastideWallSpec:
	var st := get_effective_style()
	var pts: PackedVector3Array
	var closed := false
	if _use_override:
		pts = _points_override
		closed = _closed_override
	elif curve:
		pts = BastideWallSpec.points_from_curve(curve, st.get_wall_style().station_spacing)
		closed = curve.closed
	return BastideWallSpec.from_points(pts, closed, seed, height)
