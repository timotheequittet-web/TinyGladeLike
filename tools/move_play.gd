extends SceneTree
## Partie scriptée du déplacement et des gestes fluides (outil de développement) :
## la grande maison du hameau glissée à la souris (son engawa la suit), sans
## aucune régénération pendant le geste ; une seule au relâchement, collisions
## comprises ; Ctrl+Z ; une poignée tirée sans réveiller le jardin ni les voisins ;
## une rotation sans régénération ni saut ; une maison bloquée contre sa voisine.
##   godot --headless --path . -s tools/move_play.gd

var out_dir := "/tmp/shots"
var scene: Node
var cam: Camera3D
var site: BastideBuildSite
var tool: BastideBuildTool
var _fail := 0
var _held := false
var _builds := {}


func _init() -> void:
	_run.call_deferred()


func _count(node: BastideStructure) -> void:
	if not node.rebuilt.is_connected(_on_rebuilt):
		node.rebuilt.connect(_on_rebuilt.bind(node))


func _on_rebuilt(_s: Dictionary, node: Node) -> void:
	_builds[node] = int(_builds.get(node, 0)) + 1


func _n(node: Node) -> int:
	return int(_builds.get(node, 0))


func _world_center(node: BastideStructure) -> Vector3:
	# Moyenne des sommets (l'AABB d'un maillage tourné ne suit pas son centre).
	var mi := node.get_mesh_instance()
	var sum := Vector3.ZERO
	var n := 0
	for si in mi.mesh.get_surface_count():
		var v: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for p in v:
			sum += p
		n += v.size()
	return mi.global_transform * (sum / maxi(n, 1))


func _has_body(node: Node) -> bool:
	for c in node.get_children(true):
		if c is StaticBody3D and not c.is_queued_for_deletion():
			return true
	return false


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
	var ids := site.ids()
	ids.sort()
	var big: int = ids[0]
	var engawa: int = ids[3]
	var house := site.node_of(big)
	for id in ids:
		_count(site.node_of(id))
	_count(site.garden)

	print("La grande maison glissée à la souris")
	cam.call("glide_to", Vector3(-4, 0, -2), 30.0, 0.0)
	await _wait(2.5)
	_key(KEY_2)
	await process_frame
	tool.select(big)
	await process_frame
	var h0: PackedVector3Array = site.get_record(big)["points"]
	var e0: PackedVector3Array = site.get_record(engawa)["points"]
	var grab := BastideStroke.centroid(h0)
	var c0 := _world_center(house)
	_mouse("move", _screen(grab))
	await _wait(0.3)
	check(tool.get("_hover") == big, "la souris est sur la maison sélectionnée")
	var b_house := _n(house)
	var b_garden := _n(site.garden)
	var others := 0
	for id in ids:
		others += _n(site.node_of(id))
	_mouse("down", _screen(grab))
	await process_frame
	_held = true
	var to := grab + Vector3(0, 0, 3.0)
	var worst := 0
	for k in 12:
		var f0 := Time.get_ticks_usec()
		_mouse("move", _screen(grab.lerp(to, (k + 1) / 12.0)), true)
		await process_frame
		worst = maxi(worst, Time.get_ticks_usec() - f0)
	await _wait(0.5)
	var h1: PackedVector3Array = site.get_record(big)["points"]
	var moved := (h1[0] - h0[0])
	check(moved.length() > 2.0, "la maison suit la souris (%.2f m)" % moved.length())
	check(_n(house) == b_house and _n(site.garden) == b_garden, "rien n'est régénéré pendant le geste")
	check(_world_center(house).distance_to(c0 + moved) < 0.05, "le maillage a glissé avec elle")
	var e1: PackedVector3Array = site.get_record(engawa)["points"]
	check((e1[0] - e0[0]).distance_to(moved) < 0.01, "son engawa la suit")
	print("  (image la plus lente pendant le geste : %.1f ms)" % (worst / 1000.0))
	_mouse("up", _screen(to))
	_held = false
	await _wait(3.0)
	check(_n(house) == b_house + 1, "une seule régénération au relâchement (%d)" % (_n(house) - b_house))
	check(_n(site.garden) > b_garden, "le jardin se refait une fois posé")
	check(_has_body(house), "la maison a ses collisions")
	var dd := _world_center(house) - (c0 + moved)
	check(Vector2(dd.x, dd.z).length() < 0.3, "et reste au même endroit après régénération (%s)" % dd)
	tool.undo()
	await _wait(2.0)
	check(site.get_record(big)["points"] == h0, "Ctrl+Z la remet à sa place")
	check(site.get_record(engawa)["points"] == e0, "avec son engawa")
	check(_world_center(house).distance_to(c0) < 0.3, "le maillage aussi")

	print("Une poignée tirée : seule la maison se régénère")
	await _wait(1.0)
	b_garden = _n(site.garden)
	b_house = _n(house)
	var handles: Array = tool.get("_handles")
	var edge := -1
	for i in handles.size():
		if handles[i]["kind"] == "edge":
			edge = i
			break
	var hp: Vector3 = handles[edge]["pos"]
	_mouse("move", _screen(hp))
	await _wait(0.3)
	check(tool.get("_hover_handle") >= 0, "la souris est sur une poignée")
	_mouse("down", _screen(hp))
	await process_frame
	_held = true
	var a := handles[edge]["index"] as int
	var pts: PackedVector3Array = site.get_record(big)["points"]
	var dir := (pts[(a + 1) % pts.size()] - pts[a]).normalized()
	var nrm := Vector3(dir.z, 0, -dir.x)
	for k in 10:
		_mouse("move", _screen(hp + nrm * (0.2 * (k + 1))), true)
		await _wait(0.15)
	check(_n(house) > b_house, "la maison change de forme pendant le geste")
	check(_n(site.garden) == b_garden, "le jardin attend la fin du geste")
	_mouse("up", _screen(hp + nrm * 2.0))
	_held = false
	await _wait(3.0)
	check(_n(site.garden) > b_garden, "puis se refait")
	check(_has_body(house), "collisions refaites")
	tool.undo()
	await _wait(2.0)

	print("Une rotation sans régénération pendant les crans")
	b_house = _n(house)
	c0 = _world_center(house)
	for k in 2:
		_wheel(1, true)
	await process_frame
	await process_frame
	check(_n(house) == b_house, "les crans ne régénèrent rien")
	var c_turn := _world_center(house)
	await _wait(2.5)
	check(_n(house) == b_house + 1, "une régénération quand la molette s'arrête (%d)" % (_n(house) - b_house))
	var dt := _world_center(house) - c_turn
	check(Vector2(dt.x, dt.z).length() < 0.3, "sans saut (%s)" % dt)
	tool.undo()
	await _wait(2.0)
	check(_world_center(house).distance_to(c0) < 0.3, "Ctrl+Z la remet droite (%s)" % (_world_center(house) - c0))

	print("Une maison ne passe pas à travers sa voisine")
	var kura := -1
	for id in ids:
		if site.get_record(id).get("shape", 0) == BastideSilhouette.Kind.KURA:
			kura = id
	tool.select(kura)
	var kp: PackedVector3Array = site.get_record(kura)["points"]
	var kc := BastideStroke.centroid(kp)
	var target := BastideStroke.centroid(site.get_record(big)["points"])
	cam.call("glide_to", kc.lerp(target, 0.5), 36.0, 0.0)
	await _wait(2.5)
	_mouse("move", _screen(kc))
	await _wait(0.3)
	_mouse("down", _screen(kc))
	await process_frame
	_held = true
	for k in 20:
		_mouse("move", _screen(kc.lerp(target, (k + 1) / 20.0)), true)
		await process_frame
	var k1: PackedVector3Array = site.get_record(kura)["points"]
	var blocked := false
	for id in ids:
		if id != kura and site.get_record(id)["kind"] == "house":
			blocked = blocked or R.overlaps(R.flat(k1), R.flat(site.get_record(id)["points"]))
	check(k1 != kp, "le kura a avancé")
	check(not blocked, "mais pas dans la maison voisine")
	check(tool.current_hint().begins_with("Elle toucherait"), "l'aide explique pourquoi il s'arrête")
	_mouse("up", _screen(target))
	_held = false
	await _wait(1.0)

	print("Aimantation sur les façades (règle pure)")
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
	var other := PackedVector2Array([Vector2(4.3, 0.2), Vector2(9, 0.2), Vector2(9, 5), Vector2(4.3, 5)])
	var m := R.slide_magnet(sq, [other])
	check(m.distance_to(Vector2(0.3, 0.2)) < 0.01, "colle la façade et aligne le pignon (%s)" % m)
	check(R.slide_magnet(sq, [PackedVector2Array([Vector2(6, 0.9), Vector2(9, 0.9), Vector2(9, 5), Vector2(6, 5)])]) == Vector2.ZERO, "rien si c'est trop loin")
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
