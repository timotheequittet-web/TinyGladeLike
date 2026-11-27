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
	# Étape 4 : construction en jeu.
	_test_stroke_simplify()
	_test_stroke_smooth_resample()
	_test_stroke_rectangle()
	_test_stroke_union()
	# Étape 5 : décor japonais (chemins, torii, clôtures, plantes).
	_test_path_joins_door()
	_test_path_joins_path()
	_test_fence_opens_for_path()
	_test_torii_on_path()
	_test_plants_keep_clear()
	_test_garden_determinism()
	_test_garden_meshes()
	# Étape 6 : portails dans les murets, terrasses et engawa.
	_test_wall_gate_japanese()
	_test_wall_gate_medieval()
	_test_wall_gate_cases()
	_test_terrace_rect()
	_test_terrace_engawa_snap()
	_test_terrace_build()
	_test_terrace_neighbours()
	_test_kit_trees()
	_test_forest()
	_test_terrain()
	_test_silhouettes()
	# Jardins d'eau.
	_test_pond_shape()
	_test_pond_carve()
	_test_pond_build()
	_test_pond_bridges()
	_test_pond_neighbours()
	_test_farm_build()
	_test_farm_rice()
	_test_farm_neighbours()
	# Intérieurs.
	_test_interior_plan()
	_test_interior_stairs_rules()
	_test_interior_meshes()
	_test_interior_terrain()
	_test_trees_stay_outside()
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


# --- Étape 4 ---------------------------------------------------------------------------

func _test_stroke_simplify() -> void:
	print("Tracés à main levée : simplification")
	var pts := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 101:
		pts.append(Vector3(i * 0.2, 0, rng.randf_range(-0.05, 0.05)))
	var s := BastideStroke.simplify(pts, 0.2)
	check(s.size() == 2, "une ligne tremblante devient un segment (%d points)" % s.size())
	check(s[0] == pts[0] and s[1] == pts[100], "les extrémités sont gardées")
	var corner := PackedVector3Array()
	for i in 21:
		corner.append(Vector3(i * 0.5, 0, 0))
	for i in range(1, 21):
		corner.append(Vector3(10, 0, i * 0.5))
	var c := BastideStroke.simplify(corner, 0.2)
	check(c.size() == 3 and c[1].is_equal_approx(Vector3(10, 0, 0)), "un angle droit garde son sommet")


func _test_stroke_smooth_resample() -> void:
	print("Tracés à main levée : lissage et rééchantillonnage")
	var ctrl := PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)])
	var path := BastideStroke.wall_path(ctrl, false, 0.5)
	check(path[0] == ctrl[0] and path[path.size() - 1] == ctrl[2], "un mur ouvert garde ses extrémités")
	var max_gap := 0.0
	var min_gap := 99.0
	for i in range(1, path.size()):
		var d := path[i].distance_to(path[i - 1])
		max_gap = maxf(max_gap, d)
		min_gap = minf(min_gap, d)
	check(max_gap <= 0.63 and min_gap > 0.12, "points espacés régulièrement (%.2f à %.2f m)" % [min_gap, max_gap])
	var far := 99.0
	for p in path:
		far = minf(far, p.distance_to(Vector3(10, 0, 0)))
	check(far > 0.3, "l'angle est arrondi (passe à %.2f m du sommet)" % far)
	var loop := BastideStroke.wall_path(PackedVector3Array([Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(8, 0, 8), Vector3(0, 0, 8)]), true, 0.5)
	check(loop[0].distance_to(loop[loop.size() - 1]) <= 0.6 and loop[0].distance_to(loop[loop.size() - 1]) > 0.1,
			"une enceinte fermée ne double pas son premier point")
	var spec := BastideWallSpec.from_points(path, false, 3, 1.9)
	var layout := BastideWallGenerator.generate(spec, load(JAPANESE_PATH))
	check(not layout.is_empty(), "un tracé lissé donne un mur")


func _test_stroke_rectangle() -> void:
	print("Tracés à main levée : rectangle de maison")
	var r := BastideStroke.rectangle(Vector3(0, 0, 0), Vector3(7.3, 0, 5.1), Vector3.RIGHT, 0.5, 4.0)
	check(r.size() == 4, "4 coins")
	check(is_equal_approx(r[0].distance_to(r[1]) * r[1].distance_to(r[2]), 7.5 * 5.0) or
			is_equal_approx(r[0].distance_to(r[1]) * r[1].distance_to(r[2]), 5.0 * 7.5), "dimensions arrondies au demi-mètre")
	var tiny := BastideStroke.rectangle(Vector3(0, 0, 0), Vector3(0.5, 0, -0.3), Vector3(1, 0, 1), 0.5, 4.0)
	check(tiny[0].distance_to(tiny[1]) >= 3.99 and tiny[1].distance_to(tiny[2]) >= 3.99, "taille minimale respectée")
	check(BastideStroke.signed_area(tiny) > 0.0 and BastideStroke.signed_area(r) > 0.0, "contour toujours dans le même sens")


func _test_stroke_union() -> void:
	print("Tracés à main levée : agrandir une maison")
	var a := PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 6), Vector3(0, 0, 6)])
	var b := PackedVector3Array([Vector3(6, 0, 4), Vector3(10, 0, 4), Vector3(10, 0, 14), Vector3(6, 0, 14)])
	check(BastideStroke.overlaps(a, b), "les deux rectangles se chevauchent")
	var u := BastideStroke.union(a, b)
	check(u.size() == 6, "l'union donne une maison en L (%d angles)" % u.size())
	var far := PackedVector3Array([Vector3(30, 0, 0), Vector3(34, 0, 0), Vector3(34, 0, 4), Vector3(30, 0, 4)])
	check(not BastideStroke.overlaps(a, far) and BastideStroke.union(a, far).is_empty(), "deux maisons éloignées ne fusionnent pas")
	var pts := PackedVector3Array()
	for p in u:
		pts.append(p)
	var layout := BastideBuildingGenerator.generate(BastideBuildingSpec.from_points(pts, 3), load(JAPANESE_PATH))
	check(not layout.is_empty(), "la maison en L se génère")


# --- Étape 5 : décor ------------------------------------------------------------------

## Maison 10 × 6 m au style japonais et sa description pour le voisinage.
func _garden_house(pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 6), Vector3(0, 0, 6)])) -> Dictionary:
	var st: BastideStyle = load(JAPANESE_PATH)
	var layout := BastideBuildingGenerator.generate(BastideBuildingSpec.from_points(pts, 5), st)
	var anchors := BastideBuildingMesher.anchors(layout)
	var fp := PackedVector3Array()
	for p: Vector2 in anchors["footprint"]:
		fp.append(Vector3(p.x, 0, p.y))
	return {"kind": "house", "footprint": fp, "doors": anchors["doors"], "overhang": anchors["overhang"]}


func _test_path_joins_door() -> void:
	print("Décor : un chemin rejoint la porte")
	var house := _garden_house()
	var doors: Array = house["doors"]
	check(doors.size() == 1, "la maison a une porte (%d)" % doors.size())
	if doors.is_empty():
		return
	var door: Dictionary = doors[0]
	var dpos: Vector3 = door["pos"]
	var dout: Vector3 = door["out"]
	var ctx := BastideGardenContext.from_entries([house])
	# Un tracé qui arrive en biais, à 2 m de la porte.
	var side := Vector3(-dout.z, 0, dout.x)
	var far := dpos + dout * 12.0 + side * 4.0
	var near := dpos + dout * 2.6 + side * 1.4
	var res := BastideGardenRules.snap_path_ends(PackedVector3Array([far, far.lerp(near, 0.5), near]), ctx)
	var pts: PackedVector3Array = res["points"]
	var last := pts[pts.size() - 1]
	check(not (res["door_end"] as Dictionary).is_empty(), "le bout du chemin est raccroché à la porte")
	check(last.distance_to(dpos + dout * BastideGardenRules.DOOR_GAP) < 0.01, "il s'arrête juste devant le seuil")
	var approach := BastidePolyline.flat_dir(pts[pts.size() - 2], last)
	check(approach.dot(-dout) > 0.99, "il arrive bien de face (%.3f)" % approach.dot(-dout))
	# Un bout loin de toute porte ne bouge pas.
	var res2 := BastideGardenRules.snap_path_ends(PackedVector3Array([far, far + side * 5.0]), ctx)
	check((res2["points"] as PackedVector3Array)[1] == far + side * 5.0, "un bout loin des portes reste en place")
	# Le serpentement ne touche pas à l'approche de la porte.
	var m := BastideGardenRules.meander(pts, 3, 0.3, 0.0, 1.8)
	check(m[m.size() - 1].distance_to(last) < 0.01, "le serpentement garde le bout du chemin")
	var r := BastidePathMesher.build(PackedVector3Array([far, near]), 4, load(JAPANESE_PATH), ctx)
	check(_mesh_ok(r) and r.stats.get("doors", 0) == 1, "le chemin se génère et rejoint la porte")
	check(r.stats.get("lanterns", 0) >= 1, "une lanterne accueille à la porte (%d)" % r.stats.get("lanterns", 0))


func _test_path_joins_path() -> void:
	print("Décor : un chemin se raccorde à un autre")
	var main := {"kind": "path", "points": PackedVector3Array([Vector3(-10, 0, 0), Vector3(10, 0, 0)]), "width": 1.5}
	var ctx := BastideGardenContext.from_entries([main])
	var res := BastideGardenRules.snap_path_ends(PackedVector3Array([Vector3(2, 0, 12), Vector3(2.5, 0, 1.6)]), ctx)
	var end: Vector3 = (res["points"] as PackedVector3Array)[1]
	check(absf(end.z) < 0.01 and absf(end.x - 2.5) < 0.05, "le bout rejoint l'axe de l'autre chemin (%s)" % end)
	check(res["join_end"], "le raccord est signalé")
	var near := ctx.nearest_path(Vector2(0, 3))
	check(near["index"] == 0 and absf(near["dist"] - 3.0) < 0.01 and absf(near["clearance"] - 2.25) < 0.01,
			"distance au chemin et à son bord")


func _test_fence_opens_for_path() -> void:
	print("Décor : une clôture s'ouvre pour laisser passer un chemin")
	var path := {"kind": "path", "points": PackedVector3Array([Vector3(0, 0, -6), Vector3(0, 0, 6)]), "width": 1.5}
	var ctx := BastideGardenContext.from_entries([path])
	var fence := PackedVector3Array()
	for i in 21:
		fence.append(Vector3(-5.0 + i * 0.5, 0, 1.0))
	var spans := BastideGardenRules.fence_openings(fence, false, ctx)
	check(spans.size() == 1, "une ouverture (%d)" % spans.size())
	if spans.size() == 1:
		check(spans[0].y - spans[0].x >= 1.5 + 0.8 and absf((spans[0].x + spans[0].y) * 0.5 - 5.0) < 0.01,
				"centrée sur le chemin, plus large que lui (%s)" % spans[0])
	for variant in [BastideGardenStyle.FenceKind.STONE, BastideGardenStyle.FenceKind.BAMBOO]:
		var r := BastideFenceMesher.build(fence, false, variant, 3, load(JAPANESE_PATH), ctx)
		check(_mesh_ok(r) and r.stats.get("runs", 0) == 2, "clôture %d : deux tronçons de part et d'autre" % variant)
	var none := BastideGardenRules.fence_openings(fence, false, BastideGardenContext.new())
	check(none.is_empty(), "sans chemin, pas d'ouverture")
	var loop := PackedVector3Array([Vector3(-4, 0, -4), Vector3(4, 0, -4), Vector3(4, 0, 4), Vector3(-4, 0, 4)])
	var rl := BastideFenceMesher.build(BastideStroke.resample(loop, 0.5, true), true, 0, 3, load(JAPANESE_PATH), ctx)
	check(_mesh_ok(rl) and rl.stats.get("openings", 0) == 2, "une enceinte traversée a deux ouvertures (%d)" % rl.stats.get("openings", 0))


func _test_torii_on_path() -> void:
	print("Décor : un torii se centre sur le chemin")
	var path := {"kind": "path", "points": PackedVector3Array([Vector3(0, 0, -8), Vector3(0, 0, 8)]), "width": 1.5}
	var ctx := BastideGardenContext.from_entries([path])
	var res := BastideGardenRules.place_torii(Vector3(1.8, 0, 2.0), ctx, 1.5, Vector3(0.3, 0, 1))
	var pts: PackedVector3Array = res["points"]
	check(res["snapped"], "aimanté par le chemin")
	var c := (pts[0] + pts[1]) * 0.5
	check(absf(c.x) < 0.01 and absf(c.z - 2.0) < 0.01, "centré sur l'axe (%s)" % c)
	check(absf((pts[1] - pts[0]).normalized().dot(Vector3(0, 0, 1))) < 0.01, "piliers en travers du chemin")
	check(absf(pts[0].distance_to(pts[1]) - BastideGardenRules.torii_width(1.5)) < 0.01, "largeur adaptée au chemin")
	var lone := BastideGardenRules.place_torii(Vector3(20, 0, 0), ctx, 1.5, Vector3.RIGHT)
	check(not lone["snapped"], "loin d'un chemin, posé tel quel")
	var fit := BastideGardenRules.fit_torii(Vector3(0, 0, 0), Vector3(0.5, 0, 0))
	check(absf(fit[0].distance_to(fit[1]) - 2.2) < 0.01, "jamais plus étroit que 2,2 m")
	var r := BastideToriiMesher.build(pts[0], pts[1], 3, load(JAPANESE_PATH))
	check(_mesh_ok(r) and not r.collision_faces.is_empty(), "le torii se génère, avec collisions")


func _test_plants_keep_clear() -> void:
	print("Décor : les plantes laissent la place")
	var house := _garden_house()
	var door: Dictionary = (house["doors"] as Array)[0]
	var dpos: Vector3 = door["pos"]
	var dout: Vector3 = door["out"]
	var path := {"kind": "path", "points": PackedVector3Array([dpos + dout * 1.15, dpos + dout * 12.0]), "width": 1.5}
	var wall := {"kind": "wall", "points": PackedVector3Array([Vector3(-4, 0, -3), Vector3(16, 0, -3)]), "thickness": 0.55}
	var ctx := BastideGardenContext.from_entries([house, path, wall])
	var plan := BastidePlantingMesher.plan_garden(ctx, 7, (load(JAPANESE_PATH) as BastideStyle).get_garden_style())
	var items: Array = plan["items"]
	check(items.size() > 10, "le jardin fait pousser des plantes (%d)" % items.size())
	var bad := 0
	var by_wall := 0
	for it: Dictionary in items:
		var p: Vector3 = it["pos"]
		var p2 := Vector2(p.x, p.z)
		var r := BastidePlantingMesher.footprint(it)
		if ctx.path_clearance(p2) < r or ctx.house_clearance(p2) < 0.0 or ctx.near_door(p2, 1.8) \
				or ctx.wall_clearance(p2) < 0.0:
			bad += 1
		if absf(p.z + 3.0) < 1.2:
			by_wall += 1
	check(bad == 0, "aucune plante sur le chemin, dans la maison, devant la porte ou dans le mur (%d)" % bad)
	check(by_wall > 3, "des plantes au pied du mur (%d)" % by_wall)
	check((plan["bands"] as Array).size() == 1, "une bande de galets au pied de la maison")
	var massif := BastidePlantingMesher.plan_planting(PackedVector3Array([dpos + dout * 6.0 + Vector3(-6, 0, 0),
		dpos + dout * 6.0 + Vector3(6, 0, 0)]), 3, (load(JAPANESE_PATH) as BastideStyle).get_garden_style(), ctx)
	var on_path := 0
	for it: Dictionary in massif:
		var p: Vector3 = it["pos"]
		if ctx.path_clearance(Vector2(p.x, p.z)) < BastidePlantingMesher.footprint(it):
			on_path += 1
	check(massif.size() > 5 and on_path == 0, "un massif tracé en travers du chemin le laisse libre (%d plantes)" % massif.size())
	var tree := BastidePlantingMesher.plan_planting(PackedVector3Array([Vector3(30, 0, 30)]), 9,
			(load(JAPANESE_PATH) as BastideStyle).get_garden_style(), ctx)
	check(not tree.is_empty() and BastidePlantingMesher.TREES.has(tree[0]["type"]), "un seul point : un arbre (%s)" % (tree[0]["type"] if tree.size() > 0 else "rien"))


func _test_garden_determinism() -> void:
	print("Décor : même seed, même jardin ; une retouche ailleurs ne rebrasse rien")
	var house := _garden_house()
	var gs := (load(JAPANESE_PATH) as BastideStyle).get_garden_style()
	var a := BastidePlantingMesher.plan_garden(BastideGardenContext.from_entries([house]), 7, gs)
	var b := BastidePlantingMesher.plan_garden(BastideGardenContext.from_entries([house]), 7, gs)
	check(str(a["items"]) == str(b["items"]), "deux calculs identiques")
	var wall := {"kind": "wall", "points": PackedVector3Array([Vector3(40, 0, 0), Vector3(50, 0, 0)]), "thickness": 0.55}
	var c := BastidePlantingMesher.plan_garden(BastideGardenContext.from_entries([house, wall]), 7, gs)
	var kept := 0
	for it: Dictionary in a["items"]:
		if str(c["items"]).contains(str(it)):
			kept += 1
	check(kept == (a["items"] as Array).size(), "un mur lointain ajouté ne change pas les plantes de la maison (%d/%d)" % [kept, (a["items"] as Array).size()])


func _test_garden_meshes() -> void:
	print("Décor : maillages et budget")
	var st: BastideStyle = load(JAPANESE_PATH)
	var house := _garden_house()
	var ctx := BastideGardenContext.from_entries([house])
	var t0 := Time.get_ticks_msec()
	var g := BastidePlantingMesher.build_garden(ctx, 3, st)
	var ms := Time.get_ticks_msec() - t0
	check(_mesh_ok(g), "le jardin d'une maison se génère (%d triangles, %d ms)" % [g.stats.get("triangles", 0), ms])
	check(g.stats.get("triangles", 0) < 60000, "budget du jardin raisonnable")
	for type in ["bush", "hydrangea", "fern", "grass", "rock", "maple", "sakura", "pine", "bamboo"]:
		var mb := BastideMeshBuilder.new()
		BastidePlantingMesher.draw_items(mb, [{"type": type, "pos": Vector3.ZERO, "size": 3.5 if type in ["maple", "sakura", "pine"] else 0.6,
			"key": 11, "bloom": true}], st.get_garden_style())
		check(mb.triangle_count > 20 and mb.triangle_count < 6000, "%s : %d triangles" % [type, mb.triangle_count])
	var mb2 := BastideMeshBuilder.new()
	BastideGardenMesher.lantern(mb2, Vector3.ZERO, 0.0, 1.0, Color(0.6, 0.6, 0.55), 3)
	check(mb2.triangle_count > 50, "lanterne : %d triangles" % mb2.triangle_count)
	var path := BastidePathMesher.build(PackedVector3Array([Vector3(-10, 0, 20), Vector3(0, 0, 22), Vector3(10, 0, 20)]), 2, st, ctx)
	check(_mesh_ok(path) and path.stats.get("stones", 0) > 15, "un chemin de 20 m : %d pas japonais, %d triangles" % [path.stats.get("stones", 0), path.stats.get("triangles", 0)])
	var med := BastidePathMesher.build(PackedVector3Array([Vector3(-10, 0, 20), Vector3(10, 0, 20)]), 2, load(MEDIEVAL_PATH), ctx)
	check(_mesh_ok(med) and med.stats.get("stones", 0) == 0 and med.stats.get("lanterns", 0) == 0, "médiéval : chemin de terre, sans pas japonais ni lanterne")


# --- Étape 6 : portails et terrasses ---------------------------------------------------

func _crossing_ctx(points: Array, width := 1.5) -> BastideGardenContext:
	return BastideGardenContext.from_entries([{"kind": "path", "points": PackedVector3Array(points), "width": width}])


func _gate_wall(points: Array, closed: bool, st: BastideStyle, ctx: BastideGardenContext, seed := 4) -> Array:
	var spec := BastideWallSpec.from_points(PackedVector3Array(points), closed, seed, 1.9)
	spec.context = ctx
	var layout := BastideWallGenerator.generate(spec, st)
	return [layout, BastideWallMesher.build(layout, st)]


func _test_wall_gate_japanese() -> void:
	print("Portails : un chemin traverse un muret japonais")
	var st: BastideStyle = load(JAPANESE_PATH)
	var ctx := _crossing_ctx([Vector3(0.5, 0, -6), Vector3(0, 0, 6)])
	var res := _gate_wall([Vector3(-8, 0, 0), Vector3(8, 0, 0)], false, st, ctx)
	var layout: BastideWallLayout = res[0]
	var r: BastideBuildResult = res[1]
	check(layout.gates.size() == 1, "un portail (%d)" % layout.gates.size())
	check(layout.runs.size() == 2, "deux tronçons de part et d'autre (%d)" % layout.runs.size())
	if layout.gates.size() == 1 and layout.runs.size() == 2:
		var g: Dictionary = layout.gates[0]
		var clear: float = g.width - 0.44
		check(clear >= st.get_wall_style().gate_min_clear - 0.01, "passage libre entre les poteaux : %.2f m" % clear)
		check(absf((g.s0 + g.s1) * 0.5 - 8.25) < 0.15, "centré sur le chemin (%.2f)" % ((g.s0 + g.s1) * 0.5))
		var a: BastideWallLayout.Run = layout.runs[0]
		var b: BastideWallLayout.Run = layout.runs[1]
		check(a.end_gate and b.start_gate and not a.start_gate and not b.end_gate, "les bouts qui bordent le portail sont marqués")
		check(absf(a.s1 - g.s0) < 0.01 and absf(b.s0 - g.s1) < 0.01, "le mur s'arrête pile aux poteaux")
		check(int(g.kind) == BastideWallStyle.GateKind.ROOFED, "style japonais : portail couvert")
	check(_mesh_ok(r) and r.stats.get("gates", 0) == 1, "le portail se dessine (%d triangles)" % r.stats.get("triangles", 0))
	var shut := _gate_wall([Vector3(-8, 0, 0), Vector3(8, 0, 0)], false, st, null)
	check((shut[0] as BastideWallLayout).gates.is_empty() and (shut[0] as BastideWallLayout).runs.size() == 1, "sans chemin, le mur reste plein")
	# Collisions : rien ne bloque le milieu du passage, au ras du sol.
	var blocked := 0
	var faces := r.collision_faces
	for i in range(0, faces.size(), 3):
		var lo := faces[i].min(faces[i + 1]).min(faces[i + 2])
		var hi := faces[i].max(faces[i + 1]).max(faces[i + 2])
		if lo.x < 0.3 and hi.x > -0.3 and lo.y < 1.5 and hi.y > 0.2 and lo.z < 0.3 and hi.z > -0.3:
			blocked += 1
	check(blocked == 0, "on passe : aucune collision au milieu du portail (%d)" % blocked)


func _test_wall_gate_medieval() -> void:
	print("Portails : arc de pierre entre deux piliers (médiéval)")
	var st: BastideStyle = load(MEDIEVAL_PATH)
	var ctx := _crossing_ctx([Vector3(0, 0, -6), Vector3(0, 0, 6)])
	var res := _gate_wall([Vector3(-9, 0, 0), Vector3(9, 0, 0)], false, st, ctx)
	var layout: BastideWallLayout = res[0]
	var gate_pillars := layout.pillars.filter(func(p: Dictionary) -> bool: return p.get("gate", false))
	check(layout.gates.size() == 1 and gate_pillars.size() == 2, "un portail, deux piliers (%d)" % gate_pillars.size())
	if layout.gates.size() == 1:
		var g: Dictionary = layout.gates[0]
		check(g.arch, "un arc au-dessus du passage")
		check(int(g.kind) == BastideWallStyle.GateKind.ARCH, "style médiéval : arc de pierre")
		var tops := gate_pillars.map(func(p: Dictionary) -> float: return p.top)
		var plain := layout.pillars.filter(func(p: Dictionary) -> bool: return not p.get("gate", false))
		if not plain.is_empty():
			check(tops.min() > float(plain[0].top), "les piliers du portail sont plus hauts que ceux du mur")
	check(_mesh_ok(res[1]), "le portail médiéval se dessine (%d triangles)" % (res[1] as BastideBuildResult).stats.get("triangles", 0))


func _test_wall_gate_cases() -> void:
	print("Portails : cas limites")
	var st: BastideStyle = load(JAPANESE_PATH)
	# Un chemin qui longe le mur sans le traverser : rien.
	var along := _gate_wall([Vector3(-8, 0, 0), Vector3(8, 0, 0)], false, st, _crossing_ctx([Vector3(-6, 0, 2), Vector3(6, 0, 2)]))
	check((along[0] as BastideWallLayout).gates.is_empty(), "un chemin qui longe le mur ne l'ouvre pas")
	# En biais : l'ouverture s'élargit.
	var slant := _gate_wall([Vector3(-8, 0, 0), Vector3(8, 0, 0)], false, st, _crossing_ctx([Vector3(-4, 0, -3), Vector3(4, 0, 3)]))
	var straight := _gate_wall([Vector3(-8, 0, 0), Vector3(8, 0, 0)], false, st, _crossing_ctx([Vector3(0, 0, -3), Vector3(0, 0, 3)]))
	var ws: float = ((slant[0] as BastideWallLayout).gates[0] as Dictionary).width if not (slant[0] as BastideWallLayout).gates.is_empty() else 0.0
	var wd: float = ((straight[0] as BastideWallLayout).gates[0] as Dictionary).width if not (straight[0] as BastideWallLayout).gates.is_empty() else 0.0
	check(ws > wd + 0.2, "en biais, le portail est plus large (%.2f contre %.2f m)" % [ws, wd])
	# Une enceinte traversée de part en part : deux portails.
	var loop := _gate_wall([Vector3(-6, 0, -5), Vector3(6, 0, -5), Vector3(6, 0, 5), Vector3(-6, 0, 5)], true, st,
			_crossing_ctx([Vector3(0, 0, -9), Vector3(0, 0, 9)]))
	var ll: BastideWallLayout = loop[0]
	check(ll.gates.size() == 2 and _mesh_ok(loop[1]), "une enceinte traversée : deux portails (%d)" % ll.gates.size())
	# Deux chemins côte à côte : un seul grand portail.
	var ctx2 := BastideGardenContext.from_entries([
		{"kind": "path", "points": PackedVector3Array([Vector3(0, 0, -5), Vector3(0, 0, 5)]), "width": 1.5},
		{"kind": "path", "points": PackedVector3Array([Vector3(1.6, 0, -5), Vector3(1.6, 0, 5)]), "width": 1.5}])
	var twin := _gate_wall([Vector3(-8, 0, 0), Vector3(8, 0, 0)], false, st, ctx2)
	check((twin[0] as BastideWallLayout).gates.size() == 1, "deux chemins voisins : un seul portail (%d)" % (twin[0] as BastideWallLayout).gates.size())
	# Un chemin au ras du bout du mur : pas de tronçon ridicule.
	var edge := _gate_wall([Vector3(-8, 0, 0), Vector3(8, 0, 0)], false, st, _crossing_ctx([Vector3(7.6, 0, -4), Vector3(7.6, 0, 4)]))
	var short := 0
	for run: BastideWallLayout.Run in (edge[0] as BastideWallLayout).runs:
		if run.length() < 0.44:
			short += 1
	check(short == 0 and _mesh_ok(edge[1]), "près du bout du mur, aucun bout de mur ridicule")
	# Même seed, même portail.
	var a := _gate_wall([Vector3(-8, 0, 0), Vector3(8, 0, 0)], false, st, _crossing_ctx([Vector3(0, 0, -3), Vector3(0, 0, 3)]), 9)
	var b := _gate_wall([Vector3(-8, 0, 0), Vector3(8, 0, 0)], false, st, _crossing_ctx([Vector3(0, 0, -3), Vector3(0, 0, 3)]), 9)
	check((a[1] as BastideBuildResult).stats.get("triangles") == (b[1] as BastideBuildResult).stats.get("triangles"), "déterministe")


func _is_rect(r: PackedVector3Array) -> bool:
	if r.size() != 4:
		return false
	for i in 4:
		var a := BastidePolyline.flat_dir(r[i], r[(i + 1) % 4])
		var b := BastidePolyline.flat_dir(r[(i + 1) % 4], r[(i + 2) % 4])
		if absf(a.dot(b)) > 1e-3:
			return false
	return BastideStroke.signed_area(r) > 0.0


func _test_terrace_rect() -> void:
	print("Terrasses : toujours un rectangle")
	var wobbly := PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0.3), Vector3(4.4, 0, 3), Vector3(-0.2, 0, 2.6)])
	var r := BastideTerraceRules.fit_rect(wobbly)
	check(_is_rect(r), "un tracé tremblant devient un rectangle direct")
	var again := BastideTerraceRules.fit_rect(r)
	var same := true
	for i in 4:
		same = same and again[i].distance_to(r[i]) < 1e-4
	check(same, "redresser un rectangle ne le change pas")
	var cw := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 3), Vector3(4, 0, 3), Vector3(4, 0, 0)])
	check(_is_rect(BastideTerraceRules.fit_rect(cw)), "même tracé dans l'autre sens")
	for i in 4:
		var n := BastideTerraceRules.side_normal(r, i)
		var mid := (r[i] + r[(i + 1) % 4]) * 0.5
		var c := BastideStroke.centroid(r)
		if (mid - c).dot(n) <= 0.0:
			check(false, "normale du côté %d sortante" % i)
			return
	check(true, "les normales des côtés sont sortantes")


func _test_terrace_engawa_snap() -> void:
	print("Terrasses : contre une maison, un engawa")
	var house := _garden_house()  # 10 × 6 m, porte en façade
	var ctx := BastideGardenContext.from_entries([house])
	# Tirée un peu de travers et à 0,8 m de la façade x = 10.
	var drawn := PackedVector3Array([Vector3(10.8, 0, 0.6), Vector3(12.5, 0, 0.6), Vector3(12.5, 0, 5.2), Vector3(10.8, 0, 5.2)])
	var res := BastideTerraceRules.snap_to_house(BastideStroke.ensure_direct(drawn), ctx)
	var pts: PackedVector3Array = res["points"]
	check(res["engawa"], "elle se colle à la façade")
	var minx := INF
	var maxx := -INF
	for p in pts:
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
	check(absf(minx - (10.0 + BastideTerraceRules.HOUSE_GAP)) < 0.01, "contre le mur, au jour près (x = %.3f)" % minx)
	check(maxx - minx >= BastideTerraceRules.ENGAWA_MIN_DEPTH - 0.01 and maxx - minx <= BastideTerraceRules.ENGAWA_MAX_DEPTH + 0.01,
			"profondeur d'une galerie (%.2f m)" % (maxx - minx))
	check(_is_rect(BastideTerraceRules.fit_rect(pts)), "toujours un rectangle")
	var hs := BastideTerraceRules.house_side(BastideTerraceRules.fit_rect(pts), ctx)
	check(hs >= 0, "le côté contre la maison est reconnu")
	check(BastideTerraceRules.entry_side(BastideTerraceRules.fit_rect(pts), ctx, hs) == (hs + 2) % 4, "la pierre de seuil est à l'opposé de la maison")
	# Trop longue : elle s'arrête aux angles.
	var long := PackedVector3Array([Vector3(10.2, 0, -3), Vector3(12, 0, -3), Vector3(12, 0, 9), Vector3(10.2, 0, 9)])
	var lr: PackedVector3Array = BastideTerraceRules.snap_to_house(BastideStroke.ensure_direct(long), ctx)["points"]
	var minz := INF
	var maxz := -INF
	for p in lr:
		minz = minf(minz, p.z)
		maxz = maxf(maxz, p.z)
	check(minz >= 0.0 and maxz <= 6.0, "elle ne dépasse pas les angles de la maison (%.2f → %.2f)" % [minz, maxz])
	# Devant la porte : elle s'arrête avant, du côté le plus long.
	var door: Dictionary = (house["doors"] as Array)[0]
	var dpos: Vector3 = door["pos"]
	var dout: Vector3 = door["out"]
	var along := Vector3(-dout.z, 0, dout.x)
	var front := PackedVector3Array([dpos - along * 4.5 + dout * 0.3, dpos + along * 1.5 + dout * 0.3,
		dpos + along * 1.5 + dout * 1.8, dpos - along * 4.5 + dout * 1.8])
	var fr: PackedVector3Array = BastideTerraceRules.snap_to_house(BastideStroke.ensure_direct(front), ctx)["points"]
	var clear := INF
	for p in fr:
		clear = minf(clear, absf((p - dpos).dot(along)))
	var w: float = door["width"]
	check(clear >= w * 0.5 + BastideTerraceRules.DOOR_CLEAR - 0.01, "elle laisse la porte libre (%.2f m du milieu)" % clear)
	# Loin des maisons : rien ne bouge.
	var far := BastideStroke.ensure_direct(PackedVector3Array([Vector3(20, 0, 20), Vector3(24, 0, 20), Vector3(24, 0, 23), Vector3(20, 0, 23)]))
	var fres := BastideTerraceRules.snap_to_house(far, ctx)
	check(not fres["engawa"] and fres["points"] == far, "loin des maisons, la terrasse reste où on l'a tirée")


func _test_terrace_build() -> void:
	print("Terrasses : maillages")
	var st: BastideStyle = load(JAPANESE_PATH)
	var house := _garden_house()
	var ctx := BastideGardenContext.from_entries([house])
	var eng := PackedVector3Array([Vector3(10.06, 0, 0.5), Vector3(11.56, 0, 0.5), Vector3(11.56, 0, 5.5), Vector3(10.06, 0, 5.5)])
	var r := BastideTerraceMesher.build(eng, 3, st, ctx)
	check(_mesh_ok(r) and r.stats.get("engawa", false), "engawa : %d planches, %d poteaux, %d triangles" % [r.stats.get("boards", 0), r.stats.get("posts", 0), r.stats.get("triangles", 0)])
	var doors: Array = r.anchors.get("doors", [])
	check(doors.size() == 1 and not (doors[0] as Dictionary).get("stone", true), "ses marches sont déclarées comme une porte (sans pierre de chemin)")
	if doors.size() == 1:
		check(((doors[0] as Dictionary)["out"] as Vector3).dot(Vector3.RIGHT) > 0.99, "elle donne à l'opposé de la maison")
	var free := PackedVector3Array([Vector3(20, 0, 20), Vector3(24, 0, 20), Vector3(24, 0, 23), Vector3(20, 0, 23)])
	var rf := BastideTerraceMesher.build(free, 3, st, ctx)
	check(_mesh_ok(rf) and not rf.stats.get("engawa", true), "terrasse isolée : %d triangles" % rf.stats.get("triangles", 0))
	check(rf.stats.get("triangles", 0) > r.stats.get("triangles", 0), "garde-corps et marches en plus")
	check(rf.stats.get("triangles", 0) < 8000, "budget raisonnable")
	var rm := BastideTerraceMesher.build(free, 3, load(MEDIEVAL_PATH), ctx)
	check(_mesh_ok(rm), "en médiéval aussi")
	var a := BastideTerraceMesher.build(free, 5, st, ctx)
	var b := BastideTerraceMesher.build(free, 5, st, ctx)
	check(a.stats.get("triangles") == b.stats.get("triangles") and str(a.anchors) == str(b.anchors), "déterministe")
	# Le côté des marches demandé est respecté (sauf contre la maison).
	var r2 := BastideTerraceMesher.build(free, 3, st, ctx, true, 2)
	check(r2.stats.get("entry", -1) == 2, "côté des marches choisi")
	var r3 := BastideTerraceMesher.build(eng, 3, st, ctx, true, BastideTerraceRules.house_side(BastideTerraceRules.fit_rect(eng), ctx))
	check(r3.stats.get("entry", -1) != BastideTerraceRules.house_side(BastideTerraceRules.fit_rect(eng), ctx), "jamais de marches contre la maison")


func _test_terrace_neighbours() -> void:
	print("Terrasses : les voisins les voient")
	var st: BastideStyle = load(JAPANESE_PATH)
	var free := PackedVector3Array([Vector3(20, 0, 20), Vector3(24, 0, 20), Vector3(24, 0, 23), Vector3(20, 0, 23)])
	var rf := BastideTerraceMesher.build(free, 3, st, BastideGardenContext.new(), true, 1)
	var door: Dictionary = (rf.anchors["doors"] as Array)[0]
	var terrace := {"kind": "terrace", "footprint": rf.anchors["rect"], "doors": rf.anchors["doors"], "height": 0.45}
	var ctx := BastideGardenContext.from_entries([terrace])
	check(ctx.doors().size() == 1, "ses marches comptent parmi les portes")
	var dpos: Vector3 = door["pos"]
	var dout: Vector3 = door["out"]
	var path := BastidePathMesher.build(PackedVector3Array([dpos + dout * 10.0 + Vector3(0, 0, 3), dpos + dout * 2.5]), 4, st, ctx)
	check(path.stats.get("doors", 0) == 1, "un chemin qui arrive près des marches les rejoint")
	var pl := BastidePathMesher.plan(PackedVector3Array([dpos + dout * 10.0, dpos + dout * 2.5]), 4, st.get_garden_style(), ctx)
	check((pl["step_stones"] as Array).is_empty(), "sans ajouter de pierre de seuil devant des marches")
	var plan := BastidePlantingMesher.plan_garden(ctx, 7, st.get_garden_style())
	var under := 0
	for it: Dictionary in plan["items"]:
		var p: Vector3 = it["pos"]
		if ctx.terrace_clearance(Vector2(p.x, p.z)) < 0.0:
			under += 1
	var massif := BastidePlantingMesher.plan_planting(PackedVector3Array([Vector3(18, 0, 21.5), Vector3(26, 0, 21.5)]), 3, st.get_garden_style(), ctx)
	for it: Dictionary in massif:
		var p: Vector3 = it["pos"]
		if ctx.terrace_clearance(Vector2(p.x, p.z)) < 0.0:
			under += 1
	check(under == 0, "aucune plante sous la terrasse (%d)" % under)


func _test_kit_trees() -> void:
	print("Kit nature : arbres d'Onsen à couronnes peintes")
	for sp: String in BastideKitNature.SPECIES:
		var tr := BastideKitNature.tree(sp, 0, 1.0)
		var ok: bool = tr["crown"] != null and (tr["crown"] as ArrayMesh).get_surface_count() == 1 and tr["shadow"] != null
		check(ok, "%s : couronne en cartes et silhouette d'ombre" % sp)
	var small := BastideKitNature.tree("chene", 0, 1.0)
	var big := BastideKitNature.tree("chene", 0, 1.5)
	check(absf((big["box"] as AABB).size.y / (small["box"] as AABB).size.y - 1.5) < 0.02, "l'échelle agrandit l'arbre entier")
	check(BastideKitNature.tree("chene", 0, 1.5) == big, "un même arbre n'est calculé qu'une fois (cache)")
	var far := BastideKitNature.tree("chene", 0, 1.5, true)
	var n_near := (big["crown"] as ArrayMesh).surface_get_array_len(0)
	var n_far := (far["crown"] as ArrayMesh).surface_get_array_len(0)
	check(n_far * 3 < n_near, "la version lointaine a bien moins de cartes (%d / %d)" % [n_far, n_near])
	for model in ["fern", "iris", "hydrangea_blue", "azalea_red", "bush_1", "bamboo", "flowers_meadow"]:
		var pl := BastideKitNature.plant(model)
		check(pl.get("mesh") != null, "plante %s" % model)
	check(not BastideKitNature.tuft("fern").is_empty() and not BastideKitNature.tuft("meadow").is_empty(), "touffes peintes de fougère et de fleurs")


func _test_forest() -> void:
	print("Forêts : grands arbres espacés, sous-bois, voisins évités")
	var zone := PackedVector3Array([Vector3(-30, 0, -20), Vector3(30, 0, -20), Vector3(30, 0, 20), Vector3(-30, 0, 20)])
	var poly := PackedVector2Array()
	for p in zone:
		poly.append(Vector2(p.x, p.z))
	var house := {"kind": "house", "footprint": PackedVector3Array([Vector3(-4, 0, -4), Vector3(4, 0, -4), Vector3(4, 0, 4), Vector3(-4, 0, 4)]), "doors": []}
	var path := {"kind": "path", "points": PackedVector3Array([Vector3(-40, 0, 12), Vector3(40, 0, 12)]), "width": 1.6}
	var ctx := BastideGardenContext.from_entries([house, path])
	for kind in BastideForestBuilder.Kind.values():
		var pl := BastideForestBuilder.plan(zone, 5, kind, 1.0, 1.0, 1.0, ctx)
		var trees: Array = pl["trees"]
		var inside := true
		var clear := true
		var min_gap := INF
		for i in trees.size():
			var t: Dictionary = trees[i]
			var q := Vector2((t["pos"] as Vector3).x, (t["pos"] as Vector3).z)
			inside = inside and Geometry2D.is_point_in_polygon(q, poly)
			clear = clear and ctx.house_clearance(q) > 1.0 and ctx.path_clearance(q) > 1.0
			for j in range(i + 1, trees.size()):
				var u: Dictionary = trees[j]
				min_gap = minf(min_gap, q.distance_to(Vector2((u["pos"] as Vector3).x, (u["pos"] as Vector3).z)))
		check(trees.size() >= 6 and inside and clear and min_gap > 3.0,
				"forêt %s : %d arbres dans la zone, hors maison et chemin, troncs à ≥ %.1f m" % [BastideForestBuilder.Kind.keys()[kind], trees.size(), min_gap])
	var r := BastideForestBuilder.build(zone, 5, BastideForestBuilder.Kind.MIXED, 1.0, 1.0, 1.0, ctx, true)
	check(r.stats["plants"] > 50 and not r.instances.is_empty(), "sous-bois et instances (%d plantes, %d groupes)" % [r.stats["plants"], r.instances.size()])
	check(r.collision_faces.size() == r.stats["trees"] * 8 * 6, "chaque tronc a sa collision")
	var heights := []
	for t: Dictionary in BastideForestBuilder.plan(zone, 5, BastideForestBuilder.Kind.OAKS, 1.0, 1.0, 0.0, ctx)["trees"]:
		heights.append(float(BastideKitNature.SPECIES[t["species"]]["height"]) * float(t["size"]))
	heights.sort()
	check(heights[heights.size() - 1] >= 15.0 and heights[heights.size() - 1] <= 21.0, "chênaie : les grands arbres font 15 à 20 m (%.1f m)" % heights[heights.size() - 1])
	var r0 := BastideForestBuilder.build(zone, 5, BastideForestBuilder.Kind.MIXED, 1.0, 1.0, 0.0, ctx, false)
	check(r0.stats["plants"] == 0 and r0.collision_faces.is_empty(), "sans sous-bois ni collisions sur demande")



# --- Relief ------------------------------------------------------------------------

func _box_result(x0: float, x1: float) -> BastideBuildResult:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := [Vector3(x0, 0, 0), Vector3(x1, 0, 0), Vector3(x1, 0, 2), Vector3(x0, 0, 2),
		Vector3(x0, 2, 0), Vector3(x1, 2, 0), Vector3(x1, 2, 2), Vector3(x0, 2, 2)]
	for q in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]]:
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.add_vertex(c[q[k]])
	var r := BastideBuildResult.new()
	r.mesh = st.commit()
	r.collision_faces = PackedVector3Array([c[0], c[1], c[5]])
	return r


func _test_terrain() -> void:
	# Un plan incliné : h = 0,1 x.
	var f := BastideHeightField.flat(Vector2(-20, -20), 1.0, 41, 41)
	for j in 41:
		for i in 41:
			f.set_at(i, j, 0.1 * (i - 20))
	check(absf(f.height(5.5, 3.2) - 0.55) < 1e-4, "relief : hauteur interpolée (%.3f)" % f.height(5.5, 3.2))
	check(absf(f.height(500, 0) - 2.0) < 1e-4, "relief : hors grille, la hauteur du bord")
	var hit: Variant = f.raycast(Vector3(3, 10, 0), Vector3(0, -1, 0))
	check(hit != null and absf((hit as Vector3).y - 0.3) < 0.01, "relief : un rayon vertical touche le sol")
	var hit2: Variant = f.raycast(Vector3(-10, 8, 0), Vector3(1, -0.5, 0))
	check(hit2 != null and absf((hit2 as Vector3).y - f.height((hit2 as Vector3).x, 0)) < 0.01, "relief : un rayon oblique s'arrête sur la pente")
	var rng := f.range_under(PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 2), Vector2(0, 2)]))
	check(absf(rng["min"]) < 1e-3 and absf(rng["max"] - 0.4) < 1e-3, "relief : hauteurs sous un contour (%.2f à %.2f)" % [rng["min"], rng["max"]])

	# Épouser la pente : chaque sommet monte du sol sous lui.
	var follow := _box_result(0, 4)
	follow.add_instances(BoxMesh.new(), null, [Transform3D(Basis(), Vector3(3, 0, 1))])
	BastideDrape.apply(follow, f, Transform3D.IDENTITY, BastideDrape.Mode.FOLLOW)
	var ok := true
	for v: Vector3 in follow.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var flat_y := 2.0 if v.y > 1.0 + 0.1 * v.x else 0.0
		ok = ok and absf(v.y - (flat_y + 0.1 * v.x)) < 1e-4
	check(ok, "épouser : murets et chemins suivent la pente")
	check(absf((follow.instances[0]["transforms"][0] as Transform3D).origin.y - 0.3) < 1e-4, "épouser : les plantes se posent au sol")
	check(absf(follow.collision_faces[1].y - 0.4) < 1e-4, "épouser : la collision suit")

	# D'aplomb : posé sur le point haut, le pied descend en soubassement.
	var rigid := _box_result(0, 4)
	var lift := BastideDrape.apply(rigid, f, Transform3D(Basis(), Vector3(2, 0, 0)), BastideDrape.Mode.RIGID)
	check(absf(lift - 0.6) < 1e-4, "d'aplomb : posé sur le point le plus haut de l'assise (%.2f)" % lift)
	var tops := []
	var feet_ok := true
	for v: Vector3 in rigid.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if v.y > 1.0:
			tops.append(v.y)
		else:
			feet_ok = feet_ok and absf(v.y - (0.1 * (v.x + 2.0) - BastideDrape.SINK)) < 1e-4
	check(tops.all(func(y: float) -> bool: return absf(y - 2.6) < 1e-4), "d'aplomb : le haut reste horizontal")
	check(feet_ok, "d'aplomb : le pied rejoint le sol, un peu enfoncé")


func _rect(w: float, d: float) -> PackedVector3Array:
	return PackedVector3Array([Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, d), Vector3(0, 0, d)])


func _test_silhouettes() -> void:
	var K := BastideSilhouette.Kind
	var fp := func(w: float, d: float) -> PackedVector2Array:
		return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, d), Vector2(0, d)])
	check(BastideSilhouette.resolve(K.AUTO, fp.call(4.2, 4.4), 1) == K.TOWER, "silhouette : petite base carrée → tour")
	check(BastideSilhouette.resolve(K.AUTO, fp.call(10, 7), 1) == K.HOUSE, "silhouette : grand rectangle → grande maison")
	var small: Array = []
	for sd in range(1, 30):
		small.append(BastideSilhouette.resolve(K.AUTO, fp.call(7, 4.5), sd))
	check(small.has(K.SMALL) and small.has(K.KURA) and not small.has(K.HOUSE), "silhouette : petit rectangle → petite maison ou kura selon la graine")
	check(BastideSilhouette.resolve(K.KURA, fp.call(10, 7), 1) == K.KURA, "silhouette : un choix explicite l'emporte")
	var jp: BastideStyle = load(JAPANESE_PATH)
	check(BastideSilhouette.style_for(jp, K.HOUSE) == jp, "silhouette : la grande maison garde le style tel quel")
	var tower := BastideSilhouette.style_for(jp, K.TOWER)
	check(tower == BastideSilhouette.style_for(jp, K.TOWER), "silhouette : variante en cache")
	check(jp.get_building_style().floors == 2 and not jp.get_building_style().pent_every_floor, "silhouette : le style de base n'est pas modifié")
	var tl := BastideBuildingGenerator.generate(BastideBuildingSpec.from_points(_rect(4.4, 4.4), 5), tower)
	check(tl.floors == 3 and tl.pent_roof and tl.pent_levels == 2, "tour : 3 niveaux, un auvent par étage (%d, %d)" % [tl.floors, tl.pent_levels])
	var kura := BastideSilhouette.style_for(jp, K.KURA)
	var kl := BastideBuildingGenerator.generate(BastideBuildingSpec.from_points(_rect(7, 4.5), 5), kura)
	check(not kl.is_empty() and not kl.pent_roof and kura.get_roof_style().roof_type == BastideRoofStyle.RoofType.GABLE, "kura : pignons, pas d'auvent")
	var sm := BastideSilhouette.style_for(jp, K.SMALL)
	var sl := BastideBuildingGenerator.generate(BastideBuildingSpec.from_points(_rect(7, 4.5), 5), sm)
	check(sl.floors == 1 and sl.eave_y < kl.eave_y, "petite maison : un niveau, plus basse que le kura")
	var tm := BastideBuilding.compute(BastideBuildingSpec.from_points(_rect(4.4, 4.4), 5), tower, true)
	check(tm.mesh != null and tm.mesh.get_surface_count() > 0 and not tm.collision_faces.is_empty(), "tour : maillage et collisions")


# --- Jardins d'eau -------------------------------------------------------------------

func _blob(cx: float, cz: float, r: float, n := 9) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in n:
		var a := TAU * i / n
		var rr := r * (1.0 + 0.18 * sin(a * 3.0))
		pts.append(Vector3(cx + cos(a) * rr * 1.3, 0, cz + sin(a) * rr))
	return pts


func _test_pond_shape() -> void:
	print("Étang : forme")
	var pts := _blob(0, 0, 4.0)
	var poly := BastidePondShape.outline(pts, 3)
	check(poly.size() > 30, "la rive est rééchantillonnée finement (%d points)" % poly.size())
	check(BastidePolygon.signed_area(poly) > 0.0, "la rive est dans le sens direct")
	check(not BastidePolygon.self_intersects(poly), "la rive ne se croise pas")
	var a0 := absf(BastideStroke.signed_area(pts))
	var a1 := BastidePolygon.signed_area(poly)
	check(a1 > a0 * 0.75 and a1 < a0 * 1.15, "la surface reste proche du tracé (%.0f / %.0f m²)" % [a1, a0])
	var max_turn := 0.0
	for i in poly.size():
		max_turn = maxf(max_turn, absf(BastidePolygon.turn_angle(poly, i)))
	check(max_turn < deg_to_rad(40.0), "pas d'angle vif sur la rive (%.0f°)" % rad_to_deg(max_turn))
	check(BastidePondShape.outline(pts, 3) == poly, "même tracé, même graine : même rive")
	check(BastidePondShape.outline(pts, 4) != poly, "autre graine : rive un peu différente")
	# Un tracé main levée qui se recoupe à peine ou un gribouillis minuscule.
	check(BastidePondShape.outline(_blob(0, 0, 0.8), 1).is_empty(), "un étang minuscule est refusé")
	var big := BastidePondShape.outline(_blob(0, 0, 60.0, 12), 1)
	var r := BastidePondShape.rect_of(big)
	check(maxf(r.size.x, r.size.y) <= BastidePondShape.MAX_SIDE + 3.0, "un étang géant est ramené à %.0f m" % BastidePondShape.MAX_SIDE)
	# Un carré dessiné grossièrement devient une forme douce.
	var sq := PackedVector3Array([Vector3(0, 0, 0), Vector3(8, 0, 0.3), Vector3(8.2, 0, 7), Vector3(-0.2, 0, 7.4)])
	var sp := BastidePondShape.outline(sq, 2)
	check(not sp.is_empty() and not BastidePolygon.self_intersects(sp), "un carré grossier devient un étang arrondi")
	check(BastidePondShape.signed_distance(Vector2(4, 3.6), sp) < -2.0 and BastidePondShape.signed_distance(Vector2(-3, 3.6), sp) > 1.0,
			"distance signée : négative dans l'eau, positive sur la berge")


func _slope_field(slope := 0.08) -> BastideHeightField:
	var f := BastideHeightField.flat(Vector2(-40, -40), 1.0, 81, 81)
	for j in 81:
		for i in 81:
			f.set_at(i, j, (i - 40) * slope)
	return f


func _test_pond_carve() -> void:
	print("Étang : creusement")
	var base := _slope_field()
	var poly := BastidePondShape.outline(_blob(0, 0, 5.0), 5)
	var level := BastidePondShape.water_level(base, poly)
	var lo := INF
	var hi := -INF
	for p in poly:
		lo = minf(lo, base.height(p.x, p.y))
		hi = maxf(hi, base.height(p.x, p.y))
	check(level < lo + 0.6 * (hi - lo) and level > lo - 0.5, "niveau d'eau entre bas et haut de la rive (%.2f dans [%.2f, %.2f])" % [level, lo, hi])
	var c := BastidePondShape.carve_info(poly, level)
	var f := BastideHeightField.flat(base.origin, base.cell, base.width, base.depth)
	f.heights = base.heights.duplicate()
	var paint := PackedColorArray()
	paint.resize(f.width * f.depth)
	paint.fill(Color(0, 0, 0, 1))
	var touched := BastidePondShape.apply(f, base, paint, c)
	check(touched.size.x > 10 and touched.size.y > 10, "zone touchée sur la grille")
	# Le centre est sous l'eau, la rive juste au-dessus, partout autour (pas de fuite).
	check(f.height(0, 0) < level - 0.4, "le centre est creusé (%.2f sous l'eau)" % (level - f.height(0, 0)))
	var leak := 0
	var dry_rim := 0
	for p in poly:
		var g := f.height(p.x, p.y)
		if g < level:
			leak += 1
		if g > level + 0.6:
			dry_rim += 1
	check(leak == 0, "la rive est partout au-dessus de l'eau : l'eau ne fuit pas (%d)" % leak)
	check(dry_rim < poly.size() / 10, "la rive affleure presque partout (%d points trop hauts)" % dry_rim)
	# Loin de l'étang, le sol n'a pas bougé.
	check(is_equal_approx(f.height(30, 30), base.height(30, 30)), "le sol est intact loin de l'étang")
	var wet := paint[40 * f.width + 40]
	check(wet.g > 0.9, "le lit de l'étang est peint")
	# Le relief garde la mémoire de l'eau.
	f.waters.append({"poly": poly, "level": level, "rect": BastidePondShape.rect_of(poly)})
	check(is_equal_approx(f.water_level(0, 0), level) and f.water_level(30, 30) == -INF, "le relief sait où est l'eau")
	check(f.water_depth(0, 0) > 0.4, "profondeur d'eau au centre (%.2f m)" % f.water_depth(0, 0))


func _test_pond_build() -> void:
	print("Étang : génération")
	var jp: BastideStyle = load(JAPANESE_PATH)
	var pts := _blob(0, 0, 5.0)
	var base := _slope_field(0.05)
	var r := BastidePondBuilder.build(pts, 7, BastidePondBuilder.Kind.GARDEN, jp, null, base, Transform3D.IDENTITY)
	check(r.mesh != null and r.mesh.get_surface_count() >= 3, "eau, pierres et nénuphars (%d surfaces)" % (r.mesh.get_surface_count() if r.mesh else 0))
	check(r.stats.get("rocks", 0) >= 2 and r.stats.get("stones", 0) >= 5, "rochers et pierres de rive (%d, %d)" % [r.stats.get("rocks", 0), r.stats.get("stones", 0)])
	check(r.stats.get("pebbles", 0) >= 30, "une rive de galets (%d)" % r.stats.get("pebbles", 0))
	check(r.stats.get("plants", 0) >= 6, "iris et massifs (%d)" % r.stats.get("plants", 0))
	check(r.stats.get("lilies", 0) >= 3, "nénuphars (%d)" % r.stats.get("lilies", 0))
	check(r.stats.get("koi", 0) >= 2, "carpes koï (%d)" % r.stats.get("koi", 0))
	var koi_ok := false
	for g: Dictionary in r.instances:
		if g.has("custom") and (g["custom"] as Array).size() == (g["transforms"] as Array).size():
			koi_ok = true
	check(koi_ok, "les koï portent leur cercle de nage (données par instance)")
	check(not r.collision_faces.is_empty(), "collisions (surface de l'eau, rochers)")
	check(r.anchors.has("carve") and r.anchors.has("shore"), "l'étang décrit son creusement et sa rive")
	var water_y: float = r.anchors["level"]
	var surf := -1
	for i in r.mesh.get_surface_count():
		if r.mesh.surface_get_name(i) == "water":
			surf = i
	var flat := surf >= 0
	if surf >= 0:
		for v: Vector3 in r.mesh.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX]:
			if absf(v.y - water_y) > 1e-4:
				flat = false
	check(flat, "l'eau est parfaitement à plat, même sur la pente")
	var r2 := BastidePondBuilder.build(pts, 7, BastidePondBuilder.Kind.GARDEN, jp, null, base, Transform3D.IDENTITY)
	check(r2.stats == r.stats, "même graine, même étang")
	var onsen := BastidePondBuilder.build(pts, 7, BastidePondBuilder.Kind.ONSEN, jp, null, base, Transform3D.IDENTITY)
	check(onsen.stats.get("rocks", 0) >= 15 and onsen.stats.get("koi", 0) == 0 and onsen.stats.get("lilies", 0) == 0,
			"onsen : cerné de rochers, sans koï ni nénuphars (%d rochers)" % onsen.stats.get("rocks", 0))
	check((onsen.anchors.get("steam", PackedVector3Array()) as PackedVector3Array).size() >= 3, "onsen : de la vapeur au-dessus de l'eau")
	var wild := BastidePondBuilder.build(pts, 7, BastidePondBuilder.Kind.WILD, jp, null, base, Transform3D.IDENTITY)
	check(wild.stats.get("plants", 0) > r.stats.get("plants", 0) and wild.stats.get("lilies", 0) >= r.stats.get("lilies", 0),
			"mare sauvage : plus de roseaux et de nénuphars")
	check(BastidePondBuilder.build(_blob(0, 0, 0.5), 7, 0, jp, null, base, Transform3D.IDENTITY).is_empty(), "tracé trop petit : rien")
	# Sans relief : posé à plat.
	var r0 := BastidePondBuilder.build(pts, 7, 0, jp, null, null, Transform3D.IDENTITY)
	check(not r0.is_empty() and is_equal_approx(float(r0.anchors["level"]), -BastidePondShape.FREEBOARD), "sans relief : eau juste sous le sol")
	var t0 := Time.get_ticks_msec()
	BastidePondBuilder.build(_blob(0, 0, 12.0, 12), 9, 0, jp, null, _slope_field(0.03), Transform3D.IDENTITY)
	var ms := Time.get_ticks_msec() - t0
	check(ms < 3000, "un grand étang se génère vite (%d ms)" % ms)


func _test_pond_bridges() -> void:
	print("Étang : ponts")
	var jp: BastideStyle = load(JAPANESE_PATH)
	var pts := _blob(0, 0, 5.0)
	var ctx_of := func(line: Array) -> BastideGardenContext:
		return BastideGardenContext.from_entries([{"kind": "path", "points": PackedVector3Array(line), "width": 1.5}])
	# Traverse l'étang de part en part : un pont arqué.
	var across := BastidePondBuilder.build(pts, 7, 0, jp, ctx_of.call([Vector3(-12, 0, 0.5), Vector3(12, 0, 0.5)]), null, Transform3D.IDENTITY)
	var br: Array = across.anchors.get("bridges", [])
	check(br.size() == 1, "un chemin qui traverse : un pont (%d)" % br.size())
	if br.size() == 1:
		check(br[0]["kind"] == "arch" or br[0]["kind"] == "zigzag", "au-dessus d'un bras d'eau : pont en bois (%s, %.1f m)" % [br[0]["kind"], br[0]["span"]])
	# Coupe juste un coin de l'étang : des pierres de gué.
	var corner := BastidePondBuilder.build(pts, 7, 0, jp, ctx_of.call([Vector3(5.2, 0, -8), Vector3(6.05, 0, 0.6), Vector3(5.2, 0, 8)]), null, Transform3D.IDENTITY)
	var cb: Array = corner.anchors.get("bridges", [])
	check(cb.size() >= 1 and cb[0]["kind"] == "stones", "coin de l'étang : pierres de gué (%s)" % (str(cb[0]) if cb.size() > 0 else "rien"))
	# Le chemin s'arrête dans l'eau : pas de pont vers nulle part.
	var dead := BastidePondBuilder.build(pts, 7, 0, jp, ctx_of.call([Vector3(-12, 0, 0), Vector3(0, 0, 0)]), null, Transform3D.IDENTITY)
	check((dead.anchors.get("bridges", []) as Array).is_empty(), "chemin qui finit dans l'eau : pas de pont")
	# Un long étang traversé dans la longueur : passerelle en zigzag.
	var long_pts := PackedVector3Array()
	for i in 10:
		var a := TAU * i / 10.0
		long_pts.append(Vector3(cos(a) * 9.5, 0, sin(a) * 3.2))
	var zz := BastidePondBuilder.build(long_pts, 7, 0, jp, ctx_of.call([Vector3(-16, 0, 0), Vector3(16, 0, 0.2)]), null, Transform3D.IDENTITY)
	var zb: Array = zz.anchors.get("bridges", [])
	check(zb.size() == 1 and zb[0]["kind"] == "zigzag", "longue traversée : passerelle en zigzag (%s)" % (zb[0]["kind"] if zb.size() > 0 else "rien"))
	# Le gravier du chemin noyé est retiré.
	var f := BastideHeightField.flat(Vector2(-20, -20), 1.0, 41, 41)
	var poly := BastidePondShape.outline(pts, 7)
	var c := BastidePondShape.carve_info(poly, -0.2)
	BastidePondShape.apply(f, BastideHeightField.flat(Vector2(-20, -20), 1.0, 41, 41), PackedColorArray(), c)
	f.waters.append({"poly": poly, "level": -0.2, "rect": BastidePondShape.rect_of(poly)})
	var path := BastidePathMesher.build(PackedVector3Array([Vector3(-12, 0, 0.5), Vector3(12, 0, 0.5)]), 3, jp, BastideGardenContext.new(), true)
	var before := 0
	for i in path.mesh.get_surface_count():
		before += path.mesh.surface_get_array_len(i)
	BastideDrape.apply(path, f, Transform3D.IDENTITY, BastideDrape.Mode.FOLLOW)
	var gone := BastideDrape.clip_water(path, f, Transform3D.IDENTITY)
	var after := 0
	for i in path.mesh.get_surface_count():
		after += path.mesh.surface_get_array_len(i)
	check(gone > 20 and after < before, "le gravier noyé du chemin disparaît (%d triangles)" % gone)


func _test_pond_neighbours() -> void:
	print("Étang : voisins")
	var poly := BastidePondShape.outline(_blob(0, 0, 4.0), 3)
	var shore := PackedVector3Array()
	for p in poly:
		shore.append(Vector3(p.x, -0.3, p.y))
	var ctx := BastideGardenContext.from_entries([{"kind": "pond", "footprint": shore, "pond_kind": 0}])
	check(ctx.ponds.size() == 1 and is_equal_approx(float(ctx.ponds[0]["level"]), -0.3), "le voisinage connaît l'étang et son niveau")
	check(ctx.blocked(Vector2(0, 0), 0.3), "on ne plante rien dans l'eau")
	check(not ctx.blocked(Vector2(12, 0), 0.3), "loin de l'étang, la place est libre")
	# Les arbres d'une forêt évitent l'eau.
	var forest_pts := PackedVector3Array([Vector3(-20, 0, -20), Vector3(20, 0, -20), Vector3(20, 0, 20), Vector3(-20, 0, 20)])
	var fr := BastideForestBuilder.build(forest_pts, 3, BastideForestBuilder.Kind.MIXED, 1.0, 1.0, 1.0, ctx, false)
	var wet := 0
	for t: Vector3 in fr.anchors.get("trees", []):
		if BastidePondShape.signed_distance(Vector2(t.x, t.z), poly) < 0.5:
			wet += 1
	check(wet == 0, "aucun arbre de forêt dans l'eau (%d)" % wet)


func _farm_rect(cx: float, cz: float, hx: float, hz: float) -> PackedVector3Array:
	return PackedVector3Array([Vector3(cx - hx, 0, cz - hz), Vector3(cx + hx, 0, cz - hz), Vector3(cx + hx, 0, cz + hz), Vector3(cx - hx, 0, cz + hz)])


func _test_farm_build() -> void:
	print("Champs : potager et thé")
	var jp: BastideStyle = load(JAPANESE_PATH)
	var base := _slope_field(0.04)
	var r := BastideFarmBuilder.build(_farm_rect(0, 0, 8, 6), 5, BastideFarmBuilder.Kind.VEGETABLE, jp, null, base, Transform3D.IDENTITY)
	check(r.stats.get("beds", 0) >= 5, "des planches de culture (%d)" % r.stats.get("beds", 0))
	check(r.stats.get("crops", 0) >= 100, "des légumes plantés en lignes (%d)" % r.stats.get("crops", 0))
	check(r.stats.get("fence_posts", 0) >= 15 and r.stats.get("gate", false), "une clôture de bambou avec son entrée (%d poteaux)" % r.stats.get("fence_posts", 0))
	check(r.stats.get("scarecrows", 0) == 1, "un épouvantail")
	var kinds := {}
	for g: Dictionary in r.instances:
		kinds[g["mesh"]] = true
	check(kinds.size() >= 3, "plusieurs cultures (%d maillages)" % kinds.size())
	# La terre suit le relief, juste au-dessus du sol d'origine.
	var high := 0
	var low := 0
	for g: Dictionary in r.instances:
		for t: Transform3D in g["transforms"]:
			var gy := base.height(t.origin.x, t.origin.z)
			if t.origin.y < gy:
				low += 1
			if t.origin.y > gy + 0.35:
				high += 1
	check(low == 0 and high == 0, "les légumes sont posés sur leur planche (%d dessous, %d trop haut)" % [low, high])
	var carve: Dictionary = r.anchors.get("carve", {})
	check(carve.get("type", "") == "floor", "le champ abaisse le relief sous lui")
	var probe := BastideHeightField.flat(base.origin, base.cell, base.width, base.depth)
	probe.heights = base.heights.duplicate()
	BastideTerrain._apply_floor(probe, carve)
	check(probe.height(0, 0) < base.height(0, 0) - 0.1 and is_equal_approx(probe.height(20, 0), base.height(20, 0)),
			"sous le champ seulement (%.2f m plus bas)" % (base.height(0, 0) - probe.height(0, 0)))
	var tea := BastideFarmBuilder.build(_farm_rect(0, 0, 9, 7), 6, BastideFarmBuilder.Kind.TEA, jp, null, base, Transform3D.IDENTITY)
	check(tea.stats.get("hedges", 0) >= 5, "des haies de thé (%d)" % tea.stats.get("hedges", 0))
	check(tea.stats.get("fans", 0) >= 1, "un ventilateur antigel (%d)" % tea.stats.get("fans", 0))
	# Les rangs de thé suivent les courbes de niveau (pente selon x : rangs selon z).
	var axis: Vector2 = tea.anchors.get("axis", Vector2.ZERO)
	check(absf(axis.y) > 0.95, "les rangs suivent les courbes de niveau (axe %s)" % str(axis))
	var tiny := BastideFarmBuilder.build(_farm_rect(0, 0, 1, 1), 6, BastideFarmBuilder.Kind.TEA, jp, null, base, Transform3D.IDENTITY)
	check(tiny.mesh == null, "un champ minuscule est refusé")


func _test_farm_rice() -> void:
	print("Champs : rizière en terrasses")
	var jp: BastideStyle = load(JAPANESE_PATH)
	var base := _slope_field(0.15)
	var r := BastideFarmBuilder.build(_farm_rect(0, 0, 8, 7), 8, BastideFarmBuilder.Kind.RICE, jp, null, base, Transform3D.IDENTITY)
	check(r.stats.get("terraces", 0) >= 3, "la pente est taillée en terrasses (%d)" % r.stats.get("terraces", 0))
	check(r.stats.get("rice", 0) >= 200, "du riz repiqué (%d touffes)" % r.stats.get("rice", 0))
	var surf := -1
	for i in r.mesh.get_surface_count():
		if r.mesh.surface_get_name(i) == "water":
			surf = i
	check(surf >= 0, "de l'eau dans les rizières")
	if surf >= 0:
		# Chaque terrasse est d'eau plate : peu de niveaux d'eau différents.
		var levels := {}
		for p: Vector3 in r.mesh.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX]:
			levels[snappedf(p.y, 0.01)] = true
		check(levels.size() == r.stats.get("terraces", 0), "une eau à plat par terrasse (%d niveaux)" % levels.size())
	var stone := false
	for i in r.mesh.get_surface_count():
		if r.mesh.surface_get_name(i) == "stone":
			stone = true
	check(stone, "des murets de pierres sèches entre les terrasses")
	var flat := BastideFarmBuilder.build(_farm_rect(0, 0, 8, 7), 8, BastideFarmBuilder.Kind.RICE, jp, null, _slope_field(0.0), Transform3D.IDENTITY)
	check(flat.stats.get("paddies", 0) >= 2, "sur le plat, des rizières séparées par des levées (%d)" % flat.stats.get("paddies", 0))


func _test_farm_neighbours() -> void:
	print("Champs : voisins")
	var poly := BastidePondShape.outline(_farm_rect(0, 0, 6, 5), 3, 0.0)
	var fp := PackedVector3Array()
	for p in poly:
		fp.append(Vector3(p.x, 0, p.y))
	var ctx := BastideGardenContext.from_entries([{"kind": "farm", "footprint": fp, "farm_kind": 0}])
	check(ctx.farms.size() == 1, "le voisinage connaît le champ")
	check(ctx.blocked(Vector2(0, 0), 0.3), "on ne plante rien dans un champ")
	check(not ctx.blocked(Vector2(14, 0), 0.3), "à côté, la place est libre")
	# Un chemin qui traverse : pas de planche dessus.
	var jp: BastideStyle = load(JAPANESE_PATH)
	var pctx := BastideGardenContext.from_entries([{"kind": "path", "points": PackedVector3Array([Vector3(0, 0, -10), Vector3(0, 0, 10)]), "width": 1.5}])
	var r := BastideFarmBuilder.build(_farm_rect(0, 0, 8, 6), 5, BastideFarmBuilder.Kind.VEGETABLE, jp, pctx, null, Transform3D.IDENTITY)
	var on_path := 0
	for g: Dictionary in r.instances:
		for t: Transform3D in g["transforms"]:
			if absf(t.origin.x) < 0.75:
				on_path += 1
	check(on_path == 0, "aucun légume sur le chemin qui traverse (%d)" % on_path)



# --- Intérieurs ----------------------------------------------------------------------

func _interior_for(shape: Array, kind: int, style_path: String, seed := 7) -> Array:
	var spec := BastideBuildingSpec.new()
	spec.footprint = PackedVector2Array(shape)
	spec.seed = seed
	var st := BastideSilhouette.style_for(load(style_path), kind)
	var layout := BastideBuildingGenerator.generate(spec, st)
	return [layout, BastideInteriorPlanner.plan(layout, st), st]


const JP_PATH := "res://addons/bastide/styles/presets/japanese_wood.tres"
const TOWER_BASE := [Vector2(0, 0), Vector2(4.6, 0), Vector2(4.6, 4.6), Vector2(0, 4.6)]
const KURA_BASE := [Vector2(0, 0), Vector2(6.8, 0), Vector2(6.8, 4.4), Vector2(0, 4.4)]
const SMALL_BASE := [Vector2(0, 0), Vector2(6, 0), Vector2(6, 5), Vector2(0, 5)]


func _test_interior_terrain() -> void:
	print("Intérieurs : les sols restent au-dessus du terrain")
	var spec := BastideBuildingSpec.new()
	spec.footprint = PackedVector2Array(RECT)
	spec.seed = 7
	var st := BastideSilhouette.style_for(load(JP_PATH), BastideSilhouette.Kind.HOUSE)
	var layout := BastideBuildingGenerator.generate(spec, st)
	var flat := BastideInteriorPlanner.plan(layout, st, -0.05)
	check(flat.genkan_y >= -0.05 + 0.05 and is_equal_approx(flat.genkan_y, layout.base_y + 0.03),
		"terrain plus bas que l'entrée : rien ne change (%.2f m)" % flat.genkan_y)
	var bump := BastideInteriorPlanner.plan(layout, st, 0.2)
	check(bump.genkan_y >= 0.25, "une bosse sous la maison : l'entrée passe au-dessus (%.2f m)" % bump.genkan_y)
	check(bump.levels[0].y - bump.genkan_y >= 0.12 and bump.levels[0].y >= 0.3,
		"… et le parquet reste plus haut que l'entrée (%.2f m)" % bump.levels[0].y)
	check(bump.flights.size() == flat.flights.size(), "… l'escalier monte toujours à l'étage")


func _test_trees_stay_outside() -> void:
	print("Décor : les branches des arbres ne traversent pas les murs")
	var gs := (load(JAPANESE_PATH) as BastideStyle).get_garden_style()
	var house := _garden_house()
	var ctx := BastideGardenContext.from_entries([house])
	# Maison en L : l'angle rentrant reçoit un arbre.
	var l_ctx := BastideGardenContext.from_entries([_garden_house(PackedVector3Array([Vector3(0, 0, 0), Vector3(12, 0, 0),
		Vector3(12, 0, 5), Vector3(6, 0, 5), Vector3(6, 0, 10), Vector3(0, 0, 10)]))])
	var worst := INF
	var trees := 0
	for seed in 40:
		for it: Dictionary in BastidePlantingMesher.plan_garden(l_ctx, seed, gs)["items"]:
			var r := BastidePlantingMesher.crown_reach(String(it["type"]), float(it["size"]))
			if r <= 0.0:
				continue
			trees += 1
			var p: Vector3 = it["pos"]
			worst = minf(worst, l_ctx.house_clearance(Vector2(p.x, p.z), 10.0) - r)
	check(trees == 0 or worst >= 0.0, "jardins auto : couronnes hors des murs (%d arbres, marge %.2f m)" % [trees, worst])
	# Un arbre planté contre le mur : rapetissé, sa couronne reste dehors.
	var spot := Vector3(5, 0, -1.4)
	var one := BastidePlantingMesher.plan_planting(PackedVector3Array([spot]), 3, gs, ctx)
	var t: Dictionary = one[0]
	var reach := BastidePlantingMesher.crown_reach(String(t["type"]), float(t["size"]))
	check(ctx.house_clearance(Vector2(spot.x, spot.z), 10.0) - reach >= -0.01 or float(t["size"]) <= 1.21,
		"arbre posé à 1,4 m d'un mur : plus petit (%.1f m), couronne dehors" % float(t["size"]))


func _test_interior_plan() -> void:
	print("Intérieurs : niveaux et escaliers")
	var cases := [["grande maison", RECT, BastideSilhouette.Kind.HOUSE], ["maison en L", L_SHAPE, BastideSilhouette.Kind.HOUSE],
		["petite maison", SMALL_BASE, BastideSilhouette.Kind.SMALL], ["kura", KURA_BASE, BastideSilhouette.Kind.KURA],
		["tour", TOWER_BASE, BastideSilhouette.Kind.TOWER]]
	for path in [JP_PATH, MEDIEVAL_PATH]:
		var tag := "japonais" if path == JP_PATH else "médiéval"
		for c: Array in cases:
			var r := _interior_for(c[1], c[2], path)
			var layout: BastideBuildingLayout = r[0]
			var il: BastideInteriorLayout = r[1]
			check(il.levels.size() == layout.floors, "%s %s : un plancher par étage (%d)" % [tag, c[0], il.levels.size()])
			check(il.flights.size() == layout.floors - 1, "%s %s : un escalier par étage à monter (%d) %s" % [tag, c[0], il.flights.size(), il.notes])
			check(not il.door.is_empty(), "%s %s : la porte est connue de l'intérieur" % [tag, c[0]])
			if path == JP_PATH:
				check(not il.genkan.is_empty() and il.levels[0].y - il.genkan_y > 0.25,
					"%s %s : entrée en contrebas et plancher surélevé (%.2f m)" % [tag, c[0], il.levels[0].y - il.genkan_y])
	var a: BastideInteriorLayout = _interior_for(RECT, BastideSilhouette.Kind.HOUSE, JP_PATH, 5)[1]
	var b: BastideInteriorLayout = _interior_for(RECT, BastideSilhouette.Kind.HOUSE, JP_PATH, 5)[1]
	check(a.flights[0].start == b.flights[0].start and a.flights[0].dir == b.flights[0].dir, "même maison, même escalier")


func _test_interior_stairs_rules() -> void:
	print("Intérieurs : règles des escaliers")
	for c: Array in [[RECT, BastideSilhouette.Kind.HOUSE], [L_SHAPE, BastideSilhouette.Kind.HOUSE],
			[KURA_BASE, BastideSilhouette.Kind.KURA], [TOWER_BASE, BastideSilhouette.Kind.TOWER], [U_SHAPE, BastideSilhouette.Kind.HOUSE]]:
		for path in [JP_PATH, MEDIEVAL_PATH]:
			var r := _interior_for(c[0], c[1], path, 11)
			var layout: BastideBuildingLayout = r[0]
			var il: BastideInteriorLayout = r[1]
			var name := "%s, %d côtés" % ["japonais" if path == JP_PATH else "médiéval", c[0].size()]
			var grown := BastidePolygon.offset(il.inner, -0.03)
			for fl: BastideInteriorLayout.Flight in il.flights:
				check(fl.riser() <= BastideInteriorPlanner.RISER_MAX + 1e-4 and fl.riser() > 0.15,
					"%s : marches de %.0f cm" % [name, fl.riser() * 100.0])
				# Pente gravissable par le promeneur (normale assez verticale).
				var slope := atan2(fl.riser(), fl.tread)
				check(cos(slope) > 0.62, "%s : pente de %.0f°" % [name, rad_to_deg(slope)])
				check(BastideInteriorPlanner.inside(fl.rect(0.3, 0.3), grown), "%s : la volée tient dans la maison" % name)
				if not il.genkan.is_empty() and fl.from_level == 0:
					check(not BastideInteriorPlanner.overlaps(fl.rect(0.3, 0.3), il.genkan), "%s : rien devant la porte" % name)
			for k in range(1, il.flights.size()):
				var lo: BastideInteriorLayout.Flight = il.flights[k - 1]
				var hi: BastideInteriorLayout.Flight = il.flights[k]
				check(not BastideInteriorPlanner.overlaps(hi.rect(0.3, 0.3), lo.rect(0.0, 0.5)),
					"%s : la volée %d ne mord pas la trémie du dessous" % [name, k])
			if il.flights.size() == layout.floors - 1 and layout.floors > 1:
				var up: BastideInteriorLayout.Level = il.levels[1]
				var area := 0.0
				for p: PackedVector2Array in up.pieces:
					area += BastidePolygon.signed_area(p)
				var hole: float = BastidePolygon.signed_area(up.holes[0])
				check(area < BastidePolygon.signed_area(il.inner) - hole * 0.8, "%s : la trémie est découpée dans le plancher" % name)
				check(up.railings.size() == 2, "%s : garde-corps autour de la trémie" % name)


func _test_interior_meshes() -> void:
	print("Intérieurs : maillages et collisions")
	var r := _interior_for(RECT, BastideSilhouette.Kind.HOUSE, JP_PATH)
	var layout: BastideBuildingLayout = r[0]
	var il: BastideInteriorLayout = r[1]
	var st: BastideStyle = r[2]
	var res := BastideInteriorMesher.build(il, layout, st)
	check(res.mesh != null and res.mesh.get_surface_count() >= 3, "l'intérieur a son maillage (%d surfaces)" % (res.mesh.get_surface_count() if res.mesh else 0))
	check(int(res.stats["triangles"]) < 12000, "intérieur léger (%d triangles)" % int(res.stats["triangles"]))
	check(res.collision_faces.size() % 3 == 0 and res.collision_faces.size() > 30, "planchers et escaliers ont une collision")
	check((res.anchors["lights"] as PackedVector3Array).size() == il.levels.size(), "une lumière douce par niveau")
	var closed := BastideBuildingMesher.build(layout, st, true, false)
	var open := BastideBuildingMesher.build(layout, st, true, true)
	check(not closed.anchors.has("door_leaves"), "de loin : la maison habituelle, sans vantaux à part")
	check((open.anchors["door_leaves"] as Array).size() == 2, "de près : deux vantaux de shoji qui coulissent")
	for d: Dictionary in open.anchors["door_leaves"]:
		check((d["slide"] as Vector3).length() > 0.5, "un vantail glisse de %.2f m dans le mur" % (d["slide"] as Vector3).length())
	# La porte ouverte est franchissable : un rayon horizontal passe au milieu du seuil.
	var door: Dictionary = open.anchors["doors"][0]
	var p: Vector3 = door["pos"] + Vector3(0, 1.0, 0)
	var dir: Vector3 = -(door["out"] as Vector3)
	check(_ray_hits(closed.collision_faces, p + (door["out"] as Vector3), dir, 2.0), "porte fermée : le mur arrête le pas")
	check(not _ray_hits(open.collision_faces, p + (door["out"] as Vector3), dir, 2.0), "porte ouverte : on passe")
	# Depuis l'entrée, sous le niveau du parquet : on voit le bord du plancher, pas le dessous.
	var lv0: BastideInteriorLayout.Level = il.levels[0]
	var in2: Vector2 = il.door["inward"]
	var inward := Vector3(in2.x, 0, in2.y)
	var eye_y := lerpf(il.genkan_y, lv0.y, 0.8)
	var seen := 0
	for k in 5:
		var dp: Vector2 = il.door["pos"]
		var from := Vector3(dp.x, eye_y, dp.y) + inward * 0.25 + Vector3(-inward.z, 0, inward.x) * (k - 2) * 0.15
		if _front_hit(res.mesh, from, inward, 8.0):
			seen += 1
	check(seen == 5, "entrée : le bord du plancher se voit, on ne voit pas dessous (%d/5)" % seen)
	var med := _interior_for(RECT, BastideSilhouette.Kind.HOUSE, MEDIEVAL_PATH)
	var mopen := BastideBuildingMesher.build(med[0], med[2], true, true)
	check((mopen.anchors["door_leaves"] as Array).size() == 1 and mopen.anchors["door_leaves"][0]["kind"] == "hinge",
		"médiéval : une porte de bois qui pivote")


## Vrai si le premier triangle du maillage touché par le rayon est tourné vers lui (visible).
func _front_hit(mesh: Mesh, from: Vector3, dir: Vector3, length: float) -> bool:
	var best := INF
	var front := false
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := idx.size() if not idx.is_empty() else v.size()
		for t in range(0, count, 3):
			var i0 := idx[t] if not idx.is_empty() else t
			var i1 := idx[t + 1] if not idx.is_empty() else t + 1
			var i2 := idx[t + 2] if not idx.is_empty() else t + 2
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, v[i0], v[i1], v[i2])
			if hit == null:
				hit = Geometry3D.ray_intersects_triangle(from, dir, v[i0], v[i2], v[i1])
			if hit == null:
				continue
			var d := from.distance_to(hit)
			if d < best and d <= length:
				best = d
				front = (n[i0] + n[i1] + n[i2]).dot(dir) < 0.0
	return front


func _ray_hits(faces: PackedVector3Array, from: Vector3, dir: Vector3, length: float) -> bool:
	for i in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, faces[i], faces[i + 1], faces[i + 2])
		if hit != null and from.distance_to(hit) <= length:
			return true
		hit = Geometry3D.ray_intersects_triangle(from, dir, faces[i], faces[i + 2], faces[i + 1])
		if hit != null and from.distance_to(hit) <= length:
			return true
	return false
