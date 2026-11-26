extends SceneTree
## Captures d'ambiance (outil de développement) : mêmes points de vue avant et après
## un réglage de lumière ou d'herbe, pour comparer.
##   godot --path . -s tools/ambiance_shots.gd -- <dossier_sortie> [préfixe]

var out_dir := "/tmp/shots"
var prefix := "amb"
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
	# L'herbe se couche bien sur le chemin principal (masque des constructions).
	var grass := scene.get_node("Herbe") as BastideGrass
	var mask_img := (grass.get("_viewport") as SubViewport).get_texture().get_image()
	var uv := (Vector2(0.5, 18.0) - grass.mask_rect.position) / grass.mask_rect.size
	var v := mask_img.get_pixelv(Vector2i(uv * Vector2(mask_img.get_size()))).r
	print("masque sur le chemin : %.2f (%s)" % [v, "ok" if v > 0.9 else "ÉCHEC"])
	(scene.get_node("Interface") as CanvasLayer).visible = false
	# Le halo du logiciel de rendu sans carte graphique (llvmpipe) fait des taches blanches.
	if OS.has_environment("NO_SSIL"):
		(scene.get_node("WorldEnvironment") as WorldEnvironment).environment.ssil_enabled = false
	if OS.has_environment("NO_GLOW"):
		(scene.get_node("WorldEnvironment") as WorldEnvironment).environment.glow_enabled = false
	if OS.get_environment("VIEWS") == "close":
		await _close_views()
		quit()
		return
	# 1. La vue d'ensemble du lancement.
	cam.glide_to(Vector3(-1, 0, -1), 30.0, 14.0)
	await _wait(3.0)
	await _shot("vue")
	# 2. Rasant, depuis la prairie au sud, vers le hameau.
	_walk_at(Vector3(6, 0, 30), Vector3(-2, 0, 0), -0.08)
	await _wait(2.0)
	await _shot("prairie")
	# 3. Au bord du chemin, à contre-jour.
	_walk_at(Vector3(-5, 0, 22), Vector3(-1, 0, 4), -0.1)
	await _wait(2.0)
	await _shot("chemin")
	cam.set_walking(false)
	# 4. Le relief : muret qui suit la pente, maisons posées sur leur socle.
	cam.glide_to(Vector3(-8, 0, -6), 24.0, 16.0)
	await _wait(3.0)
	await _shot("relief")
	cam.glide_to(Vector3(-4, 0, 0), 60.0, 22.0)
	await _wait(3.0)
	await _shot("collines")
	quit()


## Vues rapprochées (toits, murs, bois) : VIEWS=close.
func _close_views() -> void:
	cam.glide_to(Vector3(-5, 0, -5), 11.0, 20.0)
	await _wait(3.0)
	await _shot("pres_maison")
	cam.glide_to(Vector3(8, 0, -4), 15.0, -50.0)
	await _wait(3.0)
	await _shot("pres_toit")
	_walk_at(Vector3(-1, 0, 6), Vector3(-5, 2.5, -4), 0.08)
	await _wait(2.0)
	await _shot("pres_facade")
	# Vie du hameau : lanterne au premier plan, fumée sur le toit, papillons.
	_walk_at(Vector3(1.5, 0, 5.5), Vector3(-7, 6, -3), 0.12)
	await _wait(2.5)
	await _shot("vie")
	cam.set_walking(false)
	cam.glide_to(Vector3(-4, 0, -2), 26.0, 25.0)
	await _wait(3.0)
	await _shot("vie_haut")


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
