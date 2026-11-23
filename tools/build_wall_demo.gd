extends SceneTree
## Génère demos/01_wall/wall_demo.tscn (outil de développement).
##   godot --headless --path . -s tools/build_wall_demo.gd
## La scène produite s'édite ensuite normalement dans Godot.

const OUT := "res://demos/01_wall/wall_demo.tscn"


func _init() -> void:
	var root := Node3D.new()
	root.name = "WallDemo"
	root.set_script(load("res://demos/01_wall/wall_demo.gd"))

	# --- Ambiance ---
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.56, 0.82)
	sky_mat.sky_horizon_color = Color(0.78, 0.82, 0.86)
	sky_mat.ground_horizon_color = Color(0.7, 0.72, 0.7)
	sky_mat.ground_bottom_color = Color(0.3, 0.32, 0.28)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.5
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.8, 0.86)
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_add(root, we)

	var sun := DirectionalLight3D.new()
	sun.name = "Soleil"
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.rotation_degrees = Vector3(-42, -38, 0)
	_add(root, sun)

	# --- Sol ---
	var ground := StaticBody3D.new()
	ground.name = "Sol"
	_add(root, ground)
	var gm := MeshInstance3D.new()
	gm.name = "Mesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(800, 800)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.42, 0.55, 0.3)
	gmat.roughness = 1.0
	plane.material = gmat
	gm.mesh = plane
	_add(ground, gm, root)
	var gs := CollisionShape3D.new()
	gs.name = "Shape"
	gs.shape = WorldBoundaryShape3D.new()
	_add(ground, gs, root)

	# --- Murs ---
	var walls := Node3D.new()
	walls.name = "Murs"
	_add(root, walls)

	# 1. Mur droit avec deux piliers.
	_wall(walls, root, "MurDroit", 3, [[Vector3(-22, 0, 12)], [Vector3(-8, 0, 12)]], false)

	# 2. Mur courbe en S (poignées de Bézier).
	_wall(walls, root, "MurCourbe", 11, [
		[Vector3(-4, 0, 16), Vector3.ZERO, Vector3(5, 0, 0)],
		[Vector3(8, 0, 10), Vector3(-4, 0, 3), Vector3(4, 0, -3)],
		[Vector3(20, 0, 8), Vector3(-5, 0, 0)],
	], false)

	# 3. Enceinte fermée irrégulière : angles nets (piliers) et un côté arrondi.
	_wall(walls, root, "Enceinte", 27, [
		[Vector3(-16, 0, -4)],
		[Vector3(-4, 0, -2)],
		[Vector3(-2, 0, -12), Vector3.ZERO, Vector3(0, 0, -5)],
		[Vector3(-10, 0, -20), Vector3(5, 0, 0)],
		[Vector3(-18, 0, -14)],
	], true)

	# 4. Tour ronde : une boucle fermée sans angle, plus haute.
	var r := 3.2
	var k := r * 0.5523
	var tower := _wall(walls, root, "TourRonde", 5, [
		[Vector3(12, 0, -8 - r), Vector3(-k, 0, 0), Vector3(k, 0, 0)],
		[Vector3(12 + r, 0, -8), Vector3(0, 0, -k), Vector3(0, 0, k)],
		[Vector3(12, 0, -8 + r), Vector3(k, 0, 0), Vector3(-k, 0, 0)],
		[Vector3(12 - r, 0, -8), Vector3(0, 0, k), Vector3(0, 0, -k)],
	], true)
	tower.height = 5.5

	# --- Caméra ---
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.set_script(load("res://demos/common/free_camera.gd"))
	cam.position = Vector3(-6, 13, 34)
	cam.rotation_degrees = Vector3(-22, 0, 0)
	cam.fov = 60
	_add(root, cam)

	# --- Interface ---
	var ui := CanvasLayer.new()
	ui.name = "Interface"
	_add(root, ui)
	var panel := PanelContainer.new()
	panel.name = "Panneau"
	panel.position = Vector2(16, 16)
	_add(ui, panel, root)
	var vb := VBoxContainer.new()
	vb.name = "VBox"
	_add(panel, vb, root)
	var help := Label.new()
	help.name = "Aide"
	help.text = "Clic droit + souris : regarder   ZQSD : bouger   A/E : bas/haut   Maj : vite\nClic gauche : lancer une boule (collisions)"
	_add(vb, help, root)
	var hb := HBoxContainer.new()
	hb.name = "Seed"
	_add(vb, hb, root)
	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = "Seed"
	_add(hb, lbl, root)
	var sb := SpinBox.new()
	sb.name = "SeedBox"
	sb.unique_name_in_owner = true
	sb.min_value = 0
	sb.max_value = 99999
	sb.value = 1
	_add(hb, sb, root)
	var btn := Button.new()
	btn.name = "RandomButton"
	btn.unique_name_in_owner = true
	btn.text = "Seed aléatoire"
	_add(hb, btn, root)
	var stats := Label.new()
	stats.name = "Stats"
	stats.unique_name_in_owner = true
	stats.add_theme_font_size_override("font_size", 13)
	_add(vb, stats, root)

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


## points : liste de [position, in?, out?] (poignées relatives, optionnelles).
func _wall(parent: Node, root: Node, wall_name: String, wall_seed: int, points: Array, closed: bool) -> BastideWall:
	var w := BastideWall.new()
	w.name = wall_name
	var c := Curve3D.new()
	for p in points:
		var pin: Vector3 = p[1] if p.size() > 1 else Vector3.ZERO
		var pout: Vector3 = p[2] if p.size() > 2 else Vector3.ZERO
		c.add_point(p[0], pin, pout)
	c.closed = closed
	c.bake_interval = 0.25
	w.curve = c
	w.seed = wall_seed
	w.style = load("res://addons/bastide/styles/presets/medieval_stone.tres")
	_add(parent, w, root)
	return w
