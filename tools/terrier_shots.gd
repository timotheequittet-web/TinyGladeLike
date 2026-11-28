extends SceneTree
## Captures d'un hameau de maisons-terriers (outil de développement) : vue de chaque
## porte, bord de chemin et vue d'ensemble.
##   godot --path . -s tools/terrier_shots.gd -- <dossier_sortie> [heures séparées par des virgules]

const TERRIER := "res://addons/bastide/styles/presets/burrow_hill.tres"

var out_dir := "/tmp/shots"
var hours := [15.0]
var only := []   # numéros des vues à capturer (vide : toutes)
var inside := false   # « dedans » : captures de l'intérieur du premier terrier
var scene: Node
var cam: Camera3D
var site: BastideBuildSite


static func village() -> Array:
	var t := TERRIER
	return [
		{"kind": "house", "seed": 12, "style": t, "door": 2, "points": [[-11, 0, -9], [-3, 0, -9], [-3, 0, -3], [-11, 0, -3]]},
		{"kind": "house", "seed": 31, "style": t, "door": 2, "points": [[3, 0, -13], [11, 0, -13], [11, 0, -6.5], [3, 0, -6.5]]},
		{"kind": "house", "seed": 7, "style": t, "door": 2, "points": [[14, 0, -4], [31, 0, -4], [31, 0, 3], [14, 0, 3]]},
		{"kind": "house", "seed": 44, "style": t, "door": 1, "points": [[-24, 0, 3], [-17, 0, 3], [-17, 0, 9], [-24, 0, 9]]},
		{"kind": "path", "seed": 5, "style": t, "points": [[-1, 0, 26], [0.5, 0, 16], [-1.0, 0, 8], [-4.5, 0, 3.2], [-7, 0, 0.4]]},
		{"kind": "path", "seed": 6, "style": t, "points": [[-1.0, 0, 8], [3.5, 0, 2.5], [6.8, 0, -2.6]]},
		{"kind": "path", "seed": 8, "style": t, "points": [[0.5, 0, 16], [8, 0, 12], [15, 0, 9], [18.5, 0, 6.4]]},
		{"kind": "path", "seed": 9, "style": t, "points": [[-1.0, 0, 8], [-8, 0, 8.5], [-13.5, 0, 6.5]]},
		{"kind": "wall", "seed": 4, "height": 1.0, "style": t, "closed": false,
			"points": [[-16, 0, 13], [-10, 0, 15], [-4, 0, 15.5]]},
		{"kind": "fence", "seed": 9, "variant": 1, "style": t, "closed": false,
			"points": [[3, 0, 18], [9, 0, 16.5], [15, 0, 13.5], [19, 0, 10.5]]},
		{"kind": "fence", "seed": 11, "variant": 1, "style": t, "closed": false,
			"points": [[-3.5, 0, 22], [-4.2, 0, 17.5]]},
		{"kind": "plants", "seed": 21, "style": t, "points": [[-14, 0, -6]]},
		{"kind": "plants", "seed": 27, "style": t, "points": [[1.5, 0, -2.0]]},
		{"kind": "plants", "seed": 34, "style": t, "points": [[12.5, 0, 9.5]]},
		{"kind": "plants", "seed": 40, "style": t, "points": [[-9, 0, 11]]},
		{"kind": "plants", "seed": 22, "style": t, "points": [[5, 0, 9.5], [9, 0, 7.5], [12, 0, 5.5]]},
		{"kind": "farm", "seed": 58, "style": t, "closed": true, "farm_kind": 0,
			"points": [[-24.5, 0, 16.5], [-14.5, 0, 16.0], [-14, 0, 24.0], [-24.0, 0, 24.5]]},
	]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		hours = []
		for h in args[1].split(","):
			hours.append(float(h))
	if args.size() > 2:
		if args[2] == "dedans":
			inside = true
		else:
			for v in args[2].split(","):
				only.append(int(v))
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
	# Le hameau de départ, puis on le remplace par les terriers.
	for i in 60:
		await process_frame
	site.clear(false)
	site.garden_style = load(TERRIER)
	var data := village()
	for i in data.size():
		data[i]["id"] = i + 1
	site.from_data(data, false)
	var t0 := Time.get_ticks_msec()
	while not _all_built(data.size()) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	for i in 60:
		await process_frame
	cam.set_process(false)
	if inside:
		await _inside()
		quit()
		return
	var views := _views()
	for h: float in hours:
		day.hour = h
		day.set("_sky_hour", -100.0)
		for i in 6:
			await process_frame
		env.glow_enabled = false
		var k := 0
		for v: Array in views:
			if not only.is_empty() and not only.has(k):
				k += 1
				continue
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
	# L'interface, avec le sélecteur de styles sur le terrier.
	var ui := scene.get_node("Interface") as CanvasLayer
	ui.visible = true
	scene.call("_pick_style", load(TERRIER))
	var v: Array = views[views.size() - 2]
	cam.look_at_from_position(v[0], v[1])
	for i in 40:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("interface.png"))
	print("capture interface")
	quit()


func _views() -> Array:
	var out: Array = []
	var field := BastideTerrain.field_for(cam)
	var gh := func(p: Vector3) -> float:
		return field.height(p.x, p.z) if field else 0.0
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
		var target := Vector3(p.x, lift + p.y + 1.4, p.z)
		var eye := p + o * 8.0 + side * 3.5
		eye.y = gh.call(eye) + 2.4
		out.append([eye, target, 60.0])
	# Vue d'ensemble plongeante, comme une carte postale du hameau.
	var c := Vector3(0, 0, 0)
	var e := Vector3(10, 0, 34)
	out.append([e + Vector3(0, gh.call(e) + 19.0, 0), c, 52.0])
	var e2 := Vector3(-30, 0, 22)
	out.append([e2 + Vector3(0, gh.call(e2) + 9.0, 0), Vector3(-6, 1, -2), 55.0])
	return out


func _all_built(n: int) -> bool:
	if site.ids().size() < n:
		return false
	for id in site.ids():
		var node := site.node_of(id)
		if node == null or node.last_stats.is_empty():
			return false
	return site.garden != null and not site.garden.last_stats.is_empty()


## Entre dans le premier terrier : porte ouverte de dehors, puis la pièce de dedans.
func _inside() -> void:
	var b: BastideBuilding = null
	for id in site.ids():
		if site.node_of(id) is BastideBuilding:
			b = site.node_of(id)
			break
	b.set_interior_active(true)
	var t0 := Time.get_ticks_msec()
	while not b.is_interior_ready() and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	var il := b.interior_layout()
	var d: Dictionary = b.describe()["doors"][0]
	var p: Vector3 = d["pos"]
	var o: Vector3 = d["out"]
	var xf := b.global_transform
	var lift: float = b.last_stats.get("terrain_lift", 0.0)
	var door := xf * (p + Vector3(0, lift, 0))
	var outw := -(xf.basis * o).normalized()
	var c2 := BastidePolygon.centroid(il.inner)
	var center := xf * Vector3(c2.x, p.y + lift + 1.2, c2.y)
	var deep := (center - door)
	deep.y = 0.0
	deep = deep.normalized()
	var shots := [
		[door + outw * 4.5 + Vector3(0, 1.5, 0), door + Vector3(0, 1.0, 0), "dedans_porte"],
		[door - outw * 0.5 + Vector3(0, 1.55, 0), center + deep * 3.0 + Vector3(0, -0.4, 0), "dedans_fond"],
		[center + deep * 1.4 + Vector3(0, 0.35, 0), door + Vector3(0, 1.0, 0), "dedans_entree"],
	]
	for s in shots:
		cam.fov = 70.0
		cam.look_at_from_position(s[0], s[1])
		for i in 30:
			b.update_interior(s[0], 0.1)
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(s[2] + ".png"))
		print("capture ", s[2])
