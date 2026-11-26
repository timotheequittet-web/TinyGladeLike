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
		for mi: MeshInstance3D in _chunks.values():
			mi.material_override = v
@export_flags_3d_physics var collision_layer := 2:
	set(v):
		collision_layer = v
		if _body:
			_body.collision_layer = v

## Le relief tel qu'on le lit (étangs creusés compris).
var field: BastideHeightField
## Le relief d'origine, avant les étangs (les étangs se calent dessus).
var base_field: BastideHeightField
var height_texture: ImageTexture

## Côté d'un morceau de maillage du sol, en cases : un étang ne reconstruit que
## les morceaux qu'il touche.
const CHUNK := 32

## Étangs creusés dans le relief : clé -> {poly, level, depth, shelf, bank, rect} (monde).
var _carves := {}
var _carve_dirty := Rect2()
var _carve_queued := false
## Couleur du sol par point de grille : r = berge mouillée, g = lit d'étang.
var _paint := PackedColorArray()
var _chunks := {}  # Vector2i -> MeshInstance3D

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
	base_field = generate()
	field = _carved(base_field)
	_build_mesh()
	_build_collision()
	height_texture = ImageTexture.create_from_image(field.to_image())
	if had and is_inside_tree():
		_rebuild_structures(get_tree().root)
	changed.emit()


# --- Étangs ------------------------------------------------------------------------

## Creuse (ou recreuse) l'étang `key` : description de BastidePondShape.carve_info(),
## en monde. Le sol, sa collision et sa texture de hauteurs sont mis à jour à la
## frame suivante, puis les structures voisines se reposent dessus.
func set_carve(key: int, carve: Dictionary) -> void:
	var old: Variant = _carves.get(key)
	if old != null and _same_carve(old, carve):
		return
	if old != null:
		_mark_dirty(old["rect"])
	_carves[key] = carve
	_mark_dirty(carve["rect"])


func clear_carve(key: int) -> void:
	if not _carves.has(key):
		return
	_mark_dirty(_carves[key]["rect"])
	_carves.erase(key)


func has_carve(key: int) -> bool:
	return _carves.has(key)


static func _same_carve(a: Dictionary, b: Dictionary) -> bool:
	return is_equal_approx(float(a["level"]), float(b["level"])) and a["poly"] == b["poly"] \
			and is_equal_approx(float(a["depth"]), float(b["depth"]))


func _mark_dirty(r: Rect2) -> void:
	_carve_dirty = r if _carve_dirty.size == Vector2.ZERO else _carve_dirty.merge(r)
	if _carve_queued or not is_inside_tree():
		return
	_carve_queued = true
	_apply_carves.call_deferred()


## Relief d'origine + étangs (et la couleur du sol qui va avec).
func _carved(base: BastideHeightField) -> BastideHeightField:
	var f := BastideHeightField.flat(base.origin, base.cell, base.width, base.depth)
	f.heights = base.heights.duplicate()
	_paint = PackedColorArray()
	_paint.resize(f.width * f.depth)
	_paint.fill(Color(0, 0, 0, 1))
	for c: Dictionary in _carves.values():
		BastidePondShape.apply(f, base, _paint, c)
		f.waters.append({"poly": c["poly"], "level": c["level"], "rect": BastidePondShape.rect_of(c["poly"])})
	return f


func _apply_carves() -> void:
	_carve_queued = false
	if base_field == null:
		return
	var dirty := _carve_dirty
	_carve_dirty = Rect2()
	field = _carved(base_field)
	# Seuls les morceaux du sol touchés sont reconstruits.
	var c0 := Vector2i(floori((dirty.position.x - field.origin.x) / field.cell / CHUNK), floori((dirty.position.y - field.origin.y) / field.cell / CHUNK))
	var c1 := Vector2i(floori((dirty.end.x - field.origin.x) / field.cell / CHUNK), floori((dirty.end.y - field.origin.y) / field.cell / CHUNK))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			if _chunks.has(Vector2i(cx, cz)):
				_build_chunk(Vector2i(cx, cz))
	_build_collision()
	height_texture.update(field.to_image())
	_rebuild_near(get_tree().root, dirty)
	changed.emit()


## Les structures posées sur la zone creusée se reposent sur le nouveau sol (sauf
## les étangs : ils se calent sur le sol d'origine).
func _rebuild_near(n: Node, r: Rect2) -> void:
	if n is BastideStructure and not n is BastidePond:
		var s := n as BastideStructure
		var mi := s.get_mesh_instance()
		var hit := false
		if mi and mi.mesh:
			var box := mi.global_transform * mi.get_aabb()
			hit = Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(0.5).intersects(r)
		elif s.last_stats.is_empty():
			hit = false
		if hit:
			s.queue_rebuild()
	for c in n.get_children():
		_rebuild_near(c, r)


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
	for mi: MeshInstance3D in _chunks.values():
		mi.queue_free()
	_chunks.clear()
	var nx := ceili(float(field.width - 1) / CHUNK)
	var nz := ceili(float(field.depth - 1) / CHUNK)
	for cz in nz:
		for cx in nx:
			_build_chunk(Vector2i(cx, cz))


## Un morceau du sol : (CHUNK + 1)² sommets, normales et couleurs lues sur toute la
## grille (pas de couture visible entre deux morceaux).
func _build_chunk(c: Vector2i) -> void:
	var mi: MeshInstance3D = _chunks.get(c)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Sol_%d_%d" % [c.x, c.y]
		add_child(mi, false, Node.INTERNAL_MODE_FRONT)
		_chunks[c] = mi
	mi.material_override = material
	var i0 := c.x * CHUNK
	var j0 := c.y * CHUNK
	var w := mini(CHUNK, field.width - 1 - i0) + 1
	var d := mini(CHUNK, field.depth - 1 - j0) + 1
	if w < 2 or d < 2:
		mi.mesh = null
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	verts.resize(w * d)
	normals.resize(w * d)
	uvs.resize(w * d)
	cols.resize(w * d)
	var painted := _paint.size() == field.width * field.depth
	for j in d:
		for i in w:
			var k := j * w + i
			var gi := i0 + i
			var gj := j0 + j
			var x := field.origin.x + gi * field.cell
			var z := field.origin.y + gj * field.cell
			verts[k] = Vector3(x, field.at(gi, gj), z)
			var dx := field.at(gi + 1, gj) - field.at(gi - 1, gj)
			var dz := field.at(gi, gj + 1) - field.at(gi, gj - 1)
			normals[k] = Vector3(-dx, 2.0 * field.cell, -dz).normalized()
			uvs[k] = Vector2(x, z)
			cols[k] = _paint[gj * field.width + gi] if painted else Color(0, 0, 0, 1)
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
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mi.mesh = m


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
