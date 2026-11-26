extends SceneTree
## Partie scriptée de l'étape 5 (outil de développement) : le hameau japonais avec
## ses chemins, torii, clôtures et plantes, puis les nouveaux outils à la souris
## (vrais événements d'entrée), avec vérifications et captures.
##   godot --path . -s tools/garden_play.gd -- <dossier_sortie> [vues]
## « vues » seul : seulement les captures du hameau de départ.

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


func _run() -> void:
	scene = (load("res://demos/04_runtime/runtime_demo.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	cam = scene.get_node("Camera")
	site = scene.get_node("Chantier")
	tool = scene.get_node("Outil")
	preload("res://tools/play_light.gd").apply(scene)
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 300000:
		await process_frame
	await _wait(3.0)
	check(site.ids().size() == n0, "le hameau de départ compte %d structures" % n0)
	var garden := site.garden
	check(garden != null and garden.last_stats.get("plants", 0) > 20,
			"le jardin automatique a poussé (%d plantes)" % (garden.last_stats.get("plants", 0) if garden else 0))
	var main_path := site.node_of(5) as BastidePath
	var branch := site.node_of(6) as BastidePath
	check(main_path.last_stats.get("doors", 0) == 1, "le chemin principal rejoint la porte de la grande maison")
	check(branch.last_stats.get("doors", 0) == 1, "la branche rejoint la porte de la seconde maison")
	var fence := site.node_of(8) as BastideFence
	check(fence.last_stats.get("openings", 0) == 1, "la clôture de bambou s'ouvre pour la branche (%d)" % fence.last_stats.get("openings", 0))

	(scene.get_node("Interface") as CanvasLayer).visible = false
	cam.call("glide_to", Vector3(-1, 0, 4), 34.0, -20.0)
	await _wait(3.0)
	await _shot("etape5_vue_generale")
	cam.call("glide_to", Vector3(0, 0, 13), 13.0, 8.0)
	await _wait(3.0)
	await _shot("etape5_torii")
	cam.call("glide_to", Vector3(-3.5, 0, 2.5), 11.0, 35.0)
	await _wait(3.0)
	await _shot("etape5_porte")
	cam.call("glide_to", Vector3(4, 0, 5), 12.0, -60.0)
	await _wait(3.0)
	await _shot("etape5_cloture")
	cam.call("glide_to", Vector3(-10, 0, 11), 13.0, 25.0)
	await _wait(3.0)
	await _shot("etape5_muret_pierres")
	if views_only:
		quit(_fail)
		return
	(scene.get_node("Interface") as CanvasLayer).visible = true

	# 1. Un chemin tracé depuis le pré jusqu'à près de la porte de la seconde maison.
	cam.call("glide_to", Vector3(14, 0, 8), 30.0, -10.0)
	await _wait(3.0)
	tool.mode = BastideBuildTool.Mode.PATH
	var door: Dictionary = (site.node_of(2).describe()["doors"] as Array)[0]
	var dpos: Vector3 = door["pos"]
	await _drag([Vector3(24, 0, 16), Vector3(20, 0, 12), Vector3(16, 0, 8), dpos + Vector3(2.0, 0, 3.0)], "etape5_trace_chemin")
	await _wait(1.5)
	var new_path := tool.selected
	check(new_path >= 0 and site.get_record(new_path)["kind"] == "path", "le chemin est posé")
	var pnode := site.node_of(new_path) as BastidePath
	check(pnode != null and pnode.last_stats.get("doors", 0) == 1, "il a rejoint la porte tout seul")

	# 2. Un torii près de ce chemin : il se cale dessus.
	tool.mode = BastideBuildTool.Mode.TORII
	tool.select(-1)
	await _hover(Vector3(19.5, 0, 13.5))
	await _wait(1.0)
	await _shot("etape5_torii_fantome")
	await _click(Vector3(19.5, 0, 13.5))
	await _wait(1.5)
	var torii_ids := site.ids().filter(func(id: int) -> bool: return site.get_record(id)["kind"] == "torii")
	check(torii_ids.size() == 2, "un second torii est posé (%d)" % torii_ids.size())
	if torii_ids.size() == 2:
		var tp: PackedVector3Array = site.get_record(torii_ids.max())["points"]
		var c := (tp[0] + tp[1]) * 0.5
		var near := site.context().nearest_path(Vector2(c.x, c.z))
		check(near["dist"] < 0.3, "il est centré sur le chemin (%.2f m)" % near["dist"])

	# 3. Une clôture de pierres sèches en travers du nouveau chemin : elle s'ouvre.
	tool.mode = BastideBuildTool.Mode.WALL
	tool.wall_variant = BastideBuildTool.WallVariant.DRY_STONE
	await _drag([Vector3(14, 0, 16), Vector3(18, 0, 13), Vector3(22, 0, 9), Vector3(25, 0, 7)], "")
	await _wait(1.5)
	var fid := tool.selected
	var fnode := site.node_of(fid) as BastideFence
	check(fnode != null and fnode.last_stats.get("openings", 0) >= 1, "le muret de pierres sèches s'ouvre pour le chemin")

	# 4. Plantes : un massif tracé, puis un arbre d'un clic.
	tool.mode = BastideBuildTool.Mode.PLANTS
	tool.select(-1)
	await _drag([Vector3(13, 0, 18), Vector3(16, 0, 20), Vector3(20, 0, 21)], "")
	await _wait(1.5)
	check(site.get_record(tool.selected)["kind"] == "plants", "le massif est planté")
	tool.select(-1)
	var before := site.ids().size()
	await _click(Vector3(26, 0, 13))
	await _wait(1.5)
	check(site.ids().size() == before + 1, "un clic plante un arbre")
	tool.select(-1)
	await _wait(1.0)
	(scene.get_node("Interface") as CanvasLayer).visible = false
	cam.call("glide_to", Vector3(18, 0, 12), 20.0, -20.0)
	await _wait(3.0)
	await _shot("etape5_nouveau_coin")

	# 5. Tout s'annule.
	for i in 5:
		tool.undo()
	await _wait(1.5)
	check(site.ids().size() == n0, "5 annulations ramènent le hameau (%d)" % site.ids().size())

	print("")
	print("Partie scriptée : %d échec(s)" % _fail)
	quit(1 if _fail > 0 else 0)


## Toutes les structures existent et sont générées (les ids sont réservés avant).
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


## Point à plat (y = 0) → écran, en le posant d'abord sur le relief.
func _screen(p: Vector3) -> Vector2:
	var field := BastideTerrain.field_for(cam)
	if field:
		p.y += field.height(p.x, p.z)
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
