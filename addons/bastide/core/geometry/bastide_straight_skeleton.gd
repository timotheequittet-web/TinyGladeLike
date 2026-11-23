@tool
class_name BastideStraightSkeleton
extends RefCounted
## Squelette droit pondéré d'un polygone simple (sans trou), par simulation du front.
##
## Chaque arête du polygone avance vers l'intérieur à la vitesse de son poids
## (1 = pan de toit normal, 0 = pignon vertical). Le temps écoulé donne la hauteur
## du toit : un point atteint au temps t est à la hauteur t × tan(pente).
##
## Deux sortes d'événements font évoluer le front :
## - arête qui disparaît (ses deux sommets se rejoignent) : faîtage, arêtier ;
## - sommet rentrant qui percute une arête opposée : le front se coupe en deux
##   (c'est ce qui fait marcher les formes en L, en U, en T…).
## Les cas simultanés (formes symétriques) se règlent un par un à dt = 0, et les
## morceaux de front devenus plats (aire nulle) sont fermés en faîtages.
##
## Résultat : pour chaque arête, des bandes (trapèzes) balayées entre deux
## événements, qui pavent exactement le polygone, et les arcs du squelette
## (faîtages, arêtiers, noues, rives). Les points 3D sont Vector3(x, t, z).

const TIME_TOL := 1e-6
const AREA_EPS := 1e-5


class Vtx:
	var p: Vector2
	var t0 := 0.0
	var v := Vector2.ZERO
	var ein := 0
	var eout := 0
	var birth := Vector3.ZERO

	func at(t: float) -> Vector2:
		return p + v * (t - t0)


class Result:
	var ok := false
	var error := ""
	## Pour chaque arête : Array de PackedVector3Array (bandes convexes, sens du polygone).
	var strips: Array = []
	## { "a": Vector3, "b": Vector3, "faces": PackedInt32Array } (une ou deux faces voisines)
	var arcs: Array = []
	var max_time := 0.0
	var events := 0


var _poly := PackedVector2Array()
var _dirs := PackedVector2Array()
var _nrm := PackedVector2Array()
var _c := PackedFloat32Array()
var _w := PackedFloat32Array()
var _fronts: Array = []  # Array[Array[Vtx]]
var _res: Result
var _arc_keys := {}


## `poly` doit être direct (aire > 0), sans sommets confondus ni alignés.
## `weights` : un poids par arête (vide = tous à 1).
static func compute(poly: PackedVector2Array, weights := PackedFloat32Array()) -> Result:
	var sk := BastideStraightSkeleton.new()
	return sk._run(poly, weights)


func _run(poly: PackedVector2Array, weights: PackedFloat32Array) -> Result:
	_res = Result.new()
	var n := poly.size()
	_res.strips.resize(n)
	for i in n:
		_res.strips[i] = []
	if n < 3 or BastidePolygon.signed_area(poly) <= 0.0:
		_res.error = "polygone invalide"
		return _res
	_poly = poly
	for i in n:
		var d := (poly[(i + 1) % n] - poly[i]).normalized()
		var nr := Vector2(-d.y, d.x)
		_dirs.append(d)
		_nrm.append(nr)
		_c.append(nr.dot(poly[i]))
		_w.append(weights[i] if i < weights.size() else 1.0)

	var front: Array = []
	for i in n:
		var vx := Vtx.new()
		vx.p = poly[i]
		vx.ein = posmod(i - 1, n)
		vx.eout = i
		vx.v = _velocity(vx.ein, vx.eout)
		vx.birth = Vector3(vx.p.x, 0.0, vx.p.y)
		front.append(vx)
	_fronts = [front]

	var t := 0.0
	var guard := 0
	var max_iter := 40 + n * n * 4
	_cleanup(t)
	while not _fronts.is_empty():
		guard += 1
		if guard > max_iter:
			_res.error = "trop d'événements"
			return _res
		var ev := _next_event(t)
		if ev.is_empty():
			_res.error = "front bloqué"
			return _res
		var tn: float = t + ev.dt
		_sweep(t, tn)
		t = tn
		if ev.type == 0:
			_edge_event(ev.front, ev.i, t)
		else:
			_split_event(ev.front, ev.i, ev.j, t)
		_res.events += 1
		_cleanup(t)
	_res.max_time = t
	_res.ok = _validate(poly)
	return _res


## Vitesse d'un sommet entre deux arêtes : n_in·v = w_in et n_out·v = w_out.
func _velocity(ein: int, eout: int) -> Vector2:
	var n1 := _nrm[ein]
	var n2 := _nrm[eout]
	var w1 := _w[ein]
	var w2 := _w[eout]
	var det := n1.x * n2.y - n1.y * n2.x
	if absf(det) < 1e-9:
		if n1.dot(n2) > 0.0:
			return n1 * (w1 + w2) * 0.5
		return Vector2.ZERO  # arêtes opposées : front plat, fermé au nettoyage
	return Vector2((w1 * n2.y - w2 * n1.y) / det, (n1.x * w2 - n2.x * w1) / det)


func _is_reflex(vx: Vtx) -> bool:
	return _dirs[vx.ein].cross(_dirs[vx.eout]) < -1e-9


## Prochain événement : { dt, type (0 = arête, 1 = coupure), front, i, j }.
## À temps égal, les disparitions d'arêtes passent avant les coupures.
func _next_event(t: float) -> Dictionary:
	var best_edge := {}
	var be := INF
	var best_split := {}
	var bs := INF
	for fi in _fronts.size():
		var f: Array = _fronts[fi]
		var m := f.size()
		# Arêtes qui rétrécissent jusqu'à zéro.
		for i in m:
			var a: Vtx = f[i]
			var b: Vtx = f[(i + 1) % m]
			var d := _dirs[a.eout]
			var length := (b.at(t) - a.at(t)).dot(d)
			var rate := (b.v - a.v).dot(d)
			var dt := INF
			if length <= 1e-7:
				dt = 0.0
			elif rate < -1e-12:
				dt = -length / rate
			if dt < be:
				be = dt
				best_edge = {"dt": dt, "type": 0, "front": fi, "i": i}
		# Sommets rentrants qui percutent une arête.
		for i in m:
			var vx: Vtx = f[i]
			if not _is_reflex(vx):
				continue
			var pv := vx.at(t)
			for j in m:
				var a: Vtx = f[j]
				var b: Vtx = f[(j + 1) % m]
				if a == vx or b == vx:
					continue
				var e := a.eout
				if e == vx.ein or e == vx.eout:
					continue
				var nr := _nrm[e]
				var gap0 := nr.dot(pv) - _c[e] - _w[e] * t
				var slope := nr.dot(vx.v) - _w[e]
				if slope > -1e-12 or gap0 < -1e-6:
					continue
				var dt := maxf(gap0, 0.0) / -slope
				if dt >= bs:
					continue
				var th := t + dt
				var h := vx.at(th)
				var pa := a.at(th)
				var d := _dirs[e]
				var seg := (b.at(th) - pa).dot(d)
				var u := (h - pa).dot(d)
				if seg < -1e-6 or u < -1e-5 or u > seg + 1e-5:
					continue
				bs = dt
				best_split = {"dt": dt, "type": 1, "front": fi, "i": i, "j": j}
	if be == INF and bs == INF:
		return {}
	if be <= bs + TIME_TOL:
		return best_edge
	return best_split


## Enregistre les bandes balayées entre t0 et t1 et ramène tous les sommets à t1.
func _sweep(t0: float, t1: float) -> void:
	for f in _fronts:
		var m: int = f.size()
		if t1 > t0 + 1e-9:
			for i in m:
				var a: Vtx = f[i]
				var b: Vtx = f[(i + 1) % m]
				var a0 := a.at(t0)
				var b0 := b.at(t0)
				var a1 := a.at(t1)
				var b1 := b.at(t1)
				var strip := PackedVector3Array()
				strip.append(Vector3(a0.x, t0, a0.y))
				strip.append(Vector3(b0.x, t0, b0.y))
				if b1.distance_squared_to(a1) > 1e-12:
					strip.append(Vector3(b1.x, t1, b1.y))
				strip.append(Vector3(a1.x, t1, a1.y))
				(_res.strips[a.eout] as Array).append(strip)
		for vx: Vtx in f:
			vx.p = vx.at(t1)
			vx.t0 = t1


func _p3(vx: Vtx, t: float) -> Vector3:
	return Vector3(vx.p.x, t, vx.p.y)


func _add_arc(a: Vector3, b: Vector3, faces: PackedInt32Array) -> void:
	if a.distance_squared_to(b) < 1e-8:
		return
	# Un même segment peut être fermé des deux côtés d'un front plat : on fusionne.
	var ka := "%.3f,%.3f,%.3f" % [a.x, a.y, a.z]
	var kb := "%.3f,%.3f,%.3f" % [b.x, b.y, b.z]
	var key := ka + "|" + kb if ka < kb else kb + "|" + ka
	if _arc_keys.has(key):
		var arc: Dictionary = _res.arcs[_arc_keys[key]]
		var merged: PackedInt32Array = arc.faces
		for fc in faces:
			if not merged.has(fc):
				merged.append(fc)
		arc.faces = merged
		return
	_arc_keys[key] = _res.arcs.size()
	_res.arcs.append({"a": a, "b": b, "faces": faces})


func _end_vertex(vx: Vtx, t: float) -> void:
	_add_arc(vx.birth, _p3(vx, t), PackedInt32Array([vx.ein, vx.eout]))


func _new_vertex(p: Vector2, ein: int, eout: int, t: float) -> Vtx:
	var vx := Vtx.new()
	vx.p = p
	vx.t0 = t
	vx.ein = ein
	vx.eout = eout
	vx.v = _velocity(ein, eout)
	vx.birth = Vector3(p.x, t, p.y)
	return vx


func _edge_event(fi: int, i: int, t: float) -> void:
	var f: Array = _fronts[fi]
	var m := f.size()
	var a: Vtx = f[i]
	var j := (i + 1) % m
	var b: Vtx = f[j]
	_end_vertex(a, t)
	_end_vertex(b, t)
	var nv := _new_vertex((a.p + b.p) * 0.5, a.ein, b.eout, t)
	f[i] = nv
	f.remove_at(j)


func _split_event(fi: int, i: int, j: int, t: float) -> void:
	var f: Array = _fronts[fi]
	var m := f.size()
	var vx: Vtx = f[i]
	var e: int = (f[j] as Vtx).eout
	_end_vertex(vx, t)
	var v1 := _new_vertex(vx.p, vx.ein, e, t)
	var v2 := _new_vertex(vx.p, e, vx.eout, t)
	var fa: Array = [v1]
	var k := (j + 1) % m
	while k != i:
		fa.append(f[k])
		k = (k + 1) % m
	var fb: Array = [v2]
	k = (i + 1) % m
	while k != (j + 1) % m:
		fb.append(f[k])
		k = (k + 1) % m
	_fronts[fi] = fa
	_fronts.append(fb)


## Ferme les fronts devenus plats ou trop petits : leurs bords deviennent des faîtages.
func _cleanup(t: float) -> void:
	var fi := 0
	while fi < _fronts.size():
		var f: Array = _fronts[fi]
		var pts := PackedVector2Array()
		for vx: Vtx in f:
			pts.append(vx.p)
		if f.size() >= 3 and absf(BastidePolygon.signed_area(pts)) > AREA_EPS:
			fi += 1
			continue
		for vx: Vtx in f:
			_end_vertex(vx, t)
		var m := f.size()
		if m >= 2:
			for i in m:
				var a: Vtx = f[i]
				var b: Vtx = f[(i + 1) % m]
				_add_arc(_p3(a, t), _p3(b, t), PackedInt32Array([a.eout]))
		_fronts.remove_at(fi)


## Les bandes doivent paver exactement le polygone : on compare les aires.
func _validate(poly: PackedVector2Array) -> bool:
	var target := BastidePolygon.signed_area(poly)
	var sum := 0.0
	for e in _res.strips.size():
		for s: PackedVector3Array in _res.strips[e]:
			var flat := PackedVector2Array()
			for p in s:
				if not is_finite(p.x) or not is_finite(p.y) or not is_finite(p.z):
					_res.error = "valeur non finie"
					return false
				flat.append(Vector2(p.x, p.z))
			sum += BastidePolygon.signed_area(flat)
	if absf(sum - target) > maxf(target * 0.005, 1e-3):
		_res.error = "pavage incomplet (%.3f au lieu de %.3f)" % [sum, target]
		return false
	return true
