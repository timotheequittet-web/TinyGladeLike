extends SceneTree
## Partie scriptée de l'étape 6 (outil de développement) : portails dans les murets
## traversés par un chemin, engawa et terrasses, avec la vraie souris (événements
## d'entrée), vérifications et captures.
##   godot --path . -s tools/terrace_play.gd -- <dossier_sortie> [vues]
## « vues » seul : seulement les captures du hameau de départ.

const MEDIEVAL := preload("res://addons/bastide/styles/presets/medieval_stone.tres")
const JAPANESE := preload("res://addons/bastide/styles/presets/japanese_wood.tres")

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
	if DisplayServer.get_name() != "headless":
		(scene.get_node("WorldEnvironment") as WorldEnvironment).environment.glow_enabled = false
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await _wait(3.0)
	check(site.ids().size() == n0, "le hameau de départ compte %d structures" % n0)
	var wall := site.node_of(3) as BastideWall
	check(wall != null and wall.last_stats.get("gates", 0) == 1,
			"le grand muret s'ouvre en portail pour le chemin (%d)" % (wall.last_stats.get("gates", 0) if wall else -1))
	var engawa := site.node_of(4) as BastideTerrace
	check(engawa != null and engawa.last_stats.get("engawa", false), "la terrasse contre la grande maison est un engawa")
	var deck := site.node_of(14) as BastideTerrace
	check(deck != null and not deck.last_stats.get("engawa", true), "la terrasse de l'étang est isolée (garde-corps, marches)")
	var deck_path := site.node_of(15) as BastidePath
	check(deck_path != null and deck_path.last_stats.get("doors", 0) == 1, "le chemin de l'étang rejoint les marches de la terrasse")
	check(site.node_of(5).last_stats.get("doors", 0) == 1, "le chemin principal rejoint toujours la porte")

	(scene.get_node("Interface") as CanvasLayer).visible = false
	cam.call("glide_to", Vector3(-3, 0, 6), 34.0, -15.0)
	await _wait(3.0)
	await _shot("etape6_vue_generale")
	cam.call("glide_to", Vector3(-1, 0.8, 9), 6.0, -35.0)
	await _wait(3.0)
	await _shot("etape6_portail")
	cam.call("glide_to", Vector3(-6.6, 0.5, 1.2), 6.5, 18.0)
	await _wait(3.0)
	await _shot("etape6_engawa")
	cam.call("glide_to", Vector3(-20, 0, 15), 13.0, 60.0)
	await _wait(3.0)
	await _shot("etape6_terrasse_etang")
	if views_only:
		quit(_fail)
		return
	(scene.get_node("Interface") as CanvasLayer).visible = true

	# 1. Un engawa tiré contre la seconde maison (façade est, x = 14).
	cam.call("glide_to", Vector3(14, 0, -5), 20.0, 95.0)
	await _wait(3.0)
	tool.mode = BastideBuildTool.Mode.TERRACE
	await _drag([Vector3(14.6, 0, -9.5), Vector3(15.5, 0, -6), Vector3(16.2, 0, -2.5)], "etape6_engawa_fantome")
	await _wait(1.5)
	var tid := tool.selected
	var tnode := site.node_of(tid) as BastideTerrace if tid >= 0 else null
	check(tnode != null and tnode.last_stats.get("engawa", false), "tirée contre la façade, la terrasse devient un engawa")
	if tnode:
		var rect: PackedVector3Array = site.get_record(tid)["points"]
		var minx := INF
		for p in rect:
			minx = minf(minx, p.x)
		check(absf(minx - (14.0 + BastideTerraceRules.HOUSE_GAP)) < 0.05, "elle est collée à la façade (x = %.2f)" % minx)

	# 2. Une terrasse isolée dans le pré.
	tool.select(-1)
	cam.call("glide_to", Vector3(20, 0, 10), 22.0, -20.0)
	await _wait(3.0)
	await _drag([Vector3(18, 0, 8), Vector3(20, 0, 10), Vector3(22.4, 0, 11.2)], "")
	await _wait(1.5)
	var fid := tool.selected
	var fnode := site.node_of(fid) as BastideTerrace if fid >= 0 else null
	check(fnode != null and not fnode.last_stats.get("engawa", true), "loin des maisons, la terrasse est isolée")
	if fnode:
		var entry: int = fnode.last_stats.get("entry", -1)
		var rect2: PackedVector3Array = site.get_record(fid)["points"]
		var nrm := BastideTerraceRules.side_normal(rect2, entry)
		var to_cam := cam.global_position - BastideStroke.centroid(rect2)
		to_cam.y = 0
		check(nrm.dot(to_cam.normalized()) > 0.5, "ses marches donnent vers la caméra")

	# 3. Un chemin qui traverse le grand muret plus à l'ouest : un second portail.
	tool.select(-1)
	cam.call("glide_to", Vector3(-12, 0, 6), 22.0, 20.0)
	await _wait(3.0)
	tool.mode = BastideBuildTool.Mode.PATH
	await _drag([Vector3(-19, 0, 7), Vector3(-15, 0, 6.5), Vector3(-11, 0, 6), Vector3(-8, 0, 5)], "etape6_trace_chemin")
	await _wait(2.0)
	check(wall.last_stats.get("gates", 0) == 2, "le muret s'ouvre aussi pour le nouveau chemin (%d)" % wall.last_stats.get("gates", 0))
	tool.select(-1)
	(scene.get_node("Interface") as CanvasLayer).visible = false
	cam.call("glide_to", Vector3(-12.3, 0.8, 6.5), 9.0, -45.0)
	await _wait(3.0)
	await _shot("etape6_second_portail")

	# 4. Tout en médiéval : le portail devient un arc de pierre entre deux piliers.
	tool.set_style_everywhere(MEDIEVAL)
	await _wait(4.0)
	check(wall.last_stats.get("gates", 0) == 2, "en médiéval, les portails restent ouverts")
	cam.call("glide_to", Vector3(-1, 0, 9), 13.0, 12.0)
	await _wait(3.0)
	await _shot("etape6_portail_medieval")
	tool.undo()
	await _wait(3.0)
	(scene.get_node("Interface") as CanvasLayer).visible = true

	# 5. On annule le chemin : le portail se referme.
	tool.undo()
	await _wait(2.0)
	check(wall.last_stats.get("gates", 0) == 1, "annuler le chemin referme le portail")
	tool.undo()
	tool.undo()
	await _wait(2.0)
	check(site.ids().size() == n0, "les annulations ramènent le hameau (%d)" % site.ids().size())

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
