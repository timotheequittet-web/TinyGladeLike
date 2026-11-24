extends Node3D
## Décor de la démo : prairie, collines au loin, arbres, bambous, cerisiers, étang,
## rochers et pétales qui volent. Tout est fabriqué ici, sans aucun fichier
## d'image ni modèle, et reste hors de la zone de construction.

const GROUND_SHADER := preload("res://demos/04_runtime/ground.gdshader")
const FOLIAGE_SHADER := preload("res://demos/04_runtime/foliage.gdshader")
const WATER_SHADER := preload("res://demos/04_runtime/water.gdshader")

## Rayon de la clairière laissée libre pour construire.
@export var clearing_radius := 34.0
@export var decor_seed := 7
## Pétales de cerisier qui dérivent autour de ce que regarde la caméra.
@export var follow: Node3D

var _rng := RandomNumberGenerator.new()
var _foliage_mat: ShaderMaterial
var _trunk_mat: StandardMaterial3D
var _rock_mat: StandardMaterial3D
var _petals: CPUParticles3D


func _ready() -> void:
	_rng.seed = decor_seed
	_foliage_mat = ShaderMaterial.new()
	_foliage_mat.shader = FOLIAGE_SHADER
	_trunk_mat = StandardMaterial3D.new()
	_trunk_mat.albedo_color = Color(0.33, 0.25, 0.2)
	_trunk_mat.roughness = 0.95
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
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < 70 and tries < 2000:
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
			if q.distance_to(p) < 5.5:
				too_close = true
				break
		if too_close:
			continue
		placed.append(p)
		var roll := _rng.randf()
		var pos := Vector3(p.x, 0, p.y)
		if roll < 0.2:
			_bamboo_clump(pos)
		elif roll < 0.42:
			_tree(pos, true)
		elif roll < 0.88:
			_tree(pos, false)
		else:
			_rock(pos, _rng.randf_range(0.8, 1.8))
	# Quelques arbres isolés plus près, pour donner de la profondeur au hameau.
	_tree(Vector3(31, 0, -10), true)
	_tree(Vector3(-33, 0, -14), false)
	_bamboo_clump(Vector3(28, 0, 14))


## Arbre stylisé : tronc conique et houppier fait de quelques boules.
func _tree(pos: Vector3, blossom: bool) -> void:
	var root := Node3D.new()
	root.name = "Cerisier" if blossom else "Arbre"
	root.position = pos
	root.rotation.y = _rng.randf() * TAU
	var s := _rng.randf_range(0.8, 1.35)
	root.scale = Vector3.ONE * s
	add_child(root)
	var h := _rng.randf_range(2.2, 3.4) if blossom else _rng.randf_range(3.0, 4.6)
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.26
	cyl.height = h
	cyl.radial_segments = 8
	cyl.material = _trunk_mat
	trunk.mesh = cyl
	trunk.position.y = h * 0.5
	trunk.rotation.z = _rng.randf_range(-0.12, 0.12)
	root.add_child(trunk)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_cols := [Color(0.97, 0.78, 0.82), Color(0.94, 0.68, 0.76), Color(1.0, 0.86, 0.88)] if blossom \
			else [Color(0.27, 0.42, 0.2), Color(0.33, 0.47, 0.22), Color(0.24, 0.37, 0.2), Color(0.4, 0.5, 0.24)]
	var blobs := _rng.randi_range(4, 7)
	for i in blobs:
		var ang := _rng.randf() * TAU
		var spread := _rng.randf_range(0.3, 1.3)
		var c := Vector3(cos(ang) * spread, h + _rng.randf_range(-0.4, 1.1), sin(ang) * spread)
		var r := _rng.randf_range(0.9, 1.5) * (1.15 if blossom else 1.0)
		var col: Color = base_cols[_rng.randi() % base_cols.size()]
		_blob(st, c, Vector3(r, r * 0.8, r), col)
	var canopy := MeshInstance3D.new()
	st.generate_normals()
	canopy.mesh = st.commit()
	canopy.material_override = _foliage_mat
	root.add_child(canopy)


## Bosquet de bambous : tiges fines, nœuds plus clairs, plumets de feuilles.
func _bamboo_clump(pos: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := _rng.randi_range(9, 16)
	for i in n:
		var off := Vector3(_rng.randf_range(-1.4, 1.4), 0, _rng.randf_range(-1.4, 1.4))
		var h := _rng.randf_range(5.0, 8.5)
		var lean := Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5))
		var col := Color(0.42, 0.55, 0.26).lerp(Color(0.55, 0.62, 0.3), _rng.randf())
		var segs := int(h / 0.9)
		for k in segs:
			var t0 := float(k) / segs
			var t1 := float(k + 1) / segs
			var a := off + lean * t0 * t0 + Vector3(0, h * t0, 0)
			var b := off + lean * t1 * t1 + Vector3(0, h * t1 - 0.04, 0)
			_tube(st, a, b, 0.055, col)
		for k in 3:
			var top := off + lean + Vector3(0, h - k * 0.8, 0)
			_blob(st, top + Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5)),
					Vector3(0.7, 0.35, 0.7), Color(0.36, 0.5, 0.22).lerp(Color(0.48, 0.58, 0.27), _rng.randf()))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Bambous"
	mi.mesh = st.commit()
	mi.material_override = _foliage_mat
	mi.position = pos
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


## Ellipsoïde bosselé (icosphère grossière) à la couleur donnée.
func _blob(st: SurfaceTool, c: Vector3, r: Vector3, col: Color) -> void:
	var rings := 6
	var segs := 9
	var verts := []
	for i in rings + 1:
		var v := float(i) / rings
		var phi := v * PI
		var row := []
		for j in segs:
			var th := TAU * j / segs + (0.3 if i % 2 == 1 else 0.0)
			var bump := 1.0 + _rng.randf_range(-0.08, 0.08) if i > 0 and i < rings else 1.0
			row.append(c + Vector3(sin(phi) * cos(th) * r.x, cos(phi) * r.y, sin(phi) * sin(th) * r.z) * bump)
		verts.append(row)
	var shade := col
	for i in rings:
		for j in segs:
			var a: Vector3 = verts[i][j]
			var b: Vector3 = verts[i][(j + 1) % segs]
			var cc: Vector3 = verts[i + 1][(j + 1) % segs]
			var d: Vector3 = verts[i + 1][j]
			# Le dessous des houppiers est plus sombre.
			var k := 0.75 + 0.3 * (1.0 - float(i) / rings)
			st.set_color(Color(shade.r * k, shade.g * k, shade.b * k))
			st.add_vertex(a); st.add_vertex(b); st.add_vertex(cc)
			st.add_vertex(a); st.add_vertex(cc); st.add_vertex(d)


func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var segs := 6
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var up := side.cross(axis)
	st.set_color(col)
	for j in segs:
		var t0 := TAU * j / segs
		var t1 := TAU * (j + 1) / segs
		var o0 := (side * cos(t0) + up * sin(t0)) * r
		var o1 := (side * cos(t1) + up * sin(t1)) * r
		st.add_vertex(a + o0); st.add_vertex(b + o0); st.add_vertex(b + o1)
		st.add_vertex(a + o0); st.add_vertex(b + o1); st.add_vertex(a + o1)
	# Nœud plus clair en haut du segment.
	st.set_color(col.lightened(0.25))
	for j in segs:
		var t0 := TAU * j / segs
		var t1 := TAU * (j + 1) / segs
		var o0 := (side * cos(t0) + up * sin(t0)) * r * 1.25
		var o1 := (side * cos(t1) + up * sin(t1)) * r * 1.25
		var c0 := b - axis * 0.05
		st.add_vertex(c0 + o0); st.add_vertex(b + o0); st.add_vertex(b + o1)
		st.add_vertex(c0 + o0); st.add_vertex(b + o1); st.add_vertex(c0 + o1)


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
