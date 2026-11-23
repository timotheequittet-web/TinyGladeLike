@tool
class_name BastideBuildingSpec
extends RefCounted
## Entrée pure d'un bâtiment : un contour au sol et quelques réglages, sans nœud.
## Le nœud BastideBuilding la construit depuis sa Path3D ; un outil de construction
## en jeu pourra la remplir directement.

## Contour au sol (face extérieure des murs), Vector2(x, z) dans l'espace local.
var footprint := PackedVector2Array()
## Altitude du pied des murs.
var base_y := 0.0
var seed := 0
## Nombre d'étages ; ≤ 0 pour prendre celui du style.
var floors := 0
## Forme du toit (BastideRoofStyle.RoofType) ; < 0 pour prendre celle du style.
var roof_type := -1
## Façade de la porte (indice du côté) ; < 0 pour un choix automatique.
var door_facade := -1


static func from_points(points: PackedVector3Array, p_seed: int, p_floors := 0, p_roof_type := -1,
		p_door := -1) -> BastideBuildingSpec:
	var s := BastideBuildingSpec.new()
	var y := 0.0
	for p in points:
		s.footprint.append(Vector2(p.x, p.z))
		y += p.y
	s.base_y = y / maxf(points.size(), 1)
	s.seed = p_seed
	s.floors = p_floors
	s.roof_type = p_roof_type
	s.door_facade = p_door
	return s


## Les sommets d'un contour sont les points de contrôle de la courbe (les poignées
## sont ignorées : un bâtiment a des murs droits).
static func points_from_curve(curve: Curve3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if curve == null:
		return out
	for i in curve.point_count:
		out.append(curve.get_point_position(i))
	return out
