@tool
@icon("res://addons/bastide/editor/icons/bastide_fence.svg")
class_name BastideFence
extends BastideStructure
## Petite clôture de jardin sur sa courbe : muret de pierres sèches ou clôture de
## bambou. Elle s'ouvre toute seule là où un chemin la traverse, avec deux poteaux
## (ou deux grandes pierres) de part et d'autre du passage.
##
## Dans l'éditeur : comme un BastideWall (points de la Path3D, `closed` sur la courbe
## pour une enceinte). En jeu : set_points().

enum Variant { STONE, BAMBOO }

## Pierres sèches (muret bas) ou bambou (claire-voie).
@export var variant := Variant.STONE:
	set(value):
		variant = value
		queue_rebuild()

## Hauteur. 0 = celle du style.
@export_range(0.0, 3.0, 0.05, "suffix:m") var height := 0.0:
	set(value):
		height = value
		queue_rebuild()

var _points_override := PackedVector3Array()
var _closed_override := false
var _use_override := false


func context_level() -> int:
	return LEVEL_FENCE


func uses_context() -> bool:
	return true


func set_points(points: PackedVector3Array, closed := false) -> void:
	_points_override = points
	_closed_override = closed
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
	var pts := curve.tessellate_even_length(5, 0.5)
	if curve.closed and pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) < 0.05:
		pts.remove_at(pts.size() - 1)
	return pts


func is_closed() -> bool:
	return _closed_override if _use_override else (curve != null and curve.closed)


func _make_job() -> Callable:
	var pts := get_points()
	var closed := is_closed()
	var v := int(variant)
	var st := get_effective_style()
	var ctx := gather_context()
	var s := seed
	var col := generate_collision
	var hh := height
	return func() -> BastideBuildResult: return BastideFenceMesher.build(pts, closed, v, s, st, ctx, col, hh)


func describe() -> Dictionary:
	var pts := get_points()
	if pts.size() < 2:
		return {}
	return {"kind": "fence", "points": _to_world(pts), "closed": is_closed(), "variant": int(variant),
		"thickness": 0.55 if variant == Variant.STONE else 0.16}
