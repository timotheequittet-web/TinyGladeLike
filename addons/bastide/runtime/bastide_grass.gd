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
##
## Niveaux de détail : chaque brin a un rang (0..1). Plus la caméra est loin, moins
## on garde de brins (les autres se couchent dans le shader) et plus les brins
## restants s'élargissent pour couvrir le sol. Chaque tuile choisit aussi, selon sa
## distance, un maillage qui ne contient que les premiers brins (LEVELS) : les
## brins couchés ne coûtent alors plus rien. Au-delà de `hide_distance`, l'herbe
## disparaît et le sol (assombri à sa place) prend le relais.

const SHADER := preload("res://addons/bastide/shaders/bastide_grass.gdshader")

enum Style { PEINTE, NATURELLE }
const STYLE_NAMES := ["peinte", "naturelle"]

## Style de l'herbe : « peinte » (touffes vert vif façon dessin animé, même teinte
## que le sol, ombres de nuages) ou « naturelle » (brins dorés de fin de journée).
@export var style := Style.PEINTE:
	set(v):
		if v == style:
			return
		style = v
		if is_inside_tree() and _viewport:
			_build_rings()
			_bind_terrain()
			_process(0.0)
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
@export var near_radius := 26.0
@export var near_tile := 6.0
@export var near_density := 20.0       # brins par m² (peu de brins, mais larges : façon BotW)
@export var near_width := 0.12
@export_group("Anneau lointain")
@export var far_radius := 46.0
@export var far_tile := 14.0
@export var far_density := 3.5
@export var far_width := 0.3
@export_group("Niveaux de détail")
## Distance (m) jusqu'à laquelle l'anneau proche garde tous ses brins.
@export var near_lod_distance := 22.0
## Idem pour l'anneau lointain (ses brins sont déjà plus larges et clairsemés).
@export var far_lod_distance := 50.0
## Part minimale de brins gardés, aussi loin que soit la caméra.
@export_range(0.0, 1.0) var min_keep := 0.06
## Au-delà de cette distance caméra → centre suivi, plus d'herbe du tout.
@export var hide_distance := 120.0
## Multiplicateurs donnés par les réglages graphiques (voir BastideGraphics).
@export var density_scale := 1.0
@export var radius_scale := 1.0
@export_group("Herbe")
@export var blade_height := 0.62
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
var _near_meshes: Array[ArrayMesh] = []
var _far_meshes: Array[ArrayMesh] = []
var _lod_timer := 0.0

## Parts de brins des maillages successifs d'une tuile (préfixes du même tirage).
## Sommets et indices d'un brin : trois paires de bords et une pointe (5 triangles).
const BLADE_V := 7
const BLADE_I := 15
const LEVELS := [1.0, 0.5, 0.25, 0.125, 0.0625, 0.0]


func _ready() -> void:
	_setup_mask()
	_build_rings()
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


## Change densité et étendue (réglages graphiques) : les tuiles sont refaites.
func set_quality(density: float, radius: float) -> void:
	if is_equal_approx(density, density_scale) and is_equal_approx(radius, radius_scale) and not _near_tiles.is_empty():
		return
	density_scale = density
	radius_scale = radius
	if is_inside_tree() and _viewport:
		_build_rings()
		_bind_terrain()
		_process(0.0)


func _build_rings() -> void:
	for t in _near_tiles + _far_tiles:
		t.queue_free()
	_near_tiles.clear()
	_far_tiles.clear()
	var nr := near_radius * radius_scale
	var fr := far_radius * radius_scale
	_near_mat = _material(0.0, 0.0, nr, 5.0, near_lod_distance * sqrt(density_scale), near_width)
	_far_mat = _material(nr - 5.0, 5.0, fr, 14.0, far_lod_distance * sqrt(density_scale), far_width)
	if ground_material:
		ground_material.set_shader_parameter("painted", 1.0 if style == Style.PEINTE else 0.0)
	_near_mat.set_shader_parameter("mask", _viewport.get_texture())
	_far_mat.set_shader_parameter("mask", _viewport.get_texture())
	# Style peint : plus de brins, plus larges, pour un tapis sans trou.
	var pd := 1.7 if style == Style.PEINTE else 1.0
	var pw := 1.25 if style == Style.PEINTE else 1.0
	_near_meshes = build_tile_levels(near_tile, near_density * pd * minf(density_scale, 1.0), near_width * pw, 1)
	_far_meshes = build_tile_levels(far_tile, far_density * pd * minf(density_scale, 1.0), far_width * pw, 2)
	_near_offsets = _ring_offsets(near_tile, nr)
	_far_offsets = _ring_offsets(far_tile, fr)
	for o in _near_offsets:
		_near_tiles.append(_tile_node(_near_meshes[0], _near_mat))
	for o in _far_offsets:
		_far_tiles.append(_tile_node(_far_meshes[0], _far_mat))
	_near_cell = Vector2i(1 << 30, 0)
	_far_cell = Vector2i(1 << 30, 0)


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
	for m: ShaderMaterial in [_near_mat, _far_mat]:
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
		_lod_timer = 0.0
	var fc := Vector2i(floori(c.x / far_tile), floori(c.z / far_tile))
	if fc != _far_cell:
		_far_cell = fc
		_place(_far_tiles, _far_offsets, fc, far_tile)
		_lod_timer = 0.0
	_lod_timer -= _delta
	if _lod_timer <= 0.0 or nc != _near_cell or fc != _far_cell:
		_lod_timer = 0.15
		_update_lods(c)
	if _mask_dirty:
		_mask_dirty = false
		_canvas.queue_redraw()
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Chaque tuile prend le plus petit maillage qui contient encore tous les brins que
## le shader garde à sa distance (calcul identique à celui du shader, au point de
## la tuile le plus proche de la caméra).
func _update_lods(c: Vector3) -> void:
	var eye := _eye()
	var hidden := eye.distance_to(c) > hide_distance
	visible_tiles(_near_tiles, _near_meshes, near_tile, near_lod_distance * sqrt(density_scale), eye, hidden)
	visible_tiles(_far_tiles, _far_meshes, far_tile, far_lod_distance * sqrt(density_scale), eye, hidden)
	if ground_material:
		ground_material.set_shader_parameter("grass_far", 0.0 if hidden else far_radius * radius_scale)


func visible_tiles(tiles: Array[MeshInstance3D], meshes: Array[ArrayMesh], size: float, d0: float, eye: Vector3, hidden: bool) -> void:
	for t in tiles:
		if hidden:
			t.visible = false
			continue
		var p := t.global_position
		var q := Vector3(clampf(eye.x, p.x, p.x + size), p.y, clampf(eye.z, p.z, p.z + size))
		if terrain and terrain.field:
			q.y = terrain.field.height(q.x, q.z)
		var keep := keep_at(q.distance_to(eye), d0)
		var level := 0
		for i in LEVELS.size():
			if float(LEVELS[i]) >= keep:
				level = i
		t.visible = float(LEVELS[level]) > 0.0
		if t.visible and t.mesh != meshes[level]:
			t.mesh = meshes[level]


## Part de brins gardés à une distance donnée (même formule que le shader).
func keep_at(dist: float, d0: float) -> float:
	return clampf(pow(d0 / maxf(dist, 0.01), 1.5), min_keep, 1.0)


func _eye() -> Vector3:
	if camera:
		return camera.global_position
	return global_position + Vector3(0, 20, 0)


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


func _material(fade_in: float, fade_in_w: float, fade_out: float, fade_out_w: float, lod_d0: float, width: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("lod_d0", lod_d0)
	m.set_shader_parameter("lod_min", min_keep)
	m.set_shader_parameter("blade_width", width)
	m.set_shader_parameter("blade_height", blade_height)
	m.set_shader_parameter("wind_strength", wind_strength)
	m.set_shader_parameter("fade_in", fade_in)
	m.set_shader_parameter("fade_in_width", fade_in_w)
	m.set_shader_parameter("fade_out", fade_out)
	m.set_shader_parameter("fade_out_width", fade_out_w)
	m.set_shader_parameter("mask_rect", Vector4(mask_rect.position.x, mask_rect.position.y, mask_rect.size.x, mask_rect.size.y))
	m.set_shader_parameter("painted", 1.0 if style == Style.PEINTE else 0.0)
	if style == Style.PEINTE:
		m.set_shader_parameter("blade_height", blade_height * 1.15)
		m.set_shader_parameter("wind_strength", wind_strength * 1.4)
	return m


## Les maillages d'une tuile, du plus complet au plus léger (voir LEVELS) : mêmes
## sommets, seuls les premiers brins (rang le plus bas) sont gardés.
func build_tile_levels(size: float, density: float, width: float, seed: int) -> Array[ArrayMesh]:
	var full := build_tile(size, density, width, seed)
	var out: Array[ArrayMesh] = [full]
	var arr := full.surface_get_arrays(0)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var blades := idx.size() / BLADE_I
	for i in range(1, LEVELS.size()):
		var n := int(ceil(blades * float(LEVELS[i])))
		if n <= 0:
			out.append(full)   # tuile cachée, maillage sans importance
			continue
		var a := arr.duplicate()
		a[Mesh.ARRAY_INDEX] = idx.slice(0, n * BLADE_I)
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		m.custom_aabb = full.custom_aabb
		out.append(m)
	return out


## Maillage d'une tuile carrée : des brins posés au hasard (graine fixe), chacun en
## deux segments effilés et une pointe, légèrement courbé. Hauteur de référence
## `blade_height` ; le shader la module. Le rang du brin (ordre de tirage, 0..1)
## est rangé dans COLOR.r : les niveaux de détail gardent les premiers.
func build_tile(size: float, density: float, width: float, seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 17
	var count := int(size * size * density)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	cols.resize(count * BLADE_V)
	verts.resize(count * BLADE_V)
	normals.resize(count * BLADE_V)
	uvs.resize(count * BLADE_V)
	uv2s.resize(count * BLADE_V)
	idx.resize(count * BLADE_I)
	var h := blade_height
	var levels := [0.0, 0.4, 0.75]
	# Style peint : les brins poussent en touffes de 3 à 6 qui s'ouvrent en éventail,
	# plus pointus. Les touffes sont tirées dans le désordre pour que les niveaux de
	# détail (qui gardent les premiers brins) gardent des brins partout.
	var painted := style == Style.PEINTE
	var tufts := PackedVector2Array()
	if painted:
		var nt := maxi(1, count / 4)
		for k in nt:
			tufts.append(Vector2(rng.randf() * size, rng.randf() * size))
	var taper := 0.82 if painted else 0.6
	for b in count:
		var root := Vector2(rng.randf() * size, rng.randf() * size)
		var ang := rng.randf() * TAU
		var spread := rng.randf_range(0.12, 0.42)
		if painted:
			var tc := tufts[rng.randi() % tufts.size()]
			var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 0.09)
			root = (tc + off).posmod(size)
			# La pointe part vers l'extérieur de la touffe.
			var out_a := off.angle() if off.length() > 0.01 else rng.randf() * TAU
			ang = out_a - PI * 0.5 + rng.randf_range(-0.5, 0.5)
			spread = rng.randf_range(0.3, 0.7)
		var side := Vector3(cos(ang), 0, sin(ang))
		var face := Vector3(-side.z, 0, side.x)
		# Brins longs et courbés (façon BotW) : la pointe part loin du pied.
		var lean := face * spread
		var w := width * rng.randf_range(0.7, 1.3)
		var base := Vector3(root.x, 0, root.y)
		var v := b * BLADE_V
		for l in levels.size():
			var t: float = levels[l]
			var c := base + Vector3(0, t * h, 0) + lean * t * t * h
			var ww := w * (1.0 - t * taper)
			verts[v + l * 2] = c - side * ww * 0.5
			verts[v + l * 2 + 1] = c + side * ww * 0.5
			uvs[v + l * 2] = Vector2(-1, t)
			uvs[v + l * 2 + 1] = Vector2(1, t)
		verts[v + 6] = base + Vector3(0, h, 0) + lean * h
		uvs[v + 6] = Vector2(0, 1)
		var n := (face + Vector3(0, 0.5, 0)).normalized()
		var rank := Color((b + 0.5) / float(count), 0, 0, 1)
		for k in BLADE_V:
			normals[v + k] = n
			uv2s[v + k] = root
			cols[v + k] = rank
		var i := b * BLADE_I
		for q in 2:
			var o := v + q * 2
			idx[i] = o; idx[i + 1] = o + 1; idx[i + 2] = o + 2
			idx[i + 3] = o + 1; idx[i + 4] = o + 3; idx[i + 5] = o + 2
			i += 6
		idx[i] = v + 4; idx[i + 1] = v + 5; idx[i + 2] = v + 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_COLOR] = cols
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
