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
	# Étape 2 : bâtiments et toits.
	_test_polygon()
	_test_skeleton_shapes()
	_test_skeleton_random()
	_test_footprint_sanitizer()
	_test_gables()
	_test_roof_heights()
	_test_building_openings()
	_test_building_determinism()
	_test_building_degenerate()
	_test_building_performance()
	# Étape 3 : styles.
	_test_presets()
	_test_irimoya()
	_test_japanese_building()
	_test_japanese_wall()
	_test_style_switch()
	_test_triangle_budget()
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



# --- Étape 2 ---------------------------------------------------------------------------

func _poly(points: Array) -> PackedVector2Array:
	return PackedVector2Array(points)


const RECT := [Vector2(0, 0), Vector2(10, 0), Vector2(10, 6), Vector2(0, 6)]
const SQUARE := [Vector2(0, 0), Vector2(8, 0), Vector2(8, 8), Vector2(0, 8)]
const L_SHAPE := [Vector2(0, 0), Vector2(12, 0), Vector2(12, 5), Vector2(5, 5), Vector2(5, 10), Vector2(0, 10)]
const U_SHAPE := [Vector2(0, 0), Vector2(14, 0), Vector2(14, 10), Vector2(9, 10), Vector2(9, 5), Vector2(5, 5),
	Vector2(5, 10), Vector2(0, 10)]
const T_SHAPE := [Vector2(0, 0), Vector2(14, 0), Vector2(14, 5), Vector2(9.5, 5), Vector2(9.5, 12), Vector2(4.5, 12),
	Vector2(4.5, 5), Vector2(0, 5)]
const PLUS := [Vector2(5, 0), Vector2(10, 0), Vector2(10, 5), Vector2(15, 5), Vector2(15, 10), Vector2(10, 10),
	Vector2(10, 15), Vector2(5, 15), Vector2(5, 10), Vector2(0, 10), Vector2(0, 5), Vector2(5, 5)]
const PENTAGON := [Vector2(0, 0), Vector2(9, -1), Vector2(11, 6), Vector2(4, 9), Vector2(-2, 5)]


func _test_polygon() -> void:
	print("Polygones")
	var cw := _poly(RECT.duplicate())
	cw.reverse()
	check(BastidePolygon.signed_area(cw) < 0.0 and BastidePolygon.signed_area(BastidePolygon.ensure_direct(cw)) > 0.0, "remise dans le sens direct")
	var inner := BastidePolygon.offset(_poly(RECT), 1.0)
	check(is_equal_approx(BastidePolygon.signed_area(inner), 8.0 * 4.0), "décalage vers l'intérieur d'1 m")
	var outer := BastidePolygon.offset(_poly(L_SHAPE), -0.5)
	check(BastidePolygon.signed_area(outer) > BastidePolygon.signed_area(_poly(L_SHAPE)), "décalage vers l'extérieur (débord)")
	check(not BastidePolygon.is_convex_vertex(_poly(L_SHAPE), 3), "angle rentrant du L détecté")


func _test_skeleton_shapes() -> void:
	print("Squelette droit")
	var r := BastideStraightSkeleton.compute(_poly(RECT))
	check(r.ok and is_equal_approx(r.max_time, 3.0), "rectangle 10 × 6 : faîtage à mi-largeur (t = %.2f)" % r.max_time)
	var ridge := false
	for arc in r.arcs:
		if absf(arc.a.y - 3.0) < 1e-4 and absf(arc.b.y - 3.0) < 1e-4:
			ridge = is_equal_approx(Vector2(arc.a.x, arc.a.z).distance_to(Vector2(arc.b.x, arc.b.z)), 4.0)
	check(ridge, "rectangle : faîtage de 4 m (10 - 6) entre les deux croupes")
	var sq := BastideStraightSkeleton.compute(_poly(SQUARE))
	check(sq.ok and sq.arcs.size() == 4 and is_equal_approx(sq.max_time, 4.0), "carré : pyramide à quatre arêtiers")
	for name in ["L", "U", "T", "croix", "pentagone"]:
		var shape: Array = {"L": L_SHAPE, "U": U_SHAPE, "T": T_SHAPE, "croix": PLUS, "pentagone": PENTAGON}[name]
		var res := BastideStraightSkeleton.compute(_poly(shape))
		check(res.ok, "forme %s : pans qui pavent exactement le contour %s" % [name, res.error])
	var w := PackedFloat32Array([1, 0, 1, 0])
	var g := BastideStraightSkeleton.compute(_poly(RECT), w)
	var through := false
	for arc in g.arcs:
		if absf(arc.a.y - 3.0) < 1e-4 and absf(arc.b.y - 3.0) < 1e-4:
			through = is_equal_approx(absf(arc.a.x - arc.b.x), 10.0)
	check(g.ok and through, "pignons : le faîtage court d'un pignon à l'autre")


static func _ortho_poly(seed: int, cell: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cells := {Vector2i(2, 2): true}
	var target := rng.randi_range(2, 12)
	for tries in 200:
		if cells.size() >= target:
			break
		var keys := cells.keys()
		var c: Vector2i = keys[rng.randi() % keys.size()]
		var nc: Vector2i = c + [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][rng.randi() % 4]
		if nc.x >= 0 and nc.y >= 0 and nc.x < 6 and nc.y < 6:
			cells[nc] = true
	var edges := {}
	for c: Vector2i in cells:
		var p := [c, c + Vector2i(1, 0), c + Vector2i(1, 1), c + Vector2i(0, 1)]
		for i in 4:
			var a: Vector2i = p[i]
			var b: Vector2i = p[(i + 1) % 4]
			if edges.has([b, a]):
				edges.erase([b, a])
			else:
				edges[[a, b]] = true
	var nxt := {}
	for e in edges:
		if nxt.has(e[0]):
			return PackedVector2Array()
		nxt[e[0]] = e[1]
	var start: Vector2i = edges.keys()[0][0]
	var loop := [start]
	var cur: Vector2i = nxt[start]
	while cur != start and loop.size() < 1000:
		loop.append(cur)
		cur = nxt[cur]
	if loop.size() != edges.size():
		return PackedVector2Array()  # trou ou plusieurs boucles
	var pts := PackedVector2Array()
	for i in loop.size():
		var a: Vector2i = loop[posmod(i - 1, loop.size())]
		var b: Vector2i = loop[i]
		var c: Vector2i = loop[(i + 1) % loop.size()]
		if (b - a) != (c - b):
			pts.append(Vector2(b) * cell)
	return BastidePolygon.ensure_direct(pts)


func _test_skeleton_random() -> void:
	print("Squelette droit : contours aléatoires")
	var count := 0
	var fails := 0
	for it in 600:
		var poly := _ortho_poly(it, 4.0)
		if poly.size() < 4:
			continue
		count += 1
		if not BastideStraightSkeleton.compute(poly).ok:
			fails += 1
		if not BastideStraightSkeleton.compute(poly, BastideRoofGenerator.gable_weights(poly)).ok:
			fails += 1
	check(fails == 0, "%d contours orthogonaux aléatoires (L, U, T, escaliers…), avec et sans pignons : %d échec(s)" % [count, fails])
	var rng := RandomNumberGenerator.new()
	fails = 0
	for it in 300:
		rng.seed = 1000 + it
		var n := rng.randi_range(3, 14)
		var poly := PackedVector2Array()
		for i in n:
			var a := TAU * i / n + rng.randf_range(-0.2, 0.2)
			poly.append(Vector2(cos(a), sin(a)) * rng.randf_range(4.0, 12.0))
		if not BastideStraightSkeleton.compute(poly).ok:
			fails += 1
	check(fails == 0, "300 contours irréguliers en étoile : %d échec(s)" % fails)


func _test_footprint_sanitizer() -> void:
	print("Assainissement du contour")
	# Un L tracé à la main, un peu de travers et dans le mauvais sens.
	var sloppy := _poly([Vector2(0, 0), Vector2(0.2, 10), Vector2(5.1, 9.8), Vector2(5, 5.2), Vector2(12, 4.9),
		Vector2(11.8, 0.1), Vector2(6, 0.05)])
	var r := BastideFootprintSanitizer.sanitize(sloppy, 1.2, true, 18.0)
	var pts: PackedVector2Array = r.points
	check(r.squared and pts.size() == 6, "L redressé : 6 angles (point aligné retiré)")
	var right := true
	for i in pts.size():
		right = right and absf(rad_to_deg(BastidePolygon.turn_angle(pts, i)) - 90.0) < 0.01
	check(right, "tous les angles sont droits")
	check(BastidePolygon.signed_area(pts) > 0.0, "contour remis dans le sens direct")
	var irregular := BastideFootprintSanitizer.sanitize(_poly(PENTAGON), 1.2, true, 18.0)
	check(not irregular.squared and irregular.points.size() == 5, "contour franchement irrégulier laissé tel quel")
	var bow := BastideFootprintSanitizer.sanitize(_poly([Vector2(0, 0), Vector2(8, 6), Vector2(8, 0), Vector2(0, 6)]), 1.2, true, 18.0)
	check(bow.points.size() >= 3 and not BastidePolygon.self_intersects(bow.points), "contour croisé remplacé par un contour valide")
	var dup := BastideFootprintSanitizer.sanitize(_poly([Vector2(0, 0), Vector2(0.1, 0), Vector2(8, 0), Vector2(8, 6), Vector2(0, 6)]), 1.2, true, 18.0)
	check(dup.points.size() == 4, "points doublés fusionnés")


func _test_gables() -> void:
	print("Pignons")
	var w := BastideRoofGenerator.gable_weights(_poly(RECT))
	check(w == PackedFloat32Array([1, 0, 1, 0]), "rectangle : pignons sur les petits côtés")
	check(not BastideRoofGenerator.gable_weights(_poly(SQUARE)).has(0.0), "carré : pas de pignon (toit en pavillon)")
	var wl := BastideRoofGenerator.gable_weights(_poly(L_SHAPE))
	check(wl[1] == 0.0 and wl[4] == 0.0 and wl.count(0.0) == 2, "L : un pignon au bout de chaque aile")
	var wu := BastideRoofGenerator.gable_weights(_poly(U_SHAPE))
	check(wu.count(0.0) == 2 and wu[0] == 1.0, "U : pignons au bout des deux ailes, pas sur le fond")


func _test_roof_heights() -> void:
	print("Toit")
	var rs := BastideRoofStyle.new()
	var roof := BastideRoofGenerator.generate(_poly(RECT), 6.0, rs, BastideRoofStyle.RoofType.GABLE, 3)
	check(roof.fallback == "", "pas de repli sur une forme simple")
	var top := roof.height_at(Vector2(5, 3))
	check(is_equal_approx(snappedf(top, 0.001), snappedf(roof.ridge_y, 0.001)), "faîtage au milieu (%.2f m)" % top)
	var wall := roof.height_at(Vector2(5, 0.0))
	check(absf(wall - (6.0 + rs.thickness)) < 1e-3, "le dessous du toit repose pile sur le haut des murs")
	check(roof.height_at(Vector2(5, -0.3)) < wall and is_finite(roof.height_at(Vector2(5, -0.3))), "le toit déborde des murs")
	check(not is_finite(roof.height_at(Vector2(5, -2))), "rien au-delà du débord")
	var flat := BastideRoofGenerator.generate(_poly(PLUS), 6.0, rs, BastideRoofStyle.RoofType.HIP, 3)
	check(flat.fallback == "" and flat.arcs.size() > 8, "croix à croupes : faîtages, arêtiers et noues (%d arcs)" % flat.arcs.size())


func _building(points: Array, seed := 7, floors := 0) -> Array:
	var pts := PackedVector3Array()
	for p: Vector2 in points:
		pts.append(Vector3(p.x, 0, p.y))
	var spec := BastideBuildingSpec.from_points(pts, seed, floors)
	var layout := BastideBuildingGenerator.generate(spec, _style())
	var result := BastideBuildingMesher.build(layout, _style()) if not layout.is_empty() else BastideBuildResult.new()
	return [layout, result]


func _test_building_openings() -> void:
	print("Bâtiments : ouvertures")
	var bs := _style().get_building_style()
	for name in ["rectangle", "L", "U", "pentagone"]:
		var shape: Array = {"rectangle": RECT, "L": L_SHAPE, "U": U_SHAPE, "pentagone": PENTAGON}[name]
		var out := _building(shape)
		var layout: BastideBuildingLayout = out[0]
		var result: BastideBuildResult = out[1]
		check(layout.count(BastideBuildingLayout.OpeningKind.DOOR) == 1, "%s : une seule porte" % name)
		var ok_margin := true
		var ok_overlap := true
		var ok_height := true
		var ok_aligned := true
		for f: BastideBuildingLayout.Facade in layout.facades:
			var by_floor := {}
			var spans: Array = []
			for o in f.openings:
				if o.kind == BastideBuildingLayout.OpeningKind.ATTIC:
					continue
				ok_margin = ok_margin and o.u0 >= bs.corner_margin - 1e-3 - 0.2 and o.u1 <= f.length - bs.corner_margin + 1e-3 + 0.2
				ok_height = ok_height and o.y1 + o.arch <= layout.eave_y - 0.2
				for sp: Array in spans:
					if sp[2] == o.floor and o.u0 < sp[1] - 1e-3 and o.u1 > sp[0] + 1e-3:
						ok_overlap = false
				spans.append([o.u0, o.u1, o.floor])
				if not by_floor.has(o.floor):
					by_floor[o.floor] = []
				(by_floor[o.floor] as Array).append(snappedf((o.u0 + o.u1) * 0.5, 0.001))
			var floors := by_floor.keys()
			for k in range(1, floors.size()):
				ok_aligned = ok_aligned and by_floor[floors[k]] == by_floor[floors[0]]
		check(ok_margin and ok_overlap, "%s : ouvertures loin des angles et sans chevauchement" % name)
		check(ok_aligned, "%s : fenêtres alignées d'un étage à l'autre" % name)
		check(ok_height, "%s : ouvertures sous l'égout" % name)
		check(not result.is_empty() and result.collision_faces.size() > 0 and result.collision_faces.size() % 3 == 0,
			"%s : mesh et collisions (%d triangles)" % [name, result.stats.triangles])
	var rect: BastideBuildingLayout = _building(RECT)[0]
	var gables := 0
	var door_on_gable := false
	for f: BastideBuildingLayout.Facade in rect.facades:
		if f.gable:
			gables += 1
			door_on_gable = door_on_gable or rect.facades[f.index].openings.any(func(o): return o.kind == BastideBuildingLayout.OpeningKind.DOOR)
	check(gables == 2 and not door_on_gable, "rectangle : deux murs pignons, porte sur une façade sous égout")


func _test_building_determinism() -> void:
	print("Bâtiments : seed")
	var a: Array = _building(L_SHAPE, 4)
	var b: Array = _building(L_SHAPE, 4)
	var c: Array = _building(L_SHAPE, 5)
	check((a[1] as BastideBuildResult).stats.triangles == (b[1] as BastideBuildResult).stats.triangles
		and (a[0] as BastideBuildingLayout).roof.color == (b[0] as BastideBuildingLayout).roof.color, "même seed, même bâtiment")
	var la: BastideBuildingLayout = a[0]
	var lc: BastideBuildingLayout = c[0]
	check(la.facades[0].plaster != lc.facades[0].plaster or la.roof.color != lc.roof.color or la.shutter_color != lc.shutter_color,
		"seed différente : couleurs différentes")
	check(la.facades.size() == lc.facades.size() and la.count(BastideBuildingLayout.OpeningKind.WINDOW) == lc.count(BastideBuildingLayout.OpeningKind.WINDOW),
		"seed différente : même plan de façades (la variation reste bornée)")
	var three: BastideBuildingLayout = _building(RECT, 7, 3)[0]
	check(three.floors == 3 and is_equal_approx(three.eave_y, 3 * 2.9 + 0.35), "étages réglables (3 étages)")


func _test_building_degenerate() -> void:
	print("Bâtiments : entrées dégénérées")
	check((_building([])[0] as BastideBuildingLayout).is_empty(), "contour vide : rien, sans erreur")
	check((_building([Vector2(0, 0), Vector2(5, 0)])[0] as BastideBuildingLayout).is_empty(), "deux points : rien")
	check((_building([Vector2(0, 0), Vector2(5, 0), Vector2(10, 0)])[0] as BastideBuildingLayout).is_empty(), "points alignés : rien")
	var tiny: Array = _building([Vector2(0, 0), Vector2(2.5, 0), Vector2(2.5, 2.5), Vector2(0, 2.5)])
	check(not (tiny[1] as BastideBuildResult).is_empty(), "cabane de 2,5 m : construite quand même")


func _test_building_performance() -> void:
	print("Bâtiments : performances")
	var t0 := Time.get_ticks_usec()
	var out := _building(U_SHAPE, 7, 3)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("     manoir en U de 3 étages : %.1f ms, %d triangles" % [ms, (out[1] as BastideBuildResult).stats.triangles])
	check(ms < 600.0, "manoir en U de 3 étages en moins de 600 ms en headless")


# --- Étape 3 ---------------------------------------------------------------------------

const MEDIEVAL_PATH := "res://addons/bastide/styles/presets/medieval_stone.tres"
const JAPANESE_PATH := "res://addons/bastide/styles/presets/japanese_wood.tres"


func _styled(points: Array, st: BastideStyle, seed := 7, floors := 0) -> Array:
	var pts := PackedVector3Array()
	for p: Vector2 in points:
		pts.append(Vector3(p.x, 0, p.y))
	var spec := BastideBuildingSpec.from_points(pts, seed, floors)
	var layout := BastideBuildingGenerator.generate(spec, st)
	var result := BastideBuildingMesher.build(layout, st) if not layout.is_empty() else BastideBuildResult.new()
	return [layout, result]


static func _mesh_ok(result: BastideBuildResult) -> bool:
	if result.is_empty():
		return false
	for i in result.mesh.get_surface_count():
		for v: Vector3 in result.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
			if not v.is_finite():
				return false
	return true


func _test_presets() -> void:
	print("Styles prêts à l'emploi")
	var med: BastideStyle = load(MEDIEVAL_PATH)
	var jap: BastideStyle = load(JAPANESE_PATH)
	check(med != null and med.display_name == "Médiéval pierre", "style médiéval chargé")
	check(jap != null and jap.display_name == "Japonais traditionnel bois", "style japonais chargé")
	var names: Array = BastideStructure.presets(true).map(func(p: Array) -> String: return p[1])
	check(names.has("Médiéval pierre") and names.has("Japonais traditionnel bois"),
		"liste « Style prédéfini » : %s" % ", ".join(names))
	check(jap.get_garden_style() != null and jap.get_garden_style().gate_color != Color.BLACK, "volet décor réservé (sol, plantes, torii)")


func _test_irimoya() -> void:
	print("Toits irimoya")
	var rs := BastideRoofStyle.new()
	var rect := BastideRoofGenerator.generate(_poly(RECT), 6.0, rs, BastideRoofStyle.RoofType.IRIMOYA, 3)
	check(rect.fallback == "" and rect.gable_panels.size() == 2, "rectangle : deux petits pignons (%d)" % rect.gable_panels.size())
	check(not rect.weights.has(0.0), "rectangle : un égout sur les quatre côtés")
	check(rect.irimoya_y > rect.base_y and rect.irimoya_y < rect.ridge_y, "pignons entre l'égout et le faîte")
	var verges := rect.arcs.filter(func(a: Dictionary) -> bool: return a.kind == BastideRoofLayout.ArcKind.VERGE)
	check(verges.size() == 4 and verges.all(func(a: Dictionary) -> bool: return a.has("gable")), "quatre rives, chacune liée à son pignon")
	check(absf(rect.height_at(Vector2(0.0, 3.0)) - rect.height_at(Vector2(5.0, 0.0))) < 1e-3,
		"même hauteur sous l'égout partout (murs droits, pas de mur pignon)")
	var square := BastideRoofGenerator.generate(_poly(SQUARE), 6.0, rs, BastideRoofStyle.RoofType.IRIMOYA, 3)
	check(square.gable_panels.is_empty() and square.fallback == "croupes", "plan carré : croupes (aucun bout étroit)")
	var fails := 0
	var count := 0
	var panels := 0
	for it in 400:
		var poly := _ortho_poly(it, 4.0)
		if poly.size() < 4:
			continue
		count += 1
		var r := BastideRoofGenerator.generate(poly, 6.0, rs, BastideRoofStyle.RoofType.IRIMOYA, it)
		# Jamais pire qu'un toit à croupes (qui retombe lui-même en toit plat sur
		# quelques contours extrêmes une fois le débord ajouté).
		var worse := r.fallback == "plat" and BastideRoofGenerator.generate(poly, 6.0, rs,
			BastideRoofStyle.RoofType.HIP, it).fallback != "plat"
		if r.is_empty() or worse:
			fails += 1
		panels += r.gable_panels.size()
	check(fails == 0, "%d contours orthogonaux aléatoires en irimoya, jamais pire qu'en croupes : %d échec(s), %d petits pignons" % [count, fails, panels])


func _test_japanese_building() -> void:
	print("Bâtiment japonais")
	var jap: BastideStyle = load(JAPANESE_PATH)
	for name in ["rectangle", "L", "U", "pentagone"]:
		var shape: Array = {"rectangle": RECT, "L": L_SHAPE, "U": U_SHAPE, "pentagone": PENTAGON}[name]
		var out := _styled(shape, jap)
		var layout: BastideBuildingLayout = out[0]
		var result: BastideBuildResult = out[1]
		var posts_ok := true
		for f: BastideBuildingLayout.Facade in layout.facades:
			for u in f.posts:
				for o in f.openings:
					posts_ok = posts_ok and (u + 0.1 <= o.u0 or u - 0.1 >= o.u1)
		check(layout.timber and posts_ok, "%s : ossature bois, aucun poteau à travers une ouverture" % name)
		check(_mesh_ok(result) and layout.count(BastideBuildingLayout.OpeningKind.DOOR) == 1,
			"%s : mesh valide, une porte (%d triangles, toit %s)" % [name, result.stats.triangles, result.stats.roof])
	var rect: BastideBuildingLayout = _styled(RECT, jap)[0]
	check(rect.pent_roof and rect.noren_color.a > 0.0, "auvent entre les étages et noren devant la porte")
	var one_floor: BastideBuildingLayout = _styled(RECT, jap, 7, 1)[0]
	check(not one_floor.pent_roof, "pas d'auvent sur une maison d'un seul étage")
	var a: BastideBuildResult = _styled(L_SHAPE, jap, 4)[1]
	var b: BastideBuildResult = _styled(L_SHAPE, jap, 4)[1]
	check(a.stats.triangles == b.stats.triangles, "même seed, même maison japonaise")


func _test_japanese_wall() -> void:
	print("Muret japonais")
	var jap: BastideStyle = load(JAPANESE_PATH)
	var spec := BastideWallSpec.from_points(PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 8)]), false, 3)
	var layout := BastideWallGenerator.generate(spec, jap)
	var result := BastideWallMesher.build(layout, jap)
	check(layout.cap_roof and layout.merlons.is_empty() and layout.coping.is_empty(), "petit toit de tuiles, ni créneaux ni chaperon")
	var below := layout.stones.all(func(st: Dictionary) -> bool: return float(st.y1a) <= layout.plaster_from + 1e-3 and float(st.y1b) <= layout.plaster_from + 1e-3)
	check(not layout.stones.is_empty() and below, "pierres seulement dans le soubassement (%d pierres)" % layout.stones.size())
	check(layout.pillars.is_empty(), "pas de pilier de pierre")
	check(not result.is_empty() and result.collision_faces.size() > 0, "mesh et collisions (%d triangles)" % result.stats.triangles)


func _test_style_switch() -> void:
	print("Changement de style")
	var med: BastideStyle = load(MEDIEVAL_PATH)
	var jap: BastideStyle = load(JAPANESE_PATH)
	var m: Array = _styled(RECT, med, 11)
	var j: Array = _styled(RECT, jap, 11)
	var lm: BastideBuildingLayout = m[0]
	var lj: BastideBuildingLayout = j[0]
	check((m[1] as BastideBuildResult).stats.roof == "pignons" and (j[1] as BastideBuildResult).stats.roof == "irimoya",
		"même contour : pignons en médiéval, irimoya en japonais")
	check(lm.facades.size() == lj.facades.size(), "même contour, même nombre de façades")
	var roles := []
	for i in (j[1] as BastideBuildResult).mesh.get_surface_count():
		roles.append((j[1] as BastideBuildResult).mesh.surface_get_name(i))
	check(roles.has("wood") and roles.has("paper") and roles.has("roof"), "matériaux par rôle : %s" % ", ".join(roles))


func _test_triangle_budget() -> void:
	print("Budget de triangles")
	var med: BastideStyle = load(MEDIEVAL_PATH)
	var jap: BastideStyle = load(JAPANESE_PATH)
	var mr: int = (_styled(RECT, med)[1] as BastideBuildResult).stats.triangles
	var jr: int = (_styled(RECT, jap)[1] as BastideBuildResult).stats.triangles
	var mu: int = (_styled(U_SHAPE, med, 7, 3)[1] as BastideBuildResult).stats.triangles
	check(mr < 22000, "maison médiévale 10 × 6 m : %d triangles (< 22 000 ; ~33 000 à l'étape 2)" % mr)
	check(jr < 24000, "maison japonaise 10 × 6 m : %d triangles (< 24 000)" % jr)
	check(mu < 45000, "manoir en U de 3 étages : %d triangles (< 45 000 ; ~67 000 à l'étape 2)" % mu)
