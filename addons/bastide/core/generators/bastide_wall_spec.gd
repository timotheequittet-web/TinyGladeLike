@tool
class_name BastideWallSpec
extends RefCounted
## Entrée pure d'un mur : rien que des données, aucune référence à un nœud.
## Le nœud BastideWall la construit depuis sa Path3D ; un futur outil de
## construction en jeu pourra la remplir directement avec des points.

## Points du tracé, dans l'espace local du mur. Y = hauteur du pied du mur.
var points := PackedVector3Array()
var closed := false
var seed := 0
## Hauteur voulue ; ≤ 0 pour prendre celle du style.
var height := 0.0
## Voisinage (facultatif) : le mur s'ouvre là où un de ses chemins le traverse.
var context: BastideGardenContext


static func from_points(p_points: PackedVector3Array, p_closed: bool, p_seed: int, p_height := 0.0) -> BastideWallSpec:
	var s := BastideWallSpec.new()
	s.points = p_points
	s.closed = p_closed
	s.seed = p_seed
	s.height = p_height
	return s


## Échantillonne une Curve3D en polyligne. Les points de contrôle sans poignées
## restent des angles nets ; les portions courbes sont découpées finement.
static func points_from_curve(curve: Curve3D, spacing: float) -> PackedVector3Array:
	if curve == null or curve.point_count < 2:
		return PackedVector3Array()
	return curve.tessellate_even_length(5, maxf(spacing, 0.05))
