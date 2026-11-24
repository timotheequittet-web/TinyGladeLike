@tool
@icon("res://addons/bastide/editor/icons/bastide_plants.svg")
class_name BastidePlanting
extends BastideStructure
## Massif de plantes le long de sa courbe (buissons taillés, hortensias, fougères,
## herbes, un petit arbre de temps en temps), ou un arbre isolé si la courbe n'a
## qu'un point (érable, cerisier ou pin taillé, selon la seed et le style).
##
## Les plantes évitent toutes seules les chemins, les maisons, les portes et les
## murs voisins. En jeu : set_points().

var _points_override := PackedVector3Array()
var _use_override := false


func context_level() -> int:
	return 2


func uses_context() -> bool:
	return true


func _default_curve() -> Curve3D:
	var c := Curve3D.new()
	for p in [Vector3(-3, 0, 0), Vector3(0, 0, 0.6), Vector3(3, 0, 0)]:
		c.add_point(p)
	return c


func set_points(points: PackedVector3Array) -> void:
	_points_override = points
	_use_override = true
	queue_rebuild()


func get_points() -> PackedVector3Array:
	if _use_override:
		return _points_override
	if curve == null or curve.point_count == 0:
		return PackedVector3Array()
	if curve.point_count == 1:
		return PackedVector3Array([curve.get_point_position(0)])
	return curve.tessellate_even_length(5, 0.5)


func _make_job() -> Callable:
	var pts := get_points()
	var st := get_effective_style()
	var ctx := gather_context()
	var s := seed
	var col := generate_collision
	return func() -> BastideBuildResult: return BastidePlantingMesher.build_planting(pts, s, st, ctx, col)


func describe() -> Dictionary:
	var pts := get_points()
	if pts.is_empty():
		return {}
	return {"kind": "plants", "points": _to_world(pts)}
