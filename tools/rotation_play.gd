extends SceneTree
## Partie scriptée de la rotation (outil de développement) : une maison tournée à
## la molette pendant qu'on la tire, la grande maison du hameau tournée avec Maj +
## molette (son engawa la suit), un Ctrl+Z qui annule toute la rotation, un torii
## tourné, et une maison bloquée contre sa voisine.
##   godot --path . -s tools/rotation_play.gd -- <dossier_sortie>
## Marche aussi en --headless (vérifications seules, sans captures).

var out_dir := "/tmp/shots"
var scene: Node
var cam: Camera3D
var site: BastideBuildSite
var tool: BastideBuildTool
var _fail := 0
var _held := false


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
	preload("res://tools/play_light.gd").apply(scene)
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	await _wait(2.0)
	var R := BastideOrientationRules

	print("Une maison tournée pendant qu'on la tire")
	var c := Vector3(16, 0, 16)
	cam.call("glide_to", c, 34.0, -10.0)
	await _wait(3.0)
	_key(KEY_2)
	await process_frame
	var before := site.ids().duplicate()
	var a := c + Vector3(-3, 0, -2.5)
	var b := c + Vector3(3, 0, 2.5)
	_mouse("move", _screen(a))
	await process_frame
	_mouse("down", _screen(a))
	await process_frame
	_held = true
	for k in 6:
		_mouse("move", _screen(a.lerp(b, (k + 1) / 6.0)), true)
		await process_frame
	var cam_angle := R.angle_of(cam.global_transform.basis.x)
	_wheel(1)
	await process_frame
	_wheel(1)
	await process_frame
	_mouse("move", _screen(b), true)
	await _wait(0.6)
	await _shot("rotation_trace")
	_mouse("up", _screen(b))
	_held = false
	await process_frame
	check(tool.place_steps == 2, "la molette, clic maintenu, tourne de deux crans (%d)" % tool.place_steps)
	var hid := _new_id(before)
	check(hid >= 0 and site.get_record(hid)["kind"] == "house", "la maison est posée")
	if hid >= 0:
		var axis := R.main_axis(site.get_record(hid)["points"])
		var diff := rad_to_deg(R.wrap_angle(R.angle_of(axis) - cam_angle, PI * 0.5))
		check(absf(absf(diff) - 30.0) < 1.0, "elle est tournée de 30° par rapport à la vue (%.1f°)" % diff)
	tool.select(-1)
	(scene.get_node("Interface") as CanvasLayer).visible = false
	cam.call("glide_to", c + Vector3(-4, 0, -6), 30.0, -10.0)
	await _wait(3.0)
	await _shot("rotation_maison")
	(scene.get_node("Interface") as CanvasLayer).visible = true

	print("La grande maison tournée avec Maj + molette, son engawa la suit")
	var ids := site.ids()
	ids.sort()
	var big: int = ids[0]
	var engawa: int = ids[3]
	check(site.get_record(engawa)["kind"] == "terrace", "l'engawa du hameau est bien là")
	var h0: PackedVector3Array = site.get_record(big)["points"]
	var e0: PackedVector3Array = site.get_record(engawa)["points"]
	cam.call("glide_to", Vector3(-4, 0, -2), 30.0, 0.0)
	await _wait(2.5)
	tool.select(big)
	await process_frame
	# Trois crans d'un coup (le rendu logiciel des tests est trop lent pour un
	# vrai rythme de molette).
	for k in 3:
		_wheel(1, true)
	await process_frame
	await _wait(0.4)
	await _shot("rotation_arc")
	var h1: PackedVector3Array = site.get_record(big)["points"]
	var e1: PackedVector3Array = site.get_record(engawa)["points"]
	var turned := rad_to_deg(R.wrap_angle(R.angle_of(R.main_axis(h1)) - R.angle_of(R.main_axis(h0)), TAU))
	check(absf(turned - 45.0) < 0.5, "trois crans : 45° (%.1f°)" % turned)
	check(e1[0].distance_to(e0[0]) > 0.5, "l'engawa a tourné avec la maison")
	check(tool.call("_hugs", R.flat(e1), R.flat(h1)), "et reste collé à la façade")
	await _wait(3.0)
	tool.select(-1)
	(scene.get_node("Interface") as CanvasLayer).visible = false
	await _wait(1.0)
	await _shot("rotation_hameau")
	(scene.get_node("Interface") as CanvasLayer).visible = true
	tool.undo()
	await _wait(1.0)
	check(site.get_record(big)["points"] == h0, "un seul Ctrl+Z remet la maison droite")
	check(site.get_record(engawa)["points"] == e0, "et son engawa")
	tool.redo()
	await _wait(0.5)
	check(site.get_record(big)["points"] == h1, "Ctrl+Y la retourne")
	tool.undo()
	await _wait(0.5)

	print("Une maison ne passe pas à travers sa voisine")
	# La maison en L (rang 1) et le kura (dernier) : on approche le kura tout près.
	var kura: int = -1
	for id in ids:
		if site.get_record(id).get("shape", 0) == BastideSilhouette.Kind.KURA:
			kura = id
	var krec: Dictionary = site.get_record(kura)
	var moved := krec.duplicate(true)
	var kp: PackedVector3Array = krec["points"]
	for i in kp.size():
		kp[i] += Vector3(-5.1, 0, 0)
	moved["points"] = kp
	site.apply_record(kura, moved, false)
	await _wait(0.5)
	tool.select(kura)
	var k0: PackedVector3Array = site.get_record(kura)["points"]
	for k in 4:
		_wheel(1, true)
		await _wait(1.0)
	var k1: PackedVector3Array = site.get_record(kura)["points"]
	check(k1 != k0, "le kura tourne tant qu'il a la place")
	var blocked := false
	for id in ids:
		if id != kura and site.get_record(id)["kind"] == "house":
			blocked = blocked or R.overlaps(R.flat(k1), R.flat(site.get_record(id)["points"]))
	check(not blocked, "mais ne rentre jamais dans la maison voisine")
	check(tool.current_hint().begins_with("Elle toucherait"), "l'aide explique pourquoi il s'arrête")
	tool.select(-1)

	print("Un torii tourné avant d'être posé")
	_key(KEY_4)
	await process_frame
	var tp := Vector3(24, 0, 24)
	_mouse("move", _screen(tp))
	await _wait(0.3)
	var d0: PackedVector3Array = tool.get("_draft_rec")["points"]
	_wheel(1, true)
	await process_frame
	_wheel(1, true)
	await process_frame
	var d1: PackedVector3Array = tool.get("_draft_rec")["points"]
	var tt := rad_to_deg(R.wrap_angle(R.angle_of(d1[1] - d1[0]) - R.angle_of(d0[1] - d0[0]), TAU))
	check(absf(tt - 30.0) < 1.0, "Maj + molette tourne le torii fantôme (%.1f°)" % tt)
	print("")
	print("%s" % ("tout est bon" if _fail == 0 else "%d échec(s)" % _fail))
	quit(_fail)


func _new_id(before: Array) -> int:
	for id in site.ids():
		if not before.has(id):
			return id
	return -1


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


func _wheel(dir: int, shift := false) -> void:
	for pressed in [true, false]:
		var b := InputEventMouseButton.new()
		b.position = root.get_mouse_position()
		b.button_index = MOUSE_BUTTON_WHEEL_UP if dir > 0 else MOUSE_BUTTON_WHEEL_DOWN
		b.pressed = pressed
		b.shift_pressed = shift
		b.button_mask = MOUSE_BUTTON_MASK_LEFT if _held else 0
		root.push_input(b)


func _shot(shot_name: String) -> void:
	for i in 6:
		await process_frame
	if DisplayServer.get_name() == "headless":
		return
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("capture ", shot_name)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
