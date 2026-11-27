extends SceneTree
## Captures du hameau à différentes heures (outil de développement) : vue des portes
## (lierre, enduit patiné, lanternes), bord de chemin à hauteur d'herbe et vue
## d'ensemble.
##   godot --path . -s tools/vie_shots.gd -- <dossier_sortie> <heures séparées par des virgules> [glow 0|1]

var out_dir := "/tmp/shots"
var hours := [17.2]
var glow := false
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
		glow = args[2] == "1"
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
		gfx.call("apply", 2, false)
	var env := (scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	if cam.attributes is CameraAttributesPractical:
		(cam.attributes as CameraAttributesPractical).dof_blur_far_enabled = false
	var day := scene.get_node("JourNuit") as BastideDayNight
	day.running = false
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	for i in 40:
		await process_frame
	cam.set_process(false)
	var views := _views()
	for h: float in hours:
		day.hour = h
		day.set("_sky_hour", -100.0)
		for i in 6:
			await process_frame
		env.glow_enabled = glow
		var k := 0
		for v: Array in views:
			cam.fov = v[2]
			cam.look_at_from_position(v[0], v[1])
			if cam is BastideOrbitCamera:
				(cam as BastideOrbitCamera).target = v[1]
			for i in 14:
				await process_frame
			var img := root.get_viewport().get_texture().get_image()
			var path := out_dir.path_join("h%02d_%d.png" % [int(h), k])
			img.save_png(path)
			print("capture ", path)
			k += 1
	quit()


func _views() -> Array:
	var out: Array = []
	var field := BastideTerrain.field_for(cam)
	var gh := func(p: Vector3) -> float:
		return field.height(p.x, p.z) if field else 0.0
	var n := 0
	for id in site.ids():
		var node := site.node_of(id)
		if not node is BastideBuilding:
			continue
		var d: Dictionary = node.describe()
		var doors: Array = d.get("doors", [])
		if doors.is_empty():
			continue
		var door: Dictionary = doors[0]
		var p: Vector3 = door["pos"]
		var o: Vector3 = door["out"]
		var side := Vector3(-o.z, 0, o.x)
		var lift: float = node.last_stats.get("terrain_lift", 0.0)
		var target := Vector3(p.x, lift + p.y + 1.8, p.z)
		var eye := p + o * 6.0 + side * 3.0
		eye.y = gh.call(eye) + 1.7
		out.append([eye, target, 62.0])
		n += 1
		if n >= 3:
			break
	# Bord de chemin, à hauteur d'herbe.
	for id in site.ids():
		var node := site.node_of(id)
		if node is BastidePath:
			var dd: Dictionary = node.describe()
			var pts: PackedVector3Array = dd["points"]
			if pts.size() >= 3:
				var a := pts[pts.size() / 2]
				var b := pts[pts.size() / 2 + 1]
				var dir := (b - a).normalized()
				var eye := a - dir * 3.0 + Vector3(-dir.z, 0, dir.x) * 1.2
				eye.y = gh.call(eye) + 0.7
				var tgt := a + dir * 2.0
				tgt.y = gh.call(tgt) + 0.1
				out.append([eye, tgt, 60.0])
				break
	# Vue d'ensemble.
	out.append([Vector3(22, 0, 26) + Vector3(0, gh.call(Vector3(22, 0, 26)) + 14.0, 0), Vector3(-2, 1, -2), 50.0])
	return out


func _all_built(n: int) -> bool:
	if site.ids().size() < n:
		return false
	for id in site.ids():
		var node := site.node_of(id)
		if node == null or node.last_stats.is_empty():
			return false
	return site.garden != null and not site.garden.last_stats.is_empty()
