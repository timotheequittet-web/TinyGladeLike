extends SceneTree
## Génère demos/02_building/building_demo.tscn (outil de développement).
##   godot --headless --path . -s tools/build_building_demo.gd
## La scène produite s'édite ensuite normalement dans Godot.

const OUT := "res://demos/02_building/building_demo.tscn"
const STYLE := "res://addons/bastide/styles/presets/medieval_stone.tres"


func _init() -> void:
	var root := Node3D.new()
	root.name = "BuildingDemo"
	root.set_script(load("res://demos/02_building/building_demo.gd"))

	# --- Ambiance ---
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.56, 0.82)
	sky_mat.sky_horizon_color = Color(0.8, 0.84, 0.88)
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
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.8, 0.86)
	env.fog_density = 0.005
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

	# --- Bâtiments ---
	var group := Node3D.new()
	group.name = "Batiments"
	_add(root, group)

	# 1. Maison rectangulaire : deux pignons.
	_building(group, root, "Maison", 3, Vector3(-17, 0, -1), [
		Vector2(-5, -3), Vector2(5, -3), Vector2(5, 3), Vector2(-5, 3)], 0)
	# 2. Pavillon carré : toit en pavillon (quatre pans qui se rejoignent).
	_building(group, root, "Pavillon", 8, Vector3(-3, 0, -14), [
		Vector2(-3.5, -3.5), Vector2(3.5, -3.5), Vector2(3.5, 3.5), Vector2(-3.5, 3.5)], 1)
	# 3. Ferme en L, tracée « à la main » : les angles sont redressés.
	_building(group, root, "FermeEnL", 5, Vector3(6, 0, -4), [
		Vector2(-6, -3), Vector2(6.2, -2.7), Vector2(6, 2.3), Vector2(0.3, 2.1), Vector2(0, 8), Vector2(-6.2, 8.2)], 0)
	# 4. Manoir en U, trois étages.
	_building(group, root, "ManoirEnU", 12, Vector3(-8, 0, 17), [
		Vector2(-8, -5), Vector2(8, -5), Vector2(8, 6), Vector2(3, 6), Vector2(3, 0), Vector2(-3, 0),
		Vector2(-3, 6), Vector2(-8, 6)], 0, 3)
	# 5. Maison biscornue : contour irrégulier, toit à croupes.
	_building(group, root, "MaisonBiscornue", 21, Vector3(19, 0, 11), [
		Vector2(-4, -4), Vector2(4.5, -5), Vector2(6, 2), Vector2(0.5, 5.5), Vector2(-5, 2)], 1)
	# 6. Tour carrée, haute et étroite.
	_building(group, root, "Tour", 17, Vector3(19, 0, -10), [
		Vector2(-2.4, -2.4), Vector2(2.4, -2.4), Vector2(2.4, 2.4), Vector2(-2.4, 2.4)], 1, 4)

	# --- Un mur de l'étape 1 ferme la cour du manoir ---
	var wall := BastideWall.new()
	wall.name = "MurDeCour"
	var c := Curve3D.new()
	c.add_point(Vector3(-11.4, 0, 22.3))
	c.add_point(Vector3(-4.6, 0, 22.3))
	wall.curve = c
	wall.seed = 4
	wall.height = 2.0
	wall.style = load(STYLE)
	_add(group, wall, root)

	# --- Caméra ---
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.set_script(load("res://demos/common/free_camera.gd"))
	cam.position = Vector3(2, 19, 44)
	cam.rotation_degrees = Vector3(-24, 0, 0)
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
	hb.name = "Reglages"
	_add(vb, hb, root)
	_label(hb, root, "Seed")
	var sb := SpinBox.new()
	sb.name = "SeedBox"
	sb.unique_name_in_owner = true
	sb.max_value = 99999
	sb.value = 1
	_add(hb, sb, root)
	var btn := Button.new()
	btn.name = "RandomButton"
	btn.unique_name_in_owner = true
	btn.text = "Seed aléatoire"
	_add(hb, btn, root)
	_label(hb, root, "  Étages")
	var fb := SpinBox.new()
	fb.name = "FloorsBox"
	fb.unique_name_in_owner = true
	fb.max_value = 6
	fb.value = 0
	fb.tooltip_text = "0 = étages d'origine de chaque bâtiment"
	_add(hb, fb, root)
	_label(hb, root, "  Toits")
	var ob := OptionButton.new()
	ob.name = "RoofChoice"
	ob.unique_name_in_owner = true
	ob.add_item("D'origine")
	ob.add_item("Croupes")
	ob.add_item("Pignons")
	_add(hb, ob, root)
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


func _label(parent: Node, root: Node, text: String) -> void:
	var l := Label.new()
	l.name = "L" + str(parent.get_child_count())
	l.text = text
	_add(parent, l, root)


## Contour : angles en Vector2(x, z) relatifs à `pos`. roof : 0 style, 1 croupes, 2 pignons.
func _building(parent: Node, root: Node, b_name: String, b_seed: int, pos: Vector3, corners: Array,
		roof: int, floors := 0) -> BastideBuilding:
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
	b.roof = roof
	b.style = load(STYLE)
	# Réglages d'origine, pour que l'interface de la démo puisse y revenir.
	b.set_meta(&"demo_floors", floors)
	b.set_meta(&"demo_roof", roof)
	_add(parent, b, root)
	return b
