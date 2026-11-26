extends SceneTree
## Génère demos/04_runtime/runtime_demo.tscn (outil de développement).
##   godot --headless --path . -s tools/build_runtime_demo.gd
## Construction en jeu : caméra douce, chantier, outil de tracé, décor et sons.

const OUT := "res://demos/04_runtime/runtime_demo.tscn"


func _init() -> void:
	var root := Node3D.new()
	root.name = "RuntimeDemo"
	root.set_script(load("res://demos/04_runtime/runtime_demo.gd"))

	# --- Lumière dorée de fin de journée à la campagne ---
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.46, 0.6, 0.8)
	sky_mat.sky_horizon_color = Color(1.0, 0.8, 0.6)
	sky_mat.sky_curve = 0.1
	sky_mat.ground_horizon_color = Color(0.92, 0.76, 0.56)
	sky_mat.ground_bottom_color = Color(0.32, 0.33, 0.24)
	sky_mat.sun_angle_max = 32.0
	sky_mat.sun_curve = 0.12
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.08
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.0
	env.ssil_enabled = true
	env.ssil_intensity = 0.6
	# Halo doux autour des zones claires (ciel, pointes d'herbe au soleil).
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Brume dorée au loin, et brume volumétrique où le soleil trace ses rayons.
	env.fog_enabled = true
	env.fog_light_color = Color(1.0, 0.82, 0.62)
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.45
	env.fog_sun_scatter = 0.45
	env.fog_aerial_perspective = 0.5
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0025
	env.volumetric_fog_albedo = Color(1.0, 0.88, 0.74)
	env.volumetric_fog_anisotropy = 0.65
	env.volumetric_fog_length = 110.0
	env.volumetric_fog_sky_affect = 0.15
	env.volumetric_fog_ambient_inject = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_add(root, we)

	var sun := DirectionalLight3D.new()
	sun.name = "Soleil"
	sun.light_color = Color(1.0, 0.78, 0.55)
	sun.light_energy = 1.9
	sun.light_volumetric_fog_energy = 1.6
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.directional_shadow_max_distance = 150.0
	# Soleil bas derrière le hameau (vu depuis la caméra de départ) : contre-jour doré.
	sun.rotation_degrees = Vector3(-17, 152, 0)
	_add(root, sun)

	# --- Caméra douce ---
	var cam := BastideOrbitCamera.new()
	cam.name = "Camera"
	cam.fov = 50
	# Léger flou au loin ; la distance suit la caméra (voir runtime_demo.gd).
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 80.0
	attrs.dof_blur_far_transition = 50.0
	attrs.dof_blur_amount = 0.06
	cam.attributes = attrs
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
	# Le relief (collision du sol sur la couche 2) : clairière vallonnée, collines autour,
	# l'étang sur un replat.
	var terrain := BastideTerrain.new()
	terrain.name = "Terrain"
	terrain.flat_zones = [Vector4(-27, 16, 10.5, 7.0)] as Array[Vector4]
	root.add_child(terrain)
	terrain.owner = root
	root.move_child(terrain, 0)

	# --- Construction ---
	var site := BastideBuildSite.new()
	site.name = "Chantier"
	_add(root, site)
	var tool := BastideBuildTool.new()
	tool.name = "Outil"
	_add(root, tool)
	tool.site = site
	tool.camera = cam

	# --- Herbe haute qui suit la caméra et s'écarte des constructions ---
	var grass := BastideGrass.new()
	grass.name = "Herbe"
	_add(root, grass)
	grass.site = site
	grass.camera = cam

	# --- Vie du hameau : fumées, lanternes, oiseaux, papillons ---
	var life := BastideLife.new()
	life.name = "Vie"
	_add(root, life)
	life.site = site
	life.camera = cam

	# --- Réglages graphiques (F3 compteur, F4 niveau) ---
	var gfx := BastideGraphics.new()
	gfx.name = "Graphismes"
	_add(root, gfx)
	gfx.world_environment = we
	gfx.sun = sun
	gfx.grass = grass
	gfx.camera = cam

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
