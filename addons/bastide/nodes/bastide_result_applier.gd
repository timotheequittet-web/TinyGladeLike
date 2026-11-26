@tool
class_name BastideResultApplier
extends RefCounted
## Pose un BastideBuildResult sous un nœud hôte : un MeshInstance3D et, si demandé,
## un StaticBody3D avec une forme de collision concave.
##
## Les nœuds créés sont « internes » et sans propriétaire : ils n'apparaissent pas dans
## l'arbre de scène de l'éditeur et ne sont pas enregistrés dans le .tscn. La scène
## ne stocke donc que le tracé, le style et la seed ; tout est régénéré au chargement.

const MESH_NAME := &"_BastideMesh"
const BODY_NAME := &"_BastideBody"
const MULTI_PREFIX := "_BastideMulti"


static func apply(host: Node3D, result: BastideBuildResult, with_collision: bool, collision_layer := 1) -> void:
	var mi := host.get_node_or_null(NodePath(MESH_NAME)) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = MESH_NAME
		host.add_child(mi, false, Node.INTERNAL_MODE_BACK)
	mi.mesh = result.mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_apply_instances(host, result.instances)

	var body := host.get_node_or_null(NodePath(BODY_NAME)) as StaticBody3D
	if not with_collision or result.collision_faces.is_empty():
		if body:
			body.queue_free()
		return
	if body == null:
		body = StaticBody3D.new()
		body.name = BODY_NAME
		host.add_child(body, false, Node.INTERNAL_MODE_BACK)
		var cs := CollisionShape3D.new()
		cs.name = &"Shape"
		body.add_child(cs, false, Node.INTERNAL_MODE_BACK)
	body.collision_layer = collision_layer
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(result.collision_faces)
	(body.get_child(0, true) as CollisionShape3D).shape = shape


static func clear(host: Node3D) -> void:
	for n in [MESH_NAME, BODY_NAME]:
		var node := host.get_node_or_null(NodePath(n))
		if node:
			node.queue_free()
	_apply_instances(host, [])


## Groupes d'instances (arbres d'une forêt) : un MultiMeshInstance3D interne par groupe,
## réutilisés d'une génération à l'autre ; ceux en trop sont retirés.
static func _apply_instances(host: Node3D, groups: Array) -> void:
	var i := 0
	for g: Dictionary in groups:
		var name := NodePath("%s%d" % [MULTI_PREFIX, i])
		var mmi := host.get_node_or_null(name) as MultiMeshInstance3D
		if mmi == null:
			mmi = MultiMeshInstance3D.new()
			mmi.name = String(name)
			host.add_child(mmi, false, Node.INTERNAL_MODE_BACK)
		var transforms: Array = g["transforms"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		# Données par instance lues par le shader (carpes qui nagent…).
		var custom: Array = g.get("custom", [])
		mm.use_custom_data = custom.size() == transforms.size() and not custom.is_empty()
		mm.mesh = g["mesh"]
		mm.instance_count = transforms.size()
		for k in transforms.size():
			mm.set_instance_transform(k, transforms[k])
			if mm.use_custom_data:
				mm.set_instance_custom_data(k, custom[k])
		mmi.multimesh = mm
		mmi.material_override = g["material"]
		mmi.cast_shadow = g["shadow"]
		mmi.set_meta(&"cast", g["shadow"])
		mmi.visibility_range_begin = g["vis_begin"]
		mmi.visibility_range_end = g["vis_end"]
		mmi.visibility_range_end_margin = 6.0 if float(g["vis_end"]) > 0.0 else 0.0
		mmi.visibility_range_begin_margin = 6.0 if float(g["vis_begin"]) > 0.0 else 0.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if float(g["vis_end"]) > 0.0 or float(g["vis_begin"]) > 0.0 \
				else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		i += 1
	while true:
		var extra := host.get_node_or_null(NodePath("%s%d" % [MULTI_PREFIX, i]))
		if extra == null:
			break
		extra.name = "_old%d" % extra.get_instance_id()
		extra.queue_free()
		i += 1


## Tous les maillages posés par l'applicateur (le principal et les groupes d'instances).
static func geometry(host: Node3D) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for c in host.get_children(true):
		if c is GeometryInstance3D and (c.name == MESH_NAME or String(c.name).begins_with(MULTI_PREFIX)):
			out.append(c)
	return out
