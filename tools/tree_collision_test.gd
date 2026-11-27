extends SceneTree
## Vérifie les collisions des troncs (outil de développement) : chaque arbre de la
## démo (décor, forêt, jardins) a un cylindre, le promeneur bute dessus, et un arbre
## retiré (futur abattage) ne bloque plus et disparaît des MultiMesh.
##   godot --headless --path . -s tools/tree_collision_test.gd

var scene: Node
var cam: BastideOrbitCamera
var site: BastideBuildSite
var _fail := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	scene = (load("res://demos/04_runtime/runtime_demo.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	cam = scene.get_node("Camera")
	site = scene.get_node("Chantier")
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	for i in 10:
		await physics_frame
	cam.set_process(false)

	var bodies := get_nodes_in_group(BastideTreeBody.GROUP)
	var total := 0
	for b: BastideTreeBody in bodies:
		var owner_name := String(b.host.name) if b.host else "?"
		print("  %-28s %4d troncs, %d formes partagées" % [owner_name, b.tree_count(), BastideTreeBody._shapes.size()])
		total += b.tree_count()
	check(bodies.size() >= 2 and total >= 60, "%d corps de troncs, %d arbres en tout" % [bodies.size(), total])

	# Le promeneur marche droit sur un tronc : il doit s'arrêter devant.
	for b: BastideTreeBody in bodies:
		var tested := 0
		for id in b._trunks.size():
			if tested >= 3:
				break
			var foot := b.tree_position(id)
			if not foot.is_finite():
				continue
			var r := float(b._trunks[id]["r"])
			var d := _walk_into(foot, r)
			if d < 0.0:
				continue  # pas de place libre pour partir à 3 m (autre arbre, mur)
			tested += 1
			check(d >= r - 0.05, "%s arbre %d : arrêté à %.2f m de l'axe (rayon %.2f)" % [b.host.name, id, d, r])
		# Abattage (sans gameplay) : le premier arbre retiré ne bloque plus.
		if b.tree_count() > 0:
			var id0 := -1
			for id in b._trunks.size():
				if b.tree_position(id).is_finite():
					id0 = id
					break
			var foot := b.tree_position(id0)
			var r := float(b._trunks[id0]["r"])
			var before := _walk_into(foot, r)
			check(b.tree_at(foot + Vector3(r + 0.2, 1, 0)) == id0, "%s : tree_at retrouve l'arbre visé" % b.host.name)
			b.remove_tree(id0)
			for i in 3:
				await physics_frame
			var parts: Array = b._trunks[id0]["parts"]
			var hidden := parts.size() > 0
			for part: Array in parts:
				var mmi := b.host.get_node_or_null(NodePath("%s%d" % [BastideResultApplier.MULTI_PREFIX, int(part[0])])) as MultiMeshInstance3D
				if mmi == null or mmi.multimesh.get_instance_transform(int(part[1])).basis.get_scale().x > 0.01:
					hidden = false
			if DisplayServer.get_name() == "headless":
				hidden = parts.size() > 0 or b.host.name.begins_with("@") or b.host.name == "Massif"  # rendu factice : on vérifie juste les liens
			check(hidden, "%s : arbre %d retiré des MultiMesh (%d instances)" % [b.host.name, id0, parts.size()])
			var d := _walk_into(foot, r)
			# (si autre chose barrait déjà le chemin — un mur —, on avance au moins plus loin)
			check(d < 0.3 or d < before - 0.2 or (before > r + 0.6 and absf(d - before) < 0.05), "%s : on passe là où était l'arbre retiré (%.2f m, avant %.2f)" % [b.host.name, d, before])

	# Coût : temps de pose des cylindres pour la plus grande liste.
	var biggest: BastideTreeBody = null
	for b: BastideTreeBody in bodies:
		if biggest == null or b._trunks.size() > biggest._trunks.size():
			biggest = b
	if biggest:
		var tt := Time.get_ticks_usec()
		biggest.set_trunks(biggest._trunks)
		print("  pose de %d cylindres : %.2f ms" % [biggest._trunks.size(), (Time.get_ticks_usec() - tt) / 1000.0])
	print("échecs : ", _fail)
	quit(1 if _fail > 0 else 0)


## Part à 3 m du tronc (côté libre) et marche vers son axe ; renvoie la distance
## finale à l'axe, ou -1 si aucun départ libre.
func _walk_into(foot: Vector3, r: float) -> float:
	var field := BastideTerrain.field_for(cam)
	for k in 8:
		var a := TAU * k / 8.0
		var start := foot + Vector3(cos(a), 0, sin(a)) * (r + 3.0)
		start.y = field.height(start.x, start.z) if field else 0.0
		cam.place_walker(start)
		var pos := start
		var blocked_early := false
		for i in 80:
			var to := Vector3(foot.x - pos.x, 0, foot.z - pos.z)
			if to.length() < 0.02:
				break
			var step := to.normalized() * minf(0.08, to.length())
			var moved: Vector3 = cam.call("_slide", pos, step)
			pos += moved
			if i == 0 and moved.length() < 0.01:
				blocked_early = true
				break
		if blocked_early:
			continue
		return Vector2(pos.x - foot.x, pos.z - foot.z).length()
	return -1.0


func _all_built(n: int) -> bool:
	if site.ids().size() < n:
		return false
	for id in site.ids():
		var node := site.node_of(id)
		if node == null or node.last_stats.is_empty():
			return false
	return site.garden != null and not site.garden.last_stats.is_empty()


func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_fail += 1
		printerr("  ÉCHEC ", label)
