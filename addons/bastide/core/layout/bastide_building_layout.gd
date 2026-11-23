@tool
class_name BastideBuildingLayout
extends RefCounted
## Plan sémantique d'un bâtiment : façades, ouvertures, décor, et le plan du toit.
## Aucun triangle : le backend procédural le dessine, le futur backend kit y posera
## des pièces modulaires (une fenêtre du plan = une pièce « fenêtre » du kit).

enum OpeningKind { WINDOW, DOOR, ATTIC }


class Facade:
	var index := 0
	## Extrémités de la face extérieure, Vector2(x, z).
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var length := 0.0
	var dir := Vector2.ZERO
	## Normale horizontale vers l'extérieur.
	var out := Vector2.ZERO
	var convex_start := true
	var convex_end := true
	## Pignon : le haut du mur suit le toit au-dessus de l'égout.
	var gable := false
	## Haut du mur : Vector2(u, y), u le long de la façade (0 → length), y absolu.
	var profile := PackedVector2Array()
	## { kind, u0, u1, y0, y1, arch (rayon, 0 si aucun), floor, shutters, flowers }
	var openings: Array = []
	var plaster := Color.WHITE

	## Point 3D de la façade : u le long, y altitude, depth vers l'extérieur.
	func point(u: float, y: float, depth := 0.0) -> Vector3:
		# Les bouts tombent exactement sur les sommets : pas de fente entre deux façades.
		var p := (a if u == 0.0 else (b if u == length else a + dir * u)) + out * depth
		return Vector3(p.x, y, p.y)

	func dir3() -> Vector3:
		return Vector3(dir.x, 0.0, dir.y)

	func out3() -> Vector3:
		return Vector3(out.x, 0.0, out.y)


var seed := 0
var footprint := PackedVector2Array()
var base_y := 0.0
var eave_y := 3.0
var floors := 1
var floor_height := 2.9
var wall_thickness := 0.4
var facades: Array = []  # Array[Facade]
var roof: BastideRoofLayout
var shutter_color := Color.WHITE
## Remarques du générateur (« angles redressés »…), utiles dans l'inspecteur.
var notes := PackedStringArray()


func is_empty() -> bool:
	return facades.is_empty()


func count(kind: int) -> int:
	var c := 0
	for f: Facade in facades:
		for o in f.openings:
			if o.kind == kind:
				c += 1
	return c
