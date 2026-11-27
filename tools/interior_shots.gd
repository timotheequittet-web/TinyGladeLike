extends SceneTree
## Captures des intérieurs (outil de développement), sans simuler la marche : la
## caméra est posée à hauteur d'homme dans chaque silhouette (entrée, pièce,
## escalier, étage). Pour les vérifications, voir interior_play.gd.
##   godot --path . -s tools/interior_shots.gd -- <dossier_sortie>

var out_dir := "/tmp/shots"
var scene: Node
var cam: BastideOrbitCamera
var site: BastideBuildSite


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
	if not OS.has_environment("FULL_RENDER"):
		preload("res://tools/play_light.gd").apply(scene)
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 300000:
		await process_frame
	var small := BastideBuilding.new()
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
	await _frames(30)
	(scene.get_node("Interface") as CanvasLayer).visible = false
	cam.set_process(false)
	var done := {}
	for n in scene.get_tree().get_nodes_in_group(BastideStructure.GROUP):
		var b := n as BastideBuilding
		if b == null:
			continue
		var kind := b.resolved_silhouette()
		if done.has(kind):
			continue
		done[kind] = true
		var tag: String = {BastideSilhouette.Kind.HOUSE: "maison", BastideSilhouette.Kind.SMALL: "petite",
			BastideSilhouette.Kind.KURA: "kura", BastideSilhouette.Kind.TOWER: "tour"}.get(kind, "maison")
		await _house(b, tag)
	quit(0)


func _house(b: BastideBuilding, tag: String) -> void:
	b.set_interior_active(true)
	var t0 := Time.get_ticks_msec()
	while not b.is_interior_ready() and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	b._interior.force_open = 1.0
	var il := b.interior_layout()
	if il == null:
		return
	var lift := float(b.last_stats.get("terrain_lift", 0.0))
	var door: Dictionary = b.last_anchors["doors"][0]
	var dpos: Vector3 = door["pos"]
	var out: Vector3 = door["out"]
	var inside := dpos - out * (il.wall_thickness + 2.0) + Vector3(0, il.levels[0].y, 0)
	for i in 20:
		b.update_interior(b.to_global(inside + Vector3(0, lift, 0)), 0.2)
	var eye := 1.6
	# Dehors, face à la porte ouverte.
	_look(b, dpos + out * 4.2 + Vector3(0, lift + 1.5, 0), dpos + Vector3(0, lift + 1.2, 0))
	await _shot("interieur_%s_porte" % tag)
	# Sur le seuil : l'entrée en contrebas, le plancher, le fond de la pièce.
	_look(b, dpos - out * 0.25 + Vector3(0, lift + eye, 0), dpos - out * 6.0 + Vector3(0, lift + 1.0, 0))
	await _shot("interieur_%s_dedans" % tag)
	var g := BastidePolygon.centroid(il.inner)
	if il.flights.is_empty():
		# Du fond, vers la porte et la charpente.
		var far := Vector3(g.x, il.levels[0].y, g.y) + (Vector3(g.x, 0, g.y) - Vector3(dpos.x, 0, dpos.z)).normalized() * 1.2
		_look(b, far + Vector3(0, lift + eye, 0), dpos + Vector3(0, lift + 1.6, 0))
		await _shot("interieur_%s_entree" % tag)
		return
	for fl: BastideInteriorLayout.Flight in il.flights:
		var lv: BastideInteriorLayout.Level = il.levels[fl.from_level]
		var mid := fl.at(fl.run() * 0.5, fl.width)
		var cen := Vector3(g.x, lv.y, g.y)
		var away := (cen - Vector3(mid.x, lv.y, mid.y))
		away.y = 0.0
		var from := Vector3(mid.x, lv.y, mid.y) + away.normalized() * minf(away.length() + 1.0, 3.2)
		_look(b, from + Vector3(0, lift + eye, 0), Vector3(mid.x, lv.y + 1.0 + lift, mid.y))
		await _shot("interieur_%s_escalier_%d" % [tag, fl.from_level])
		var up: BastideInteriorLayout.Level = il.levels[fl.from_level + 1]
		var arrive := fl.at(fl.run() + 0.3, fl.width * 0.5)
		var c2 := Vector3(g.x, up.y, g.y)
		_look(b, Vector3(arrive.x, up.y + eye + lift, arrive.y), c2 + Vector3(0, lift + 1.2, 0) + (c2 - Vector3(arrive.x, up.y, arrive.y)) * 0.6)
		for i in 10:
			b.update_interior(b.to_global(Vector3(arrive.x, up.y + lift, arrive.y)), 0.2)
		await _shot("interieur_%s_niveau_%d" % [tag, up.index])
	# Vue de l'étage vers la trémie et son garde-corps.
	var last: BastideInteriorLayout.Flight = il.flights[il.flights.size() - 1]
	var top: BastideInteriorLayout.Level = il.levels[last.from_level + 1]
	var rail := last.at(last.run() * 0.4, last.width)
	var from2 := Vector3(rail.x, top.y, rail.y) + Vector3(last.side.x, 0, last.side.y) * 2.2
	_look(b, from2 + Vector3(0, lift + eye, 0), Vector3(rail.x, top.y + lift, rail.y))
	await _shot("interieur_%s_tremie" % tag)
	b.set_interior_active(false)


func _look(b: BastideBuilding, from_local: Vector3, at_local: Vector3) -> void:
	var f := b.to_global(from_local)
	var a := b.to_global(at_local)
	cam.fov = 70.0
	cam.global_transform = Transform3D(Basis.IDENTITY, f).looking_at(a, Vector3.UP)


func _all_built(n: int) -> bool:
	if site.ids().size() < n:
		return false
	for id in site.ids():
		var node := site.node_of(id)
		if node == null or node.last_stats.is_empty():
			return false
	return true


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await _frames(4)
	if DisplayServer.get_name() == "headless":
		return
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("capture ", shot_name)
