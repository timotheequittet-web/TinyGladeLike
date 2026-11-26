extends SceneTree
## Mesure de ce que coûte chaque couche du rendu (outil de développement).
## Pour trois distances de caméra, on coupe une couche à la fois (herbe, forêts,
## décor, vie, effets…) et on note triangles, appels de dessin, objets et temps.
##   godot --path . -s tools/perf_probe.gd -- <fichier_sortie.csv>
## Les triangles et appels de dessin ne dépendent pas de la carte graphique ; les
## temps, eux, n'ont de sens que relativement entre deux lignes d'une même machine.

var out_file := "/tmp/perf.csv"
var scene: Node
var cam: Camera3D
var site: BastideBuildSite
var env: Environment
var sun: DirectionalLight3D
var frames := 8
var lines: PackedStringArray = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_file = args[0]
	if args.size() > 1:
		frames = int(args[1])
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	scene = (load("res://demos/04_runtime/runtime_demo.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	cam = scene.get_node("Camera")
	site = scene.get_node("Chantier")
	env = (scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	sun = scene.get_node("Soleil")
	(scene.get_node("Interface") as CanvasLayer).visible = false
	var gfx := scene.get_node_or_null("Graphismes") as BastideGraphics
	if gfx:
		gfx.auto_apply = false
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	await _frames(30)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	lines.append("vue;sans;triangles_vus;triangles_ombres;appels_vus;appels_ombres;objets_vus;ms_image;ms_cpu_rendu;ms_gpu")
	var views := {
		"proche": [Vector3(2, 0, 4), 14.0, 25.0],
		"moyen": [Vector3(0, 0, 0), 40.0, 25.0],
		"dezoom": [Vector3(0, 0, -6), 90.0, 25.0],
	}
	for v: String in views:
		var p: Array = views[v]
		cam.call("glide_to", p[0], p[1], p[2], 0.01)
		await _frames(20)
		var layers := ["rien", "herbe", "forets", "decor", "vie", "structures", "terrain",
				"ombres", "brouillard_vol", "ssao", "ssil", "glow", "flou", "tout_effet", "tout"]
		if gfx and OS.get_cmdline_user_args().has("niveaux"):
			layers = ["rien", "herbe"]
			for q in BastideGraphics.PRESETS.size():
				gfx.apply(q, false)
				await _frames(8)
				lines.append(await _measure(v, "niveau_" + BastideGraphics.NAMES[q]))
				print(lines[-1])
			gfx.apply(BastideGraphics.Preset.HAUT, false)
			await _frames(8)
		for layer in layers:
			_toggle(layer, false)
			await _frames(6)
			lines.append(await _measure(v, layer))
			print(lines[-1])
			_toggle(layer, true)
	var f := FileAccess.open(out_file, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()


func _nodes(layer: String) -> Array:
	var out := []
	match layer:
		"herbe": out.append(scene.get_node("Herbe"))
		"decor": out.append(scene.get_node("Decor"))
		"vie": out.append(scene.get_node("Vie"))
		"terrain": out.append(scene.get_node("Terrain"))
		"forets", "structures":
			for id in site.ids():
				var forest := String(site.get_record(id).get("kind", "")) == "forest"
				if forest == (layer == "forets"):
					out.append(site.node_of(id))
			if layer == "structures" and site.garden:
				out.append(site.garden)
		"tout":
			for l in ["herbe", "forets", "decor", "vie", "structures", "terrain"]:
				out.append_array(_nodes(l))
	return out


func _toggle(layer: String, on: bool) -> void:
	for n: Variant in _nodes(layer):
		if n is Node3D:
			(n as Node3D).visible = on
	match layer:
		"ombres": sun.shadow_enabled = on
		"brouillard_vol": env.volumetric_fog_enabled = on
		"ssao": env.ssao_enabled = on
		"ssil": env.ssil_enabled = on
		"glow": env.glow_enabled = on
		"flou": _dof(on)
		"tout_effet", "tout":
			sun.shadow_enabled = on
			env.volumetric_fog_enabled = on
			env.ssao_enabled = on
			env.ssil_enabled = on
			env.glow_enabled = on
			_dof(on)


func _dof(on: bool) -> void:
	if cam.attributes is CameraAttributesPractical:
		(cam.attributes as CameraAttributesPractical).dof_blur_far_enabled = on


func _measure(view: String, layer: String) -> String:
	var vp := root.get_viewport_rid()
	var tv := 0.0; var ts := 0.0; var dv := 0.0; var ds := 0.0; var ov := 0.0
	var ms := 0.0; var cpu := 0.0; var gpu := 0.0
	for i in frames:
		var t := Time.get_ticks_usec()
		await process_frame
		ms += (Time.get_ticks_usec() - t) / 1000.0
		tv += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		ts += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		dv += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		ds += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		ov += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var n := float(frames)
	return "%s;%s;%d;%d;%d;%d;%d;%.1f;%.1f;%.1f" % [view, layer, tv / n, ts / n, dv / n, ds / n, ov / n, ms / n, cpu / n, gpu / n]


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _all_built(n: int) -> bool:
	if site.ids().size() < n:
		return false
	for id in site.ids():
		var node := site.node_of(id)
		if node == null or node.last_stats.is_empty():
			return false
	return site.garden != null and not site.garden.last_stats.is_empty()
