extends SceneTree
## Génère demos/06_terraces/terrace_demo.tscn (outil de développement).
##   godot --headless --path . -s tools/build_terrace_demo.gd
## Étape 6 avec les nœuds de l'éditeur : engawa contre les maisons, terrasse isolée,
## grand muret qui s'ouvre en portail là où les chemins le traversent (japonais et
## médiéval). Tout est modifiable à la main.

const OUT := "res://demos/06_terraces/terrace_demo.tscn"
const MEDIEVAL := "res://addons/bastide/styles/presets/medieval_stone.tres"
const JAPANESE := "res://addons/bastide/styles/presets/japanese_wood.tres"


func _init() -> void:
	var root := Node3D.new()
	root.name = "TerrassesDemo"
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

	# --- Structures : toutes dans le même dossier, elles se voient toutes ---
	var village := Node3D.new()
	village.name = "Hameau"
	_add(root, village)
	_building(village, root, st, "Maison", 12, Vector3(0, 0, -4),
			[Vector2(-5, -3), Vector2(5, -3), Vector2(5, 3), Vector2(-5, 3)], 2, 2)
	_building(village, root, st, "Annexe", 31, Vector3(13, 0, -3),
			[Vector2(-3, -2.5), Vector2(3, -2.5), Vector2(3, 2.5), Vector2(-3, 2.5)], 1, 2)
	# Engawa : sur la façade est de la maison, et en façade, à gauche de la porte.
	_terrace(village, root, st, "EngawaEst", 4, [Vector3(5.06, 0, -6.5), Vector3(6.56, 0, -6.5), Vector3(6.56, 0, -1.5), Vector3(5.06, 0, -1.5)])
	_terrace(village, root, st, "EngawaFacade", 5, [Vector3(-4.7, 0, -0.94), Vector3(-1.4, 0, -0.94), Vector3(-1.4, 0, 0.56), Vector3(-4.7, 0, 0.56)])
	# Terrasse isolée dans le pré, et son chemin.
	_terrace(village, root, st, "Terrasse", 9, [Vector3(9, 0, 11), Vector3(13, 0, 11), Vector3(13, 0, 14), Vector3(9, 0, 14)], 3)
	# Le grand muret : les chemins le traversent, il s'ouvre en portails.
	var wall := BastideWall.new()
	wall.name = "Muret"
	wall.curve = _curve([Vector3(-12, 0, -2), Vector3(-12.5, 0, 4), Vector3(-6, 0, 6.5), Vector3(4, 0, 6.5), Vector3(9, 0, 5.5), Vector3(18, 0, 4)])
	wall.seed = 4
	wall.height = 1.9
	wall.style = st
	_add(village, wall, root)
	_path(village, root, st, "CheminPrincipal", 5, [Vector3(1, 0, 24), Vector3(1, 0, 18), Vector3(-1, 0, 10), Vector3(0, 0, 3.5)])
	_path(village, root, st, "CheminTerrasse", 6, [Vector3(0.6, 0, 16), Vector3(5, 0, 15), Vector3(8.2, 0, 12.6)])
	_path(village, root, st, "CheminAnnexe", 7, [Vector3(0, 0, 3.5), Vector3(6, 0, 3), Vector3(11, 0, 1.5), Vector3(13, 0, 0.6)])
	var torii := BastideTorii.new()
	torii.name = "Torii"
	torii.position = Vector3(0, 0, 19)
	var tc := Curve3D.new()
	tc.add_point(Vector3(-1.6, 0, 0))
	tc.add_point(Vector3(1.6, 0, 0))
	torii.curve = tc
	torii.style = st
	torii.seed = 2
	_add(village, torii, root)
	_planting(village, root, st, "Erable", 14, [Vector3(-8, 0, 9.5)])
	_planting(village, root, st, "Cerisier", 8, [Vector3(16, 0, 9)])
	_planting(village, root, st, "Massif", 21, [Vector3(-7, 0, 13), Vector3(-4.5, 0, 15), Vector3(-2.5, 0, 16.5)])
	# Le même muret en style médiéval, à l'ouest : piliers et arc de pierre.
	var med_wall := BastideWall.new()
	med_wall.name = "MuretMedieval"
	med_wall.curve = _curve([Vector3(-40, 0, 2), Vector3(-24, 0, 2)])
	med_wall.seed = 6
	med_wall.height = 2.4
	med_wall.style = load(MEDIEVAL)
	_add(village, med_wall, root)
	_path(village, root, load(MEDIEVAL), "CheminMedieval", 8, [Vector3(-31, 0, -8), Vector3(-32, 0, 2), Vector3(-31.5, 0, 12)])
	var garden := BastideGarden.new()
	garden.name = "Jardin"
	garden.style = st
	garden.seed = 7
	_add(village, garden, root)

	# --- Caméra et aide ---
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.set_script(load("res://demos/common/free_camera.gd"))
	cam.position = Vector3(4, 12, 34)
	cam.rotation_degrees = Vector3(-18, 0, 0)
	cam.fov = 55
	_add(root, cam)
	var ui := CanvasLayer.new()
	ui.name = "Interface"
	_add(root, ui)
	var help := Label.new()
	help.name = "Aide"
	help.position = Vector2(18, 14)
	help.text = "Terrasses et portails (étape 6) : dans l'éditeur, déplace les points d'un chemin à travers le muret\n(un portail s'ouvre) ou ceux d'une terrasse près d'une maison (elle s'y colle). Clic droit + souris : regarder   ZQSD : bouger   A/E : bas/haut   Maj : vite"
	_add(ui, help, root)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://demos/06_terraces"))
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


func _terrace(parent: Node, root: Node, st: Resource, t_name: String, t_seed: int, points: Array, entry := -1) -> void:
	# Le nœud est posé au centre de son emprise (pratique pour le déplacer).
	var c := Vector3.ZERO
	for p: Vector3 in points:
		c += p
	c /= points.size()
	var t := BastideTerrace.new()
	t.name = t_name
	t.position = c
	var curve := Curve3D.new()
	for p: Vector3 in points:
		curve.add_point(p - c)
	curve.closed = true
	t.curve = curve
	t.seed = t_seed
	t.entry_side = entry
	t.style = st
	_add(parent, t, root)
