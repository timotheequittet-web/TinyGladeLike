@tool
class_name BastideRng
extends RefCounted
## Hasard déterministe et sans état.
##
## Chaque tirage dépend uniquement de (seed, canal, index). Deux appels avec les
## mêmes arguments donnent toujours le même résultat, sur toutes les machines.
## On peut donc modifier un bout de mur sans rebrasser le reste : chaque pierre
## tire ses valeurs à partir de sa propre position, pas d'un compteur global.

const _MASK := 0xFFFFFFFF
const _INV_MAX := 1.0 / 4294967295.0


## Mélange un entier sur 32 bits (fonction de hachage de type « lowbias32 »).
static func hash_int(x: int) -> int:
	x = x & _MASK
	x = (((x >> 16) ^ x) * 0x45d9f3b) & _MASK
	x = (((x >> 16) ^ x) * 0x45d9f3b) & _MASK
	return ((x >> 16) ^ x) & _MASK


## Combine deux entiers en un seul hachage.
static func combine(a: int, b: int) -> int:
	a = a & _MASK
	return hash_int(a ^ ((hash_int(b) + 0x9e3779b9 + ((a << 6) & _MASK) + (a >> 2)) & _MASK))


## Clé entière pour un tirage donné.
static func key(seed: int, channel: String, index: int = 0) -> int:
	return combine(combine(seed, channel.hash()), index)


## Flottant uniforme dans [0, 1].
static func randf_at(seed: int, channel: String, index: int = 0) -> float:
	return float(key(seed, channel, index)) * _INV_MAX


## Flottant dans [0, 1] tiré d'une clé déjà calculée : rapide pour plusieurs
## valeurs d'un même élément (clé + 0, clé + 1, …).
static func unit(k: int) -> float:
	return float(hash_int(k)) * _INV_MAX


## Flottant uniforme dans [lo, hi].
static func randf_range_at(seed: int, channel: String, index: int, lo: float, hi: float) -> float:
	return lerpf(lo, hi, randf_at(seed, channel, index))


## Flottant uniforme dans [-1, 1].
static func signed_at(seed: int, channel: String, index: int = 0) -> float:
	return randf_at(seed, channel, index) * 2.0 - 1.0


## Bruit de valeur 1D lissé, dans [0, 1]. Avec period > 0, le bruit boucle
## exactement tous les `period` unités (utile pour les murs fermés).
static func noise1(seed: int, channel: String, x: float, period: int = 0) -> float:
	var i := floori(x)
	var f := x - float(i)
	var ia := i
	var ib := i + 1
	if period > 0:
		ia = posmod(ia, period)
		ib = posmod(ib, period)
	var a := randf_at(seed, channel, ia)
	var b := randf_at(seed, channel, ib)
	var t := f * f * (3.0 - 2.0 * f)
	return lerpf(a, b, t)


## Générateur classique dérivé, pour une suite de tirages dans un même contexte.
static func derive(seed: int, channel: String, index: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = key(seed, channel, index)
	return rng
