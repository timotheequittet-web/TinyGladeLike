extends SceneTree
## Partie scriptée des escaliers (outil de développement) : en promenade, on monte et
## on descend chaque volée de chaque silhouette de maison, en marchant et en courant,
## à 60, 30 et 20 images/s. À chaque pas, on mesure la hauteur de l'œil : elle doit
## suivre la rampe sans plonger ni rester coincée, et on doit arriver en haut / en bas.
##   godot --headless --path . -s tools/stairs_play.gd
## (headless suffit : la marche ne dépend que de la physique.)

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
	preload("res://tools/play_light.gd").apply(scene)
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	var houses := {}
	for n in scene.get_tree().get_nodes_in_group(BastideStructure.GROUP):
		if n is BastideBuilding and not houses.has((n as BastideBuilding).resolved_silhouette()):
			houses[(n as BastideBuilding).resolved_silhouette()] = n
	for kind in houses:
		await _visit(houses[kind], String(BastideSilhouette.NAMES[kind]))
	print("")
	print("Escaliers : %d échec(s)" % _fail)
	quit(_fail)


func _visit(b: BastideBuilding, label: String) -> void:
	var lift := float(b.last_stats.get("terrain_lift", 0.0))
	var doors: Array = b.last_anchors.get("doors", [])
	var door_pos: Vector3 = b.to_global(doors[0]["pos"] + Vector3(0, lift, 0)) if not doors.is_empty() else b.global_position
	cam.target = Vector3(door_pos.x, 0, door_pos.z)
	cam.set_walking(true)
	cam.place_walker(door_pos)
	var t0 := Time.get_ticks_msec()
	while not b.is_interior_ready() and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	for i in 10:
		await physics_frame
	var il := b.interior_layout()
	if il == null or il.flights.is_empty():
		print("--- %s : pas d'escalier" % label)
		cam.set_walking(false)
		return
	print("--- ", label)
	cam.set_process(false)
	for fl: BastideInteriorLayout.Flight in il.flights:
		for fps: int in [60, 30, 20]:
			for run: bool in [false, true]:
				await _climb(b, fl, lift, fps, run, true, label)
				await _climb(b, fl, lift, fps, run, false, label)
	cam.set_process(true)
	cam.set_walking(false)
	await _frames(10)


## Une montée (ou descente) complète, pas à pas, avec un pas de temps imposé.
func _climb(b: BastideBuilding, fl: BastideInteriorLayout.Flight, lift: float, fps: int, run: bool, up: bool, label: String) -> void:
	var mid := fl.width * 0.5
	var start_al := -0.5 if up else fl.run() + 0.5
	var y_start := fl.y0 if up else fl.y1
	var y_end := fl.y1 if up else fl.y0
	var a2 := fl.at(start_al, mid)
	var p := b.to_global(Vector3(a2.x, y_start + lift, a2.y))
	var d2 := fl.dir if up else -fl.dir
	var d3 := (b.global_transform.basis * Vector3(d2.x, 0, d2.y)).normalized()
	cam.place_walker(p, rad_to_deg(atan2(-d3.x, -d3.z)))
	cam.set("_goal_walk_pitch", 0.0)
	_key(KEY_SHIFT, run)
	_key(KEY_W, true)
	var dt := 1.0 / fps
	var speed := cam.run_speed if run else cam.walk_speed
	var steps := ceili((fl.run() + 1.0) / speed * 1.6 / dt) + 4
	var worst := 0.0   # écart maximal de l'œil sous / au-dessus de la rampe
	var drop := 0.0    # plus grande chute d'une image à l'autre en montant (ou remontée en descendant)
	var last_y := INF
	var arrived := false
	var reach := -INF if up else INF
	for i in steps:
		cam.call("_walk", dt)
		await physics_frame
		var lp := b.to_local(cam.global_position)
		var eye := lp.y - lift - cam.eye_height
		var al := (Vector2(lp.x, lp.z) - fl.start).dot(fl.dir)
		var across := (Vector2(lp.x, lp.z) - fl.start).dot(fl.side)
		if across < -0.1 or across > fl.width + 0.1:
			break
		reach = maxf(reach, al) if up else minf(reach, al)
		var ideal := fl.height_at(al)
		worst = maxf(worst, absf(eye - ideal))
		if is_finite(last_y):
			drop = maxf(drop, (last_y - eye) if up else (eye - last_y))
		last_y = eye
		if (up and al > fl.run() + 0.1) or (not up and al < -0.05):
			arrived = true
			break
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	var lp := b.to_local(cam.walker_position())
	var tag := "%s volée %d %s, %s, %d im/s" % [label, fl.from_level, "montée" if up else "descente", "course" if run else "marche", fps]
	check(arrived, "%s : arrive au bout (%.2f m sur %.2f)" % [tag, reach, fl.run()])
	check(absf(lp.y - lift - y_end) < 0.12, "%s : pieds sur le bon plancher (%.2f / %.2f)" % [tag, lp.y - lift, y_end])
	check(drop < 0.08, "%s : pas de saut de l'œil (%.2f m)" % [tag, drop])
	check(worst < 0.4, "%s : l'œil suit la rampe (écart %.2f m)" % [tag, worst])


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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()
