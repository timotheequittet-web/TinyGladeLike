extends SceneTree
## Captures des jardins d'eau (outil de développement) : l'étang du hameau vu de
## haut, depuis la rive et à hauteur de promeneur.
##   godot --path . -s tools/pond_shots.gd -- <dossier_sortie> [préfixe]

var out_dir := "/tmp/shots"
var prefix := "etang"
var scene: Node
var cam: BastideOrbitCamera
var site: BastideBuildSite


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		prefix = args[1]
	_run.call_deferred()


func _run() -> void:
	scene = (load("res://demos/04_runtime/runtime_demo.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	cam = scene.get_node("Camera")
	site = scene.get_node("Chantier")
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while (site.ids().size() < n0 or not _all_built()) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	await _wait(2.0)
	(scene.get_node("Interface") as CanvasLayer).visible = false
	if OS.has_environment("NO_GLOW"):
		(scene.get_node("WorldEnvironment") as WorldEnvironment).environment.glow_enabled = false
	var c := Vector3(-27, 0, 16)
	var env_c := OS.get_environment("POND_AT")
	if env_c != "":
		var parts := env_c.split(",")
		c = Vector3(float(parts[0]), 0, float(parts[1]))
	cam.glide_to(c, 24.0, 115.0)
	await _wait(3.0)
	await _shot("haut")
	cam.glide_to(c + Vector3(-2, 0, 1), 12.0, 150.0)
	await _wait(3.0)
	await _shot("rive")
	_walk_at(c + Vector3(9, 0, -3), c + Vector3(-2, 0, 2), -0.16)
	await _wait(2.5)
	await _shot("promeneur")
	cam.set_walking(false)
	if OS.get_environment("EXTRA") != "":
		# Un étang traversé par un chemin (pont) et une source chaude.
		var j := "res://addons/bastide/styles/presets/japanese_wood.tres"
		site.apply_record(900, {"kind": "pond", "seed": 61, "style": j, "closed": true, "pond_kind": 0,
			"points": PackedVector3Array([Vector3(11, 0, 15), Vector3(17, 0, 13.5), Vector3(22, 0, 16), Vector3(21, 0, 21),
				Vector3(15, 0, 22.5), Vector3(10.5, 0, 19.5)])}, false)
		site.apply_record(901, {"kind": "path", "seed": 62, "style": j,
			"points": PackedVector3Array([Vector3(6, 0, 17.5), Vector3(12, 0, 18), Vector3(19, 0, 18.4), Vector3(27, 0, 17.6)])}, false)
		site.apply_record(902, {"kind": "pond", "seed": 63, "style": j, "closed": true, "pond_kind": 1,
			"points": PackedVector3Array([Vector3(25, 0, 3), Vector3(29, 0, 2), Vector3(31, 0, 6), Vector3(28, 0, 9), Vector3(24.5, 0, 7)])}, false)
		await _wait(6.0)
		cam.glide_to(Vector3(17, 0, 18), 22.0, 160.0)
		await _wait(3.0)
		await _shot("pont_haut")
		_walk_at(Vector3(16, 0, 27), Vector3(16, 1, 18), -0.08)
		await _wait(2.5)
		await _shot("pont")
		cam.set_walking(false)
		cam.glide_to(Vector3(28, 0, 5.5), 12.0, 60.0)
		await _wait(3.0)
		await _shot("onsen")
	quit()


func _walk_at(p: Vector3, look: Vector3, pitch: float) -> void:
	if cam.walking:
		cam.set_walking(false)
	cam.target = p
	cam.focus(p)
	cam.set_walking(true)
	var d := look - p
	var yaw := atan2(-d.x, -d.z)
	cam.set("_goal_yaw", yaw)
	cam.set("_yaw", yaw)
	cam.set("_goal_walk_pitch", pitch)
	cam.set("_walk_pitch", pitch)


func _all_built() -> bool:
	for id in site.ids():
		var node := site.node_of(id)
		if node == null or node.last_stats.is_empty():
			return false
	return true


func _wait(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < sec * 1000.0:
		await process_frame


func _shot(shot_name: String) -> void:
	for i in 6:
		await process_frame
	if DisplayServer.get_name() == "headless":
		return
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [prefix, shot_name]))
	print("capture ", shot_name)
