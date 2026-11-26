extends SceneTree
## Partie scriptée des cultures (outil de développement) : un potager tracé à la
## souris (touche H), une rizière (V), un champ de thé, annuler / rétablir /
## retirer, avec vérifications et captures.
##   godot --path . -s tools/farm_play.gd -- <dossier_sortie>
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


func _farm_ids() -> Array:
	var out := []
	for id in site.ids():
		if site.get_record(id)["kind"] == "farm":
			out.append(id)
	return out


func _loop(c: Vector3, rx: float, rz: float, n := 12) -> Array:
	var out: Array = []
	for i in n + 1:
		var a := TAU * i / n
		out.append(Vector3(c.x + cos(a) * rx, 0, c.z + sin(a) * rz))
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

	print("Tracer un potager (H)")
	var c := Vector3(17, 0, 17)
	cam.call("glide_to", c, 40.0, -10.0)
	await _wait(3.0)
	_key(KEY_H, true)
	_key(KEY_H, false)
	await process_frame
	check(tool.mode == BastideBuildTool.Mode.FARM, "la touche H choisit l'outil Champ")
	var before := _farm_ids()
	var h0 := terrain.field.height(c.x, c.z)
	await _drag(_loop(c, 7.0, 5.0), "champ_trace")
	var farm := await _new_farm(before)
	check(farm != null and int(farm.farm_kind) == BastideFarmBuilder.Kind.VEGETABLE, "le contour devient un potager")
	check(farm != null and farm.last_stats.get("beds", 0) >= 4, "avec ses planches (%d)" % (farm.last_stats.get("beds", 0) if farm else 0))
	check(farm != null and farm.last_stats.get("crops", 0) >= 60, "et ses légumes (%d)" % (farm.last_stats.get("crops", 0) if farm else 0))
	await _wait(1.0)
	check(terrain.field.height(c.x, c.z) < h0 - 0.05, "le sol est abaissé sous la terre du champ")
	var grass := scene.get_node("Herbe") as BastideGrass
	await _wait(0.5)
	var vp := grass.get("_viewport") as SubViewport
	var mask_img := vp.get_texture().get_image() if vp else null
	if mask_img:
		var uv := (Vector2(c.x, c.z) - grass.mask_rect.position) / grass.mask_rect.size
		check(mask_img.get_pixelv(Vector2i(uv * Vector2(mask_img.get_size()))).r > 0.9, "pas d'herbe dans le champ")
	tool.select(-1)
	(scene.get_node("Interface") as CanvasLayer).visible = false
	cam.call("glide_to", c, 18.0, 25.0)
	await _wait(3.0)
	await _shot("champ_potager")
	(scene.get_node("Interface") as CanvasLayer).visible = true

	print("Une rizière (V)")
	_key(KEY_H, true)
	_key(KEY_H, false)
	await process_frame
	_key(KEY_V, true)
	_key(KEY_V, false)
	await process_frame
	check(tool.farm_kind == BastideFarmBuilder.Kind.RICE, "V passe à la rizière")
	var c2 := Vector3(27, 0, 3)
	cam.call("glide_to", c2, 34.0, -10.0)
	await _wait(3.0)
	before = _farm_ids()
	await _drag(_loop(c2, 5.5, 4.0), "")
	var rice := await _new_farm(before)
	check(rice != null and int(rice.farm_kind) == BastideFarmBuilder.Kind.RICE, "le contour devient une rizière")
	check(rice != null and rice.last_stats.get("rice", 0) >= 50, "le riz est repiqué (%d)" % (rice.last_stats.get("rice", 0) if rice else 0))
	tool.select(-1)

	print("Annuler, rétablir, retirer")
	var rid := site.id_of(rice) if rice else -1
	var hr := terrain.base_field.height(c2.x, c2.z)
	await _wait(1.0)
	check(_lowered(c2), "la rizière abaisse le sol (déblai des terrasses)")
	tool.undo()
	await _wait(2.0)
	check(not site.has(rid), "Ctrl+Z retire la rizière")
	check(is_equal_approx(terrain.field.height(c2.x, c2.z), hr), "et le sol revient")
	tool.redo()
	await _wait(3.0)
	check(site.has(rid) and _lowered(c2), "Ctrl+Y la remet")
	tool.select(rid)
	tool.delete_selected()
	await _wait(2.0)
	check(is_equal_approx(terrain.field.height(c2.x, c2.z), hr), "Suppr la retire et rend le sol")
	print("")
	print("%s" % ("tout est bon" if _fail == 0 else "%d échec(s)" % _fail))
	quit(_fail)


## Vrai si le sol est abaissé quelque part sous le champ.
func _lowered(c: Vector3) -> bool:
	for dx in range(-4, 5):
		for dz in range(-3, 4):
			var x := c.x + dx
			var z := c.z + dz
			if terrain.field.height(x, z) < terrain.base_field.height(x, z) - 0.05:
				return true
	return false


func _new_farm(before: Array) -> BastideFarm:
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 60000:
		await process_frame
		for id in _farm_ids():
			if not before.has(id):
				var n := site.node_of(id) as BastideFarm
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
