@tool
@icon("res://addons/bastide/editor/icons/bastide_garden.svg")
class_name BastideFarm
extends BastideStructure
## Cultures dans le contour fermé de sa courbe : potager (planches, légumes, clôture
## de bambou, épouvantail), rizière en terrasses sur une pente (eau à plat, levées,
## murets de pierres sèches, riz repiqué) ou champ de thé (haies arrondies).
## Le sol est abaissé sous le champ (BastideTerrain) ; la terre du champ est posée
## par-dessus. Les forêts, massifs, le jardin et l'herbe l'évitent.
## En jeu : set_footprint() avec le contour.

## Sorte de culture.
@export var farm_kind: BastideFarmBuilder.Kind = BastideFarmBuilder.Kind.VEGETABLE:
	set(value):
		farm_kind = value
		queue_rebuild()

var _points_override := PackedVector3Array()
var _use_override := false
var _carve_key := 0


## Les champs se calent sur les maisons, terrasses et chemins ; clôtures, massifs,
## forêts et jardin les évitent ensuite.
func context_level() -> int:
	return LEVEL_WALL


func uses_context() -> bool:
	return true


## Le champ est posé à la main sur le relief (terrasses, terre au-dessus du sol).
func terrain_mode() -> int:
	return BastideDrape.Mode.NONE


func _default_curve() -> Curve3D:
	var c := Curve3D.new()
	for p in [Vector3(-6, 0, -4), Vector3(6, 0, -4.5), Vector3(7, 0, 4), Vector3(-5.5, 0, 4.5)]:
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
	var k := int(farm_kind)
	var st := get_effective_style()
	var col := generate_collision
	var terrain := BastideTerrain.find(self)
	# Le relief d'origine : le champ ne se cale pas sur son propre creusement.
	var field := terrain.base_field if terrain else null
	var xf := Transform3D(global_transform.basis.orthonormalized(), global_transform.origin) if is_inside_tree() else Transform3D.IDENTITY
	return func() -> BastideBuildResult: return BastideFarmBuilder.build(pts, s, k, st, ctx, field, xf, col)


func _apply(result: BastideBuildResult) -> void:
	super(result)
	_update_carve(result)


## Abaisse le relief sous le champ (à la frame suivante, voir BastideTerrain.set_carve).
func _update_carve(result: BastideBuildResult) -> void:
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


## Pour les voisins : le contour du champ (monde).
func describe() -> Dictionary:
	var outline: Variant = last_anchors.get("outline")
	if outline == null:
		return {}
	var pts := PackedVector3Array()
	for p: Vector2 in outline:
		pts.append(Vector3(p.x, 0.0, p.y))
	return {"kind": "farm", "footprint": _to_world(pts), "farm_kind": int(farm_kind)}
