@tool
@icon("res://addons/bastide/editor/icons/bastide_garden.svg")
class_name BastideHill
extends BastideStructure
## Colline tracée dans le contour fermé de sa courbe : le relief monte en une colline
## douce (BastideHillShape), couverte de la même herbe que la prairie. Un terrier
## posé contre elle s'y creuse (voir BastideBurrowBuilder).
## En jeu : set_footprint() avec le contour.

## Hauteur au sommet (0 : selon la taille du contour).
@export_range(0.0, 20.0, 0.1) var height := 0.0:
	set(value):
		height = value
		queue_rebuild()

var _points_override := PackedVector3Array()
var _use_override := false
var _carve_key := 0


func terrain_mode() -> int:
	return BastideDrape.Mode.NONE


func _default_curve() -> Curve3D:
	var c := Curve3D.new()
	for p in [Vector3(-8, 0, -5), Vector3(2, 0, -7), Vector3(9, 0, -2), Vector3(6, 0, 6), Vector3(-3, 0, 6), Vector3(-9, 0, 2)]:
		c.add_point(p)
	c.closed = true
	return c


func set_footprint(points: PackedVector3Array) -> void:
	_points_override = points
	_use_override = true
	queue_rebuild()


func get_points() -> PackedVector3Array:
	if _use_override:
		return _points_override
	var out := PackedVector3Array()
	if curve:
		for i in curve.point_count:
			out.append(curve.get_point_position(i))
	return out


## Hauteur au sommet : réglée, ou d'après la taille (grande colline, grand sommet).
static func auto_height(poly: PackedVector2Array, seed: int) -> float:
	var area := absf(BastidePolygon.signed_area(poly))
	return clampf(sqrt(area) * 0.42, 2.5, 8.0) * (0.9 + 0.2 * BastideRng.randf_at(seed, "colline"))


func _make_job() -> Callable:
	var pts := get_points()
	var s := seed
	var hh := height
	var terrain := BastideTerrain.find(self)
	var field := terrain.base_field if terrain else null
	var xf := Transform3D(global_transform.basis.orthonormalized(), global_transform.origin) if is_inside_tree() else Transform3D.IDENTITY
	return func() -> BastideBuildResult:
		var r := BastideBuildResult.new()
		var poly := PackedVector2Array()
		for p in pts:
			var w := xf * p
			poly.append(Vector2(w.x, w.z))
		if poly.size() >= 3 and field:
			var h := hh if hh > 0.0 else auto_height(poly, s)
			r.anchors["carve"] = BastideHillShape.carve(poly, h, field, s)
			r.anchors["height"] = h
		r.stats = {"points": poly.size()}
		return r


func _apply(result: BastideBuildResult) -> void:
	super(result)
	var terrain := BastideTerrain.find(self)
	if terrain == null:
		return
	if _carve_key == 0:
		_carve_key = get_instance_id()
	var carve: Variant = result.anchors.get("carve") if result else null
	if carve == null or (carve as Dictionary).is_empty() or not context_enabled and mesh_transparency > 0.0:
		terrain.clear_carve(_carve_key)
		return
	terrain.set_carve(_carve_key, carve)


func _exit_tree() -> void:
	var terrain := BastideTerrain.find(self)
	if terrain and _carve_key != 0:
		terrain.clear_carve(_carve_key)
	super()
