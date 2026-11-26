class_name BastideLife
extends Node3D
## La vie du hameau, sans rien à placer à la main :
## - la fumée monte des cheminées (ou des évents sous le faîtage d'une maison
##   japonaise) et part avec le vent ;
## - les lanternes de pierre des chemins sont allumées et vacillent doucement ;
## - quelques vols d'oiseaux tournent haut au-dessus du hameau ;
## - des papillons volettent au ras de l'herbe autour de la caméra.
## Les points de fumée et de lumière viennent des générations (anchors "smoke" et
## "lights", déjà posés sur le relief) : tout suit les constructions du joueur.

@export var site: BastideBuildSite
@export var camera: Camera3D
## Sens et force du vent (m/s) pour la fumée.
@export var wind := Vector3(0.7, 0.0, 0.3)
@export_group("Fumée")
@export var smoke_enabled := true
## Part des maisons dont le foyer fume (choix stable par maison).
@export_range(0.0, 1.0) var smoke_share := 0.85
@export var smoke_color := Color(0.88, 0.85, 0.8, 0.42)
@export_group("Lanternes")
@export var lanterns_enabled := true
@export var lantern_color := Color(1.0, 0.68, 0.36)
@export var lantern_energy := 1.8
@export var lantern_range := 5.0
## Au-delà, les lumières les plus lointaines de la caméra sont éteintes.
@export var max_lights := 16
@export_group("Oiseaux")
@export var bird_flocks := 2
@export var birds_per_flock := 6
@export var bird_height := Vector2(18.0, 30.0)
@export var bird_radius := 34.0
@export_group("Papillons")
@export var butterflies := 14
@export var butterfly_radius := 13.0
@export var butterfly_colors := PackedColorArray([Color(0.98, 0.96, 0.9), Color(0.98, 0.84, 0.36),
		Color(0.95, 0.56, 0.24), Color(0.7, 0.78, 0.98)])

const FLYER_SHADER := preload("res://addons/bastide/shaders/bastide_flyer.gdshader")

var _smokes := {}    # Vector3i (clé de position) → CPUParticles3D
var _lights: Array = []   # [{light: OmniLight3D, pos: Vector3, phase: float}]
var _light_keys := {}
var _birds: MultiMeshInstance3D
var _flocks: Array = []   # [{center, radius, height, speed, angle, offsets: Array[Vector3]}]
var _flies: MultiMeshInstance3D
var _fly_state: Array = []   # [{pos, vel, target, rest}]
var _rng := RandomNumberGenerator.new()
var _scan_timer := 0.0
var _signature := ""


func _ready() -> void:
	_rng.seed = 2207
	if site:
		site.structure_added.connect(_dirty.unbind(1))
		site.structure_changed.connect(_dirty.unbind(1))
		site.structure_removed.connect(_dirty.unbind(1))
	_make_birds()
	_make_butterflies()


func _dirty() -> void:
	_scan_timer = minf(_scan_timer, 0.4)


func _process(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 1.5
		_scan()
	_update_lights()
	_update_birds(delta)
	_update_butterflies(delta)


# --- Fumées et lanternes ---------------------------------------------------------

## Relit les points de vie de toutes les constructions ; ne recrée que ce qui change.
func _scan() -> void:
	if site == null:
		return
	var smoke_pts: Array = []
	var light_pts: Array = []
	for id in site.ids():
		var node := site.node_of(id)
		if node == null or node.last_anchors.is_empty():
			continue
		var xf := Transform3D(node.global_transform.basis.orthonormalized(), node.global_transform.origin)
		if smoke_enabled and node.last_anchors.get("smoke") is PackedVector3Array:
			# Une maison sur quatre environ a son feu éteint (choix stable).
			if _hash(id * 7919 + 13) < smoke_share:
				for p: Vector3 in node.last_anchors["smoke"]:
					smoke_pts.append(xf * p)
		if lanterns_enabled and node.last_anchors.get("lights") is PackedVector3Array:
			for p: Vector3 in node.last_anchors["lights"]:
				light_pts.append(xf * p)
	if site.garden and site.garden.last_anchors.get("lights") is PackedVector3Array:
		var gx := site.garden.global_transform
		for p: Vector3 in site.garden.last_anchors["lights"]:
			light_pts.append(gx * p)
	var sig := "%s|%s" % [smoke_pts, light_pts]
	if sig == _signature:
		return
	_signature = sig
	_sync_smokes(smoke_pts)
	_sync_lights(light_pts)


static func _key(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x * 10.0), roundi(p.y * 10.0), roundi(p.z * 10.0))


static func _hash(n: int) -> float:
	var h := (n * 374761393) ^ (n >> 13)
	h = (h * 1274126177) & 0x7fffffff
	return float(h % 10000) / 10000.0


func _sync_smokes(points: Array) -> void:
	var keep := {}
	for p: Vector3 in points:
		var k := _key(p)
		keep[k] = true
		if not _smokes.has(k):
			_smokes[k] = _make_smoke(p)
	for k: Vector3i in _smokes.keys():
		if not keep.has(k):
			(_smokes[k] as Node).queue_free()
			_smokes.erase(k)


func _make_smoke(p: Vector3) -> CPUParticles3D:
	var s := CPUParticles3D.new()
	s.name = "Fumee"
	s.amount = 34
	s.lifetime = 7.5
	s.preprocess = 7.5
	s.local_coords = false
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = 0.12
	s.direction = Vector3.UP
	s.spread = 8.0
	s.initial_velocity_min = 0.35
	s.initial_velocity_max = 0.6
	# Le vent emporte la fumée de plus en plus en montant.
	s.gravity = wind * 0.16 + Vector3(0, 0.03, 0)
	s.damping_min = 0.02
	s.damping_max = 0.05
	s.angle_min = 0.0
	s.angle_max = 360.0
	s.angular_velocity_min = -14.0
	s.angular_velocity_max = 14.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(0.4, 0.75))
	grow.add_point(Vector2(1.0, 1.6))
	s.scale_amount_curve = grow
	s.scale_amount_min = 0.9
	s.scale_amount_max = 1.3
	var ramp := Gradient.new()
	var c := smoke_color
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	ramp.colors = PackedColorArray([Color(c, 0.0), Color(c, c.a), Color(c.darkened(0.05), c.a * 0.55), Color(c, 0.0)])
	s.color_ramp = ramp
	s.mesh = _puff_mesh()
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)
	s.global_position = p
	return s


static var _puff: QuadMesh

static func _puff_mesh() -> QuadMesh:
	if _puff:
		return _puff
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	tex.gradient = g
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 0.6
	_puff = QuadMesh.new()
	_puff.size = Vector2(1.2, 1.2)
	_puff.material = mat
	return _puff


func _sync_lights(points: Array) -> void:
	var keep := {}
	for p: Vector3 in points:
		keep[_key(p)] = p
	var still: Array = []
	for l: Dictionary in _lights:
		if keep.has(_key(l["pos"])):
			still.append(l)
			keep.erase(_key(l["pos"]))
		else:
			(l["light"] as Node).queue_free()
	for k: Vector3i in keep:
		var p: Vector3 = keep[k]
		var o := OmniLight3D.new()
		o.name = "Lanterne"
		o.light_color = lantern_color
		o.light_energy = lantern_energy
		o.omni_range = lantern_range
		o.omni_attenuation = 1.4
		o.shadow_enabled = false
		o.light_specular = 0.2
		add_child(o)
		o.global_position = p
		still.append({"light": o, "pos": p, "phase": _rng.randf() * TAU})
	_lights = still


func _update_lights() -> void:
	if _lights.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	var eye := camera.global_position if camera else Vector3.ZERO
	# Seules les plus proches restent allumées (les autres gardent leur papier lumineux).
	var order := range(_lights.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return (_lights[a]["pos"] as Vector3).distance_squared_to(eye) < (_lights[b]["pos"] as Vector3).distance_squared_to(eye))
	for rank in order.size():
		var l: Dictionary = _lights[order[rank]]
		var o: OmniLight3D = l["light"]
		o.visible = rank < max_lights
		if o.visible:
			var ph: float = l["phase"]
			var f := 0.9 + 0.06 * sin(t * 7.3 + ph) + 0.04 * sin(t * 13.1 + ph * 2.0)
			o.light_energy = lantern_energy * f


# --- Oiseaux -------------------------------------------------------------------

func _flyer_mesh(span: float, length: float, wing_tip_back: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var root_f := Vector3(0.0, 0.0, -length * 0.5)
		var root_b := Vector3(0.0, 0.0, length * 0.5)
		var tip := Vector3(side * span * 0.5, 0.0, wing_tip_back)
		var mid := Vector3(side * span * 0.25, 0.0, -length * 0.35)
		for v in [root_f, mid, root_b, mid, tip, root_b]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


func _flyer_material(backlight: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FLYER_SHADER
	m.set_shader_parameter(&"backlight", backlight)
	return m


func _make_birds() -> void:
	var count := bird_flocks * birds_per_flock
	if count <= 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _flyer_mesh(0.9, 0.3, 0.12)
	mm.instance_count = count
	_birds = MultiMeshInstance3D.new()
	_birds.name = "Oiseaux"
	_birds.multimesh = mm
	_birds.material_override = _flyer_material(0.1)
	_birds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_birds.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 200, 400))
	add_child(_birds)
	for f in bird_flocks:
		var offsets: Array = []
		for i in birds_per_flock:
			# Vol en V lâche : chacun un peu en retrait et sur le côté du précédent.
			var side := 1.0 if i % 2 == 0 else -1.0
			var rank := float((i + 1) / 2)
			offsets.append(Vector3(side * rank * 1.3 + _rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.4, 0.4), rank * 1.5))
		_flocks.append({"center": Vector3(_rng.randf_range(-12, 12), 0, _rng.randf_range(-12, 12)),
			"radius": bird_radius * _rng.randf_range(0.7, 1.15),
			"height": _rng.randf_range(bird_height.x, bird_height.y),
			"speed": _rng.randf_range(0.11, 0.16) * (1.0 if f % 2 == 0 else -1.0),
			"angle": _rng.randf() * TAU, "offsets": offsets})
		for i in birds_per_flock:
			var k := f * birds_per_flock + i
			mm.set_instance_color(k, Color(0.16, 0.14, 0.13))
			mm.set_instance_custom_data(k, Color(_rng.randf(), _rng.randf_range(7.0, 9.0), 0.55, 0.0))


func _update_birds(delta: float) -> void:
	if _birds == null:
		return
	var mm := _birds.multimesh
	var t := Time.get_ticks_msec() / 1000.0
	for f in _flocks.size():
		var fl: Dictionary = _flocks[f]
		fl["angle"] = float(fl["angle"]) + float(fl["speed"]) * delta
		var a: float = fl["angle"]
		var r: float = float(fl["radius"]) * (1.0 + 0.15 * sin(a * 2.3))
		var c: Vector3 = fl["center"]
		var lead := c + Vector3(cos(a) * r, float(fl["height"]) + sin(a * 1.7) * 2.0, sin(a) * r)
		var dir := Vector3(-sin(a), 0.0, cos(a)) * signf(fl["speed"])
		var basis := Basis.looking_at(dir, Vector3.UP).rotated(dir, -0.25 * signf(fl["speed"]))
		for i in birds_per_flock:
			var k := f * birds_per_flock + i
			var off: Vector3 = fl["offsets"][i]
			var pos := lead + basis * Vector3(off.x, off.y + 0.3 * sin(t * 0.9 + i), off.z)
			mm.set_instance_transform(k, Transform3D(basis, pos))
			# Battements, puis de longs planés.
			var glide := smoothstep(0.2, 0.7, sin(t * 0.35 + f * 2.0 + i * 0.3))
			var cd := mm.get_instance_custom_data(k)
			cd.a = glide
			mm.set_instance_custom_data(k, cd)


# --- Papillons -------------------------------------------------------------------

func _make_butterflies() -> void:
	if butterflies <= 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _flyer_mesh(0.13, 0.05, 0.02)
	mm.instance_count = butterflies
	_flies = MultiMeshInstance3D.new()
	_flies.name = "Papillons"
	_flies.multimesh = mm
	_flies.material_override = _flyer_material(0.6)
	_flies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flies.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 200, 400))
	add_child(_flies)
	for i in butterflies:
		mm.set_instance_color(i, butterfly_colors[i % butterfly_colors.size()])
		mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf_range(14.0, 20.0), 1.1, 0.0))
		_fly_state.append({"pos": Vector3.INF, "vel": Vector3.ZERO, "target": Vector3.ZERO, "rest": 0.0})


func _ground_y(x: float, z: float) -> float:
	var field := BastideTerrain.field_for(self)
	return field.height(x, z) if field else 0.0


func _random_spot(around: Vector3) -> Vector3:
	var a := _rng.randf() * TAU
	var d := sqrt(_rng.randf()) * butterfly_radius
	var p := around + Vector3(cos(a) * d, 0.0, sin(a) * d)
	p.y = _ground_y(p.x, p.z) + _rng.randf_range(0.35, 1.4)
	return p


func _update_butterflies(delta: float) -> void:
	if _flies == null:
		return
	var mm := _flies.multimesh
	var focus := Vector3.ZERO
	if camera:
		var tgt: Variant = camera.get("target")
		focus = tgt if tgt is Vector3 else camera.global_position
	var t := Time.get_ticks_msec() / 1000.0
	for i in _fly_state.size():
		var s: Dictionary = _fly_state[i]
		var pos: Vector3 = s["pos"]
		if pos == Vector3.INF or Vector2(pos.x - focus.x, pos.z - focus.z).length() > butterfly_radius * 1.6:
			pos = _random_spot(focus)
			s["target"] = _random_spot(focus)
		var target: Vector3 = s["target"]
		if pos.distance_to(target) < 0.4:
			s["target"] = _random_spot(focus)
			target = s["target"]
		# Vol erratique : un cap vers la cible, plus des zigzags et des sautillements.
		var to := (target - pos).normalized()
		var wob := Vector3(sin(t * 3.1 + i * 1.7), sin(t * 4.3 + i) * 0.8, cos(t * 2.7 + i * 2.3))
		var vel: Vector3 = (s["vel"] as Vector3).lerp(to * 1.1 + wob * 0.7, clampf(delta * 2.5, 0.0, 1.0))
		pos += vel * delta
		var floor_y := _ground_y(pos.x, pos.z) + 0.25
		pos.y = maxf(pos.y, floor_y)
		s["pos"] = pos
		s["vel"] = vel
		var flat := Vector3(vel.x, 0.0, vel.z)
		var basis := Basis.looking_at(flat.normalized(), Vector3.UP) if flat.length() > 0.05 else Basis()
		mm.set_instance_transform(i, Transform3D(basis, pos))
