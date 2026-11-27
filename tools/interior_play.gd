extends SceneTree
## Partie scriptée des intérieurs (outil de développement) : en promenade (P), on
## entre dans chaque silhouette de maison (grande maison, petite maison, kura, tour)
## par sa porte, on monte les escaliers jusqu'en haut, puis on ressort. Vérifications
## et captures.
##   godot --path . --fixed-fps 60 -s tools/interior_play.gd -- <dossier_sortie>
## (--fixed-fps : le temps du jeu avance d'1/60 s par image, même quand le rendu
## logiciel est lent ; les attentes sont comptées en images.)

var out_dir := "/tmp/shots"
var scene: Node
var cam: BastideOrbitCamera
var site: BastideBuildSite
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
	preload("res://tools/play_light.gd").apply(scene)
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	# Une petite maison de paysan dans le pré, pour avoir les quatre silhouettes.
	var small := BastideBuilding.new()
	small.name = "PetiteMaison"
	small.style = load("res://addons/bastide/styles/presets/japanese_wood.tres")
	small.silhouette = BastideSilhouette.Kind.SMALL
	small.seed = 77
	small.door_facade = 0
	var c := Curve3D.new()
	for p in [Vector3(15, 0, 12), Vector3(21, 0, 12), Vector3(21, 0, 16.5), Vector3(15, 0, 16.5)]:
		c.add_point(p)
	c.closed = true
	small.curve = c
	scene.add_child(small)
	await _wait(3.0)
	(scene.get_node("Interface") as CanvasLayer).visible = false

	var houses: Array = []
	for n in scene.get_tree().get_nodes_in_group(BastideStructure.GROUP):
		if n is BastideBuilding:
			houses.append(n)
	check(houses.size() >= 5, "%d maisons dans le hameau" % houses.size())
	check(_interior_nodes() == 0, "vu d'en haut, aucune maison n'a d'intérieur")

	var done := {}
	for b: BastideBuilding in houses:
		var kind := b.resolved_silhouette()
		if done.has(kind):
			continue
		done[kind] = true
		await _visit(b, String(BastideSilhouette.NAMES[kind]), kind)

	cam.set_walking(false)
	await _wait(1.5)
	check(_interior_nodes() == 0, "en remontant, tous les intérieurs sont retirés")
	print("")
	print("Partie scriptée : %d échec(s)" % _fail)
	quit(_fail)


func _visit(b: BastideBuilding, label: String, kind: int) -> void:
	print("--- ", label)
	var tag: String = {BastideSilhouette.Kind.HOUSE: "maison", BastideSilhouette.Kind.SMALL: "petite",
		BastideSilhouette.Kind.KURA: "kura", BastideSilhouette.Kind.TOWER: "tour"}.get(kind, "maison")
	var doors: Array = b.last_anchors.get("doors", [])
	if doors.is_empty():
		check(false, "%s : une porte" % label)
		return
	var lift := float(b.last_stats.get("terrain_lift", 0.0))
	var door_pos: Vector3 = b.to_global(doors[0]["pos"] + Vector3(0, lift, 0))
	var out: Vector3 = (b.global_transform.basis * (doors[0]["out"] as Vector3)).normalized()
	# Dehors, à 5 m de la porte, face à elle.
	if cam.walking:
		cam.set_walking(false)
		await _wait(0.6)
	var start := door_pos + out * 5.0
	cam.target = Vector3(start.x, 0, start.z)
	cam.focus(cam.target)
	cam.set_walking(true)
	await _wait(0.3)
	var field := BastideTerrain.field_for(cam)
	var gy := field.height(start.x, start.z) if field else 0.0
	cam.place_walker(Vector3(start.x, gy, start.z), rad_to_deg(atan2(out.x, out.z)))
	cam.set("_goal_walk_pitch", -0.05)
	var t0 := Time.get_ticks_msec()
	while not b.is_interior_ready() and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	check(b.is_interior_ready(), "%s : l'intérieur apparaît quand on approche" % label)
	await _wait(0.4)
	await _shot("interieur_%s_porte" % tag)
	var il := b.interior_layout()
	if il == null:
		return
	# On entre : la porte s'ouvre, on passe le seuil, on monte sur le plancher.
	var max_open := 0.0
	_key(KEY_W, true)
	var walked := 0.0
	var inside_at := -1.0
	while walked < 7.0:
		await process_frame
		walked += 1.0 / 60.0
		max_open = maxf(max_open, b.doors_open())
		var lp := b.to_local(cam.walker_position())
		if il.contains(Vector2(lp.x, lp.z)) and inside_at < 0.0:
			inside_at = walked
		if inside_at > 0.0 and walked - inside_at > 1.6:
			break
	_key(KEY_W, false)
	await _wait(0.8)
	var lp := b.to_local(cam.walker_position())
	check(max_open > 0.9, "%s : la porte s'ouvre devant le promeneur (%.2f)" % [label, max_open])
	check(il.contains(Vector2(lp.x, lp.z)), "%s : on entre dans la maison" % label)
	var ground: BastideInteriorLayout.Level = il.levels[0]
	check(absf(lp.y - lift - ground.y) < 0.12, "%s : on marche sur le parquet (%.2f m, plancher à %.2f m)" % [label, lp.y - lift, ground.y])
	# Regard vers le fond de la pièce, puis vers l'escalier.
	cam.set("_goal_walk_pitch", 0.02)
	await _wait(1.2)
	await _shot("interieur_%s_dedans" % tag)
	if il.flights.is_empty():
		check(il.levels.size() == 1, "%s : un seul niveau, pas d'escalier" % label)
		cam.set("_goal_yaw", float(cam.get("_goal_yaw")) + PI)
		await _wait(1.5)
		await _shot("interieur_%s_entree" % tag)
		return
	for fl: BastideInteriorLayout.Flight in il.flights:
		var lv: BastideInteriorLayout.Level = il.levels[fl.from_level]
		var foot2 := fl.at(-0.3, fl.width * 0.5)
		var foot := b.to_global(Vector3(foot2.x, lv.y + lift, foot2.y))
		var d3 := (b.global_transform.basis * Vector3(fl.dir.x, 0, fl.dir.y)).normalized()
		# Un peu en retrait et de biais : on voit la volée avant d'y monter.
		var side3 := (b.global_transform.basis * Vector3(fl.side.x, 0, fl.side.y)).normalized()
		var back := foot
		for cand: Vector3 in [foot - d3 * 0.4 + side3 * 1.8, foot + side3 * 1.6, foot - d3 * 0.3 + side3 * 0.9]:
			if _on_floor(b, lv, cand - Vector3(0, lift, 0)):
				back = cand
				break
		cam.place_walker(back, rad_to_deg(atan2(-(foot - back).x, -(foot - back).z)) + 20.0)
		cam.set("_goal_walk_pitch", 0.18)
		await _wait(1.4)
		await _shot("interieur_%s_escalier_%d" % [tag, fl.from_level])
		cam.place_walker(foot, rad_to_deg(atan2(-d3.x, -d3.z)))
		cam.set("_goal_walk_pitch", 0.1)
		await _wait(0.4)
		_key(KEY_W, true)
		await _wait(fl.run() / cam.walk_speed + 1.2)
		_key(KEY_W, false)
		await _wait(0.8)
		var up: BastideInteriorLayout.Level = il.levels[fl.from_level + 1]
		var q := b.to_local(cam.walker_position())
		check(absf(q.y - lift - up.y) < 0.15, "%s : l'escalier monte au niveau %d (%.2f m, plancher à %.2f m)" % [label, up.index, q.y - lift, up.y])
		cam.set("_goal_yaw", float(cam.get("_goal_yaw")) + 2.3)
		cam.set("_goal_walk_pitch", 0.08)
		await _wait(1.6)
		await _shot("interieur_%s_niveau_%d" % [tag, up.index])
	# Le garde-corps retient au bord de la trémie.
	var top: BastideInteriorLayout.Level = il.levels[il.flights[il.flights.size() - 1].from_level + 1]
	if not top.railings.is_empty():
		var fl: BastideInteriorLayout.Flight = il.flights[il.flights.size() - 1]
		var a := fl.at(fl.run() * 0.5, fl.width + 1.2)
		var p := b.to_global(Vector3(a.x, top.y + lift, a.y))
		var toward := (b.global_transform.basis * Vector3(-fl.side.x, 0, -fl.side.y)).normalized()
		cam.place_walker(p, rad_to_deg(atan2(-toward.x, -toward.z)))
		await _wait(0.3)
		_key(KEY_W, true)
		await _wait(1.6)
		_key(KEY_W, false)
		await _wait(0.4)
		var q := b.to_local(cam.walker_position())
		check(absf(q.y - lift - top.y) < 0.15, "%s : le garde-corps empêche de tomber dans la trémie" % label)


func _on_floor(b: BastideBuilding, lv: BastideInteriorLayout.Level, world: Vector3) -> bool:
	var p := b.to_local(world)
	for piece: PackedVector2Array in lv.pieces:
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), BastidePolygon.offset(piece, 0.45)):
			return true
	return false


func _interior_nodes() -> int:
	var n := 0
	for s in scene.get_tree().get_nodes_in_group(BastideStructure.GROUP):
		for c in (s as Node).get_children(true):
			if String(c.name) == String(BastideInteriorHost.INTERIOR_NAME):
				n += 1
	return n


func _all_built(n: int) -> bool:
	if site.ids().size() < n:
		return false
	for id in site.ids():
		var node := site.node_of(id)
		if node == null or node.last_stats.is_empty():
			return false
	return true


func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_fail += 1
		printerr("  ÉCHEC ", label)


func _wait(sec: float) -> void:
	for i in ceili(sec * 60.0):
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
