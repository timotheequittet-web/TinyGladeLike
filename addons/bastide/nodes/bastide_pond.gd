@tool
@icon("res://addons/bastide/editor/icons/bastide_garden.svg")
class_name BastidePond
extends BastideStructure
## Jardin d'eau dans le contour fermé de sa courbe : la rive est arrondie toute
## seule, le sol est creusé dans le relief (BastideTerrain), l'eau reste à plat même
## sur une pente (petite digue côté bas). Rochers, galets, iris, nénuphars, koï ;
## un chemin qui traverse l'eau reçoit un pont, une passerelle ou des pierres de gué.
##
## Trois sortes : étang de jardin, source chaude (onsen, eau laiteuse et vapeur),
## mare sauvage (roseaux, nénuphars).
## En jeu : set_footprint() avec le contour.

## Sorte d'étang.
@export var pond_kind: BastidePondBuilder.Kind = BastidePondBuilder.Kind.GARDEN:
	set(value):
		pond_kind = value
		queue_rebuild()

var _points_override := PackedVector3Array()
var _use_override := false
var _carve_key := 0
var _steam: CPUParticles3D


## Les étangs se calent sur les maisons, terrasses et chemins (ponts) ; clôtures,
## massifs, forêts et jardin les évitent ensuite.
func context_level() -> int:
	return LEVEL_WALL


func uses_context() -> bool:
	return true


## L'étang est posé à la main sur le relief (niveau d'eau, fond creusé).
func terrain_mode() -> int:
	return BastideDrape.Mode.NONE


func _default_curve() -> Curve3D:
	var c := Curve3D.new()
	for p in [Vector3(-5, 0, -3), Vector3(1, 0, -4.5), Vector3(6, 0, -1), Vector3(4, 0, 4), Vector3(-2, 0, 3.5), Vector3(-6, 0, 1)]:
		c.add_point(p)
	c.closed = true
	return c


func set_footprint(points: PackedVector3Array) -> void:
	_points_override = points
	_use_override = true
	queue_rebuild()


func clear_footprint() -> void:
	_use_override = false
	queue_rebuild()


func get_points() -> PackedVector3Array:
	if _use_override:
		return _points_override
	var out := PackedVector3Array()
	if curve:
		for i in curve.point_count:
			out.append(curve.get_point_position(i))
	return out


func _make_job() -> Callable:
	var pts := get_points()
	var ctx := gather_context()
	var s := seed
	var k := int(pond_kind)
	var st := get_effective_style()
	var col := generate_collision
	var terrain := BastideTerrain.find(self)
	# Le sol d'origine (sans étang) : le niveau d'eau ne dépend pas de l'étang lui-même.
	var field := terrain.base_field if terrain else null
	var xf := Transform3D(global_transform.basis.orthonormalized(), global_transform.origin) if is_inside_tree() else Transform3D.IDENTITY
	return func() -> BastideBuildResult: return BastidePondBuilder.build(pts, s, k, st, ctx, field, xf, col)


func _apply(result: BastideBuildResult) -> void:
	super(result)
	_update_carve(result)
	_update_steam(result)


## Creuse le relief sous l'eau (à la frame suivante, voir BastideTerrain.set_carve).
func _update_carve(result: BastideBuildResult) -> void:
	var terrain := BastideTerrain.find(self)
	if terrain == null:
		return
	if _carve_key == 0:
		_carve_key = get_instance_id()
	var carve: Variant = result.anchors.get("carve") if result else null
	if carve == null or not context_enabled and mesh_transparency > 0.0:
		terrain.clear_carve(_carve_key)
		return
	terrain.set_carve(_carve_key, carve)


func _update_steam(result: BastideBuildResult) -> void:
	var pts: PackedVector3Array = result.anchors.get("steam", PackedVector3Array()) if result else PackedVector3Array()
	if pts.is_empty():
		if _steam:
			_steam.queue_free()
			_steam = null
		return
	if _steam == null:
		_steam = CPUParticles3D.new()
		_steam.name = "_Vapeur"
		add_child(_steam, false, Node.INTERNAL_MODE_BACK)
		_steam.amount = 140
		_steam.lifetime = 7.0
		_steam.preprocess = 7.0
		_steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
		_steam.direction = Vector3.UP
		_steam.spread = 25.0
		_steam.gravity = Vector3(0.12, 0.18, 0.05)
		_steam.initial_velocity_min = 0.08
		_steam.initial_velocity_max = 0.25
		_steam.damping_min = 0.02
		_steam.damping_max = 0.08
		_steam.scale_amount_min = 1.6
		_steam.scale_amount_max = 3.2
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.5))
		curve.add_point(Vector2(0.5, 1.2))
		curve.add_point(Vector2(1, 2.2))
		_steam.scale_amount_curve = curve
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0.0))
		grad.add_point(0.3, Color(0.96, 0.97, 0.98, 0.07))
		grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0.0))
		_steam.color_ramp = grad
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = _soft_dot()
		mat.disable_receive_shadows = true
		quad.material = mat
		_steam.mesh = quad
		_steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_steam.emission_points = pts
	_steam.emitting = true


static func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _exit_tree() -> void:
	var terrain := BastideTerrain.find(self)
	if terrain and _carve_key != 0:
		terrain.clear_carve(_carve_key)
	super()


## Pour les voisins : la rive (monde, y = niveau de l'eau).
func describe() -> Dictionary:
	var shore: Variant = last_anchors.get("shore")
	if shore == null:
		return {}
	var level: float = last_anchors.get("level", 0.0)
	var pts := PackedVector3Array()
	for p: Vector2 in shore:
		pts.append(Vector3(p.x, level, p.y))
	return {"kind": "pond", "footprint": _to_world(pts), "pond_kind": int(pond_kind)}
