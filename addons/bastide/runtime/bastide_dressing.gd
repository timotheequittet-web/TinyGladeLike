class_name BastideDressing
extends Node3D
## Habille les maisons du chantier (voir BastideHouseDressing) : lanternes de papier,
## lierre, pots et bonsaïs, jardinières, fougères et buissons à baies, caisses,
## paniers, sandales, bannières. Seulement aux niveaux graphiques Haut et Ultra
## (BastideGraphics.detail >= `min_detail`), et chaque maison n'est habillée que
## jusqu'à `visible_distance` (× le niveau de détail) de la caméra.
##
## L'habillage d'une maison est refait quand elle change ; il est calculé sur le
## fil principal (quelques millisecondes), une maison par image au plus.

@export var site: BastideBuildSite
## Distance d'affichage de l'habillage (m), multipliée par BastideGraphics.detail.
@export var visible_distance := 70.0
## Niveau de détail minimal (1 = Haut) pour habiller les maisons.
@export var min_detail := 0.99

const PROPS_KEY := &"bastide_dressing"

## Les lanternes habillées ont changé (voir light_points).
signal lights_changed

var _hosts := {}       # id → Node3D
var _lights := {}      # id → PackedVector3Array (monde)
var _pending := {}     # id → true
var _watched := {}     # id → true (signal rebuilt branché)
var _props_mat: StandardMaterial3D
var _paper_mat: StandardMaterial3D
var _cloth_mat: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	if site:
		site.structure_added.connect(_mark)
		site.structure_changed.connect(_mark)
		site.structure_removed.connect(_remove)
		for id in site.ids():
			_mark(id)


func _mark(id: int) -> void:
	var node := site.node_of(id) if site else null
	if not node is BastideBuilding:
		return
	# Chaque nouvelle génération de la maison refait son habillage.
	if not _watched.has(id):
		_watched[id] = true
		node.rebuilt.connect(_on_rebuilt.bind(id))
	if not node.last_anchors.is_empty():
		_pending[id] = true


func _on_rebuilt(_stats: Dictionary, id: int) -> void:
	_pending[id] = true


func _remove(id: int) -> void:
	_pending.erase(id)
	_watched.erase(id)
	if _hosts.has(id):
		(_hosts[id] as Node).queue_free()
		_hosts.erase(id)
	if _lights.erase(id):
		lights_changed.emit()


## Centres (monde) des lanternes de papier des maisons habillées ; rien quand
## l'habillage est masqué (niveaux Bas et Moyen).
func light_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	if not visible:
		return out
	for id: int in _lights:
		out.append_array(_lights[id])
	return out


func _process(_delta: float) -> void:
	visible = BastideGraphics.detail >= min_detail
	if not visible or _pending.is_empty() or site == null:
		return
	# Une maison par image : pas d'à-coup quand tout le hameau se construit.
	for id: int in _pending.keys():
		var node := site.node_of(id)
		if node == null:
			_pending.erase(id)
			continue
		if not node is BastideBuilding or node.last_anchors.is_empty():
			_pending.erase(id)
			continue
		_pending.erase(id)
		_dress(id, node)
		return


func _dress(id: int, node: BastideStructure) -> void:
	if _hosts.has(id):
		(_hosts[id] as Node).queue_free()
		_hosts.erase(id)
	var res := BastideHouseDressing.build(node.last_anchors, node.seed)
	if res.is_empty():
		return
	var host := Node3D.new()
	host.name = "Habillage_%d" % id
	add_child(host)
	# Même repère que la maison, posée sur le relief comme elle (hauteur de pose).
	var lift: float = node.last_stats.get("terrain_lift", 0.0)
	host.global_transform = Transform3D(node.global_transform.basis.orthonormalized(), node.global_transform.origin + Vector3(0, lift, 0))
	var range_end := visible_distance
	_mesh(host, res["props"], _props_mat, range_end)
	_mesh(host, res["paper"], _paper_mat, range_end)
	_mesh(host, res["cloth"], _cloth_mat, range_end)
	for k in ["ivy", "berries"]:
		if res.has(k) and res[k]["mesh"] != null:
			_mesh(host, res[k]["mesh"], res[k]["mat"], range_end)
	for g: Dictionary in res["plants"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g["mesh"]
		var xfs: Array = g["xf"]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = g["mat"]
		_setup(mmi, range_end)
		host.add_child(mmi)
	_hosts[id] = host
	var pts := PackedVector3Array()
	for p: Vector3 in res.get("lights", PackedVector3Array()):
		pts.append(host.global_transform * p)
	_lights[id] = pts
	lights_changed.emit()
	BastideGraphics.scale_ranges(host)


func _mesh(host: Node3D, mesh: Mesh, mat: Material, range_end: float) -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	_setup(mi, range_end)
	host.add_child(mi)


func _setup(g: GeometryInstance3D, range_end: float) -> void:
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.visibility_range_end = range_end
	g.visibility_range_end_margin = 8.0
	g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _make_materials() -> void:
	_props_mat = StandardMaterial3D.new()
	_props_mat.vertex_color_use_as_albedo = true
	_props_mat.roughness = 0.85
	_props_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Papier des lanternes : laisse passer la lumière, et luit doucement de l'intérieur.
	_paper_mat = StandardMaterial3D.new()
	_paper_mat.vertex_color_use_as_albedo = true
	_paper_mat.roughness = 0.9
	_paper_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_paper_mat.emission_enabled = true
	_paper_mat.emission = Color(1.0, 0.62, 0.3)
	_paper_mat.emission_energy_multiplier = 0.9
	_paper_mat.backlight_enabled = true
	_paper_mat.backlight = Color(0.9, 0.6, 0.3)
	# La nuit, le papier luit fort : le halo (bloom) déborde sur les poutres.
	BastideGlow.register(_paper_mat, 0.9, 4.0)
	_cloth_mat = StandardMaterial3D.new()
	_cloth_mat.vertex_color_use_as_albedo = true
	_cloth_mat.roughness = 0.95
	_cloth_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cloth_mat.backlight_enabled = true
	_cloth_mat.backlight = Color(0.35, 0.3, 0.25)
