@tool
@icon("res://addons/bastide/editor/icons/bastide_terrace.svg")
class_name BastideTerrace
extends BastideStructure
## Terrasse de bois sur sa courbe : plancher sur poteaux courts et pierres d'assise.
##
## Les points de la courbe donnent l'emprise ; elle est toujours redressée en
## rectangle (axe du premier côté). Posée contre une maison, elle devient un engawa :
## collée à la façade, sans garde-corps, une pierre de seuil devant. Isolée, elle a
## un garde-corps et des marches. Un chemin qui arrive près des marches les rejoint.
##
## En jeu : set_footprint() avec les quatre angles.

## Côté des marches (0 = du premier au deuxième point…). -1 = automatique.
@export_range(-1, 3, 1) var entry_side := -1:
	set(value):
		entry_side = value
		queue_rebuild()

## Hauteur du plancher. 0 = celle du style (volet Garden).
@export_range(0.0, 1.5, 0.01, "suffix:m") var height := 0.0:
	set(value):
		height = value
		queue_rebuild()

var _points_override := PackedVector3Array()
var _use_override := false


func context_level() -> int:
	return LEVEL_TERRACE


func uses_context() -> bool:
	return true


func _default_curve() -> Curve3D:
	var c := Curve3D.new()
	for p in [Vector3(-2, 0, -1), Vector3(2, 0, -1), Vector3(2, 0, 1), Vector3(-2, 0, 1)]:
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
	var st := get_effective_style()
	var ctx := gather_context()
	var s := seed
	var col := generate_collision
	var e := entry_side
	var hh := height
	return func() -> BastideBuildResult: return BastideTerraceMesher.build(pts, s, st, ctx, col, e, hh)


## Pour les voisins : l'emprise réellement construite (après redressement) et les
## marches, déclarées comme une porte.
func describe() -> Dictionary:
	var rect: PackedVector3Array = last_anchors.get("rect", BastideTerraceRules.fit_rect(get_points()))
	if rect.size() != 4:
		return {}
	var xf := global_transform
	var doors: Array = []
	for d: Dictionary in last_anchors.get("doors", []):
		doors.append({"pos": xf * (d["pos"] as Vector3), "out": (xf.basis * (d["out"] as Vector3)).normalized(),
			"width": d["width"], "stone": false})
	return {"kind": "terrace", "footprint": _to_world(rect), "doors": doors,
		"height": last_anchors.get("height", get_effective_style().get_garden_style().terrace_height)}


func terrain_mode() -> int:
	return BastideDrape.Mode.RIGID


## Une terrasse collée à une maison (engawa) se pose au moins à la hauteur de la maison.
func _terrain_min_lift() -> float:
	var mine := _flat_rect(describe())
	if mine.size == Vector2.ZERO or get_parent() == null:
		return -INF
	var best := -INF
	for n in get_parent().get_children():
		if n is BastideBuilding and n.last_stats.has("terrain_lift"):
			var r := _flat_rect((n as BastideBuilding).describe())
			if r.grow(2.5).intersects(mine):
				best = maxf(best, float(n.last_stats["terrain_lift"]))
	return best


func _flat_rect(d: Dictionary) -> Rect2:
	var fp: PackedVector3Array = d.get("footprint", PackedVector3Array())
	if fp.is_empty():
		return Rect2()
	var r := Rect2(Vector2(fp[0].x, fp[0].z), Vector2.ZERO)
	for p in fp:
		r = r.expand(Vector2(p.x, p.z))
	return r
