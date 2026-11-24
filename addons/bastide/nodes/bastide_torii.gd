@tool
@icon("res://addons/bastide/editor/icons/bastide_torii.svg")
class_name BastideTorii
extends BastideStructure
## Torii (portique) dont les deux points de la courbe sont les pieds des piliers.
##
## Dans l'éditeur : ajoute un nœud BastideTorii, déplace-le, ou tire ses deux points
## pour l'élargir (2,2 à 7 m). Le bouton « Aligner sur le chemin » le centre sur le
## chemin le plus proche, en travers, à la bonne largeur.
##
## En jeu : set_points([pied gauche, pied droit]).

@export_tool_button("Aligner sur le chemin", "CurveLinear") var _align_button := align_to_path

var _points_override := PackedVector3Array()
var _use_override := false


func context_level() -> int:
	return 1


func _default_curve() -> Curve3D:
	var c := Curve3D.new()
	c.add_point(Vector3(-1.6, 0, 0))
	c.add_point(Vector3(1.6, 0, 0))
	return c


func set_points(points: PackedVector3Array) -> void:
	_points_override = points
	_use_override = true
	queue_rebuild()


func get_points() -> PackedVector3Array:
	if _use_override:
		return _points_override
	var out := PackedVector3Array()
	if curve:
		for i in mini(curve.point_count, 2):
			out.append(curve.get_point_position(i))
	return out


func _make_job() -> Callable:
	var pts := get_points()
	var st := get_effective_style()
	var s := seed
	var col := generate_collision
	return func() -> BastideBuildResult:
		if pts.size() < 2:
			return BastideBuildResult.new()
		return BastideToriiMesher.build(pts[0], pts[1], s, st, col)


func describe() -> Dictionary:
	var pts := get_points()
	if pts.size() < 2:
		return {}
	return {"kind": "gate", "points": _to_world(BastideGardenRules.fit_torii(pts[0], pts[1]))}


## Centre le torii sur le chemin le plus proche (à moins de 6 m), en travers.
func align_to_path() -> void:
	var pts := get_points()
	if pts.size() < 2:
		return
	var center := (pts[0] + pts[1]) * 0.5
	var res := BastideGardenRules.place_torii(center, gather_context(), get_effective_style().get_garden_style().path_width,
			pts[1] - pts[0], 6.0)
	if not res["snapped"]:
		push_warning("Bastide : aucun chemin à moins de 6 m de ce torii.")
		return
	var np: PackedVector3Array = res["points"]
	if _use_override:
		set_points(np)
		return
	var editor := Engine.get_singleton(&"EditorInterface") if Engine.has_singleton(&"EditorInterface") else null
	if Engine.is_editor_hint() and editor:
		var ur: Object = editor.call(&"get_editor_undo_redo")
		ur.call(&"create_action", "Aligner le torii sur le chemin")
		for i in 2:
			ur.call(&"add_do_method", curve, &"set_point_position", i, np[i])
			ur.call(&"add_undo_method", curve, &"set_point_position", i, pts[i])
		ur.call(&"commit_action")
	else:
		for i in 2:
			curve.set_point_position(i, np[i])
