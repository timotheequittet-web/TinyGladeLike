extends SceneTree
## Partie scriptée de la démo de construction en jeu (outil de développement) :
## simule la souris (vrais événements d'entrée), vérifie le résultat et prend des
## captures.   godot --path . -s tools/runtime_play.gd -- <dossier_sortie>

var out_dir := "/tmp/shots"
var scene: Node
var cam: Camera3D
var site: BastideBuildSite
var tool: BastideBuildTool
var _fail := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	_run.call_deferred()


func _run() -> void:
	scene = (load("res://demos/04_runtime/runtime_demo.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	cam = scene.get_node("Camera")
	site = scene.get_node("Chantier")
	tool = scene.get_node("Outil")
	# Le rendu logiciel des conteneurs de test fait des points blancs isolés que le
	# glow transforme en taches : on le coupe pour les captures seulement.
	if DisplayServer.get_name() != "headless":
		(scene.get_node("WorldEnvironment") as WorldEnvironment).environment.glow_enabled = false
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while site.ids().size() < n0 and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	while absf(cam.get("distance") - 30.0) > 0.2 and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	await _wait(1.0)
	check(site.ids().size() == n0, "le hameau de départ compte %d structures (%d)" % [n0, site.ids().size()])
	await _shot("etape4_hameau")

	# 1. Un muret dessiné à main levée, capture pendant le tracé (fantôme).
	tool.mode = BastideBuildTool.Mode.WALL
	var path: Array[Vector3] = []
	for i in 25:
		var t := i / 24.0
		path.append(Vector3(-14 + t * 24.0, 0, 12.5 + sin(t * PI * 1.5) * 2.0))
	await _drag(path, "etape4_trace_fantome")
	await _wait(1.5)
	check(site.ids().size() == n0 + 1, "le muret est posé (%d structures)" % site.ids().size())
	var wall_id := tool.selected
	check(wall_id >= 0 and site.get_record(wall_id)["kind"] == "wall", "le muret posé est sélectionné")
	await _shot("etape4_muret_pose")

	# 2. Une maison tirée au rectangle.
	tool.mode = BastideBuildTool.Mode.HOUSE
	await _drag([Vector3(-26, 0, -20), Vector3(-20, 0, -15), Vector3(-17, 0, -13)], "etape4_maison_fantome")
	await _wait(1.5)
	check(site.ids().size() == n0 + 2, "la maison est posée (%d structures)" % site.ids().size())
	var house_id := tool.selected

	# 3. Un rectangle par-dessus la première maison : elle s'agrandit en L.
	var before_pts: int = site.get_record(1)["points"].size()
	await _drag([Vector3(-2, 0, -3), Vector3(-1, 0, 3), Vector3(-0.5, 0, 5.5)], "etape4_agrandir_fantome")
	await _wait(1.5)
	check(site.ids().size() == n0 + 2, "agrandir ne crée pas de nouvelle structure")
	var after_pts: int = site.get_record(1)["points"].size()
	check(after_pts > before_pts, "la maison 1 a gagné des angles (%d → %d)" % [before_pts, after_pts])
	var n1 := site.node_of(1)
	var ghosts := 0
	for c in site.get_children():
		if c is BastideStructure and site.id_of(c) < 0 and c != site.garden:
			ghosts += 1
	check(n1.visible and n1.mesh_transparency == 0.0 and ghosts == 0,
			"la maison agrandie est solide, aucun fantôme ne traîne (visible %s, transparence %.2f, fantômes %d)" % [n1.visible, n1.mesh_transparency, ghosts])
	await _shot("etape4_maison_en_l")

	# 4. Sélection par clic, puis poignées.
	await _click(Vector3(-6, 3, -3))
	check(tool.selected == 1, "un clic sur la maison la sélectionne (%d)" % tool.selected)
	await _wait(0.5)
	await _shot("etape4_poignees")
	# Tire un angle de la nouvelle maison vers l'extérieur.
	tool.select(house_id)
	await _wait(0.3)
	var hp: PackedVector3Array = site.get_record(house_id)["points"]
	var corner := hp[2]
	await _drag([corner, corner + Vector3(1.5, 0, 1.0), corner + Vector3(3, 0, 2)], "")
	await _wait(1.0)
	var moved: Vector3 = site.get_record(house_id)["points"][2]
	check(moved.distance_to(corner) > 2.0, "l'angle a suivi la poignée (%.1f m)" % moved.distance_to(corner))

	# 5. Étages, variation, style.
	tool.select(house_id)
	tool.change_floors(1)
	tool.reroll_selected()
	tool.set_style(load("res://addons/bastide/styles/presets/medieval_stone.tres"))
	await _wait(1.5)
	check(site.get_record(house_id)["style"].contains("medieval"), "le style change sur la sélection")

	# 6. Annuler tout ce qui vient d'être fait, puis rétablir.
	for i in 7:
		tool.undo()
	await _wait(1.5)
	check(site.ids().size() == n0, "7 annulations ramènent le hameau de départ (%d)" % site.ids().size())
	check(site.get_record(1)["points"].size() == before_pts, "la maison 1 a retrouvé sa forme")
	for i in 7:
		tool.redo()
	await _wait(1.5)
	check(site.ids().size() == n0 + 2, "7 rétablissements redonnent tout (%d)" % site.ids().size())

	# 7. Sauvegarde / rechargement.
	var data := site.to_data()
	var json := JSON.stringify(data)
	site.from_data(JSON.parse_string(json), false)
	await _wait(1.5)
	check(site.to_data().size() == data.size(), "le chantier se recharge depuis du JSON")
	cam.call("focus", Vector3(-6, 0, -4), 26.0)
	await _wait(2.0)
	tool.select(-1)
	await _shot("etape4_vue_rapprochee")

	# Vue d'ambiance, sans interface, à hauteur de promeneur.
	(scene.get_node("Interface") as CanvasLayer).visible = false
	cam.call("glide_to", Vector3(-3, 0, 2), 15.0, 32.0)
	await _wait(3.0)
	await _shot("etape4_ambiance")
	cam.call("glide_to", Vector3(-2, 0, -3), 48.0, -18.0)
	await _wait(3.0)
	await _shot("etape4_vue_generale")

	print("")
	print("Partie scriptée : %d échec(s)" % _fail)
	quit(1 if _fail > 0 else 0)


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


func _mouse(type: String, pos: Vector2, pressed := false, button := MOUSE_BUTTON_LEFT) -> void:
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
		b.button_index = button
		b.pressed = type == "down"
		ev = b
	root.push_input(ev)


func _drag(points: Array, shot_name: String) -> void:
	_mouse("move", _screen(points[0]))
	await process_frame
	_mouse("down", _screen(points[0]))
	await process_frame
	for i in range(1, points.size()):
		_mouse("move", _screen(points[i]), true)
		await process_frame
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
