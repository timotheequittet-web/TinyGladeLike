extends SceneTree
## Partie scriptée des jardins d'eau (outil de développement) : l'étang du hameau,
## un étang tracé à la souris (touche J), une source chaude (V), un chemin qui
## traverse l'eau et reçoit son pont, annuler / rétablir / retirer, avec
## vérifications et captures.
##   godot --path . -s tools/pond_play.gd -- <dossier_sortie>
## Marche aussi en --headless (vérifications seules, sans captures).

var out_dir := "/tmp/shots"
var scene: Node
var cam: Camera3D
var site: BastideBuildSite
var tool: BastideBuildTool
var terrain: BastideTerrain
var _fail := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	_run.call_deferred()


func _pond_ids() -> Array:
	var out := []
	for id in site.ids():
		if site.get_record(id)["kind"] == "pond":
			out.append(id)
	return out


func _run() -> void:
	scene = (load("res://demos/04_runtime/runtime_demo.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	cam = scene.get_node("Camera")
	site = scene.get_node("Chantier")
	tool = scene.get_node("Outil")
	terrain = scene.get_node("Terrain")
	preload("res://tools/play_light.gd").apply(scene)
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	await _wait(2.0)

	print("L'étang du hameau")
	var ids := _pond_ids()
	check(ids.size() == 1, "le hameau a son étang")
	var pond := site.node_of(ids[0]) as BastidePond if ids.size() > 0 else null
	check(pond != null and pond.last_stats.get("koi", 0) >= 3, "des koï y nagent (%d)" % (pond.last_stats.get("koi", 0) if pond else 0))
	check(pond != null and pond.last_stats.get("lilies", 0) >= 3, "des nénuphars (%d)" % (pond.last_stats.get("lilies", 0) if pond else 0))
	var c := Vector3(-28, 0, 16)
	var level := terrain.field.water_level(c.x, c.z)
	check(level > -INF, "le relief sait qu'il y a de l'eau au milieu")
	check(terrain.field.water_depth(c.x, c.z) > 0.4, "le fond est creusé (%.2f m d'eau)" % terrain.field.water_depth(c.x, c.z))
	check(absf(terrain.base_field.height(c.x, c.z) - terrain.field.height(c.x, c.z)) > 0.4, "le sol d'origine est gardé à part")
	var grass := scene.get_node("Herbe") as BastideGrass
	await _wait(0.5)
	var mask_img := (grass.get("_viewport") as SubViewport).get_texture().get_image()
	if mask_img:
		var uv := (Vector2(c.x, c.z) - grass.mask_rect.position) / grass.mask_rect.size
		check(mask_img.get_pixelv(Vector2i(uv * Vector2(mask_img.get_size()))).r > 0.9, "pas d'herbe dans l'eau")
	# La terrasse au bord de l'eau et le jardin n'ont rien planté dans l'étang.
	var wet_plants := 0
	if site.garden:
		var gm := site.garden.get_mesh_instance()
		if gm and gm.mesh:
			for s in gm.mesh.get_surface_count():
				var v: PackedVector3Array = gm.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for i in range(0, v.size(), 30):
					var w := site.garden.to_global(v[i])
					if terrain.field.water_depth(w.x, w.z) > 0.3:
						wet_plants += 1
	check(wet_plants == 0, "le jardin automatique ne plante rien dans l'eau (%d)" % wet_plants)

	(scene.get_node("Interface") as CanvasLayer).visible = false
	cam.call("glide_to", c, 24.0, 30.0)
	await _wait(3.0)
	await _shot("etang_hameau")
	(scene.get_node("Interface") as CanvasLayer).visible = true

	print("Tracer un étang (J)")
	cam.call("glide_to", Vector3(17, 0, 16), 40.0, -10.0)
	await _wait(3.0)
	_key(KEY_J, true)
	_key(KEY_J, false)
	await process_frame
	check(tool.mode == BastideBuildTool.Mode.POND, "la touche J choisit l'outil Étang")
	var loop: Array = []
	for i in 13:
		var a := TAU * i / 12.0
		loop.append(Vector3(17.0 + cos(a) * 6.0 * (1.0 + 0.15 * sin(a * 2.0)), 0, 17.5 + sin(a) * 4.2))
	var before := _pond_ids()
	await _drag(loop, "etang_trace")
	var drawn := await _new_pond(before)
	check(drawn != null and int(drawn.pond_kind) == BastidePondBuilder.Kind.GARDEN, "le contour devient un étang de jardin")
	check(drawn != null and drawn.last_stats.get("rocks", 0) >= 2, "avec ses rochers (%d)" % (drawn.last_stats.get("rocks", 0) if drawn else 0))
	await _wait(1.0)
	check(terrain.field.water_depth(17, 17.5) > 0.3, "le sol est creusé sous l'eau (%.2f m)" % terrain.field.water_depth(17, 17.5))

	print("Un chemin qui traverse")
	_key(KEY_3, true)
	_key(KEY_3, false)
	await process_frame
	var pbefore := site.ids().size()
	await _drag([Vector3(6, 0, 18.5), Vector3(11, 0, 18.2), Vector3(17, 0, 18.0), Vector3(23, 0, 18.4), Vector3(28, 0, 18.8)], "")
	await _wait(4.0)
	var path_id := -1
	for id in site.ids():
		if site.get_record(id)["kind"] == "path" and id > 0 and site.ids().size() > pbefore:
			path_id = id
	var bridges: Array = drawn.last_anchors.get("bridges", []) if drawn else []
	check(bridges.size() >= 1, "l'étang pose un pont sur le chemin (%s)" % (bridges[0]["kind"] if bridges.size() > 0 else "aucun"))
	var path_node := site.node_of(path_id) if path_id >= 0 else null
	check(path_node != null and path_node.last_stats.get("under_water", 0) > 0, "le gravier noyé du chemin a disparu (%d triangles)" % (path_node.last_stats.get("under_water", 0) if path_node else 0))
	tool.select(-1)
	(scene.get_node("Interface") as CanvasLayer).visible = false
	cam.call("glide_to", Vector3(17, 0, 18), 18.0, 25.0)
	await _wait(3.0)
	await _shot("etang_pont")
	(scene.get_node("Interface") as CanvasLayer).visible = true

	print("Une source chaude (V)")
	_key(KEY_J, true)
	_key(KEY_J, false)
	await process_frame
	_key(KEY_V, true)
	_key(KEY_V, false)
	await process_frame
	check(tool.pond_kind == BastidePondBuilder.Kind.ONSEN, "V passe à la source chaude")
	cam.call("glide_to", Vector3(27, 0, 4), 30.0, -10.0)
	await _wait(3.0)
	var loop2: Array = []
	for i in 11:
		var a := TAU * i / 10.0
		loop2.append(Vector3(27.5 + cos(a) * 3.4, 0, 5.0 + sin(a) * 2.6))
	before = _pond_ids()
	await _drag(loop2, "")
	var onsen := await _new_pond(before)
	check(onsen != null and int(onsen.pond_kind) == BastidePondBuilder.Kind.ONSEN, "le contour devient une source chaude")
	var steam := 0
	if onsen:
		for ch in onsen.get_children(true):
			if ch is CPUParticles3D:
				steam += 1
	check(steam == 1, "de la vapeur monte de l'eau")
	tool.select(-1)
	(scene.get_node("Interface") as CanvasLayer).visible = false
	cam.call("glide_to", Vector3(27.5, 0, 5), 12.0, 200.0)
	await _wait(3.0)
	await _shot("etang_onsen")
	(scene.get_node("Interface") as CanvasLayer).visible = true

	print("Annuler, rétablir, retirer")
	var oid := site.id_of(onsen) if onsen else -1
	tool.undo()
	await _wait(2.0)
	check(not site.has(oid), "Ctrl+Z retire la source chaude")
	check(terrain.field.water_level(27.5, 5.0) == -INF, "et le sol se rebouche")
	tool.redo()
	await _wait(3.0)
	check(site.has(oid) and terrain.field.water_level(27.5, 5.0) > -INF, "Ctrl+Y la remet, creusée")
	tool.select(oid)
	tool.delete_selected()
	await _wait(2.0)
	check(terrain.field.water_level(27.5, 5.0) == -INF, "Suppr la retire et rebouche le sol")
	print("")
	print("%s" % ("tout est bon" if _fail == 0 else "%d échec(s)" % _fail))
	quit(_fail)


func _new_pond(before: Array) -> BastidePond:
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 60000:
		await process_frame
		for id in _pond_ids():
			if not before.has(id):
				var n := site.node_of(id) as BastidePond
				if n and not n.last_stats.is_empty():
					await _wait(0.5)
					return n
	return null


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


func _shot(shot_name: String) -> void:
	for i in 6:
		await process_frame
	if DisplayServer.get_name() == "headless":
		return
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("capture ", shot_name)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
