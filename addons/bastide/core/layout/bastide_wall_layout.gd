@tool
class_name BastideWallLayout
extends RefCounted
## Plan sémantique d'un mur : le pivot entre « quoi construire » et « comment le dessiner ».
##
## Il décrit des tronçons (runs) entre deux angles nets, des piliers, des assises de
## pierres, des dalles de chaperon et des merlons, sans contenir aucun triangle.
## Le backend procédural le transforme en mesh ; le futur backend kit y placera des pièces.

enum EndKind { OPEN, CORNER, PILLAR, LOOP }


## Un tronçon de mur entre deux extrémités (bout, angle, pilier) avec ses stations.
class Run:
	var index := 0
	## Abscisses curvilignes (globales, le long du tracé) de début et de fin.
	var s0 := 0.0
	var s1 := 0.0
	var start_kind := EndKind.OPEN
	var end_kind := EndKind.OPEN
	## Stations : abscisse, position du pied (axe du mur) et décalage latéral par mètre de demi-épaisseur.
	var s := PackedFloat32Array()
	var pos := PackedVector3Array()
	var off := PackedVector3Array()

	func length() -> float:
		return s1 - s0

	func _segment(sv: float) -> int:
		var lo := 0
		var hi := s.size() - 2
		while lo < hi:
			var mid := (lo + hi + 1) >> 1
			if s[mid] <= sv:
				lo = mid
			else:
				hi = mid - 1
		return lo

	func _t(i: int, sv: float) -> float:
		var d := s[i + 1] - s[i]
		return clampf((sv - s[i]) / d, 0.0, 1.0) if d > 1e-6 else 0.0

	func pos_at(sv: float) -> Vector3:
		var i := _segment(sv)
		return pos[i].lerp(pos[i + 1], _t(i, sv))

	func off_at(sv: float) -> Vector3:
		var i := _segment(sv)
		return off[i].lerp(off[i + 1], _t(i, sv))

	func dir_at(sv: float) -> Vector3:
		var i := _segment(sv)
		return BastidePolyline.flat_dir(pos[i], pos[i + 1])


var closed := false
var seed := 0
## Longueur totale du tracé (à plat).
var length := 0.0
## Hauteur nominale et paramètres du sommet irrégulier.
var height := 3.0
var top_amplitude := 0.0
var top_wavelength := 5.0
## Pour une boucle : nombre de cellules de bruit sur le tour (le sommet boucle sans saut).
var noise_period := 0
## Demi-épaisseurs au sommet et au pied (fruit).
var half_top := 0.45
var half_base := 0.5
## Altitude relative de la première assise (sous le sol, pour cacher le raccord).
var footing := -0.25

var runs: Array = []          # Array[Run]
var corners: Array = []       # { pos, s, angle_deg, pillar }
var pillars: Array = []       # { pos, dir, width, top, s }
var courses := PackedFloat32Array()  # limites d'assises (y relatif)
var stones: Array = []        # { run, side, s0, s1, y0, y1a, y1b, quoin, tint, alt, bulge }
var coping: Array = []        # { run, s0, s1, dy, thickness }
var merlons: Array = []       # { run, s0, s1, height, depth }

var coping_thickness := 0.16
var coping_overhang := 0.07


func is_empty() -> bool:
	return runs.is_empty() and pillars.is_empty()


const HEIGHT_STEP := 0.1
var _height_table := PackedFloat32Array()


## Précalcule le profil du sommet (appelé une fois par le générateur) : height_at
## devient une simple interpolation dans une table.
func bake_heights() -> void:
	_height_table = PackedFloat32Array()
	var count := ceili(length / HEIGHT_STEP) + 2
	_height_table.resize(count)
	for i in count:
		_height_table[i] = _height_exact(i * HEIGHT_STEP)


## Hauteur du sommet du mur (au-dessus du pied) à l'abscisse s. Continue sur tout le tracé.
func height_at(sv: float) -> float:
	if _height_table.is_empty():
		return _height_exact(sv)
	if closed:
		sv = fposmod(sv, length)
	var x := clampf(sv / HEIGHT_STEP, 0.0, _height_table.size() - 1.001)
	var i := int(x)
	return lerpf(_height_table[i], _height_table[i + 1], x - i)


func _height_exact(sv: float) -> float:
	if top_amplitude <= 0.0:
		return height
	var x: float
	if noise_period > 0:
		x = sv / length * noise_period
	else:
		x = sv / top_wavelength
	var n := BastideRng.noise1(seed, "top", x, noise_period) * 0.75 \
		+ BastideRng.noise1(seed, "top_fine", x * 3.0, noise_period * 3 if noise_period > 0 else 0) * 0.25
	return height + (n - 0.5) * 2.0 * top_amplitude


## Demi-épaisseur à la hauteur y (relative au pied).
func half_thickness_at(y: float) -> float:
	return lerpf(half_base, half_top, clampf(y / maxf(height, 0.01), 0.0, 1.0))


## Point sur une face du mur : side = +1 (droite du tracé) ou -1 (gauche).
func face_point(run: Run, sv: float, y: float, side: float, extra := 0.0) -> Vector3:
	return run.pos_at(sv) + run.off_at(sv) * (half_thickness_at(y) + extra) * side + Vector3(0.0, y, 0.0)


## Point latéral à une demi-largeur donnée (chaperon, merlons).
func lateral_point(run: Run, sv: float, y: float, half_width: float) -> Vector3:
	return run.pos_at(sv) + run.off_at(sv) * half_width + Vector3(0.0, y, 0.0)
