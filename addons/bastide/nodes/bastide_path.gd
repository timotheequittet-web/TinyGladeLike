@tool
@icon("res://addons/bastide/editor/icons/bastide_path.svg")
class_name BastidePath
extends BastideStructure
## Chemin de jardin sur sa propre courbe : gravier ratissé, pas japonais, bordure de
## pierres, lanternes.
##
## Dans l'éditeur : ajoute un nœud BastidePath et place ses points (outils de
## Path3D). Si un bout du chemin arrive à moins de 3,6 m d'une porte de maison, il
## la rejoint tout seul, bien de face, sur une pierre de seuil ; près d'un autre
## chemin, il s'y raccorde. Le tracé serpente doucement.
##
## En jeu : set_points().

## Largeur. 0 = celle du style (volet Garden).
@export_range(0.0, 4.0, 0.05, "suffix:m") var width := 0.0:
	set(value):
		width = value
		queue_rebuild()

var _points_override := PackedVector3Array()
var _use_override := false


func context_level() -> int:
	return LEVEL_PATH


func uses_context() -> bool:
	return true


func _default_curve() -> Curve3D:
	var c := Curve3D.new()
	for p in [Vector3(-4, 0, 0), Vector3(0, 0, 1), Vector3(4, 0, 0)]:
		c.add_point(p)
	return c


func set_points(points: PackedVector3Array) -> void:
	_points_override = points
	_use_override = true
	queue_rebuild()


func clear_points() -> void:
	_use_override = false
	queue_rebuild()


func get_points() -> PackedVector3Array:
	if _use_override:
		return _points_override
	if curve == null or curve.point_count < 2:
		return PackedVector3Array()
	return curve.tessellate_even_length(5, 0.4)


func get_width() -> float:
	return width if width > 0.0 else get_effective_style().get_garden_style().path_width


func _make_job() -> Callable:
	var pts := get_points()
	var st := get_effective_style()
	var ctx := gather_context()
	var s := seed
	var col := generate_collision
	var w := width
	return func() -> BastideBuildResult: return BastidePathMesher.build(pts, s, st, ctx, col, w)


## Pour les voisins : l'axe réellement dessiné (après raccords) et la largeur.
func describe() -> Dictionary:
	var center: PackedVector3Array = last_anchors.get("center", get_points())
	if center.size() < 2:
		return {}
	return {"kind": "path", "points": _to_world(center), "width": get_width()}
