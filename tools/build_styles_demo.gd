extends SceneTree
## Génère demos/03_styles/styles_demo.tscn (outil de développement).
##   godot --headless --path . -s tools/build_styles_demo.gd
## Deux hameaux identiques (mêmes contours, mêmes tracés de murs), l'un en style
## « médiéval pierre », l'autre en « japonais traditionnel bois ».

const OUT := "res://demos/03_styles/styles_demo.tscn"
const MEDIEVAL := "res://addons/bastide/styles/presets/medieval_stone.tres"
const JAPANESE := "res://addons/bastide/styles/presets/japanese_wood.tres"


func _init() -> void:
	var root := Node3D.new()
	root.name = "StylesDemo"
	root.set_script(load("res://demos/03_styles/styles_demo.gd"))

	# --- Ambiance ---
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.38, 0.58, 0.84)
	sky_mat.sky_horizon_color = Color(0.82, 0.85, 0.88)
	sky_mat.ground_horizon_color = Color(0.72, 0.74, 0.7)
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
	env.fog_light_color = Color(0.76, 0.8, 0.86)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_add(root, we)

	var sun := DirectionalLight3D.new()
	sun.name = "Soleil"
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.rotation_degrees = Vector3(-40, -30, 0)
	_add(root, sun)

	# --- Sol : une parcelle par style, un chemin entre les deux ---
	var ground := StaticBody3D.new()
	ground.name = "Sol"
	_add(root, ground)
	var gs := CollisionShape3D.new()
	gs.name = "Shape"
	gs.shape = WorldBoundaryShape3D.new()
	_add(ground, gs, root)
	_ground_patch(ground, root, "SolGauche", Vector3(-200, 0, 0), Vector2(400, 600), Color(0.42, 0.55, 0.3), 0.0)
	_ground_patch(ground, root, "SolDroite", Vector3(200, 0, 0), Vector2(400, 600), Color(0.42, 0.55, 0.3), 0.0)
	_ground_patch(ground, root, "Chemin", Vector3(0, 0, 0), Vector2(4, 600), Color(0.66, 0.6, 0.49), 0.01)

	# --- Deux hameaux : mêmes contours, mêmes seeds ---
	for side in 2:
		var group := Node3D.new()
		group.name = "Medieval" if side == 0 else "Japonais"
		group.position = Vector3(-21 if side == 0 else 21, 0, 0)
		group.set_meta(&"demo_style", MEDIEVAL if side == 0 else JAPANESE)
		_add(root, group)
		var st := load(MEDIEVAL if side == 0 else JAPANESE)
		# Maison rectangulaire, façade principale vers la caméra.
		_building(group, root, st, "Maison", 3, Vector3(-6, 0, 8), [
			Vector2(-5, -3), Vector2(5, -3), Vector2(5, 3), Vector2(-5, 3)], 0, 2)
		# Ferme en L tracée à main levée (angles redressés).
		_building(group, root, st, "FermeEnL", 5, Vector3(6, 0, -6), [
			Vector2(-6, -3), Vector2(6.2, -2.7), Vector2(6, 2.3), Vector2(0.3, 2.1), Vector2(0, 8), Vector2(-6.2, 8.2)], 0, 4)
		# Petite maison basse d'un étage.
		_building(group, root, st, "Cabane", 9, Vector3(-9, 0, -8), [
			Vector2(-3.2, -2.4), Vector2(3.2, -2.4), Vector2(3.2, 2.4), Vector2(-3.2, 2.4)], 1, 2)
		# Muret de clôture devant la maison, ouvert au milieu pour l'entrée.
		_wall(group, root, st, "MuretGauche", 4, [Vector3(-14.5, 0, 9), Vector3(-14.5, 0, 14.5), Vector3(-8.5, 0, 14.5)])
		_wall(group, root, st, "MuretDroit", 6, [Vector3(-3.5, 0, 14.5), Vector3(2.5, 0, 14.5), Vector3(2.5, 0, 9)])

	# --- Caméra ---
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.set_script(load("res://demos/common/free_camera.gd"))
	cam.position = Vector3(0, 17, 44)
	cam.rotation_degrees = Vector3(-21, 0, 0)
	cam.fov = 62
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
	hb.name = "Styles"
	_add(vb, hb, root)
	for b in [["SideBySide", "Côte à côte"], ["AllMedieval", "Tout médiéval"], ["AllJapanese", "Tout japonais"], ["Swap", "Inverser"]]:
		var btn := Button.new()
		btn.name = b[0]
		btn.unique_name_in_owner = true
		btn.text = b[1]
		_add(hb, btn, root)
	var hb2 := HBoxContainer.new()
	hb2.name = "Reglages"
	_add(vb, hb2, root)
	var l := Label.new()
	l.name = "LSeed"
	l.text = "Seed"
	_add(hb2, l, root)
	var sb := SpinBox.new()
	sb.name = "SeedBox"
	sb.unique_name_in_owner = true
	sb.max_value = 99999
	sb.value = 1
	_add(hb2, sb, root)
	var rnd := Button.new()
	rnd.name = "RandomButton"
	rnd.unique_name_in_owner = true
	rnd.text = "Seed aléatoire"
	_add(hb2, rnd, root)
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


func _ground_patch(parent: Node, root: Node, p_name: String, pos: Vector3, size: Vector2, color: Color, lift: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = p_name
	var plane := PlaneMesh.new()
	plane.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	plane.material = mat
	mi.mesh = plane
	mi.position = pos + Vector3(0, lift, 0)
	_add(parent, mi, root)


## door : côté du tracé qui reçoit la porte (vers la caméra).
func _building(parent: Node, root: Node, st: Resource, b_name: String, b_seed: int, pos: Vector3, corners: Array,
		floors := 0, door := -1) -> void:
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


func _wall(parent: Node, root: Node, st: Resource, w_name: String, w_seed: int, points: Array) -> void:
	var w := BastideWall.new()
	w.name = w_name
	var c := Curve3D.new()
	for p: Vector3 in points:
		c.add_point(p)
	w.curve = c
	w.seed = w_seed
	w.height = 1.9
	w.style = st
	_add(parent, w, root)
