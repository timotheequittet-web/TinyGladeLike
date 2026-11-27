@tool
class_name BastideGlow
extends RefCounted
## État des lumières du hameau, partagé par tous les matériaux qui luisent (papier
## des shoji et des lanternes, vitres le soir) et par les lumières des lanternes.
## Le cycle jour/nuit (BastideDayNight) le met à jour ; sans lui (`cycle` faux), les
## matériaux gardent leur énergie de jour et les lanternes restent allumées.
##
##  - `night` : 0 en plein jour, 1 en pleine nuit (obscurité) ;
##  - `lamps` : 0 lanternes éteintes, 1 allumées à fond (commence au crépuscule).

static var night := 0.0
static var lamps := 0.0
## Vrai quand un cycle jour/nuit pilote l'état.
static var cycle := false
## [WeakRef du matériau, énergie de jour, énergie de nuit]
static var _mats: Array = []


## Inscrit un matériau lumineux : son énergie d'émission suivra `lamps`, de
## `day_energy` (lanternes éteintes) à `night_energy` (pleine nuit).
static func register(m: BaseMaterial3D, day_energy: float, night_energy: float) -> void:
	if m == null:
		return
	for e: Array in _mats:
		if (e[0] as WeakRef).get_ref() == m:
			e[1] = day_energy
			e[2] = night_energy
			_apply(e)
			return
	var e := [weakref(m), day_energy, night_energy]
	_mats.append(e)
	_apply(e)


## Force des lanternes (lumières et halos) : 1 sans cycle jour/nuit.
static func lamp_strength() -> float:
	return lamps * (0.65 + 0.35 * night) if cycle else 1.0


## Nouvel état (appelé par le cycle jour/nuit). Ne touche aux matériaux que si
## l'état a assez changé pour se voir.
static func set_state(n: float, l: float) -> void:
	var changed := absf(l - lamps) > 0.002 or absf(n - night) > 0.002
	cycle = true
	night = clampf(n, 0.0, 1.0)
	lamps = clampf(l, 0.0, 1.0)
	if not changed:
		return
	var alive: Array = []
	for e: Array in _mats:
		if (e[0] as WeakRef).get_ref() != null:
			_apply(e)
			alive.append(e)
	_mats = alive


static func _apply(e: Array) -> void:
	var m := (e[0] as WeakRef).get_ref() as BaseMaterial3D
	if m:
		# Courbe douce : la lumière « prend » vite au crépuscule puis se renforce.
		var k := lamps * (0.6 + 0.4 * night)
		m.emission_energy_multiplier = lerpf(float(e[1]), float(e[2]), k)
