extends SceneTree
## Génère demos/04_runtime/runtime_demo.tscn (outil de développement).
##   godot --headless --path . -s tools/build_runtime_demo.gd
## Construction en jeu : caméra douce, chantier, outil de tracé, décor et sons.

const OUT := "res://demos/04_runtime/runtime_demo.tscn"


func _init() -> void:
	var root := Node3D.new()
	root.name = "RuntimeDemo"
	root.set_script(load("res://demos/04_runtime/runtime_demo.gd"))

	# --- Lumière de fin d'après-midi à la campagne ---
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.6, 0.84)
	sky_mat.sky_horizon_color = Color(0.93, 0.86, 0.78)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.86, 0.8, 0.7)
	sky_mat.ground_bottom_color = Color(0.35, 0.38, 0.3)
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.08
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.ssil_enabled = true
	env.ssil_intensity = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.9, 0.84, 0.76)
	env.fog_density = 0.003
	env.fog_sky_affect = 0.35
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.03
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_add(root, we)

	var sun := DirectionalLight3D.new()
	sun.name = "Soleil"
	sun.light_color = Color(1.0, 0.87, 0.7)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_max_distance = 150.0
	sun.rotation_degrees = Vector3(-31, -38, 0)
	_add(root, sun)

	# --- Caméra douce ---
	var cam := BastideOrbitCamera.new()
	cam.name = "Camera"
	cam.fov = 50
	cam.target = Vector3(0, 0, 0)
	cam.distance = 70.0
	cam.yaw_degrees = -25.0
	cam.max_distance = 75.0
	cam.bounds_radius = 45.0
	_add(root, cam)

	# --- Décor (prairie, arbres, étang, pétales) : collision du sol sur la couche 2 ---
	var decor := Node3D.new()
	decor.name = "Decor"
	decor.set_script(load("res://demos/04_runtime/scenery.gd"))
	_add(root, decor)
	decor.set("follow", cam)
	var ground := StaticBody3D.new()
	ground.name = "Sol"
	ground.collision_layer = 2
	_add(root, ground)
	var gs := CollisionShape3D.new()
	gs.name = "Shape"
	gs.shape = WorldBoundaryShape3D.new()
	_add(ground, gs, root)

	# --- Construction ---
	var site := BastideBuildSite.new()
	site.name = "Chantier"
	_add(root, site)
	var tool := BastideBuildTool.new()
	tool.name = "Outil"
	_add(root, tool)
	tool.site = site
	tool.camera = cam

	var amb := Node.new()
	amb.name = "Ambiance"
	amb.set_script(load("res://demos/04_runtime/ambience.gd"))
	_add(root, amb)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("Scène écrite : ", OUT, " (", error_string(err), ")")
	root.free()
	quit(0 if err == OK else 1)


func _add(parent: Node, child: Node, owner: Node = null) -> void:
	parent.add_child(child)
	child.owner = owner if owner else parent
