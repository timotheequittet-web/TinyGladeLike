@tool
class_name BastideDistributor
extends RefCounted
## Répartit des éléments répétés « pile » sur une longueur (« toujours beau », famille 2).
##
## Jamais de demi-merlon coupé au bout d'un mur : on choisit un nombre entier
## d'éléments et on les étire légèrement (dans une tolérance) pour remplir exactement.


## Éléments séparés par des vides, avec un élément plein à chaque bout.
## Retourne { "count", "item", "gap", "stretch" } ; count = 0 si rien ne rentre.
static func fit_with_full_ends(length: float, item: float, gap: float, tolerance: float) -> Dictionary:
	if length < item * 0.6:
		return {"count": 0, "item": 0.0, "gap": 0.0, "stretch": 1.0}
	var best := {}
	var best_err := INF
	var guess := maxi(1, roundi((length + gap) / (item + gap)))
	for n in [guess - 1, guess, guess + 1]:
		if n < 1:
			continue
		var nominal: float = n * item + (n - 1) * gap
		var k := length / nominal
		var err := absf(k - 1.0)
		if err < best_err:
			best_err = err
			best = {"count": n, "item": item * k, "gap": gap * k, "stretch": k}
	# Hors tolérance : un seul élément étiré sur toute la longueur reste plus joli qu'un vide.
	if best_err > tolerance and best.count == 1:
		best = {"count": 1, "item": length, "gap": 0.0, "stretch": length / item}
	return best


## Motif périodique sur une boucle fermée : count × (item + gap) = length exactement.
static func fit_loop(length: float, item: float, gap: float) -> Dictionary:
	var n := maxi(1, roundi(length / (item + gap)))
	var k := length / (n * (item + gap))
	return {"count": n, "item": item * k, "gap": gap * k, "stretch": k}


## Découpe une longueur en morceaux de longueurs aléatoires bornées, dont la somme
## vaut exactement `length`. `first` force la longueur du premier morceau (≤ 0 : aléatoire).
static func split_lengths(seed: int, channel: String, index: int, length: float,
		min_len: float, max_len: float, first: float = -1.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if length <= 1e-4:
		return out
	var rng := BastideRng.derive(seed, channel, index)
	var acc := 0.0
	var i := 0
	while acc < length - 1e-4:
		var l := first if (i == 0 and first > 0.0) else rng.randf_range(min_len, max_len)
		var remaining := length - acc
		if remaining - l < min_len * 0.5:
			# Le reste serait un éclat de pierre : on l'absorbe.
			l = remaining
			if l > max_len * 1.4:
				l = remaining * 0.5
		out.append(l)
		acc += l
		i += 1
	return out
