extends SceneTree
## Banc d'essai des arbres et plantes du kit nature (outil de développement) : une
## rangée d'arbres sur un pré, en lumière de fin de journée, vue de face et d'en haut.
##   godot --path . -s tools/tree_preview.gd -- <dossier_sortie> [essences] [prefixe]
## essences : liste séparée par des virgules, « essence:variante:échelle »
## (ex. cedre:0:1.8,cedre:1:1.8) ; « plant:hydrangea_blue:1.5 » pour une plante.

var out_dir := "/tmp/shots"
var prefix := "arbres_"
var items := ["cedre:0:1.8", "cedre:1:1.8", "cedre:2:1.6", "cedre:3:1.6", "matsu:0:1.2", "chene:0:1.5"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1 and args[1] != "":
		items = Array(args[1].split(","))
	if args.size() > 2:
		prefix = args[2]
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.42, 0.56, 0.78)
	sm.sky_horizon_color = Color(0.92, 0.82, 0.68)
	sm.ground_horizon_color = Color(0.7, 0.62, 0.5)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -140, 0)
	sun.light_color = Color(1.0, 0.88, 0.72)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.42, 0.18)
	gm.roughness = 1.0
	plane.material = gm
	ground.mesh = plane
	world.add_child(ground)
	var spacing := 11.0
	var x0 := -spacing * (items.size() - 1) * 0.5
	var top := 0.0
	for i in items.size():
		var parts: PackedStringArray = String(items[i]).split(":")
		var pos := Vector3(x0 + i * spacing, 0, 0)
		if parts[0] == "plant":
			var pl := BastideKitNature.plant(parts[1])
			var sc := float(parts[2]) if parts.size() > 2 else 1.0
			_add(world, pl["mesh"], pl["mat"], Transform3D(Basis.from_scale(Vector3.ONE * sc), pos), false)
			if pl.get("trunk") != null:
				_add(world, pl["trunk"], BastideKitNature.trunk_material(), Transform3D(Basis.from_scale(Vector3.ONE * sc), pos), false)
			continue
		var tr := BastideKitNature.tree(parts[0], int(parts[1]), float(parts[2]))
		var xf := Transform3D(Basis(Vector3.UP, i * 1.3), pos)
		_add(world, tr["trunk"], BastideKitNature.trunk_material(), xf, false)
		_add(world, tr["crown"], tr["crown_mat"], xf, false)
		_add(world, tr["shadow"], BastideKitNature.trunk_material(), xf, true)
		top = maxf(top, float(tr["height"]))
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 55
	var w := spacing * items.size()
	var shots := {
		"face": [Vector3(0, 1.7, w * 0.62 + 6.0), Vector3(0, top * 0.42, 0)],
		"haut": [Vector3(0, top * 1.9 + 8.0, w * 0.55 + 8.0), Vector3(0, top * 0.25, 0)],
		"pres": [Vector3(x0 + 4.0, 1.7, 9.0), Vector3(x0, top * 0.35, 0)],
	}
	for k: String in shots:
		var s: Array = shots[k]
		cam.look_at_from_position(s[0], s[1])
		for f in 8:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path := out_dir.path_join("%s%s.png" % [prefix, k])
		img.save_png(path)
		print("capture ", path)
	quit()


func _add(parent: Node, mesh: Mesh, mat: Material, xf: Transform3D, shadow_only: bool) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if shadow_only \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
