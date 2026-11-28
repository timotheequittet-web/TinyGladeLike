@tool
class_name BastideInteriorHost
extends RefCounted
## L'intérieur d'un BastideBuilding, créé à la demande et libéré dès qu'on s'éloigne.
##
## Tant qu'il est inactif, la maison ne coûte rien de plus : son maillage habituel
## (portes fermées, fond sombre) et sa collision pleine. Activé (promenade tout près,
## ou aperçu dans l'éditeur), il calcule sur un thread de fond :
## - la variante « on peut entrer » de la maison (passage dans la collision,
##   vantaux à part qui coulissent ou pivotent) ;
## - le plan de l'intérieur (BastideInteriorPlanner) et son maillage (BastideInteriorMesher) ;
## puis l'échange sur le fil principal et pose ses nœuds internes. Désactivé, il
## rend la maison d'origine et retire tout.

const INTERIOR_NAME := &"_BastideInterior"
const BODY_NAME := &"_BastideInteriorBody"
const LEAF_PREFIX := "_BastideDoorLeaf"
const LIGHT_PREFIX := "_BastideInteriorLight"

var building: BastideBuilding
## Voulu actif (le calcul peut être en cours).
var wanted := false
## Nœuds posés.
var built := false
var layout: BastideInteriorLayout
var _task := -1
var _gen := 0
var _closed_mesh: Mesh
var _closed_shape: Shape3D
var _lift := 0.0
var _leaves: Array = []   # [{node: MeshInstance3D, data: Dictionary}]
var _lights: Array = []   # [OmniLight3D]
var _doors: Array = []    # [Vector3 local, lift compris]
var _open := 0.0
var _lit := 0.0
## Ouverture forcée des portes (aperçu éditeur) ; < 0 : selon le promeneur.
var force_open := -1.0


func _init(b: BastideBuilding) -> void:
	building = b


func activate() -> void:
	if wanted:
		return
	wanted = true
	_start()


func deactivate() -> void:
	wanted = false
	_gen += 1
	if built:
		_restore()
	_clear_nodes()
	built = false
	layout = null


## La maison vient d'être regénérée : son maillage d'origine a changé, on refait l'intérieur.
func refresh() -> void:
	if not wanted:
		return
	_closed_mesh = null
	_closed_shape = null
	_clear_nodes()
	built = false
	_start()


func wait() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _start() -> void:
	if building == null or not building.is_inside_tree() or building.get_mesh_instance() == null:
		return
	_gen += 1
	var gen := _gen
	var spec := building.build_spec()
	var kind := BastideSilhouette.resolve(building.silhouette, spec.footprint, spec.seed)
	var st := BastideSilhouette.style_for(building.get_effective_style(), kind)
	st.prepare()
	var with_collision := building.generate_collision
	var ground_top := _ground_top(spec.footprint)
	var burrow := building.is_burrow()
	var job := func() -> Array:
		if burrow:
			# Terrier : la butte « ouverte » porte elle-même sa pièce voûtée.
			var br := BastideBurrowBuilder.build(spec, st, with_collision, true)
			if not br.anchors.has("interior_result"):
				return []
			return [br, br.anchors["interior_result"], br.anchors["interior_layout"]]
		var lay := BastideBuildingGenerator.generate(spec, st)
		if lay.is_empty():
			return []
		var ext := BastideBuildingMesher.build(lay, st, with_collision, true)
		var il := BastideInteriorPlanner.plan(lay, st, ground_top)
		var inr := BastideInteriorMesher.build(il, lay, st)
		return [ext, inr, il]
	var me := weakref(self)
	wait()
	_task = WorkerThreadPool.add_task(func() -> void:
		var out: Array = job.call()
		var host: Object = me.get_ref()
		if host:
			host.call_deferred(&"_finish", gen, out)
	, false, "Bastide : intérieur")


## Point le plus haut du terrain sous la maison, dans son repère (pose comprise) :
## les sols de l'intérieur restent au-dessus, même quand le sol bosse sous la maison.
func _ground_top(footprint: PackedVector2Array) -> float:
	var field := BastideTerrain.field_for(building)
	if field == null or footprint.size() < 3 or not building.last_stats.has("terrain_lift"):
		return -INF
	var lift := float(building.last_stats.get("terrain_lift", 0.0)) - 0.01
	var xf := building.global_transform
	var inv := xf.affine_inverse()
	var poly := BastidePolygon.ensure_direct(footprint)
	var box := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		box = box.expand(q)
	var step := 0.4
	var best := -INF
	var x := box.position.x + step * 0.5
	while x < box.end.x:
		var z := box.position.y + step * 0.5
		while z < box.end.y:
			if Geometry2D.is_point_in_polygon(Vector2(x, z), poly):
				var w := xf * Vector3(x, 0.0, z)
				best = maxf(best, (inv * Vector3(w.x, field.height(w.x, w.z), w.z)).y - lift)
			z += step
		x += step
	return best


func _finish(gen: int, out: Array) -> void:
	wait()
	if gen != _gen or not wanted or building == null or not building.is_inside_tree() or out.is_empty():
		return
	var ext: BastideBuildResult = out[0]
	var inr: BastideBuildResult = out[1]
	layout = out[2]
	_lift = float(building.last_stats.get("terrain_lift", 0.0))
	var field := building._drape_field() if building.is_burrow() else BastideTerrain.field_for(building)
	if field != null and building.last_stats.has("terrain_lift"):
		var xf := Transform3D(building.global_transform.basis.orthonormalized(), building.global_transform.origin)
		_lift = BastideDrape.apply(ext, field, xf, BastideDrape.Mode.RIGID, _lift - 0.01)
		ext.stats["terrain_lift"] = _lift
		BastideBuilding.add_door_steps(ext, field, xf, building.get_effective_style())
	var mi := building.get_mesh_instance()
	if mi == null:
		return
	if _closed_mesh == null:
		_closed_mesh = mi.mesh
	mi.mesh = ext.mesh
	var body := building.get_node_or_null(NodePath(BastideResultApplier.BODY_NAME)) as StaticBody3D
	if body and body.get_child_count(true) > 0 and not ext.collision_faces.is_empty():
		var cs := body.get_child(0, true) as CollisionShape3D
		if _closed_shape == null:
			_closed_shape = cs.shape
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(ext.collision_faces)
		cs.shape = shape

	var lifted := Transform3D(Basis.IDENTITY, Vector3(0.0, _lift, 0.0))
	var imi := MeshInstance3D.new()
	imi.name = INTERIOR_NAME
	imi.mesh = inr.mesh
	imi.transform = lifted
	# Dans une maison, l'intérieur n'a pas besoin de porter d'ombre : murs et toit le font.
	imi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	building.add_child(imi, false, Node.INTERNAL_MODE_BACK)
	if building.generate_collision and not inr.collision_faces.is_empty():
		var ib := StaticBody3D.new()
		ib.name = BODY_NAME
		ib.collision_layer = building.collision_layer
		ib.transform = lifted
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(inr.collision_faces)
		cs.shape = shape
		ib.add_child(cs)
		building.add_child(ib, false, Node.INTERNAL_MODE_BACK)
	var i := 0
	for d: Dictionary in ext.anchors.get("door_leaves", []):
		var leaf := MeshInstance3D.new()
		leaf.name = "%s%d" % [LEAF_PREFIX, i]
		leaf.mesh = d["mesh"]
		leaf.transform = lifted
		building.add_child(leaf, false, Node.INTERNAL_MODE_BACK)
		_leaves.append({"node": leaf, "data": d})
		i += 1
	_doors.clear()
	for d: Dictionary in ext.anchors.get("doors", []):
		_doors.append((d["pos"] as Vector3) + Vector3(0.0, _lift, 0.0))
	i = 0
	for p: Vector3 in inr.anchors.get("lights", PackedVector3Array()):
		var l := OmniLight3D.new()
		l.name = "%s%d" % [LIGHT_PREFIX, i]
		l.position = p + Vector3(0.0, _lift, 0.0)
		l.light_color = Color(1.0, 0.8, 0.58)
		l.omni_range = 7.0
		l.omni_attenuation = 0.9
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		building.add_child(l, false, Node.INTERNAL_MODE_BACK)
		_lights.append(l)
		i += 1
	built = true
	building._apply_look()
	_place_leaves()
	building.interior_ready.emit()


func _restore() -> void:
	var mi := building.get_mesh_instance() if building else null
	if mi and _closed_mesh:
		mi.mesh = _closed_mesh
	var body := building.get_node_or_null(NodePath(BastideResultApplier.BODY_NAME)) if building else null
	if body and _closed_shape and body.get_child_count(true) > 0:
		(body.get_child(0, true) as CollisionShape3D).shape = _closed_shape
	_closed_mesh = null
	_closed_shape = null


func _clear_nodes() -> void:
	if building == null:
		return
	for c in building.get_children(true):
		var n := String(c.name)
		if n == INTERIOR_NAME or n == BODY_NAME or n.begins_with(LEAF_PREFIX) or n.begins_with(LIGHT_PREFIX):
			c.name = "_old%d" % c.get_instance_id()
			c.queue_free()
	_leaves.clear()
	_lights.clear()
	_doors.clear()
	_open = 0.0
	_lit = 0.0


## Portes et lumière selon la position du promeneur (espace local de la maison).
func update(local: Vector3, delta: float) -> void:
	if not built:
		return
	var want := 0.0
	for d: Vector3 in _doors:
		var flat := Vector2(local.x - d.x, local.z - d.z).length()
		if flat < BastideInteriors.DOOR_DISTANCE and absf(local.y - d.y) < 2.5:
			want = 1.0
	if force_open >= 0.0:
		want = force_open
	var k := 1.0 - exp(-5.0 * delta)
	var before := _open
	_open = move_toward(_open, want, delta * 1.6) if absf(want - _open) > 0.5 else lerpf(_open, want, k)
	if absf(_open - want) < 0.002:
		_open = want
	if _open != before:
		_place_leaves()
	var inside := layout != null and layout.contains(Vector2(local.x, local.z))
	var goal := 1.0 if inside else 0.0
	_lit = move_toward(_lit, goal, delta * 1.5)
	for l: OmniLight3D in _lights:
		l.visible = _lit > 0.01
		l.light_energy = 0.55 * _lit


func _place_leaves() -> void:
	var t := smoothstep(0.0, 1.0, _open)
	for e: Dictionary in _leaves:
		var node: MeshInstance3D = e["node"]
		var d: Dictionary = e["data"]
		var lift := Vector3(0.0, _lift, 0.0)
		if d["kind"] == "slide":
			node.position = lift + (d["slide"] as Vector3) * t
		else:
			var pivot: Vector3 = d["pivot"]
			var rot := Basis(Vector3.UP, float(d["angle"]) * t)
			node.transform = Transform3D(rot, lift + pivot - rot * pivot)


func doors_open() -> float:
	return _open
