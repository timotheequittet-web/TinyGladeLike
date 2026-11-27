extends SceneTree
## Captures pour comparer les niveaux de détail et les réglages graphiques
## (outil de développement) : trois distances de caméra, pour chaque niveau demandé.
##   godot --path . -s tools/lod_shots.gd -- <dossier_sortie> [Bas,Moyen,Haut,Ultra] [prefixe]

var out_dir := "/tmp/shots"
var levels := ["Haut"]
var prefix := ""
var scene: Node
var cam: Camera3D
var site: BastideBuildSite

const VIEWS := {
	"proche": [Vector3(2, 0, 4), 14.0, 25.0],
	"moyen": [Vector3(0, 0, 0), 40.0, 25.0],
	"dezoom": [Vector3(0, 0, -6), 90.0, 25.0],
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		levels = Array(args[1].split(","))
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
	# Sans typage : l'outil sert aussi sur d'anciennes versions sans réglages graphiques.
	var gfx: Node = scene.get_node_or_null("Graphismes")
	if gfx:
		gfx.set("auto_apply", false)
	# Le rendu logiciel fait des taches avec le glow : on le coupe pour les captures.
	var env := (scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	for lv: String in levels:
		if gfx:
			gfx.call("apply", ["Bas", "Moyen", "Haut", "Ultra"].find(lv), false)
		env.glow_enabled = false
		# Le flou de profondeur suit la caméra avec retard : il brouillerait les comparaisons.
		if cam.attributes is CameraAttributesPractical:
			(cam.attributes as CameraAttributesPractical).dof_blur_far_enabled = false
		for v: String in VIEWS:
			var p: Array = VIEWS[v]
			cam.call("glide_to", p[0], p[1], p[2], 0.01)
			for i in 12:
				await process_frame
			var img := root.get_viewport().get_texture().get_image()
			var path := out_dir.path_join("%s%s_%s.png" % [prefix, v, lv.to_lower()])
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
