extends SceneTree
## Partie scriptée des forêts (outil de développement) : la forêt du hameau, une
## forêt tracée à la souris (outil Forêt, touche B), les sortes de forêt (V), avec
## vérifications et captures.
##   godot --path . -s tools/forest_play.gd -- <dossier_sortie> [vues]

var out_dir := "/tmp/shots"
var views_only := false
var scene: Node
var cam: Camera3D
var site: BastideBuildSite
var tool: BastideBuildTool
var _fail := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	views_only = args.has("vues")
	_run.call_deferred()


func _forest_id() -> int:
	for id in site.ids():
		if site.get_record(id)["kind"] == "forest":
			return id
	return -1


func _run() -> void:
	scene = (load("res://demos/04_runtime/runtime_demo.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	cam = scene.get_node("Camera")
	site = scene.get_node("Chantier")
	tool = scene.get_node("Outil")
	if DisplayServer.get_name() != "headless":
		(scene.get_node("WorldEnvironment") as WorldEnvironment).environment.glow_enabled = false
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	await _wait(3.0)
	var fid := _forest_id()
	var forest := site.node_of(fid) as BastideForest if fid >= 0 else null
	check(forest != null and forest.last_stats.get("trees", 0) >= 20,
			"la forêt du hameau compte %d grands arbres" % (forest.last_stats.get("trees", 0) if forest else 0))
	check(forest != null and forest.last_stats.get("plants", 0) >= 200, "et un sous-bois fourni (%d plantes)" % (forest.last_stats.get("plants", 0) if forest else 0))

	(scene.get_node("Interface") as CanvasLayer).visible = false
	cam.call("glide_to", Vector3(0, 0, -14), 52.0, -10.0)
	await _wait(3.5)
	await _shot("foret_vue_generale")
	cam.call("glide_to", Vector3(-6, 0, -12), 14.0, 160.0)
	await _wait(3.5)
	await _shot("foret_lisiere")
	# Au cœur de la forêt, à hauteur de promeneur, dans une allée dégagée.
	cam.set_process(false)
	var views := _walker_views(forest)
	for i in views.size():
		cam.global_transform = views[i]
		await _wait(2.0)
		await _shot("foret_dedans" if i == 0 else "foret_dedans_%d" % (i + 1))
	cam.set_process(true)
	if views_only:
		quit(_fail)
		return
	(scene.get_node("Interface") as CanvasLayer).visible = true

	# Une forêt d'érables tracée à la main dans le pré à l'est.
	cam.call("glide_to", Vector3(30, 0, 6), 42.0, -30.0)
	await _wait(3.5)
	tool.mode = BastideBuildTool.Mode.FOREST
	tool.forest_kind = BastideForestBuilder.Kind.MAPLES
	var loop: Array = []
	for i in 13:
		var a := TAU * i / 12.0
		loop.append(Vector3(31.0 + cos(a) * 11.0, 0, 6.0 + sin(a) * 8.0))
	var before := site.ids().size()
	await _drag(loop, "foret_trace")
	var t1 := Time.get_ticks_msec()
	var mid := -1
	while Time.get_ticks_msec() - t1 < 60000:
		await process_frame
		if site.ids().size() > before:
			mid = site.ids()[site.ids().size() - 1]
			var mn := site.node_of(mid)
			if mn and not mn.last_stats.is_empty():
				break
	var maples := site.node_of(mid) as BastideForest if mid >= 0 else null
	check(maples != null and int(maples.forest_kind) == BastideForestBuilder.Kind.MAPLES, "le tracé fermé devient une forêt d'érables")
	check(maples != null and maples.last_stats.get("trees", 0) >= 4, "elle compte %d arbres" % (maples.last_stats.get("trees", 0) if maples else 0))
	tool.select(-1)
	(scene.get_node("Interface") as CanvasLayer).visible = false
	await _wait(2.0)
	cam.call("glide_to", Vector3(31, 0, 6), 26.0, -20.0)
	await _wait(3.5)
	await _shot("foret_erables")

	# Les autres sortes, sur la même zone.
	for k in [BastideForestBuilder.Kind.CEDARS, BastideForestBuilder.Kind.SAKURA, BastideForestBuilder.Kind.PINES]:
		var rec: Dictionary = site.get_record(mid).duplicate(true)
		rec["forest_kind"] = int(k)
		site.configure(site.node_of(mid), rec)
		await _wait(6.0)
		await _shot("foret_" + String(BastideForestBuilder.Kind.keys()[k]).to_lower())
	(scene.get_node("Interface") as CanvasLayer).visible = true

	# Annuler retire la forêt tracée.
	tool.undo()
	await _wait(2.5)
	check(site.ids().size() == before, "annuler retire la forêt (%d structures)" % site.ids().size())

	print("")
	print("Partie scriptée : %d échec(s)" % _fail)
	quit(_fail)


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


func _wait(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < sec * 1000.0:
		await process_frame


func _screen(p: Vector3) -> Vector2:
	return cam.unproject_position(p)


func _mouse(type: String, pos: Vector2, pressed := false) -> void:
	var ev: InputEvent
	if type == "move":
		var m := InputEventMouseMotion.new()
		m.position = pos
		m.global_position = pos
		m.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev = m
	else:
		var b := InputEventMouseButton.new()
		b.position = pos
		b.global_position = pos
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = type == "down"
		ev = b
	root.push_input(ev)


func _hover(p: Vector3) -> void:
	_mouse("move", _screen(p))
	await process_frame


func _drag(points: Array, shot_name: String) -> void:
	_mouse("move", _screen(points[0]))
	await process_frame
	_mouse("down", _screen(points[0]))
	await process_frame
	for i in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		for k in 4:
			_mouse("move", _screen(a.lerp(b, (k + 1) / 4.0)), true)
			await process_frame
	await _wait(0.8)
	if shot_name != "":
		await _shot(shot_name)
	_mouse("up", _screen(points[points.size() - 1]))
	await process_frame


func _click(p: Vector3) -> void:
	var s := _screen(p)
	_mouse("move", s)
	await process_frame
	_mouse("down", s)
	await process_frame
	_mouse("up", s)
	await process_frame


func _shot(shot_name: String) -> void:
	for i in 6:
		await process_frame
	if DisplayServer.get_name() == "headless":
		return
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("capture ", shot_name)


## Deux points de vue de promeneur : loin des troncs, regard le long de la plus
## longue trouée, pour voir la forêt sans buter sur une écorce.
func _walker_views(forest: BastideForest) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if forest == null:
		return out
	var trees: Array = forest.last_anchors.get("trees", [])
	var outline: Array = forest.last_anchors.get("outline", [])
	if trees.is_empty():
		return out
	var pts: Array[Vector3] = []
	for t in trees:
		pts.append(forest.to_global(t))
	var poly := PackedVector2Array()
	for o in outline:
		var g := forest.to_global(Vector3(o.x, 0.0, o.y) if o is Vector2 else o)
		poly.append(Vector2(g.x, g.z))
	var cands: Array = []
	var box := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		box = box.expand(v)
	var x := box.position.x + 4.0
	while x < box.end.x - 4.0:
		var z := box.position.y + 4.0
		while z < box.end.y - 4.0:
			if Geometry2D.is_point_in_polygon(Vector2(x, z), poly):
				var best := INF
				for p in pts:
					best = minf(best, Vector2(p.x - x, p.z - z).length())
				# Assez loin des troncs, mais encore entouré d'arbres.
				if best > 3.5 and best < 9.0:
					cands.append([best, Vector3(x, 0, z)])
			z += 2.0
		x += 2.0
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var used: Array[Vector3] = []
	for c in cands:
		var at: Vector3 = c[1]
		if used.any(func(u: Vector3) -> bool: return u.distance_to(at) < 12.0):
			continue
		# Direction dont le premier tronc rencontré est le plus loin.
		var best_dir := Vector3.FORWARD
		var best_free := -1.0
		for k in 24:
			var d := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 24.0)
			var free := 40.0
			for p in pts:
				var rel := p - at
				rel.y = 0.0
				var along := rel.dot(d)
				if along > 0.0 and (rel - d * along).length() < 1.6:
					free = minf(free, along)
			if free > best_free:
				best_free = free
				best_dir = d
		var eye := at + Vector3(0, 1.7, 0)
		out.append(Transform3D.IDENTITY.translated(eye).looking_at(eye + best_dir + Vector3(0, 0.12, 0), Vector3.UP))
		used.append(at)
		if out.size() >= 2:
			break
	return out
