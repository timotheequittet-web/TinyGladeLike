class_name BastideGrass
extends Node3D
## Herbe haute autour de ce que regarde la caméra : deux anneaux de tuiles (brins
## fins et serrés près du centre, brins plus larges et clairsemés plus loin) qui
## suivent le point visé. L'herbe se couche toute seule sur les chemins, sous les
## maisons, les terrasses et les murets : un masque est redessiné à chaque
## changement du chantier.
##
## Le maillage d'une tuile est construit une fois ; les tuiles sont seulement
## déplacées quand le centre suivi change de case. Le vent, la hauteur, le
## masque et le fondu sont calculés dans le shader.

const SHADER := preload("res://addons/bastide/shaders/bastide_grass.gdshader")

## Chantier dont les constructions écartent l'herbe.
@export var site: BastideBuildSite
## Caméra suivie (son point visé, ou le promeneur).
@export var camera: Camera3D
## Relief sur lequel pousse l'herbe (facultatif ; sinon, le premier de la scène).
@export var terrain: BastideTerrain
## Matériau du sol (facultatif) : on lui donne `grass_center` et `grass_far` pour
## qu'il s'assombrisse sous l'herbe.
@export var ground_material: ShaderMaterial
@export_group("Anneau proche")
@export var near_radius := 24.0
@export var near_tile := 4.0
@export var near_density := 110.0      # brins par m²
@export var near_width := 0.04
@export_group("Anneau lointain")
@export var far_radius := 72.0
@export var far_tile := 10.0
@export var far_density := 14.0
@export var far_width := 0.13
@export_group("Herbe")
@export var blade_height := 0.48
@export var wind_strength := 0.22
@export_group("Masque")
## Zone couverte par le masque des constructions (monde, xz) et sa résolution.
@export var mask_rect := Rect2(-80, -80, 160, 160)
@export var mask_size := 512

var _near_mat: ShaderMaterial
var _far_mat: ShaderMaterial
var _near_tiles: Array[MeshInstance3D] = []
var _far_tiles: Array[MeshInstance3D] = []
var _near_offsets: Array[Vector2] = []
var _far_offsets: Array[Vector2] = []
var _near_cell := Vector2i(1 << 30, 0)
var _far_cell := Vector2i(1 << 30, 0)
var _viewport: SubViewport
var _canvas: Node2D
var _blockers: Array = []   # [Vector4(x, z, rx, rz), force]
var _mask_dirty := true


func _ready() -> void:
	_near_mat = _material(0.0, 0.0, near_radius, 5.0)
	_far_mat = _material(near_radius - 5.0, 5.0, far_radius, 14.0)
	_setup_mask()
	_near_mat.set_shader_parameter("mask", _viewport.get_texture())
	_far_mat.set_shader_parameter("mask", _viewport.get_texture())
	var near_mesh := build_tile(near_tile, near_density, near_width, 1)
	var far_mesh := build_tile(far_tile, far_density, far_width, 2)
	_near_offsets = _ring_offsets(near_tile, near_radius)
	_far_offsets = _ring_offsets(far_tile, far_radius)
	for o in _near_offsets:
		_near_tiles.append(_tile_node(near_mesh, _near_mat))
	for o in _far_offsets:
		_far_tiles.append(_tile_node(far_mesh, _far_mat))
	if terrain == null:
		terrain = BastideTerrain.find(self)
	if terrain:
		terrain.changed.connect(_bind_terrain)
		_bind_terrain()
	if site:
		site.structure_added.connect(func(_id: int) -> void: _mask_dirty = true)
		site.structure_changed.connect(func(_id: int) -> void: _mask_dirty = true)
		site.structure_removed.connect(func(_id: int) -> void: _mask_dirty = true)
	_process(0.0)


## Une zone où l'herbe ne pousse pas (un étang, un rocher…) : ellipse en monde.
func add_blocker(center: Vector3, radii: Vector2, strength := 1.0) -> void:
	_blockers.append([Vector4(center.x, center.z, radii.x, radii.y), strength])
	_mask_dirty = true


func _bind_terrain() -> void:
	# Un étang vient d'être creusé (ou comblé) : le masque change aussi.
	_mask_dirty = true
	if terrain == null or terrain.field == null:
		return
	var r := terrain.field.rect()
	for m in [_near_mat, _far_mat]:
		m.set_shader_parameter("height_tex", terrain.height_texture)
		m.set_shader_parameter("height_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))


func _process(_delta: float) -> void:
	var c := _center()
	_near_mat.set_shader_parameter("center", c)
	_far_mat.set_shader_parameter("center", c)
	if ground_material:
		ground_material.set_shader_parameter("grass_center", c)
		ground_material.set_shader_parameter("grass_far", far_radius)
	var nc := Vector2i(floori(c.x / near_tile), floori(c.z / near_tile))
	if nc != _near_cell:
		_near_cell = nc
		_place(_near_tiles, _near_offsets, nc, near_tile)
	var fc := Vector2i(floori(c.x / far_tile), floori(c.z / far_tile))
	if fc != _far_cell:
		_far_cell = fc
		_place(_far_tiles, _far_offsets, fc, far_tile)
	if _mask_dirty:
		_mask_dirty = false
		_canvas.queue_redraw()
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _center() -> Vector3:
	if camera is BastideOrbitCamera:
		return (camera as BastideOrbitCamera).target
	if camera:
		return camera.global_position
	return global_position


func _place(tiles: Array[MeshInstance3D], offsets: Array[Vector2], cell: Vector2i, size: float) -> void:
	for i in tiles.size():
		var o := offsets[i]
		tiles[i].global_position = Vector3((cell.x + o.x) * size, global_position.y, (cell.y + o.y) * size)


static func _ring_offsets(size: float, radius: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := ceili(radius / size) + 1
	for x in range(-n, n + 1):
		for z in range(-n, n + 1):
			# Coin de tuile le plus proche du centre de la case courante.
			var dx := maxf(0.0, absf(x + 0.5) - 1.0) * size
			var dz := maxf(0.0, absf(z + 0.5) - 1.0) * size
			if Vector2(dx, dz).length() < radius:
				out.append(Vector2(x, z))
	return out


func _tile_node(mesh: ArrayMesh, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 1.0
	add_child(mi)
	return mi


func _material(fade_in: float, fade_in_w: float, fade_out: float, fade_out_w: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("blade_height", blade_height)
	m.set_shader_parameter("wind_strength", wind_strength)
	m.set_shader_parameter("fade_in", fade_in)
	m.set_shader_parameter("fade_in_width", fade_in_w)
	m.set_shader_parameter("fade_out", fade_out)
	m.set_shader_parameter("fade_out_width", fade_out_w)
	m.set_shader_parameter("mask_rect", Vector4(mask_rect.position.x, mask_rect.position.y, mask_rect.size.x, mask_rect.size.y))
	return m


## Maillage d'une tuile carrée : des brins posés au hasard (graine fixe), chacun en
## deux segments effilés et une pointe, légèrement courbé. Hauteur de référence
## `blade_height` ; le shader la module.
func build_tile(size: float, density: float, width: float, seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 17
	var count := int(size * size * density)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(count * 5)
	normals.resize(count * 5)
	uvs.resize(count * 5)
	uv2s.resize(count * 5)
	idx.resize(count * 9)
	var h := blade_height
	for b in count:
		var root := Vector2(rng.randf() * size, rng.randf() * size)
		var ang := rng.randf() * TAU
		var side := Vector3(cos(ang), 0, sin(ang))
		var face := Vector3(-side.z, 0, side.x)
		var lean := face * rng.randf_range(0.05, 0.25)
		var w := width * rng.randf_range(0.7, 1.3)
		var base := Vector3(root.x, 0, root.y)
		var v := b * 5
		var levels := [0.0, 0.5]
		for l in 2:
			var t: float = levels[l]
			var c := base + Vector3(0, t * h, 0) + lean * t * t * h
			var ww := w * (1.0 - t * 0.55)
			verts[v + l * 2] = c - side * ww * 0.5
			verts[v + l * 2 + 1] = c + side * ww * 0.5
			uvs[v + l * 2] = Vector2(-1, t)
			uvs[v + l * 2 + 1] = Vector2(1, t)
		verts[v + 4] = base + Vector3(0, h, 0) + lean * h
		uvs[v + 4] = Vector2(0, 1)
		var n := (face + Vector3(0, 0.5, 0)).normalized()
		for k in 5:
			normals[v + k] = n
			uv2s[v + k] = root
		var i := b * 9
		idx[i] = v; idx[i + 1] = v + 1; idx[i + 2] = v + 2
		idx[i + 3] = v + 1; idx[i + 4] = v + 3; idx[i + 5] = v + 2
		idx[i + 6] = v + 2; idx[i + 7] = v + 3; idx[i + 8] = v + 4
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# Hauteur généreuse : le shader pose les brins sur le relief.
	mesh.custom_aabb = AABB(Vector3(-1, -30, -1), Vector3(size + 2, 80, size + 2))
	return mesh


# --- Masque des constructions ------------------------------------------------------

func _setup_mask() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(mask_size, mask_size)
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(mask_size, mask_size)
	_viewport.add_child(bg)
	_canvas = Node2D.new()
	_viewport.add_child(_canvas)
	_canvas.draw.connect(_draw_mask)


func _px(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.z) - mask_rect.position) / mask_rect.size * float(mask_size)


func _pxv(p: Vector2) -> Vector2:
	return (p - mask_rect.position) / mask_rect.size * float(mask_size)


func _draw_mask() -> void:
	var k := float(mask_size) / mask_rect.size.x   # pixels par mètre
	for b: Array in _blockers:
		var e: Vector4 = b[0]
		var pts := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0
			pts.append(_pxv(Vector2(e.x + cos(a) * e.z, e.y + sin(a) * e.w)))
		_canvas.draw_colored_polygon(pts, Color(1, 1, 1, float(b[1])))
	if site == null:
		return
	var xf := site.global_transform
	var ctx := site.context()
	for d: Dictionary in ctx.houses:
		_poly(d["footprint"], xf, 0.9, k)
	for d: Dictionary in ctx.terraces:
		_poly(d["footprint"], xf, 0.5, k)
	# Pas d'herbe dans l'eau, une berge plus rase autour.
	for d: Dictionary in ctx.ponds:
		_poly(d["footprint"], xf, 0.7, k)
	# Les champs ont leur propre terre.
	for d: Dictionary in ctx.farms:
		_poly(d["footprint"], xf, 0.25, k)
	for d: Dictionary in ctx.paths:
		_line(d["points"], xf, float(d["width"]) + 0.7, 1.0, k, false)
	for d: Dictionary in ctx.walls:
		_line(d["points"], xf, float(d["thickness"]), 0.6, k, bool(d["closed"]))
	for d: Dictionary in ctx.fences:
		_line(d["points"], xf, 0.25, 0.25, k, bool(d["closed"]))
	# Les forêts gardent une herbe plus rase sous les arbres.
	for id in site.ids():
		var rec: Dictionary = site.get_record(id)
		if String(rec.get("kind", "")) == "forest":
			var pts := PackedVector2Array()
			for p: Variant in rec.get("points", []):
				var v: Vector3 = p if p is Vector3 else Vector3(p[0], p[1], p[2])
				pts.append(_px(xf * v))
			if pts.size() >= 3:
				_canvas.draw_colored_polygon(pts, Color(1, 1, 1, 0.38))


func _poly(fp: PackedVector2Array, xf: Transform3D, grow: float, k: float) -> void:
	if fp.size() < 3:
		return
	var world := PackedVector2Array()
	for p in fp:
		world.append(_px(xf * Vector3(p.x, 0, p.y)))
	# Bord adouci : un liseré plus large et plus pâle, puis le cœur plein.
	var soft := PackedVector2Array(world)
	soft.append(world[0])
	_canvas.draw_polyline(soft, Color(1, 1, 1, 0.45), grow * 2.0 * k)
	_canvas.draw_colored_polygon(world, Color.WHITE)
	_canvas.draw_polyline(soft, Color.WHITE, grow * k)


func _line(pts: PackedVector3Array, xf: Transform3D, width: float, soft: float, k: float, closed: bool) -> void:
	if pts.size() < 2:
		return
	var line := PackedVector2Array()
	for p in pts:
		line.append(_px(xf * p))
	if closed:
		line.append(line[0])
	_canvas.draw_polyline(line, Color(1, 1, 1, 0.45), (width + soft * 2.0) * k)
	_canvas.draw_polyline(line, Color.WHITE, width * k)
	for p in line:
		_canvas.draw_circle(p, width * 0.5 * k, Color.WHITE)
