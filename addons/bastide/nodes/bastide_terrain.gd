@tool
class_name BastideTerrain
extends Node3D
## Le sol en relief : une clairière doucement vallonnée où l'on construit, des
## collines qui montent autour. Fournit à tout le reste un BastideHeightField
## (hauteur du sol en tout point, lisible depuis les threads de génération) :
## murets et chemins épousent la pente, maisons et terrasses se posent d'aplomb
## sur un soubassement (voir BastideDrape), plantes et arbres se posent au sol.
##
## Le maillage, la collision (HeightMapShape3D) et une texture de hauteurs (pour
## l'herbe) sont reconstruits à chaque changement de réglage.

signal changed

const GROUP := &"bastide_terrain"

@export var size := 480.0:
	set(v):
		size = maxf(v, 8.0)
		_queue()
@export var cell := 1.5:
	set(v):
		cell = clampf(v, 0.25, 8.0)
		_queue()
@export var seed := 11:
	set(v):
		seed = v
		_queue()
@export_group("Clairière")
## Rayon de la zone où l'on construit : relief doux, pas de colline.
@export var clearing_radius := 40.0:
	set(v):
		clearing_radius = v
		_queue()
## Amplitude des bosses et creux dans la clairière (m).
@export var clearing_relief := 1.4:
	set(v):
		clearing_relief = v
		_queue()
## Pente générale de la clairière (m sur son rayon), vers `tilt_dir`.
@export var tilt := 1.2:
	set(v):
		tilt = v
		_queue()
@export var tilt_dir := Vector2(0.3, -1.0):
	set(v):
		tilt_dir = v
		_queue()
@export_group("Collines")
@export var hill_height := 16.0:
	set(v):
		hill_height = v
		_queue()
## Distance à laquelle les collines ont atteint leur pleine hauteur.
@export var hill_full := 120.0:
	set(v):
		hill_full = v
		_queue()
@export_group("Zones plates")
## Zones aplanies (étang, place…) : (x, z, rayon, fondu) en monde.
@export var flat_zones: Array[Vector4] = []:
	set(v):
		flat_zones = v
		_queue()
@export_group("Rendu")
@export var material: Material:
	set(v):
		material = v
		if _mesh_instance:
			_mesh_instance.material_override = v
@export_flags_3d_physics var collision_layer := 2:
	set(v):
		collision_layer = v
		if _body:
			_body.collision_layer = v

var field: BastideHeightField
var height_texture: ImageTexture

var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D
var _queued := false


## Le relief qui porte `node` (le premier terrain de sa scène), ou null.
static func field_for(node: Node) -> BastideHeightField:
	var t := find(node)
	return t.field if t else null


static func find(node: Node) -> BastideTerrain:
	if node == null or not node.is_inside_tree():
		return null
	var list := node.get_tree().get_nodes_in_group(GROUP)
	for n in list:
		if n is BastideTerrain and (n as BastideTerrain).field != null:
			return n
	return null


func _enter_tree() -> void:
	add_to_group(GROUP)
	if field == null:
		rebuild()


func _queue() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	(func() -> void:
		_queued = false
		rebuild()).call_deferred()


## Hauteur du sol en un point du monde.
func height_at(p: Vector3) -> float:
	return field.height(p.x, p.z) if field else 0.0


func rebuild() -> void:
	var had := field != null
	field = generate()
	_build_mesh()
	_build_collision()
	height_texture = ImageTexture.create_from_image(field.to_image())
	if had and is_inside_tree():
		_rebuild_structures(get_tree().root)
	changed.emit()


static func _rebuild_structures(n: Node) -> void:
	if n is BastideStructure:
		(n as BastideStructure).queue_rebuild()
	for c in n.get_children():
		_rebuild_structures(c)


## Le relief seul (sans nœud) : bruit de collines, clairière apaisée, zones plates.
func generate() -> BastideHeightField:
	var n := int(ceil(size / cell)) + 1
	var f := BastideHeightField.flat(Vector2(-size, -size) * 0.5, cell, n, n)
	var hills := FastNoiseLite.new()
	hills.seed = seed
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.frequency = 0.012
	hills.fractal_octaves = 4
	var bumps := FastNoiseLite.new()
	bumps.seed = seed + 7
	bumps.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	bumps.frequency = 0.045
	bumps.fractal_octaves = 2
	var td := tilt_dir.normalized() if tilt_dir.length() > 0.01 else Vector2.ZERO
	for iz in n:
		for ix in n:
			var x := f.origin.x + ix * cell
			var z := f.origin.y + iz * cell
			var r := Vector2(x, z).length()
			# Dans la clairière : bosses douces et une légère pente.
			var h := bumps.get_noise_2d(x, z) * clearing_relief
			h += clampf(Vector2(x, z).dot(td) / maxf(clearing_radius, 1.0), -1.5, 1.5) * tilt
			# Au-delà : les collines montent, de plus en plus hautes.
			var k := smoothstep(clearing_radius, hill_full, r)
			h += k * (hills.get_noise_2d(x, z) * 0.5 + 0.55) * hill_height * (0.6 + 0.4 * k)
			f.set_at(ix, iz, h)
	for z4 in flat_zones:
		_flatten(f, z4)
	return f


static func _flatten(f: BastideHeightField, z4: Vector4) -> void:
	var c := Vector2(z4.x, z4.y)
	var target := f.height(c.x, c.y)
	var reach := z4.z + z4.w
	var i0 := maxi(0, int((c.x - reach - f.origin.x) / f.cell))
	var i1 := mini(f.width - 1, int((c.x + reach - f.origin.x) / f.cell) + 1)
	var j0 := maxi(0, int((c.y - reach - f.origin.y) / f.cell))
	var j1 := mini(f.depth - 1, int((c.y + reach - f.origin.y) / f.cell) + 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := f.origin + Vector2(i, j) * f.cell
			var t := 1.0 - smoothstep(z4.z, reach, p.distance_to(c))
			f.set_at(i, j, lerpf(f.at(i, j), target, t))


func _build_mesh() -> void:
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "Sol"
		add_child(_mesh_instance, false, Node.INTERNAL_MODE_FRONT)
	_mesh_instance.material_override = material
	var w := field.width
	var d := field.depth
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(w * d)
	normals.resize(w * d)
	uvs.resize(w * d)
	for j in d:
		for i in w:
			var k := j * w + i
			var x := field.origin.x + i * field.cell
			var z := field.origin.y + j * field.cell
			verts[k] = Vector3(x, field.at(i, j), z)
			var dx := field.at(i + 1, j) - field.at(i - 1, j)
			var dz := field.at(i, j + 1) - field.at(i, j - 1)
			normals[k] = Vector3(-dx, 2.0 * field.cell, -dz).normalized()
			uvs[k] = Vector2(x, z)
	var idx := PackedInt32Array()
	idx.resize((w - 1) * (d - 1) * 6)
	var t := 0
	for j in d - 1:
		for i in w - 1:
			var a := j * w + i
			idx[t] = a; idx[t + 1] = a + 1; idx[t + 2] = a + w
			idx[t + 3] = a + 1; idx[t + 4] = a + w + 1; idx[t + 5] = a + w
			t += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh_instance.mesh = m


func _build_collision() -> void:
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = "Collision"
		add_child(_body, false, Node.INTERNAL_MODE_FRONT)
		_shape = CollisionShape3D.new()
		_body.add_child(_shape)
	_body.collision_layer = collision_layer
	var hm := HeightMapShape3D.new()
	hm.map_width = field.width
	hm.map_depth = field.depth
	hm.map_data = field.heights
	_shape.shape = hm
	# La forme est centrée et a des cases de 1 m : on la met à l'échelle de la grille.
	var center := field.origin + field.size() * 0.5
	_shape.transform = Transform3D(Basis.from_scale(Vector3(field.cell, 1.0, field.cell)), Vector3(center.x, 0, center.y))
