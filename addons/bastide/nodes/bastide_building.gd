@tool
@icon("res://addons/bastide/editor/icons/bastide_building.svg")
class_name BastideBuilding
extends BastideStructure
## Bâtiment procédural posé sur un contour au sol.
##
## Dans l'éditeur : ajoute un nœud BastideBuilding (une maison rectangulaire
## apparaît), puis déplace, ajoute ou supprime des points avec les outils de Path3D.
## Chaque point de la courbe est un angle de la maison ; les poignées sont ignorées.
## Le contour est toujours fermé. Murs, ouvertures et toit se recalculent en direct.
##
## En jeu : appelle set_footprint() avec les angles du contour.

enum RoofChoice { STYLE, HIP, GABLE, IRIMOYA }

## Nombre d'étages. 0 = celui du style.
@export_range(0, 6, 1) var floors := 0:
	set(value):
		floors = value
		queue_rebuild()

## Forme du toit. « Style » : celle du style ; « Croupes » : pans de tous côtés ;
## « Pignons » : les bouts étroits deviennent des murs triangulaires ;
## « Irimoya » : croupes en bas, petits pignons de bois en haut (toit japonais).
@export var roof := RoofChoice.STYLE:
	set(value):
		roof = value
		queue_rebuild()

## Façade de la porte : numéro du côté du tracé (0 = du premier au deuxième point,
## 1 = du deuxième au troisième…). -1 = automatique (la plus longue façade sous égout).
@export_range(-1, 64, 1) var door_facade := -1:
	set(value):
		door_facade = value
		queue_rebuild()

var _points_override := PackedVector3Array()
var _use_override := false


func _default_curve() -> Curve3D:
	var c := Curve3D.new()
	for p in [Vector3(-4, 0, -3), Vector3(4, 0, -3), Vector3(4, 0, 3), Vector3(-4, 0, 3)]:
		c.add_point(p)
	c.closed = true
	return c


## Construit le bâtiment à partir des angles du contour (espace local), sans la courbe.
## Prévu pour la construction en jeu ; clear_footprint() revient à la courbe.
func set_footprint(points: PackedVector3Array) -> void:
	_points_override = points
	_use_override = true
	queue_rebuild()


func clear_footprint() -> void:
	_use_override = false
	queue_rebuild()


func _make_job() -> Callable:
	var spec := build_spec()
	var st := get_effective_style()
	var with_collision := generate_collision
	return func() -> BastideBuildResult: return compute(spec, st, with_collision)


## Calcul pur (aucun accès à l'arbre de scène) : peut tourner sur n'importe quel thread.
static func compute(spec: BastideBuildingSpec, st: BastideStyle, with_collision: bool) -> BastideBuildResult:
	var layout := BastideBuildingGenerator.generate(spec, st)
	if layout.is_empty():
		return BastideBuildResult.new()
	return BastideBuildingMesher.build(layout, st, with_collision)


## Pour les voisins : contour (celui de la dernière génération, redressé) et portes.
func describe() -> Dictionary:
	var fp := PackedVector3Array()
	var y := 0.0
	if last_anchors.has("footprint"):
		y = last_anchors.get("base_y", 0.0)
		for p: Vector2 in last_anchors["footprint"]:
			fp.append(Vector3(p.x, y, p.y))
	else:
		for p: Vector2 in build_spec().footprint:
			fp.append(Vector3(p.x, 0.0, p.y))
	if fp.size() < 3:
		return {}
	var xf := global_transform
	var doors: Array = []
	for d: Dictionary in last_anchors.get("doors", []):
		doors.append({"pos": xf * (d["pos"] as Vector3), "out": (xf.basis * (d["out"] as Vector3)).normalized(),
			"width": d["width"]})
	return {"kind": "house", "footprint": _to_world(fp), "doors": doors,
		"overhang": last_anchors.get("overhang", 0.6)}


func build_spec() -> BastideBuildingSpec:
	var pts := _points_override if _use_override else BastideBuildingSpec.points_from_curve(curve)
	var roof_type := -1
	match roof:
		RoofChoice.HIP:
			roof_type = BastideRoofStyle.RoofType.HIP
		RoofChoice.GABLE:
			roof_type = BastideRoofStyle.RoofType.GABLE
		RoofChoice.IRIMOYA:
			roof_type = BastideRoofStyle.RoofType.IRIMOYA
	return BastideBuildingSpec.from_points(pts, seed, floors, roof_type, door_facade)


## Une maison reste d'aplomb : un soubassement rattrape la pente.
func terrain_mode() -> int:
	return BastideDrape.Mode.RIGID
