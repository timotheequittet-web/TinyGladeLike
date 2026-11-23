extends SceneTree
## Tests headless du core de Bastide (aucun rendu nécessaire).
##
## Lancement, depuis la racine du projet :
##   godot --headless --path . -s tests/run_core_tests.gd
## Code de sortie 0 si tout passe, 1 sinon.

var _failures := 0
var _count := 0


func _init() -> void:
	_test_rng_determinism()
	_test_sanitizer()
	_test_distributor()
	_test_split_lengths()
	_test_open_wall()
	_test_closed_square()
	_test_smooth_loop()
	_test_sharp_spike()
	_test_seed_changes_wall()
	_test_degenerate_inputs()
	_test_performance()
	print("")
	print("%d vérifications, %d échec(s)" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, label: String) -> void:
	_count += 1
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  ÉCHEC ", label)


func _style() -> BastideStyle:
	return BastideStyle.create_default()


func _build(points: Array, closed: bool, seed := 7) -> Array:
	var spec := BastideWallSpec.from_points(PackedVector3Array(points), closed, seed)
	var layout := BastideWallGenerator.generate(spec, _style())
	var result := BastideWallMesher.build(layout, _style())
	return [layout, result]


func _test_rng_determinism() -> void:
	print("RNG")
	check(BastideRng.randf_at(42, "a", 3) == BastideRng.randf_at(42, "a", 3), "même entrée, même tirage")
	check(BastideRng.randf_at(42, "a", 3) != BastideRng.randf_at(43, "a", 3), "seed différente, tirage différent")
	var lo := 1.0
	var hi := 0.0
	for i in 2000:
		var v := BastideRng.randf_at(1, "range", i)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	check(lo >= 0.0 and hi <= 1.0 and lo < 0.01 and hi > 0.99, "tirages répartis dans [0, 1]")
	check(is_equal_approx(BastideRng.noise1(5, "n", 0.0, 4), BastideRng.noise1(5, "n", 4.0, 4)), "bruit périodique qui boucle")


func _test_sanitizer() -> void:
	print("Assainissement du tracé")
	var r := BastidePathSanitizer.sanitize(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0.05, 0, 0), Vector3(5, 0, 0), Vector3(5.1, 0, 0.02), Vector3(10, 0, 0)]), false, 0.3)
	check(r.points.size() == 3, "points trop proches fusionnés (%d points)" % r.points.size())
	check(r.points[r.points.size() - 1] == Vector3(10, 0, 0), "le vrai dernier point est conservé")
	var loop := BastidePathSanitizer.sanitize(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4), Vector3(0, 0, 0.01)]), true, 0.3)
	check(loop.points.size() == 4 and loop.closed, "point de fermeture en double retiré")
	var spike := BastidePathSanitizer.sanitize(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(0.5, 0, 0.1), Vector3(0.5, 0, 5)]), false, 0.3)
	check(spike.points.size() == 3, "épine (demi-tour) supprimée")
	var tiny := BastidePathSanitizer.sanitize(PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)]), true, 0.3)
	check(not tiny.closed, "boucle de 2 points dégradée en mur ouvert")


func _test_distributor() -> void:
	print("Répartition pile")
	for length in [3.7, 5.0, 8.33, 12.1, 21.4]:
		var f := BastideDistributor.fit_with_full_ends(length, 0.8, 0.55, 0.18)
		var total: float = f.count * f.item + (f.count - 1) * f.gap
		check(is_equal_approx(snappedf(total, 0.0001), snappedf(length, 0.0001)), "%.2f m rempli exactement par %d merlons" % [length, f.count])
		check(absf(f.stretch - 1.0) <= 0.18, "%.2f m : étirement %.2f dans la tolérance" % [length, f.stretch])
	var loop := BastideDistributor.fit_loop(31.4, 0.8, 0.55)
	check(is_equal_approx(loop.count * (loop.item + loop.gap), 31.4), "boucle fermée : motif périodique exact")
	check(BastideDistributor.fit_with_full_ends(0.3, 0.8, 0.55, 0.18).count == 0, "trop court : aucun merlon plutôt qu'un merlon écrasé")


func _test_split_lengths() -> void:
	print("Découpe des pierres")
	for i in 30:
		var length := 0.4 + i * 0.73
		var parts := BastideDistributor.split_lengths(3, "t", i, length, 0.45, 0.95)
		var sum := 0.0
		var min_part := INF
		for p in parts:
			sum += p
			min_part = minf(min_part, p)
		if not is_equal_approx(snappedf(sum, 0.0001), snappedf(length, 0.0001)) or (parts.size() > 1 and min_part < 0.45 * 0.5 - 1e-4):
			check(false, "découpe de %.2f m (somme %.3f, plus petit %.3f)" % [length, sum, min_part])
			return
	check(true, "30 longueurs découpées exactement, sans éclat de pierre")


func _test_open_wall() -> void:
	print("Mur ouvert en L")
	var out := _build([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 8)], false)
	var layout: BastideWallLayout = out[0]
	var result: BastideBuildResult = out[1]
	check(layout.runs.size() == 2, "deux tronçons de part et d'autre de l'angle")
	check(layout.pillars.size() == 3, "piliers aux deux bouts et dans l'angle droit (%d)" % layout.pillars.size())
	check(layout.stones.size() > 100, "pierres posées (%d)" % layout.stones.size())
	check(layout.merlons.size() >= 10, "merlons posés (%d)" % layout.merlons.size())
	check(not result.is_empty(), "mesh généré (%d triangles)" % result.stats.triangles)
	check(result.collision_faces.size() > 0 and result.collision_faces.size() % 3 == 0, "collisions générées")
	var top := 0.0
	for st in layout.stones:
		top = maxf(top, maxf(st.y1a, st.y1b))
	check(top <= layout.height + layout.top_amplitude + 0.03, "aucune pierre au-dessus du sommet")


func _test_closed_square() -> void:
	print("Enceinte carrée fermée")
	var out := _build([Vector3(0, 0, 0), Vector3(12, 0, 0), Vector3(12, 0, 12), Vector3(0, 0, 12)], true)
	var layout: BastideWallLayout = out[0]
	check(layout.runs.size() == 4, "quatre côtés")
	check(layout.pillars.size() == 4, "un pilier par angle droit")
	check(is_equal_approx(snappedf(layout.length, 0.001), 48.0), "périmètre de 48 m")


func _test_smooth_loop() -> void:
	print("Boucle ronde sans angle")
	var pts: Array = []
	for i in 48:
		var a := TAU * i / 48.0
		pts.append(Vector3(cos(a) * 8.0, 0, sin(a) * 8.0))
	var out := _build(pts, true)
	var layout: BastideWallLayout = out[0]
	check(layout.runs.size() == 1 and layout.runs[0].start_kind == BastideWallLayout.EndKind.LOOP, "un seul tronçon bouclé")
	check(layout.pillars.is_empty(), "aucun pilier sur une courbe douce")
	check(absf(layout.height_at(0.0) - layout.height_at(layout.length)) < 1e-4, "le sommet irrégulier se referme sans saut")
	var first: Dictionary = layout.merlons[0]
	var last: Dictionary = layout.merlons[layout.merlons.size() - 1]
	var gap_end: float = layout.length - last.s1 + first.s0
	check(gap_end > 0.3, "créneaux réguliers jusqu'au raccord (créneau de %.2f m)" % gap_end)


func _test_sharp_spike() -> void:
	print("Angle très aigu")
	var out := _build([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 0, 2)], false)
	var layout: BastideWallLayout = out[0]
	var pillared := false
	for c in layout.corners:
		pillared = pillared or c.pillar
	check(pillared, "un pilier masque l'angle aigu")


func _test_seed_changes_wall() -> void:
	print("Seed")
	var pts := [Vector3(0, 0, 0), Vector3(15, 0, 0)]
	var a: BastideWallLayout = _build(pts, false, 1)[0]
	var a2: BastideWallLayout = _build(pts, false, 1)[0]
	var b: BastideWallLayout = _build(pts, false, 2)[0]
	check(a.stones.size() == a2.stones.size() and a.stones[10].s0 == a2.stones[10].s0, "même seed, même mur")
	check(a.stones[10].s0 != b.stones[10].s0 or a.height_at(3.0) != b.height_at(3.0), "seed différente, mur différent")
	# Prolonger le mur ne doit pas rebrasser le début.
	var longer: BastideWallLayout = _build([Vector3(0, 0, 0), Vector3(25, 0, 0)], false, 1)[0]
	check(is_equal_approx(a.height_at(4.0), longer.height_at(4.0)), "prolonger le mur ne change pas le sommet existant")


func _test_degenerate_inputs() -> void:
	print("Entrées dégénérées")
	check(BastideWallGenerator.generate(BastideWallSpec.new(), _style()).is_empty(), "tracé vide : rien, sans erreur")
	var one: BastideWallLayout = _build([Vector3(1, 0, 1)], false)[0]
	check(one.is_empty(), "un seul point : rien")
	var same: BastideWallLayout = _build([Vector3(1, 0, 1), Vector3(1, 0, 1.05)], false)[0]
	check(same.is_empty(), "deux points confondus : rien")
	var short: Array = _build([Vector3(0, 0, 0), Vector3(0.6, 0, 0)], false)
	check(not (short[1] as BastideBuildResult).is_empty(), "mur très court : au moins des piliers")


func _test_performance() -> void:
	print("Performances")
	var pts := []
	for i in 9:
		pts.append(Vector3(i * 5.0, 0, sin(i * 0.9) * 3.0))
	var t0 := Time.get_ticks_usec()
	var out := _build(pts, false)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var layout: BastideWallLayout = out[0]
	print("     mur de %.1f m : %.1f ms, %d triangles" % [layout.length, ms, (out[1] as BastideBuildResult).stats.triangles])
	check(ms < 400.0, "génération d'un mur de 40 m en moins de 400 ms en headless")
