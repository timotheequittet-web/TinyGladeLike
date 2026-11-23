@tool
class_name BastideRoofLayout
extends RefCounted
## Plan d'un toit : pans (polygones 3D), arcs du squelette (faîtages, arêtiers,
## noues, rives), cheminée. Aucun triangle de rendu ici : le backend s'en charge.

enum ArcKind { RIDGE, HIP, VALLEY, VERGE }

## Contour du toit (débord compris), dans le sens direct.
var outline := PackedVector2Array()
## Poids de chaque côté : 1 = pan, 0 = pignon.
var weights := PackedFloat32Array()
## Altitude du dessus du toit au bord du débord, et du haut des murs.
var base_y := 0.0
var eave_y := 0.0
var ridge_y := 0.0
var pitch_deg := 42.0
var tan_pitch := 0.9
var thickness := 0.2
var overhang := 0.45
## "" si tout va bien, sinon la forme de repli utilisée ("croupes", "plat").
var fallback := ""
var color := Color(0.66, 0.32, 0.22)

## Un pan par côté : { weight, normal (Vector3), up_dir (Vector3 horizontal, vers le haut
## de la pente), dir (Vector3 le long de l'égout), polys: Array[PackedVector3Array] }.
var faces: Array = []
## { a: Vector3, b: Vector3, kind: ArcKind, faces: PackedInt32Array }
var arcs: Array = []
## Vide ou { pos: Vector2, size: float, y0: float, y1: float }
var chimney := {}

var _tris: Array = []  # [Vector2 a, Vector2 b, Vector2 c, float ha, float hb, float hc]


func is_empty() -> bool:
	return faces.is_empty()


## Prépare la recherche de hauteur (appelé par le générateur).
func bake() -> void:
	_tris.clear()
	for f in faces:
		if f.weight <= 0.0:
			continue
		for poly: PackedVector3Array in f.polys:
			for i in range(1, poly.size() - 1):
				var a := poly[0]
				var b := poly[i]
				var c := poly[i + 1]
				_tris.append([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), a.y, b.y, c.y])


## Altitude du dessus du toit à la verticale de p (-INF en dehors du toit).
func height_at(p: Vector2) -> float:
	var best := -INF
	for t in _tris:
		var a: Vector2 = t[0]
		var b: Vector2 = t[1]
		var c: Vector2 = t[2]
		var v0 := b - a
		var v1 := c - a
		var den := v0.cross(v1)
		if absf(den) < 1e-10:
			continue
		var v2 := p - a
		var l1 := v2.cross(v1) / den
		var l2 := v0.cross(v2) / den
		var l0 := 1.0 - l1 - l2
		if l0 < -1e-5 or l1 < -1e-5 or l2 < -1e-5:
			continue
		best = maxf(best, l0 * t[3] + l1 * t[4] + l2 * t[5])
	return best


## Points 2D où le segment a-b traverse une arête de triangle du toit
## (paramètres dans [0, 1]) : le profil du toit est linéaire entre deux.
func crossings(a: Vector2, b: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0, 1.0])
	var d := b - a
	for t in _tris:
		for k in 3:
			var p: Vector2 = t[k]
			var q: Vector2 = t[(k + 1) % 3]
			var e := q - p
			var den := d.cross(e)
			if absf(den) < 1e-10:
				continue
			var s := (p - a).cross(e) / den
			var u := (p - a).cross(d) / den
			if s > 0.0 and s < 1.0 and u >= -1e-6 and u <= 1.0 + 1e-6:
				out.append(s)
	out.sort()
	return out
