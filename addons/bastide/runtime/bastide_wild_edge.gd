class_name BastideWildEdge
extends Node3D
## Lisière sauvage (voir BastideWildScatter) : fleurs des champs qui débordent sur
## les dalles des chemins, fougères et hautes herbes au pied des murets et des
## clôtures, et touffes fleuries éparses dans la prairie autour de la caméra.
##
## Une seule MultiMesh par sorte de plante (cinq appels de dessin en tout), sans
## ombre ni collision. La lisière est refaite quand le chantier change ; les touffes
## de prairie, quand le point regardé change de case. Masquée au niveau Bas, plus
## clairsemée en Moyen, et quand la caméra s'éloigne.

@export var site: BastideBuildSite
@export var camera: Camera3D
## Rayon (m) des touffes de prairie autour du point regardé (× le niveau de détail).
@export var meadow_radius := 22.0
## Au-delà de cette distance de la caméra au point regardé, plus de lisière.
@export var hide_distance := 95.0
@export var scatter_seed := 5
## Niveau de détail minimal (BastideGraphics.detail) : 0,75 = Moyen.
@export var min_detail := 0.7

var _mmis := {}          # sorte → MultiMeshInstance3D
var _edges: Array = []
var _meadow: Array = []
var _edges_dirty := true
var _edges_timer := 0.0
var _meadow_center := Vector2(INF, INF)
var _detail := -1.0
var _field: BastideHeightField


func _ready() -> void:
	if site:
		site.structure_added.connect(_dirty.unbind(1))
		site.structure_changed.connect(_dirty.unbind(1))
		site.structure_removed.connect(_dirty.unbind(1))
	for kind: int in BastideWildScatter.KINDS:
		var item := _item(kind)
		if item.is_empty():
			continue
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Lisiere_%d" % kind
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.material_override = item["mat"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = item["mesh"]
		mmi.multimesh = mm
		add_child(mmi)
		_mmis[kind] = mmi


static func _item(kind: int) -> Dictionary:
	match kind:
		BastideWildScatter.MEADOW:
			return BastideKitNature.tuft("meadow", Color.WHITE, 1.0)
		BastideWildScatter.MEADOW_SMALL:
			return BastideKitNature.tuft("meadow", Color.WHITE, 0.6)
		BastideWildScatter.FERN:
			return BastideKitNature.tuft("fern", Color.WHITE, 0.9)
		BastideWildScatter.TALL:
			return BastideKitNature.tuft("reed", Color(0.95, 1.0, 0.78), 1.05)
		BastideWildScatter.FLOWER:
			return BastideKitNature.tuft("flower", Color.WHITE, 0.42)
	return {}


func _dirty() -> void:
	_edges_dirty = true
	_edges_timer = 0.5
	_meadow_center = Vector2(INF, INF)


func _process(delta: float) -> void:
	var d := BastideGraphics.detail
	var on := d >= min_detail
	if camera:
		on = on and camera.global_position.distance_to(_focus()) < hide_distance
	visible = on
	if not on or site == null:
		return
	if not is_equal_approx(d, _detail):
		_detail = d
		_edges_dirty = true
		_meadow_center = Vector2(INF, INF)
	var rebuild := false
	_edges_timer -= delta
	if _edges_dirty and _edges_timer <= 0.0:
		_edges_dirty = false
		var ctx := site.context()
		_edges = BastideWildScatter.edges(ctx, scatter_seed, _density())
		rebuild = true
	var f := _focus()
	var c := Vector2(f.x, f.z)
	if c.distance_to(_meadow_center) > 5.0:
		_meadow_center = c
		_meadow = BastideWildScatter.meadow(site.context(), c, meadow_radius * minf(d, 1.2), scatter_seed, _density())
		rebuild = true
	if rebuild:
		_fill()


func _density() -> float:
	return clampf(BastideGraphics.detail, 0.5, 1.2)


func _focus() -> Vector3:
	if camera is BastideOrbitCamera:
		return (camera as BastideOrbitCamera).target
	return camera.global_position if camera else global_position


## Remplit les MultiMesh d'un coup (tampon brut : 12 flottants de repère + 4 de couleur).
func _fill() -> void:
	if _field == null:
		_field = BastideTerrain.field_for(self)
	var xf := site.global_transform
	var lists := {}
	for kind in _mmis:
		lists[kind] = PackedFloat32Array()
	for e: Array in _edges + _meadow:
		var kind: int = e[0]
		if not lists.has(kind):
			continue
		var p2: Vector2 = e[1]
		var w := xf * Vector3(p2.x, 0.0, p2.y)
		w.y = _field.height(w.x, w.z) if _field else w.y
		var b := Basis(Vector3.UP, float(e[2]))
		var col: Color = e[3]
		var buf: PackedFloat32Array = lists[kind]
		buf.append_array([b.x.x, b.y.x, b.z.x, w.x, b.x.y, b.y.y, b.z.y, w.y, b.x.z, b.y.z, b.z.z, w.z,
			col.r, col.g, col.b, 1.0])
		lists[kind] = buf
	for kind in _mmis:
		var mm: MultiMesh = (_mmis[kind] as MultiMeshInstance3D).multimesh
		var buf: PackedFloat32Array = lists[kind]
		mm.instance_count = buf.size() / 16
		if mm.instance_count > 0:
			mm.buffer = buf
