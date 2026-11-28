@tool
@icon("res://addons/bastide/editor/icons/bastide_building.svg")
class_name BastideBuilding
extends BastideStructure
## Bâtiment procédural posé sur un contour au sol.
##
## Dans l'éditeur : ajoute un nœud BastideBuilding (une maison rectangulaire
## apparaît), puis déplace, ajoute ou supprime des points avec les outils de Path3D.
## Chaque point de la courbe est un angle de la maison ; les poignées sont ignorées.
## Le contour est toujours fermé. Murs, ouvertures et toit se recalculent en direct.
##
## En jeu : appelle set_footprint() avec les angles du contour.

enum RoofChoice { STYLE, HIP, GABLE, IRIMOYA }

## Nombre d'étages. 0 = celui du style.
@export_range(0, 6, 1) var floors := 0:
	set(value):
		floors = value
		queue_rebuild()

## Forme du toit. « Style » : celle du style ; « Croupes » : pans de tous côtés ;
## « Pignons » : les bouts étroits deviennent des murs triangulaires ;
## « Irimoya » : croupes en bas, petits pignons de bois en haut (toit japonais).
@export var roof := RoofChoice.STYLE:
	set(value):
		roof = value
		queue_rebuild()

## Volume du bâtiment, décliné du style : grande maison, petite maison, kura
## (entrepôt), tour à étages. « Automatique » choisit d'après le tracé.
@export var silhouette: BastideSilhouette.Kind = BastideSilhouette.Kind.AUTO:
	set(value):
		silhouette = value
		queue_rebuild()

## Façade de la porte : numéro du côté du tracé (0 = du premier au deuxième point,
## 1 = du deuxième au troisième…). -1 = automatique (la plus longue façade sous égout).
@export_range(-1, 64, 1) var door_facade := -1:
	set(value):
		door_facade = value
		queue_rebuild()

## Aperçu de l'intérieur dans l'éditeur (parquet, escaliers), portes ouvertes. En jeu,
## l'intérieur apparaît tout seul quand on s'approche en promenade (BastideInteriors).
@export var preview_interior := false:
	set(value):
		preview_interior = value
		if not is_inside_tree():
			return
		if value:
			set_interior_active(true)
			_interior.force_open = 1.0
		else:
			set_interior_active(false)

## L'intérieur vient d'être posé (planchers, escaliers, vantaux).
signal interior_ready

var _points_override := PackedVector3Array()
var _use_override := false
var _interior: BastideInteriorHost
var _bounds := Vector3.ZERO
var _mound_key := 0  # centre (x, z) et rayon du contour, espace local


func _default_curve() -> Curve3D:
	var c := Curve3D.new()
	for p in [Vector3(-4, 0, -3), Vector3(4, 0, -3), Vector3(4, 0, 3), Vector3(-4, 0, 3)]:
		c.add_point(p)
	c.closed = true
	return c


## Construit le bâtiment à partir des angles du contour (espace local), sans la courbe.
## Prévu pour la construction en jeu ; clear_footprint() revient à la courbe.
func set_footprint(points: PackedVector3Array) -> void:
	_points_override = points
	_use_override = true
	queue_rebuild()


func clear_footprint() -> void:
	_use_override = false
	queue_rebuild()


func _make_job() -> Callable:
	var spec := build_spec()
	var kind := BastideSilhouette.resolve(silhouette, spec.footprint, spec.seed)
	var st := BastideSilhouette.style_for(get_effective_style(), kind)
	var with_collision := generate_collision
	return func() -> BastideBuildResult:
		var r := compute(spec, st, with_collision)
		r.stats["silhouette"] = BastideSilhouette.NAMES[kind]
		# Entrepôt et tour de guet n'ont pas de foyer : pas de fumée.
		if not BastideSilhouette.has_hearth(kind):
			r.anchors["smoke"] = PackedVector3Array()
		return r


## Silhouette réellement utilisée (AUTO résolu d'après le tracé).
func resolved_silhouette() -> int:
	var spec := build_spec()
	return BastideSilhouette.resolve(silhouette, spec.footprint, spec.seed)


## Calcul pur (aucun accès à l'arbre de scène) : peut tourner sur n'importe quel thread.
static func compute(spec: BastideBuildingSpec, st: BastideStyle, with_collision: bool) -> BastideBuildResult:
	if st.get_building_style().form == BastideBuildingStyle.Form.BURROW:
		return BastideBurrowBuilder.build(spec, st, with_collision)
	var layout := BastideBuildingGenerator.generate(spec, st)
	if layout.is_empty():
		return BastideBuildResult.new()
	return BastideBuildingMesher.build(layout, st, with_collision)


## Pour les voisins : contour (celui de la dernière génération, redressé) et portes.
func describe() -> Dictionary:
	var fp := PackedVector3Array()
	var y := 0.0
	if last_anchors.has("footprint"):
		y = last_anchors.get("base_y", 0.0)
		for p: Vector2 in last_anchors["footprint"]:
			fp.append(Vector3(p.x, y, p.y))
	else:
		for p: Vector2 in build_spec().footprint:
			fp.append(Vector3(p.x, 0.0, p.y))
	if fp.size() < 3:
		return {}
	var xf := global_transform
	var doors: Array = []
	for d: Dictionary in last_anchors.get("doors", []):
		doors.append({"pos": xf * (d["pos"] as Vector3), "out": (xf.basis * (d["out"] as Vector3)).normalized(),
			"width": d["width"]})
	return {"kind": "house", "footprint": _to_world(fp), "doors": doors,
		"overhang": last_anchors.get("overhang", 0.6)}


func build_spec() -> BastideBuildingSpec:
	var pts := _points_override if _use_override else BastideBuildingSpec.points_from_curve(curve)
	var roof_type := -1
	match roof:
		RoofChoice.HIP:
			roof_type = BastideRoofStyle.RoofType.HIP
		RoofChoice.GABLE:
			roof_type = BastideRoofStyle.RoofType.GABLE
		RoofChoice.IRIMOYA:
			roof_type = BastideRoofStyle.RoofType.IRIMOYA
	return BastideBuildingSpec.from_points(pts, seed, floors, roof_type, door_facade)


# --- Intérieur ---------------------------------------------------------------------

## Crée (ou retire) l'intérieur : variante de la maison qu'on peut franchir, planchers,
## escaliers, vantaux mobiles, lumière. Rien n'existe tant qu'il n'est pas actif.
func set_interior_active(on: bool) -> void:
	if on:
		if _interior == null:
			_interior = BastideInteriorHost.new(self)
		_interior.activate()
	elif _interior:
		_interior.deactivate()


## Un terrier se pose sur le relief d'origine : sa butte, qu'il fait lui-même monter
## dans le relief, ne doit pas le soulever.
func _drape_field() -> BastideHeightField:
	if is_burrow():
		var t := BastideTerrain.find(self)
		return t.base_field if t else null
	return super._drape_field()


## Fait monter le relief sous la butte d'un terrier (et autour), ou le rend.
func _update_mound(result: BastideBuildResult) -> void:
	var terrain := BastideTerrain.find(self)
	if terrain == null or terrain.base_field == null:
		return
	if _mound_key == 0:
		_mound_key = get_instance_id()
	var data: Variant = result.anchors.get("mound_data") if result else null
	# Fantômes et aperçus transparents : le sol ne bouge pas.
	if data == null or not context_enabled and mesh_transparency > 0.0:
		terrain.clear_carve(_mound_key)
		return
	var lift := float(result.stats.get("terrain_lift", 0.0))
	var xf := Transform3D(global_transform.basis.orthonormalized(), global_transform.origin + Vector3(0, lift, 0))
	terrain.set_carve(_mound_key, BastideBurrowBuilder.carve(data, xf, terrain.base_field))


## Maison-terrier (style à buttes herbeuses) plutôt que maison à murs et toit.
func is_burrow() -> bool:
	return get_effective_style().get_building_style().form == BastideBuildingStyle.Form.BURROW


func is_interior_active() -> bool:
	return _interior != null and _interior.wanted


## Intérieur posé et prêt (le calcul de fond est terminé).
func is_interior_ready() -> bool:
	return _interior != null and _interior.built


## Plan de l'intérieur posé (null s'il n'est pas actif).
func interior_layout() -> BastideInteriorLayout:
	return _interior.layout if _interior and _interior.built else null


## Portes et lumière selon le promeneur (position monde), à appeler chaque image.
func update_interior(walker: Vector3, delta: float) -> void:
	if _interior:
		_interior.update(global_transform.affine_inverse() * walker, delta)


## Ouverture des portes (0 fermé → 1 ouvert).
func doors_open() -> float:
	return _interior.doors_open() if _interior else 0.0


## Distance horizontale approximative du promeneur aux murs (0 ou moins : dedans).
func walker_distance(walker: Vector3) -> float:
	var local := global_transform.affine_inverse() * walker
	return Vector2(local.x - _bounds.x, local.z - _bounds.y).length() - _bounds.z


func _apply(result: BastideBuildResult) -> void:
	super._apply(result)
	_update_mound(result)
	var fp: PackedVector2Array = last_anchors.get("footprint", PackedVector2Array())
	if fp.size() >= 3:
		var c := BastidePolygon.centroid(fp)
		var r := 0.0
		for p in fp:
			r = maxf(r, p.distance_to(c))
		_bounds = Vector3(c.x, c.y, r)
	if _interior and _interior.wanted:
		_interior.refresh()
	elif preview_interior and Engine.is_editor_hint():
		set_interior_active(true)
		_interior.force_open = 1.0


func _exit_tree() -> void:
	if _interior:
		_interior.wait()
	var terrain := BastideTerrain.find(self)
	if terrain and _mound_key != 0:
		terrain.clear_carve(_mound_key)
	super._exit_tree()


## Sur une pente, la maison est posée sur un socle : des marches de pierre descendent
## alors de chaque porte jusqu'au sol (sinon on ne pourrait pas y entrer à pied).
func _drape_result(result: BastideBuildResult, drape: Dictionary) -> void:
	super._drape_result(result, drape)
	if result != null and not drape.is_empty():
		add_door_steps(result, drape["field"], drape["xf"], get_effective_style())


static func add_door_steps(result: BastideBuildResult, field: BastideHeightField, xf: Transform3D, st: BastideStyle) -> void:
	if result == null or result.mesh == null or field == null:
		return
	var lift := float(result.stats.get("terrain_lift", 0.0))
	var base_y := float(result.anchors.get("base_y", 0.0))
	var inv := xf.affine_inverse()
	var ws := st.get_wall_style()
	if result.anchors.get("burrow", false):
		return
	var sliding := st.get_building_style().door_kind == BastideBuildingStyle.DoorKind.SLIDING
	var start := 0.58 if sliding else 0.4
	var top := base_y + lift + (0.12 if sliding else 0.13)
	var mb := BastideMeshBuilder.new()
	for d: Dictionary in result.anchors.get("doors", []):
		var pos: Vector3 = d["pos"]
		var out: Vector3 = (d["out"] as Vector3).normalized()
		var side := out.cross(Vector3.UP).normalized()
		var half := float(d["width"]) * 0.5 + 0.2
		var ground := func(depth: float) -> float:
			var w := xf * (pos + out * depth)
			return (inv * Vector3(w.x, field.height(w.x, w.z), w.z)).y
		# La pierre de seuil porte le pas (elle n'est que dessinée par la façade).
		var sk: Array = []
		for y in [top - 0.4, top]:
			for p: Vector3 in [pos - side * half + out * -0.02, pos + side * half + out * -0.02,
					pos + side * half + out * start, pos - side * half + out * start]:
				sk.append(Vector3(p.x, y, p.z))
		result.add_box(sk)
		var g: float = ground.call(start + 0.5)
		var n := 0
		for it in 3:
			var drop := top - g
			if drop < 0.28:
				n = 0
				break
			n = ceili(drop / 0.19) - 1
			g = ground.call(start + (n + 0.5) * 0.32)
		if n <= 0:
			continue
		var r := (top - g) / (n + 1)
		for k in range(1, n + 1):
			var d0 := start + (k - 1) * 0.32 - 0.04
			var d1 := start + k * 0.32
			var yt := top - k * r
			var yb: float = ground.call(d1) - 0.3
			var hw := half + BastideRng.signed_at(k, "marche", int(pos.x * 10.0)) * 0.05
			var c := pos + Vector3(0.0, 0.0, 0.0)
			var corners := [c + side * -hw + out * d0, c + side * hw + out * d0, c + side * hw + out * d1, c + side * -hw + out * d1]
			var kk: Array = []
			for y in [yb, yt]:
				for p: Vector3 in corners:
					kk.append(Vector3(p.x, y, p.z))
			var tint := BastideRng.signed_at(k, "marche_teinte", int(pos.z * 10.0)) * 0.05
			var stone := ws.stone_color.darkened(0.05 - tint)
			mb.add_block(BastideBuildingMesher.ROLE_BODY, kk, 0.035, 0.01, stone, ws.mortar_color.lerp(stone, 0.4))
			result.add_box(kk)
	if mb.triangle_count == 0:
		return
	var extra := mb.commit()
	var mesh := result.mesh as ArrayMesh
	var body := -1
	for i in mesh.get_surface_count():
		if mesh.surface_get_name(i) == String(BastideBuildingMesher.ROLE_BODY):
			body = i
	var add: Array = extra.surface_get_arrays(0)
	if body < 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, add)
		mesh.surface_set_material(mesh.get_surface_count() - 1, st.get_material())
		return
	var arr := mesh.surface_get_arrays(body)
	var mat := mesh.surface_get_material(body)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var old_n := v.size()
	var add_n: int = (add[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	# Autres canaux par sommet (tangentes, données du shader) : complétés à zéro.
	for i in arr.size():
		if i == Mesh.ARRAY_VERTEX or i == Mesh.ARRAY_NORMAL or i == Mesh.ARRAY_COLOR or arr[i] == null:
			continue
		var a: Variant = arr[i]
		if a is PackedFloat32Array or a is PackedByteArray or a is PackedVector2Array or a is PackedInt32Array:
			if i == Mesh.ARRAY_INDEX or old_n == 0:
				return
			var per: int = a.size() / old_n
			a.resize(a.size() + per * add_n)
			arr[i] = a
	var fmt := mesh.surface_get_format(body)
	var flags := 0
	for ch in 4:
		var shift: int = Mesh.ARRAY_FORMAT_CUSTOM_BASE + ch * Mesh.ARRAY_FORMAT_CUSTOM_BITS
		flags |= fmt & (Mesh.ARRAY_FORMAT_CUSTOM_MASK << shift)
	var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	v.append_array(add[Mesh.ARRAY_VERTEX])
	nn.append_array(add[Mesh.ARRAY_NORMAL])
	cc.append_array(add[Mesh.ARRAY_COLOR])
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nn
	arr[Mesh.ARRAY_COLOR] = cc
	mesh.surface_remove(body)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	var o := mesh.get_surface_count() - 1
	mesh.surface_set_material(o, mat)
	mesh.surface_set_name(o, String(BastideBuildingMesher.ROLE_BODY))


## Une maison reste d'aplomb : un soubassement rattrape la pente.
func terrain_mode() -> int:
	return BastideDrape.Mode.RIGID
