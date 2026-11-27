@tool
class_name BastideInteriorLayout
extends RefCounted
## Plan de l'intérieur d'un bâtiment : niveaux (planchers), escaliers, entrée.
## Aucune géométrie de rendu : le backend (BastideInteriorMesher) la dessine.
##
## Pensé pour grandir : un niveau porte une liste de pièces (aujourd'hui une seule,
## tout le plateau). Des cloisons, du mobilier ou une aile ajoutée plus tard par un
## village qui s'agrandit viendront s'y greffer sans toucher aux escaliers.


class Level:
	var index := 0
	## Dessus du plancher (y local).
	var y := 0.0
	## Dessous du plafond : le plancher du niveau suivant, ou INF sous le toit.
	var ceiling_y := INF
	## Plancher : morceaux de polygone (sens direct) une fois retirées la trémie et l'entrée.
	var pieces: Array = []  # Array[PackedVector2Array]
	## Trémies (ouverture de l'escalier qui arrive par en dessous), rectangles.
	var holes: Array = []  # Array[PackedVector2Array]
	## Côtés de trémie à protéger d'un garde-corps : [Vector2 a, Vector2 b].
	var railings: Array = []
	## Pièces du niveau : { poly: PackedVector2Array, kind: String }.
	var rooms: Array = []


class Flight:
	## Niveau de départ (on monte vers from_level + 1).
	var from_level := 0
	## Pied de la volée, contre le mur.
	var start := Vector2.ZERO
	## Sens de la montée (le long du mur) et vers la pièce.
	var dir := Vector2.ZERO
	var side := Vector2.ZERO
	var width := 0.8
	var y0 := 0.0
	var y1 := 0.0
	var steps := 12
	## Giron (profondeur d'une marche) ; la volée fait steps * tread de long.
	var tread := 0.24
	## Façade contre laquelle elle s'appuie.
	var facade := -1

	func run() -> float:
		return steps * tread

	func riser() -> float:
		return (y1 - y0) / steps

	## Coin de la volée : `along` le long de la montée, `across` vers la pièce.
	func at(along: float, across: float) -> Vector2:
		return start + dir * along + side * across

	## Emprise au sol (rectangle direct).
	func rect(extra_back := 0.0, extra_front := 0.0, into_wall := 0.0) -> PackedVector2Array:
		var r := PackedVector2Array([at(-extra_back, -into_wall), at(run() + extra_front, -into_wall),
			at(run() + extra_front, width), at(-extra_back, width)])
		return BastidePolygon.ensure_direct(r)

	## Hauteur de la rampe de marche à l'abscisse `along`.
	func height_at(along: float) -> float:
		return lerpf(y0, y1, clampf(along / run(), 0.0, 1.0))


var timber := false
var base_y := 0.0
## Contour intérieur des murs (sens direct).
var inner := PackedVector2Array()
var wall_thickness := 0.4
var slab_thickness := 0.18
var levels: Array = []   # Array[Level]
var flights: Array = []  # Array[Flight]
## Entrée en contrebas (genkan) : rectangle et hauteur du sol ; vide s'il n'y en a pas.
var genkan := PackedVector2Array()
var genkan_y := 0.0
## Marche de pierre devant le plancher (kutsunugi-ishi) : rectangle et dessus.
var step_stone := PackedVector2Array()
var step_stone_y := 0.0
## Porte d'entrée : { facade, u0, u1, y0, y1, arch, pos (Vector2, milieu côté intérieur), inward (Vector2) }.
var door := {}
## Remarques du planificateur (« pas de place pour l'escalier »…).
var notes := PackedStringArray()


func is_empty() -> bool:
	return levels.is_empty()


func top_level() -> Level:
	return levels[levels.size() - 1] if not levels.is_empty() else null


## Le point (plan) est-il à l'intérieur des murs ?
func contains(p: Vector2) -> bool:
	return inner.size() >= 3 and Geometry2D.is_point_in_polygon(p, inner)


## Niveau dont le plancher est juste sous l'altitude y.
func level_at(y: float) -> int:
	var best := 0
	for l: Level in levels:
		if y >= l.y - 0.3:
			best = l.index
	return best
