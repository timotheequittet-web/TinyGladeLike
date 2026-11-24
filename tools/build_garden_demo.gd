extends SceneTree
## Génère demos/05_garden/garden_demo.tscn (outil de développement).
##   godot --headless --path . -s tools/build_garden_demo.gd
## Jardin japonais construit avec les nœuds de l'éditeur : maisons, chemins, torii,
## clôtures, massifs, arbres et jardin automatique. Tout est modifiable à la main.

const OUT := "res://demos/05_garden/garden_demo.tscn"
const JAPANESE := "res://addons/bastide/styles/presets/japanese_wood.tres"


func _init() -> void:
	var root := Node3D.new()
	root.name = "JardinDemo"
	var st := load(JAPANESE)

	# --- Lumière dorée de fin d'après-midi ---
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.6, 0.84)
	sky_mat.sky_horizon_color = Color(0.93, 0.86, 0.78)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.86, 0.8, 0.7)
	sky_mat.ground_bottom_color = Color(0.35, 0.38, 0.3)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.9, 0.84, 0.76)
	env.fog_density = 0.004
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_add(root, we)
	var sun := DirectionalLight3D.new()
	sun.name = "Soleil"
	sun.light_color = Color(1.0, 0.87, 0.7)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 120.0
	sun.rotation_degrees = Vector3(-31, -38, 0)
	_add(root, sun)

	# --- Sol ---
	var ground := StaticBody3D.new()
	ground.name = "Sol"
	_add(root, ground)
	var gs := CollisionShape3D.new()
	gs.name = "Shape"
	gs.shape = WorldBoundaryShape3D.new()
	_add(ground, gs, root)
	var mi := MeshInstance3D.new()
	mi.name = "Prairie"
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://demos/04_runtime/ground.gdshader")
	plane.material = mat
	mi.mesh = plane
	_add(ground, mi, root)

	# --- Structures : toutes dans le même dossier, le jardin les voit toutes ---
	var village := Node3D.new()
	village.name = "Hameau"
	_add(root, village)
	_building(village, root, st, "Maison", 12, Vector3(0, 0, -4),
			[Vector2(-5, -3), Vector2(5, -3), Vector2(5, 3), Vector2(-5, 3)], 2, 2)
	_building(village, root, st, "Annexe", 31, Vector3(10, 0, 2),
			[Vector2(-3, -2.5), Vector2(3, -2.5), Vector2(3, 2.5), Vector2(-3, 2.5)], 1, 3)
	_path(village, root, st, "CheminPrincipal", 5, [Vector3(1, 0, 22), Vector3(1, 0, 18), Vector3(-1, 0, 10), Vector3(0.2, 0, 2.2)])
	_path(village, root, st, "CheminAnnexe", 6, [Vector3(-0.6, 0, 8.5), Vector3(3, 0, 5.5), Vector3(5.2, 0, 2.6)])
	var torii := BastideTorii.new()
	torii.name = "Torii"
	torii.position = Vector3(-0.25, 0, 13)
	var tc := Curve3D.new()
	tc.add_point(Vector3(-1.5, 0, 0.37))
	tc.add_point(Vector3(1.5, 0, -0.37))
	torii.curve = tc
	torii.style = st
	torii.seed = 2
	_add(village, torii, root)
	_fence(village, root, st, "ClotureBambou", 3, BastideFence.Variant.BAMBOO,
			[Vector3(4, 0, -7), Vector3(4.3, 0, 1), Vector3(3.8, 0, 10)])
	_fence(village, root, st, "MuretPierres", 9, BastideFence.Variant.STONE,
			[Vector3(-8.5, 0, -6), Vector3(-10, 0, 4), Vector3(-9, 0, 12), Vector3(-5, 0, 16)])
	_planting(village, root, st, "Massif", 21, [Vector3(-6.5, 0, 9), Vector3(-5, 0, 11.5), Vector3(-3, 0, 13)])
	_planting(village, root, st, "Erable", 14, [Vector3(6.5, 0, 10)])
	_planting(village, root, st, "Pin", 3, [Vector3(-7, 0, 1.5)])
	_planting(village, root, st, "Cerisier", 8, [Vector3(13, 0, -6)])
	var garden := BastideGarden.new()
	garden.name = "Jardin"
	garden.style = st
	garden.seed = 7
	_add(village, garden, root)

	# --- Caméra et aide ---
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.set_script(load("res://demos/common/free_camera.gd"))
	cam.position = Vector3(2, 11, 30)
	cam.rotation_degrees = Vector3(-18, 0, 0)
	cam.fov = 55
	_add(root, cam)
	var ui := CanvasLayer.new()
	ui.name = "Interface"
	_add(root, ui)
	var help := Label.new()
	help.name = "Aide"
	help.position = Vector2(18, 14)
	help.text = "Jardin japonais (étape 5) : ouvre cette scène dans l'éditeur et déplace les points des chemins,\nclôtures et massifs. Clic droit + souris : regarder   ZQSD : bouger   A/E : bas/haut   Maj : vite"
	_add(ui, help, root)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://demos/05_garden"))
		err = ResourceSaver.save(packed, OUT)
	print("Scène écrite : ", OUT, " (", error_string(err), ")")
	root.free()
	quit(0 if err == OK else 1)


func _add(parent: Node, child: Node, owner: Node = null) -> void:
	parent.add_child(child)
	child.owner = owner if owner else parent


func _building(parent: Node, root: Node, st: Resource, b_name: String, b_seed: int, pos: Vector3, corners: Array,
		floors: int, door: int) -> void:
	var b := BastideBuilding.new()
	b.name = b_name
	b.position = pos
	var c := Curve3D.new()
	for p: Vector2 in corners:
		c.add_point(Vector3(p.x, 0, p.y))
	c.closed = true
	b.curve = c
	b.seed = b_seed
	b.floors = floors
	b.door_facade = door
	b.style = st
	_add(parent, b, root)


func _curve(points: Array) -> Curve3D:
	var c := Curve3D.new()
	for p: Vector3 in points:
		c.add_point(p)
	return c


func _path(parent: Node, root: Node, st: Resource, p_name: String, p_seed: int, points: Array) -> void:
	var p := BastidePath.new()
	p.name = p_name
	p.curve = _curve(points)
	p.seed = p_seed
	p.style = st
	_add(parent, p, root)


func _fence(parent: Node, root: Node, st: Resource, f_name: String, f_seed: int, variant: int, points: Array) -> void:
	var f := BastideFence.new()
	f.name = f_name
	f.curve = _curve(points)
	f.seed = f_seed
	f.variant = variant
	f.style = st
	_add(parent, f, root)


func _planting(parent: Node, root: Node, st: Resource, p_name: String, p_seed: int, points: Array) -> void:
	var p := BastidePlanting.new()
	p.name = p_name
	p.curve = _curve(points)
	p.seed = p_seed
	p.style = st
	_add(parent, p, root)
