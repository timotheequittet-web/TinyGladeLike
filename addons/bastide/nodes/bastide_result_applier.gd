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


static func apply(host: Node3D, result: BastideBuildResult, with_collision: bool, collision_layer := 1) -> void:
	var mi := host.get_node_or_null(NodePath(MESH_NAME)) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = MESH_NAME
		host.add_child(mi, false, Node.INTERNAL_MODE_BACK)
	mi.mesh = result.mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

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
