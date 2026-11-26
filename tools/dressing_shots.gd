extends SceneTree
## Captures de l'habillage des maisons (outil de développement) : pour quelques
## maisons du hameau, une vue de leur porte à hauteur de promeneur, de trois quarts.
##   godot --path . -s tools/dressing_shots.gd -- <dossier_sortie> [prefixe] [Haut|Moyen…]

var out_dir := "/tmp/shots"
var prefix := "habillage_"
var level := "Haut"
var scene: Node
var cam: Camera3D
var site: BastideBuildSite


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		prefix = args[1]
	if args.size() > 2:
		level = args[2]
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
		gfx.call("apply", ["Bas", "Moyen", "Haut", "Ultra"].find(level), false)
	var env := (scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	env.glow_enabled = false
	if cam.attributes is CameraAttributesPractical:
		(cam.attributes as CameraAttributesPractical).dof_blur_far_enabled = false
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	for i in 40:
		await process_frame
	var dressing := scene.get_node_or_null("Habillage")
	print("maisons habillées : ", dressing.get_child_count() if dressing else -1)
	cam.set_process(false)
	var shots := 0
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
		var out: Vector3 = door["out"]
		var side := Vector3(-out.z, 0, out.x)
		var field := BastideTerrain.field_for(cam)
		var gy := field.height(p.x, p.z) if field else 0.0
		var lift: float = node.last_stats.get("terrain_lift", 0.0)
		var target := Vector3(p.x, lift + p.y + 2.0, p.z)
		var eye := p + out * 6.5 + side * 2.5
		eye.y = (field.height(eye.x, eye.z) if field else 0.0) + 1.7
		cam.fov = 62
		cam.look_at_from_position(eye, target)
		for i in 10:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path := out_dir.path_join("%s%d.png" % [prefix, shots])
		img.save_png(path)
		print("capture ", path, " (sol ", gy, ")")
		shots += 1
		if shots >= 4:
			break
	quit()


func _all_built(n: int) -> bool:
	if site.ids().size() < n:
		return false
	for id in site.ids():
		var node := site.node_of(id)
		if node == null or node.last_stats.is_empty():
			return false
	return site.garden != null and not site.garden.last_stats.is_empty()
