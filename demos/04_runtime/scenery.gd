extends Node3D
## Décor de la démo : prairie, collines au loin, arbres, bambous, cerisiers, étang,
## rochers et pétales qui volent. Tout est fabriqué ici, sans aucun fichier
## d'image ni modèle, et reste hors de la zone de construction.

const GROUND_SHADER := preload("res://demos/04_runtime/ground.gdshader")
const WATER_SHADER := preload("res://demos/04_runtime/water.gdshader")

## Rayon de la clairière laissée libre pour construire.
@export var clearing_radius := 34.0
@export var decor_seed := 7
## Pétales de cerisier qui dérivent autour de ce que regarde la caméra.
@export var follow: Node3D

var _rng := RandomNumberGenerator.new()
var _rock_mat: StandardMaterial3D
var _petals: CPUParticles3D


func _ready() -> void:
	_rng.seed = decor_seed
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.albedo_color = Color(0.56, 0.55, 0.5)
	_rock_mat.roughness = 0.9
	_ground()
	_hills()
	# La rive est dégagée là où la terrasse de la démo avance sur l'eau.
	_pond(Vector3(-27, 0, 16), Vector2(9.0, 6.0), Rect2(-23.5, 13.0, 6.0, 4.6))
	_groves()
	_petals_fx()


func _process(_delta: float) -> void:
	if _petals and follow:
		var p := follow.global_position
		_petals.global_position = Vector3(p.x, 12.0, p.z)


func _ground() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Prairie"
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 700)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	plane.material = mat
	mi.mesh = plane
	add_child(mi)


## Collines douces au loin : elles referment l'horizon dans la brume.
func _hills() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	for i in 14:
		var a := TAU * i / 14.0 + _rng.randf_range(-0.15, 0.15)
		var r := _rng.randf_range(150.0, 230.0)
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 32
		s.rings = 16
		s.material = mat
		mi.mesh = s
		mi.position = Vector3(cos(a) * r, -_rng.randf_range(6.0, 14.0), sin(a) * r)
		mi.scale = Vector3(_rng.randf_range(50, 90), _rng.randf_range(22, 42), _rng.randf_range(40, 70))
		mi.rotation.y = _rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _pond(center: Vector3, size: Vector2, clear := Rect2()) -> void:
	var water := MeshInstance3D.new()
	water.name = "Etang"
	var plane := PlaneMesh.new()
	plane.size = size * 2.0
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	plane.material = mat
	water.mesh = plane
	water.position = center + Vector3(0, 0.05, 0)
	add_child(water)
	# Rive : galets autour de l'eau.
	var n := 34
	for i in n:
		var a := TAU * i / n + _rng.randf_range(-0.05, 0.05)
		var p := center + Vector3(cos(a) * size.x * 0.97, 0, sin(a) * size.y * 0.97)
		var sz := _rng.randf_range(0.35, 0.8)
		if clear.has_point(Vector2(p.x, p.z)):
			continue
		_rock(p, sz)
	_rock(center + Vector3(size.x * 0.6, 0, -size.y * 0.9), 1.5)
	_rock(center + Vector3(-size.x * 0.9, 0, size.y * 0.4), 1.1)


func _groves() -> void:
	# Mêmes essences que le hameau (addon) : pins taillés, feuillus en dôme,
	# cerisiers, bambous et quelques érables rouges. Tout est fusionné en quelques
	# maillages par secteur, pour rester léger et laisser la caméra les écarter.
	var style: BastideStyle = load("res://addons/bastide/styles/presets/japanese_wood.tres")
	var gs: BastideGardenStyle = style.get_garden_style()
	var green := gs.duplicate() as BastideGardenStyle
	green.maple_colors = PackedColorArray([Color(0.3, 0.46, 0.2), Color(0.36, 0.5, 0.22), Color(0.27, 0.41, 0.2), Color(0.42, 0.52, 0.24)])
	var sectors := 8
	var red_items: Array = []
	var green_items: Array = []
	for i in sectors:
		red_items.append([])
		green_items.append([])
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < 85 and tries < 3000:
		tries += 1
		var a := _rng.randf() * TAU
		var r := clearing_radius + 4.0 + pow(_rng.randf(), 1.6) * 60.0
		var p := Vector2(cos(a) * r, sin(a) * r)
		# Garde une trouée vers le sud (vue de départ de la caméra) et autour de l'étang.
		if p.y > 0 and absf(p.x) < 14.0:
			continue
		if p.distance_to(Vector2(-27, 16)) < 12.0:
			continue
		var too_close := false
		for q in placed:
			if q.distance_to(p) < 4.6:
				too_close = true
				break
		if too_close:
			continue
		placed.append(p)
		var sec := int(posmod(atan2(p.y, p.x), TAU) / TAU * sectors) % sectors
		var pos := Vector3(p.x, 0, p.y)
		var key := _rng.randi()
		var roll := _rng.randf()
		# Plus loin, plus grand : l'œil lit mieux les silhouettes dans la brume.
		var far := clampf((r - clearing_radius) / 60.0, 0.0, 1.0)
		var grow := lerpf(1.25, 1.7, far) * _rng.randf_range(0.9, 1.15)
		if roll < 0.16:
			green_items[sec].append({"type": "bamboo", "pos": pos, "size": _rng.randf_range(1.4, 1.9), "key": key})
		elif roll < 0.34:
			green_items[sec].append({"type": "sakura", "pos": pos, "size": 4.3 * grow, "key": key})
		elif roll < 0.6:
			green_items[sec].append({"type": "pine", "pos": pos, "size": 3.4 * grow, "key": key})
		elif roll < 0.92:
			green_items[sec].append({"type": "maple", "pos": pos, "size": 4.0 * grow, "key": key})
		elif roll < 0.955:
			red_items[sec].append({"type": "maple", "pos": pos, "size": 3.8 * grow, "key": key})
		else:
			_rock(pos, _rng.randf_range(0.8, 1.8))
	# Quelques arbres isolés plus près, pour donner de la profondeur au hameau.
	green_items[7].append({"type": "sakura", "pos": Vector3(31, 0, -10), "size": 5.6, "key": 11})
	green_items[3].append({"type": "pine", "pos": Vector3(-33, 0, -14), "size": 4.6, "key": 12})
	green_items[0].append({"type": "bamboo", "pos": Vector3(28, 0, 14), "size": 1.8, "key": 13})
	var mats := BastideGardenMesher.materials(style)
	for i in sectors:
		var mb := BastideMeshBuilder.new()
		BastidePlantingMesher.draw_items(mb, green_items[i], green)
		BastidePlantingMesher.draw_items(mb, red_items[i], gs)
		if mb.triangle_count == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Bosquet%d" % i
		mi.mesh = mb.commit(mats)
		add_child(mi)


func _rock(pos: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 9
	s.rings = 5
	s.material = _rock_mat
	mi.mesh = s
	mi.position = pos + Vector3(0, size * 0.15, 0)
	mi.scale = Vector3(size * _rng.randf_range(0.8, 1.3), size * _rng.randf_range(0.4, 0.65), size * _rng.randf_range(0.8, 1.2))
	mi.rotation = Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf() * TAU, _rng.randf_range(-0.2, 0.2))
	add_child(mi)





## Pétales de cerisier qui dérivent lentement dans l'air.
func _petals_fx() -> void:
	var p := CPUParticles3D.new()
	p.name = "Petales"
	p.amount = 160
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(45, 1, 45)
	p.position = Vector3(0, 0, 0)
	p.direction = Vector3(1, -0.4, 0.3)
	p.spread = 25.0
	p.gravity = Vector3(0.25, -0.35, 0.1)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.9
	p.angular_velocity_min = -90.0
	p.angular_velocity_max = 90.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.local_coords = false
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.08, 0.85, 1.0])
	grad.colors = PackedColorArray([Color(1, 0.86, 0.9, 0), Color(1, 0.84, 0.88, 1), Color(0.98, 0.8, 0.85, 1), Color(1, 0.8, 0.85, 0)])
	p.color_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.06)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	# Émis en hauteur : la boîte est placée à 12 m, la caméra suit au sol.
	p.emission_box_extents = Vector3(45, 4, 45)
	p.position.y = 12.0
	_petals = p
