@tool
@icon("res://addons/bastide/editor/icons/bastide_forest.svg")
class_name BastideForest
extends BastideStructure
## Forêt dans le contour fermé de sa courbe : grands arbres du kit nature (couronnes
## peintes reprises d'Onsen), espacés pour qu'on circule entre les troncs, et un
## sous-bois de fougères, fleurs et massifs. Les troncs ont des collisions.
##
## Elle évite d'elle-même les maisons, terrasses, chemins, murs et portes voisins.
## En jeu : set_footprint() avec le contour.

## Sorte de forêt (essences).
@export var forest_kind: BastideForestBuilder.Kind = BastideForestBuilder.Kind.MIXED:
	set(value):
		forest_kind = value
		queue_rebuild()

## Taille des arbres : 1 = chênes et cèdres vers 17 à 19 m (2 = géants de 35 m).
@export_range(0.4, 2.0, 0.05) var tree_scale := 1.0:
	set(value):
		tree_scale = value
		queue_rebuild()

## Densité des arbres (1 = couronnes qui se touchent à peine).
@export_range(0.3, 2.0, 0.05) var density := 1.0:
	set(value):
		density = value
		queue_rebuild()

## Densité du sous-bois (0 = aucun).
@export_range(0.0, 3.0, 0.05) var undergrowth := 1.0:
	set(value):
		undergrowth = value
		queue_rebuild()

var _points_override := PackedVector3Array()
var _use_override := false


func context_level() -> int:
	return LEVEL_FENCE


func uses_context() -> bool:
	return true


func _default_curve() -> Curve3D:
	var c := Curve3D.new()
	for p in [Vector3(-20, 0, -14), Vector3(20, 0, -16), Vector3(24, 0, 14), Vector3(-18, 0, 16)]:
		c.add_point(p)
	c.closed = true
	return c


func set_footprint(points: PackedVector3Array) -> void:
	_points_override = points
	_use_override = true
	queue_rebuild()


func clear_footprint() -> void:
	_use_override = false
	queue_rebuild()


func get_points() -> PackedVector3Array:
	if _use_override:
		return _points_override
	var out := PackedVector3Array()
	if curve:
		for i in curve.point_count:
			out.append(curve.get_point_position(i))
	return out


func _make_job() -> Callable:
	var pts := get_points()
	var ctx := gather_context()
	var s := seed
	var col := generate_collision
	var k := forest_kind
	var sc := tree_scale
	var d := density
	var u := undergrowth
	return func() -> BastideBuildResult: return BastideForestBuilder.build(pts, s, k, sc, d, u, ctx, col)


func describe() -> Dictionary:
	var pts := get_points()
	if pts.size() < 3:
		return {}
	return {"kind": "forest", "points": _to_world(pts)}
