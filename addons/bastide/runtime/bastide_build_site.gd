class_name BastideBuildSite
extends Node3D
## Chantier de construction en jeu : il possède les murs et les maisons posés par
## le joueur, chacun décrit par un « enregistrement » (un simple Dictionary).
##
## Toute modification passe par apply_record(id, record) : créer (record d'un id
## inconnu), modifier (id connu) ou supprimer (record null). C'est ce qui rend
## l'annulation triviale (on réapplique l'ancien record) et la sauvegarde aussi
## (to_data / from_data ne manipulent que des records).
##
## Format d'un record :
##   kind    : "wall", "house", "path" (chemin), "torii", "fence" (clôture basse),
##             "plants" (massif ; un seul point = un arbre) ou "terrace" (terrasse
##             de bois ; contre une maison, un engawa), "forest" (forêt) ou
##             "pond" (jardin d'eau : étang creusé dans le relief),
##             "farm" (cultures : potager, rizière en terrasses, champ de thé)
##   points  : PackedVector3Array, en coordonnées du chantier (points de contrôle
##             du mur, angles de la maison). Chantier à l'origine = coordonnées monde.
##   closed  : bool (murs : enceinte fermée)
##   seed    : int
##   floors  : int (maisons ; 0 = style)
##   shape   : int (maisons ; BastideSilhouette.Kind, 0 = automatique)
##   door    : int (maisons, facultatif : côté de la porte, -1 = automatique)
##   height  : float (murs ; 0 = style)
##   variant : int (clôtures : 0 pierres sèches, 1 bambou)
##   entry   : int (terrasses, facultatif : côté des marches, -1 = automatique)
##   pond_kind : int (étangs : BastidePondBuilder.Kind, jardin / onsen / mare)
##   farm_kind : int (champs : BastideFarmBuilder.Kind, potager / rizière / thé)
##   style   : chemin du .tres de style

signal structure_added(id: int)
signal structure_changed(id: int)
signal structure_removed(id: int)

## Durée de l'apparition (pousse depuis le sol) et de la disparition.
@export var rise_time := 0.9
@export var sink_time := 0.55
## Couche de collision des structures posées (pour les retrouver sous la souris).
@export_flags_3d_physics var structure_layer := 1
## Petits nuages de poussière quand une structure sort de terre ou y retourne.
@export var dust := true
@export var dust_color := Color(0.78, 0.71, 0.58, 0.3)
## Jardin automatique : galets, plantes au pied des murs et des maisons, touffes au
## bord des chemins. Il suit tout seul chaque changement du chantier.
@export var auto_garden := true
## Style du jardin automatique (vide : style par défaut).
@export var garden_style: BastideStyle:
	set(value):
		garden_style = value
		if garden:
			garden.style = value

## Le jardin automatique (null si auto_garden est faux).
var garden: BastideGarden

var _nodes := {}    # id -> BastideStructure
var _records := {}  # id -> Dictionary
var _next_id := 1
var _style_cache := {}
var _dust_texture: Texture2D


func _ready() -> void:
	if auto_garden and garden == null:
		garden = BastideGarden.new()
		garden.name = "Jardin"
		garden.style = garden_style
		garden.generate_collision = false
		add_child(garden)


## Voisinage de tout le chantier (pour placer un torii, par exemple), en
## coordonnées du chantier.
func context() -> BastideGardenContext:
	var entries: Array = []
	var to_local := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	for id in _nodes:
		var node: BastideStructure = _nodes[id]
		if node and node.context_enabled and node.is_inside_tree():
			var d := node.describe()
			if not d.is_empty():
				entries.append(BastideGardenContext.transform_entry(d, to_local))
	return BastideGardenContext.from_entries(entries)


func new_id() -> int:
	_next_id += 1
	return _next_id - 1


func ids() -> Array:
	return _records.keys()


func has(id: int) -> bool:
	return _records.has(id)


## Copie de l'enregistrement d'une structure (null si elle n'existe pas).
func get_record(id: int) -> Variant:
	return copy_record(_records[id]) if _records.has(id) else null


func node_of(id: int) -> BastideStructure:
	return _nodes.get(id) as BastideStructure


## Id d'une structure, ou d'un nœud qui lui appartient (collision, mesh). -1 sinon.
func id_of(node: Node) -> int:
	while node != null and node != self:
		if node is BastideStructure:
			for id in _nodes:
				if _nodes[id] == node:
					return id
			return -1
		node = node.get_parent()
	return -1


static func copy_record(rec: Dictionary) -> Dictionary:
	var c := rec.duplicate(true)
	c["points"] = PackedVector3Array(rec.get("points", PackedVector3Array()))
	return c


## Crée, modifie ou supprime (record null) la structure `id`.
## animate : pousse depuis le sol à la création, s'enfonce à la suppression,
## petit tassement à la modification.
func apply_record(id: int, rec: Variant, animate := true) -> void:
	if rec == null:
		_remove(id, animate)
		return
	var r: Dictionary = copy_record(rec)
	var node := node_of(id)
	if node == null:
		node = make_node(r)
		_nodes[id] = node
		_records[id] = r
		_next_id = maxi(_next_id, id + 1)
		add_child(node)
		configure(node, r)
		node.generate_collision = true
		node.collision_layer = structure_layer
		if animate:
			_rise(node)
		structure_added.emit(id)
		return
	if node.is_queued_for_deletion():
		return
	_records[id] = r
	configure(node, r)
	if animate:
		_settle(node)
	structure_changed.emit(id)


## Adopte une structure d'aperçu (déjà dans l'arbre, déjà générée) comme structure
## définitive : pas de régénération, elle passe juste du fantôme au solide.
func adopt(id: int, node: BastideStructure, rec: Dictionary) -> void:
	var r := copy_record(rec)
	if node.get_parent() != self:
		node.reparent(self)
	_nodes[id] = node
	_records[id] = r
	_next_id = maxi(_next_id, id + 1)
	configure(node, r)
	node.generate_collision = true
	node.collision_layer = structure_layer
	node.mesh_overlay = null
	node.context_enabled = true
	var tw := node.create_tween().set_parallel()
	tw.tween_property(node, "mesh_transparency", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: node.mesh_casts_shadow = true).set_delay(0.12)
	_settle(node)
	_puff(r)
	structure_added.emit(id)


func clear(animate := false) -> void:
	for id in _records.keys():
		_remove(id, animate)


## Nouveau nœud (pas encore dans l'arbre) pour un record.
func make_node(rec: Dictionary) -> BastideStructure:
	var node: BastideStructure
	match String(rec.get("kind", "wall")):
		"house":
			node = BastideBuilding.new()
			node.name = "Maison"
		"path":
			node = BastidePath.new()
			node.name = "Chemin"
		"torii":
			node = BastideTorii.new()
			node.name = "Torii"
		"fence":
			node = BastideFence.new()
			node.name = "Cloture"
		"plants":
			node = BastidePlanting.new()
			node.name = "Massif"
		"terrace":
			node = BastideTerrace.new()
			node.name = "Terrasse"
		"forest":
			node = BastideForest.new()
			node.name = "Foret"
		"pond":
			node = BastidePond.new()
			node.name = "Etang"
		"farm":
			node = BastideFarm.new()
			node.name = "Champ"
		_:
			node = BastideWall.new()
			node.name = "Mur"
	node.generate_collision = false
	var pts: PackedVector3Array = rec.get("points", PackedVector3Array())
	if pts.size() > 0:
		var c := BastideStroke.centroid(pts)
		node.position = Vector3(c.x, pts[0].y, c.z)
	return node


## Recopie un record sur un nœud (points en coordonnées locales du nœud).
func configure(node: BastideStructure, rec: Dictionary) -> void:
	var st := style_of(rec)
	if node.style != st:
		node.style = st
	if node.seed != int(rec.get("seed", 1)):
		node.seed = int(rec.get("seed", 1))
	var origin := node.position
	var local := PackedVector3Array()
	for p: Vector3 in rec.get("points", PackedVector3Array()):
		local.append(p - origin)
	if node is BastideBuilding:
		var b := node as BastideBuilding
		var f := int(rec.get("floors", 0))
		if b.floors != f:
			b.floors = f
		var shape := int(rec.get("shape", BastideSilhouette.Kind.AUTO))
		if b.silhouette != shape:
			b.silhouette = shape
		var door := int(rec.get("door", -1))
		if b.door_facade != door:
			b.door_facade = door
		b.set_footprint(local)
	elif node is BastideWall:
		var w := node as BastideWall
		var h := float(rec.get("height", 0.0))
		if w.height != h:
			w.height = h
		var closed := bool(rec.get("closed", false))
		w.set_points(BastideStroke.wall_path(local, closed, st.get_wall_style().station_spacing), closed)
	elif node is BastidePath:
		(node as BastidePath).set_points(BastideStroke.wall_path(local, false, 0.4))
	elif node is BastideFence:
		var fe := node as BastideFence
		var closed := bool(rec.get("closed", false))
		var v := int(rec.get("variant", 0))
		if int(fe.variant) != v:
			fe.variant = v
		fe.set_points(BastideStroke.wall_path(local, closed, 0.45), closed)
	elif node is BastideTorii:
		if local.size() >= 2:
			(node as BastideTorii).set_points(BastideGardenRules.fit_torii(local[0], local[1]))
	elif node is BastideTerrace:
		var t := node as BastideTerrace
		var e := int(rec.get("entry", -1))
		if t.entry_side != e:
			t.entry_side = e
		t.set_footprint(local)
	elif node is BastideForest:
		var fo := node as BastideForest
		var fk := int(rec.get("forest_kind", 0))
		if int(fo.forest_kind) != fk:
			fo.forest_kind = fk
		fo.set_footprint(local)
	elif node is BastidePond:
		var po := node as BastidePond
		var pk := int(rec.get("pond_kind", 0))
		if int(po.pond_kind) != pk:
			po.pond_kind = pk
		po.set_footprint(local)
	elif node is BastideFarm:
		var fa := node as BastideFarm
		var fk := int(rec.get("farm_kind", 0))
		if int(fa.farm_kind) != fk:
			fa.farm_kind = fk
		fa.set_footprint(local)
	elif node is BastidePlanting:
		(node as BastidePlanting).set_points(local if local.size() < 2 else BastideStroke.wall_path(local, false, 0.5))


func style_of(rec: Dictionary) -> BastideStyle:
	var path: String = rec.get("style", "")
	if path.is_empty():
		return null
	if not _style_cache.has(path):
		_style_cache[path] = load(path)
	return _style_cache[path] as BastideStyle


# --- Sauvegarde ------------------------------------------------------------------

## Toutes les structures, en données simples (convertibles en JSON).
func to_data() -> Array:
	var out := []
	var keys := _records.keys()
	keys.sort()
	for id in keys:
		var r: Dictionary = _records[id]
		var pts := []
		for p: Vector3 in r["points"]:
			pts.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)])
		var d := r.duplicate()
		d["points"] = pts
		d["id"] = id
		out.append(d)
	return out


## Remplace le chantier par des données de to_data(). `stagger` : délai entre deux
## apparitions (0 = tout d'un coup), pour une jolie arrivée au lancement.
func from_data(data: Array, animate := true, stagger := 0.0) -> void:
	clear(false)
	var i := 0
	for d: Dictionary in data:
		var rec := d.duplicate()
		var pts := PackedVector3Array()
		for p: Array in d.get("points", []):
			pts.append(Vector3(p[0], p[1], p[2]))
		rec["points"] = pts
		rec["seed"] = int(rec.get("seed", 1))
		rec["floors"] = int(rec.get("floors", 0))
		var id := int(rec.get("id", new_id()))
		rec.erase("id")
		if stagger > 0.0 and i > 0:
			_records[id] = copy_record(rec)  # réserve l'id tout de suite
			get_tree().create_timer(stagger * i).timeout.connect(func() -> void:
				_records.erase(id)
				apply_record(id, rec, animate))
		else:
			apply_record(id, rec, animate)
		i += 1


# --- Animations ------------------------------------------------------------------

func _remove(id: int, animate: bool) -> void:
	var node := node_of(id)
	var rec: Variant = _records.get(id)
	_nodes.erase(id)
	_records.erase(id)
	if node == null:
		return
	structure_removed.emit(id)
	# Les voisins (jardin, clôtures, chemins) l'oublient tout de suite.
	node.context_enabled = false
	if not animate or not node.is_inside_tree():
		node.queue_free()
		return
	node.generate_collision = false
	node.mesh_casts_shadow = false
	var tw := node.create_tween().set_parallel()
	tw.tween_property(node, "scale:y", 0.02, sink_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(node, "mesh_transparency", 1.0, sink_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(node.queue_free)
	if rec != null:
		_puff(rec)


## La structure sort de terre dès que son mesh est prêt.
func _rise(node: BastideStructure) -> void:
	node.scale = Vector3(1, 0.02, 1)
	node.mesh_transparency = 0.6
	node.mesh_casts_shadow = false
	var start := func(_stats: Dictionary) -> void:
		var tw := node.create_tween().set_parallel()
		tw.tween_property(node, "scale:y", 1.0, rise_time).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "mesh_transparency", 0.0, rise_time * 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func() -> void: node.mesh_casts_shadow = true).set_delay(rise_time * 0.3)
		var id := id_of(node)
		if id >= 0:
			_puff(_records[id])
	node.rebuilt.connect(start, CONNECT_ONE_SHOT)


## Petit tassement : la structure « se pose » après une retouche.
func _settle(node: BastideStructure) -> void:
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3(1.0, 0.97, 1.0), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Nuage de poussière le long du pied d'une structure.
func _puff(rec: Dictionary) -> void:
	if not dust or not is_inside_tree():
		return
	var pts: PackedVector3Array = rec.get("points", PackedVector3Array())
	if pts.size() == 1:
		pts = PackedVector3Array([pts[0] + Vector3(-0.8, 0, 0), pts[0] + Vector3(0.8, 0, 0)])
	if pts.size() < 2:
		return
	var closed: bool = rec.get("kind", "") in ["house", "terrace", "forest", "pond", "farm"] or bool(rec.get("closed", false))
	var emit_pts := PackedVector3Array()
	var path := BastideStroke.resample(pts, 0.6, closed)
	for p in path:
		emit_pts.append(p + Vector3(0, 0.15, 0))
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = clampi(emit_pts.size(), 8, 60)
	p.lifetime = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	p.emission_points = emit_pts
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.3
	p.gravity = Vector3(0, -0.3, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 1.4))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, dust_color)
	grad.set_color(1, Color(dust_color, 0.0))
	p.color_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	mat.disable_receive_shadows = true
	quad.material = mat
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _soft_dot() -> Texture2D:
	if _dust_texture == null:
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
		_dust_texture = t
	return _dust_texture
