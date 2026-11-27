extends SceneTree
## Captures de l'herbe (outil de développement) : promenade de près, à hauteur
## d'herbe, vue mi-haute et vue de dessus, aux heures demandées.
##   godot --path . -s tools/grass_shots.gd -- <dossier_sortie> <heures, ex. 12,17.5> [préfixe]

var out_dir := "/tmp/shots"
var hours := [12.0, 17.5]
var prefix := "herbe"
var scene: Node
var cam: Camera3D
var site: BastideBuildSite


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		hours = []
		for h in args[1].split(","):
			hours.append(float(h))
	if args.size() > 2:
		prefix = args[2]
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	scene = (load("res://demos/04_runtime/runtime_demo.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	cam = scene.get_node("Camera")
	site = scene.get_node("Chantier")
	(scene.get_node("Interface") as CanvasLayer).visible = false
	var gfx: Node = scene.get_node_or_null("Graphismes")
	if gfx:
		gfx.set("auto_apply", false)
		gfx.call("apply", int(OS.get_environment("NIVEAU")) if OS.has_environment("NIVEAU") else 2, false)
	var env := (scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	if OS.has_environment("NO_SSIL"):
		env.ssil_enabled = false
	if cam.attributes is CameraAttributesPractical:
		(cam.attributes as CameraAttributesPractical).dof_blur_far_enabled = false
	var day := scene.get_node("JourNuit") as BastideDayNight
	day.running = false
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	for i in 30:
		await process_frame
	cam.set_process(false)
	if OS.has_environment("MASK"):
		var g := scene.get_node("Herbe") as BastideGrass
		(g.get("_viewport") as SubViewport).get_texture().get_image().save_png(out_dir.path_join("mask.png"))
	var field := BastideTerrain.field_for(cam)
	var gh := func(p: Vector3) -> float:
		return field.height(p.x, p.z) if field else 0.0
	# [nom, œil (y = au-dessus du sol), visée (y = au-dessus du sol), fov]
	var views := [
		["promenade", Vector3(6, 1.65, 30), Vector3(-2, 1.2, 4), 70.0],
		["ras", Vector3(9, 0.55, 26), Vector3(2, 0.3, 18), 60.0],
		["mi_haut", Vector3(8, 6.0, 38), Vector3(0, 0.0, 20), 55.0],
		["dessus", Vector3(22, 30.0, 40), Vector3(0, 0.0, 6), 50.0],
	]
	for h: float in hours:
		day.hour = h
		day.set("_sky_hour", -100.0)
		for i in 6:
			await process_frame
		for v: Array in views:
			if OS.has_environment("VIEWS") and not String(v[0]) in OS.get_environment("VIEWS").split(","):
				continue
			var eye: Vector3 = v[1]
			eye.y += gh.call(eye)
			var tgt: Vector3 = v[2]
			tgt.y += gh.call(tgt)
			cam.fov = v[3]
			if cam is BastideOrbitCamera:
				# L'herbe suit le point visé (ou l'œil en promenade).
				(cam as BastideOrbitCamera).target = eye if eye.y - gh.call(eye) < 3.0 else tgt
			cam.look_at_from_position(eye, tgt)
			for i in 16:
				await process_frame
			var img := root.get_viewport().get_texture().get_image()
			var path := out_dir.path_join("%s_h%02d_%s.png" % [prefix, int(h), v[0]])
			img.save_png(path)
			print("capture ", path)
	quit()


func _all_built(n: int) -> bool:
	if site.ids().size() < n:
		return false
	for id in site.ids():
		var node := site.node_of(id)
		if node == null or node.last_stats.is_empty():
			return false
	return site.garden != null and not site.garden.last_stats.is_empty()
