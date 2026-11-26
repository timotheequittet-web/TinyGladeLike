@tool
class_name BastideCrops
extends RefCounted
## Les plantes des cultures, en petits maillages partagés (une instance par pied) :
## chou, daikon, negi (poireau japonais), aubergine sur tuteur, tomate, potiron,
## et la touffe de riz repiquée. Couleurs dans les sommets (matériau feuillage :
## l'alpha règle la souplesse au vent).
##
## Fonctions pures, sur n'importe quel thread (cache protégé).

const KINDS := ["cabbage", "daikon", "negi", "eggplant", "tomato", "pumpkin"]
## Écart entre deux pieds sur la planche (m) et nombre de lignes par planche.
const SPACING := {"cabbage": 0.42, "daikon": 0.28, "negi": 0.16, "eggplant": 0.55, "tomato": 0.5, "pumpkin": 0.95}
const LINES := {"cabbage": 2, "daikon": 2, "negi": 2, "eggplant": 1, "tomato": 1, "pumpkin": 1}
## Poids de tirage d'une culture par planche.
const WEIGHT := {"cabbage": 0.22, "daikon": 0.2, "negi": 0.18, "eggplant": 0.14, "tomato": 0.13, "pumpkin": 0.13}

const ROLE := BastideGardenMesher.ROLE_FOLIAGE

static var _mutex := Mutex.new()
static var _cache := {}


## Maillage d'un pied (variante 0 à 2), sol à y = 0.
static func mesh(kind: String, variant := 0) -> ArrayMesh:
	var key := "%s/%d" % [kind, variant]
	_mutex.lock()
	var cached: Variant = _cache.get(key)
	_mutex.unlock()
	if cached != null:
		return cached
	var mb := BastideMeshBuilder.new()
	var k := BastideRng.combine(kind.hash(), variant + 1)
	match kind:
		"cabbage":
			_cabbage(mb, k)
		"daikon":
			_daikon(mb, k)
		"negi":
			_negi(mb, k)
		"eggplant":
			_eggplant(mb, k)
		"tomato":
			_tomato(mb, k)
		"pumpkin":
			_pumpkin(mb, k, variant)
		"rice":
			_rice(mb, k)
	var m := mb.commit({})
	_mutex.lock()
	_cache[key] = m
	_mutex.unlock()
	return m


## Culture tirée pour une planche.
static func pick(key: int) -> String:
	var r := BastideGardenMesher.h(key, 0)
	var acc := 0.0
	for c: String in KINDS:
		acc += float(WEIGHT[c])
		if r <= acc:
			return c
	return KINDS[0]


static func h(key: int, i: int) -> float:
	return BastideGardenMesher.h(key, i)


static func hs(key: int, i: int) -> float:
	return BastideGardenMesher.hs(key, i)


## Feuille en ruban courbé : part de `base` dans la direction `dir` (horizontale),
## se lève de `lift` (radians) puis retombe (`droop`). Visible des deux côtés.
static func leaf(mb: BastideMeshBuilder, base: Vector3, dir: Vector3, length: float, width: float, lift: float,
		droop: float, c0: Color, c1: Color, segs := 3, cup := 0.15) -> void:
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_c := c0
	for i in segs + 1:
		var t := float(i) / segs
		var x := length * t * cos(lift)
		var y := length * (sin(lift) * t - droop * t * t)
		var center := base + dir * x + Vector3.UP * y
		var w := width * 0.5 * sin(PI * minf(t * 0.85 + 0.15, 1.0))
		if i == segs:
			w = 0.0
		var l := center - side * w + Vector3.UP * w * cup
		var r := center + side * w + Vector3.UP * w * cup
		var col := c0.lerp(c1, t)
		col.a = clampf(t * 1.2, 0.0, 1.0)
		if i > 0:
			var nrm := (r - prev_l).cross(prev_r - prev_l).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			mb.add_tri_2s(ROLE, prev_l, prev_r, r, nrm, prev_c, prev_c, col)
			if w > 0.0:
				mb.add_tri_2s(ROLE, prev_l, r, l, nrm, prev_c, col, col)
		prev_l = l
		prev_r = r
		prev_c = col


static func _cabbage(mb: BastideMeshBuilder, k: int) -> void:
	# Pomme serrée, pâle, au milieu d'une rosette de grandes feuilles bleutées.
	BastideGardenMesher.blob(mb, ROLE, Vector3(0, 0.12, 0), Vector3(0.14, 0.12, 0.14), Color(0.66, 0.78, 0.48), k,
			5, 9, 0.25, 0.06, Color(0, 0, 0, 0), 0.2)
	var n := 7
	for i in n:
		var a := TAU * (i + h(k, i) * 0.4) / n
		var dir := Vector3(cos(a), 0, sin(a))
		leaf(mb, Vector3(0, 0.03, 0) + dir * 0.05, dir, 0.3 + h(k, 10 + i) * 0.06, 0.26, 0.75, 0.75,
				Color(0.4, 0.58, 0.42), Color(0.5, 0.66, 0.46), 3, 0.3)


static func _daikon(mb: BastideMeshBuilder, k: int) -> void:
	# Le collet blanc dépasse un peu de la terre ; longues feuilles découpées.
	BastideGardenMesher.tube(mb, ROLE, Vector3(0, -0.03, 0), Vector3(0, 0.08, 0), 0.045, 0.04, Color(0.9, 0.92, 0.84), 7, 0.0,
			Color(0.72, 0.84, 0.6))
	var n := 8
	for i in n:
		var a := TAU * (i + h(k, i) * 0.5) / n
		var dir := Vector3(cos(a), 0, sin(a))
		leaf(mb, Vector3(0, 0.07, 0) + dir * 0.02, dir, 0.34 + h(k, 20 + i) * 0.1, 0.075, 1.05, 0.55,
				Color(0.3, 0.48, 0.2), Color(0.4, 0.58, 0.24), 3, 0.1)


static func _negi(mb: BastideMeshBuilder, k: int) -> void:
	# Une touffe de tiges droites, blanches au pied, bleu-vert en haut.
	var n := 6
	for i in n:
		var a := TAU * (i + h(k, i)) / n
		var off := Vector3(cos(a), 0, sin(a)) * 0.025
		var tip := off * 3.5 + Vector3(hs(k, 30 + i) * 0.05, 0.46 + h(k, 40 + i) * 0.12, hs(k, 50 + i) * 0.05)
		var mid := off + Vector3(0, 0.06, 0)
		BastideGardenMesher.tube(mb, ROLE, off - Vector3(0, 0.02, 0), mid, 0.012, 0.011, Color(0.8, 0.84, 0.72), 5, 0.0, Color(0.6, 0.72, 0.55))
		var c := Color(0.36, 0.54, 0.4).lerp(Color(0.42, 0.6, 0.38), h(k, 60 + i))
		BastideGardenMesher.tube(mb, ROLE, mid, tip, 0.011, 0.003, c, 5, 0.8)


static func _eggplant(mb: BastideMeshBuilder, k: int) -> void:
	# Tuteur de bambou, tiges violacées, feuilles larges, aubergines pendantes.
	BastideGardenMesher.tube(mb, ROLE, Vector3(0.06, -0.05, 0), Vector3(0.06, 0.85, 0), 0.012, 0.01, Color(0.66, 0.6, 0.4), 5, 0.0)
	BastideGardenMesher.tube(mb, ROLE, Vector3(0, 0, 0), Vector3(0.02, 0.5, 0), 0.016, 0.01, Color(0.32, 0.24, 0.3), 5, 0.2)
	for i in 3:
		var y := 0.28 + i * 0.14
		var a := TAU * h(k, i)
		var c := Vector3(cos(a) * 0.08, y, sin(a) * 0.08)
		BastideGardenMesher.blob(mb, ROLE, c, Vector3(0.17, 0.1, 0.17) * (1.0 - i * 0.15), Color(0.25, 0.4, 0.21), k + i,
				4, 8, 0.4, 0.3, Color(0, 0, 0, 0), 0.7)
	for i in 3:
		var a := TAU * (h(k, 10 + i) + i / 3.0)
		var p := Vector3(cos(a) * 0.11, 0.22 + h(k, 20 + i) * 0.12, sin(a) * 0.11)
		BastideGardenMesher.blob(mb, ROLE, p, Vector3(0.035, 0.08, 0.035), Color(0.2, 0.07, 0.22), k + 30 + i,
				4, 7, 0.3, 0.0, Color(0, 0, 0, 0), 0.3)
		BastideGardenMesher.tube(mb, ROLE, p + Vector3(0, 0.07, 0), p + Vector3(0, 0.11, 0), 0.02, 0.008, Color(0.3, 0.42, 0.25), 5, 0.3)


static func _tomato(mb: BastideMeshBuilder, k: int) -> void:
	# Haut pied attaché à son tuteur, feuillage en grappes, tomates rouges et vertes.
	BastideGardenMesher.tube(mb, ROLE, Vector3(0, -0.05, 0.05), Vector3(0, 1.3, 0.05), 0.013, 0.011, Color(0.66, 0.6, 0.4), 5, 0.0)
	for i in 5:
		var y := 0.25 + i * 0.2
		var a := TAU * h(k, i)
		var c := Vector3(cos(a) * 0.07, y, sin(a) * 0.07)
		BastideGardenMesher.blob(mb, ROLE, c, Vector3(0.16, 0.12, 0.16) * (1.0 - i * 0.08), Color(0.28, 0.44, 0.22), k + i,
				4, 8, 0.4, 0.35, Color(0, 0, 0, 0), 0.7)
	for i in 7:
		var a := TAU * h(k, 20 + i)
		var p := Vector3(cos(a) * 0.13, 0.3 + h(k, 30 + i) * 0.75, sin(a) * 0.13)
		var ripe := h(k, 40 + i) < 0.6
		var col := Color(0.86, 0.2, 0.1) if ripe else Color(0.55, 0.68, 0.3)
		BastideGardenMesher.blob(mb, ROLE, p, Vector3.ONE * (0.033 + h(k, 50 + i) * 0.012), col, k + 60 + i,
				3, 6, 0.3, 0.0, Color(0, 0, 0, 0), 0.4)


static func _pumpkin(mb: BastideMeshBuilder, k: int, variant: int) -> void:
	# Grandes feuilles rondes au ras du sol et une courge (kabocha vert sombre ou orange).
	for i in 5:
		var a := TAU * (i + h(k, i) * 0.5) / 5.0
		var dir := Vector3(cos(a), 0, sin(a))
		leaf(mb, Vector3(0, 0.04, 0) + dir * 0.12, dir, 0.42, 0.36, 0.5, 0.45, Color(0.28, 0.45, 0.2), Color(0.36, 0.54, 0.24), 3, 0.25)
	var col := Color(0.86, 0.5, 0.16) if variant == 1 else Color(0.27, 0.34, 0.24)
	var p := Vector3(0.22, 0.1, -0.08)
	BastideGardenMesher.blob(mb, ROLE, p, Vector3(0.17, 0.11, 0.17), col, k + 9, 5, 10, 0.35, 0.08, Color(0, 0, 0, 0), 0.0)
	BastideGardenMesher.tube(mb, ROLE, p + Vector3(0, 0.1, 0), p + Vector3(0.02, 0.15, 0), 0.018, 0.012, Color(0.45, 0.42, 0.28), 5, 0.0)
	# Les tiges rampantes.
	for i in 2:
		var a := TAU * h(k, 70 + i)
		BastideGardenMesher.tube(mb, ROLE, Vector3(0, 0.03, 0), Vector3(cos(a) * 0.5, 0.02, sin(a) * 0.5), 0.012, 0.008,
				Color(0.32, 0.46, 0.22), 4, 0.3)


static func _rice(mb: BastideMeshBuilder, k: int) -> void:
	# Jeune touffe de riz repiquée : quelques brins fins, droits puis arqués.
	var n := 6
	for i in n:
		var a := TAU * (i + h(k, i) * 0.6) / n
		var dir := Vector3(cos(a), 0, sin(a))
		var c0 := Color(0.34, 0.56, 0.2)
		var c1 := Color(0.56, 0.72, 0.3).lerp(Color(0.66, 0.74, 0.34), h(k, 10 + i))
		leaf(mb, dir * 0.015, dir, 0.4 + h(k, 20 + i) * 0.16, 0.028, 1.32, 0.42, c0, c1, 2, 0.0)
