extends Node3D
## Décor de la démo : prairie, collines au loin, arbres, bambous, cerisiers, étang,
## rochers et pétales qui volent. Tout est fabriqué ici, sans aucun fichier
## d'image ni modèle, et reste hors de la zone de construction.

const GROUND_SHADER := preload("res://demos/04_runtime/ground.gdshader")

## Rayon de la clairière laissée libre pour construire.
@export var clearing_radius := 34.0
@export var decor_seed := 7
## Pétales de cerisier qui dérivent autour de ce que regarde la caméra.
@export var follow: Node3D

var _rng := RandomNumberGenerator.new()
var _rock_mat: StandardMaterial3D
var _petals: CPUParticles3D
var _terrain: BastideTerrain
## Rochers épars : [MeshInstance3D, décalage au-dessus du sol], recalés quand le
## relief change (un étang creusé dessous les noie au lieu de les laisser en l'air).
var _rocks: Array = []


## Hauteur du sol (relief s'il y en a un).
func _h(x: float, z: float) -> float:
	return _terrain.field.height(x, z) if _terrain and _terrain.field else 0.0


func _ready() -> void:
	_rng.seed = decor_seed
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.albedo_color = Color(0.56, 0.55, 0.5)
	_rock_mat.roughness = 0.9
	_terrain = get_parent().get_node_or_null("Terrain") as BastideTerrain
	_ground()
	if _terrain == null:
		_hills()
	# L'étang de la démo est maintenant une vraie structure (BastidePond, dans le
	# hameau de départ) : il creuse le relief et vit avec le reste.
	_groves()
	_petals_fx()
	if _terrain:
		_terrain.changed.connect(_resnap_rocks)


func _process(_delta: float) -> void:
	if _petals and follow:
		var p := follow.global_position
		_petals.global_position = Vector3(p.x, 12.0, p.z)


func _ground() -> void:
	if _terrain:
		# Le relief porte la prairie : on lui donne son matériau.
		var tm := ShaderMaterial.new()
		tm.shader = GROUND_SHADER
		_terrain.material = tm
		var g := get_parent().get_node_or_null("Herbe") as BastideGrass
		if g:
			g.ground_material = tm
		return
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
	var grass := get_parent().get_node_or_null("Herbe") as BastideGrass
	if grass:
		grass.ground_material = mat


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


func _groves() -> void:
	# Les mêmes arbres que les forêts (kit nature, couronnes peintes d'Onsen) :
	# feuillus, cèdres, pins taillés, cerisiers, quelques érables rouges et des bambous.
	# Une instance par arbre, regroupées par modèle ; au loin, la version à peu de cartes.
	var groups := {}
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < 80 and tries < 3000:
		tries += 1
		var a := _rng.randf() * TAU
		var r := clearing_radius + 4.0 + pow(_rng.randf(), 1.6) * 60.0
		var p := Vector2(cos(a) * r, sin(a) * r)
		# Garde une trouée vers le sud (vue de départ de la caméra) et autour de l'étang.
		if p.y > 0 and absf(p.x) < 14.0:
			continue
		if p.distance_to(Vector2(-27, 16)) < 12.0:
			continue
		# La forêt du hameau occupe le nord.
		if p.y < -10.0 and p.y > -58.0 and absf(p.x) < 44.0:
			continue
		var too_close := false
		for q in placed:
			if q.distance_to(p) < 6.0:
				too_close = true
				break
		if too_close:
			continue
		placed.append(p)
		var roll := _rng.randf()
		var pos := Vector3(p.x, _h(p.x, p.y), p.y)
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), pos)
		if roll < 0.14:
			_add_to(groups, "bamboo", BastideKitNature.plant("bamboo"), xf.scaled_local(Vector3.ONE * _rng.randf_range(0.8, 1.1)))
			continue
		if roll > 0.96:
			_rock(pos, _rng.randf_range(0.8, 1.8))
			continue
		var sp := "sakura" if roll < 0.3 else ("cedre" if roll < 0.45 else ("matsu" if roll < 0.55 else ("momiji" if roll < 0.62 else ("chene" if roll < 0.8 else "hetre"))))
		var size := {"sakura": 1.4, "cedre": 1.6, "matsu": 1.1, "momiji": 1.4, "chene": 1.3, "hetre": 1.3}[sp] as float
		var variant := _rng.randi_range(0, 3)
		var far := r > clearing_radius + 30.0
		var tr := BastideKitNature.tree(sp, variant, size, far)
		var key := "%s%d%s" % [sp, variant, "f" if far else ""]
		_add_to(groups, "t" + key, {"mesh": tr["trunk"], "mat": BastideKitNature.trunk_material()}, xf)
		_add_to(groups, "c" + key, {"mesh": tr["crown"], "mat": tr["crown_mat"]}, xf)
		_add_to(groups, "s" + key, {"mesh": tr["shadow"], "mat": BastideKitNature.trunk_material(), "shadow": true}, xf)
	for k: String in groups:
		var g: Dictionary = groups[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g["mesh"]
		var xfs: Array = g["xf"]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Bosquet_" + k
		mmi.multimesh = mm
		mmi.material_override = g["mat"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if g.get("shadow", false) \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _add_to(groups: Dictionary, key: String, item: Dictionary, xf: Transform3D) -> void:
	if item.is_empty() or item.get("mesh") == null:
		return
	if not groups.has(key):
		groups[key] = {"mesh": item["mesh"], "mat": item["mat"], "xf": [], "shadow": item.get("shadow", false)}
	(groups[key]["xf"] as Array).append(xf)


func _rock(pos: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 9
	s.rings = 5
	s.material = _rock_mat
	mi.mesh = s
	mi.position = Vector3(pos.x, _h(pos.x, pos.z) + size * 0.15, pos.z)
	mi.scale = Vector3(size * _rng.randf_range(0.8, 1.3), size * _rng.randf_range(0.4, 0.65), size * _rng.randf_range(0.8, 1.2))
	mi.rotation = Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf() * TAU, _rng.randf_range(-0.2, 0.2))
	add_child(mi)
	_rocks.append([mi, size * 0.15])


func _resnap_rocks() -> void:
	if _terrain == null or _terrain.field == null:
		return
	for r: Array in _rocks:
		var mi := r[0] as MeshInstance3D
		var p := mi.position
		mi.position.y = _h(p.x, p.z) + float(r[1])
		mi.visible = _terrain.field.water_level(p.x, p.z) == -INF





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
