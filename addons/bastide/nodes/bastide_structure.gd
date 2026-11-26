@tool
class_name BastideStructure
extends Path3D
## Base commune des structures générées depuis une Path3D (murs, bâtiments).
##
## Elle gère le style, la seed, les collisions, la génération sur un thread de fond
## et la pose du résultat. Une sous-classe n'a qu'à fournir `_make_job()` : une
## fonction pure (sans accès à l'arbre de scène) qui renvoie un BastideBuildResult.

signal rebuilt(stats: Dictionary)

## Style partagé. Vide : style « médiéval pierre » par défaut.
@export var style: BastideStyle:
	set(value):
		if style and style.changed.is_connected(queue_rebuild):
			style.changed.disconnect(queue_rebuild)
		style = value
		if style:
			style.changed.connect(queue_rebuild)
		queue_rebuild()

## Dossier des styles prêts à l'emploi, proposés dans la liste « Style prédéfini ».
## Un .tres de style ajouté ici apparaît automatiquement dans la liste.
const PRESETS_DIR := "res://addons/bastide/styles/presets/"

static var _presets_cache: Array = []  # [[chemin, nom affiché], …]

## Graine de variation : même seed = même résultat, au caillou près.
@export var seed := 1:
	set(value):
		seed = value
		queue_rebuild()

## Génère sur un thread de fond : l'éditeur et le jeu ne figent pas pendant un
## glisser de point, le résultat apparaît dès que le calcul est prêt.
@export var async_build := true

@export_group("Collisions")
@export var generate_collision := true:
	set(value):
		generate_collision = value
		queue_rebuild()
@export_flags_3d_physics var collision_layer := 1:
	set(value):
		collision_layer = value
		queue_rebuild()

@export_group("")
@export_tool_button("Nouvelle seed", "RandomNumberGenerator") var _new_seed_button := _randomize_seed
@export_tool_button("Régénérer", "Reload") var _rebuild_button := rebuild

## Changer de style en un clic : liste des styles du dossier PRESETS_DIR, juste
## sous la propriété `style` dans l'inspecteur. Marche aussi sur plusieurs nœuds
## sélectionnés à la fois. Rien n'est enregistré en plus : c'est `style` qui change.
func _get_property_list() -> Array[Dictionary]:
	var names := PackedStringArray(["Personnalisé"])
	for p in presets():
		names.append(p[1])
	return [{
		"name": "style_preset",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": ",".join(names),
		"usage": PROPERTY_USAGE_EDITOR,
	}]


func _get(property: StringName) -> Variant:
	if property == &"style_preset":
		if style == null:
			return 0
		var list := presets()
		for i in list.size():
			if list[i][0] == style.resource_path:
				return i + 1
		return 0
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == &"style_preset":
		var list := presets()
		var i := int(value) - 1
		if i >= 0 and i < list.size():
			style = load(list[i][0])
		return true
	return false


## Styles prêts à l'emploi : [[chemin, nom affiché], …], triés par nom.
static func presets(refresh := false) -> Array:
	if not _presets_cache.is_empty() and not refresh:
		return _presets_cache
	var out: Array = []
	for file in ResourceLoader.list_directory(PRESETS_DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var path := PRESETS_DIR + file
		var res := load(path)
		if res is BastideStyle:
			out.append([path, (res as BastideStyle).display_name])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	_presets_cache = out
	return out


## Apparence du mesh généré, gardée d'une régénération à l'autre (construction en
## jeu : aperçu fantôme, surbrillance au survol). Sans effet sur le calcul.
var mesh_transparency := 0.0:
	set(value):
		mesh_transparency = value
		_apply_look()
var mesh_overlay: Material:
	set(value):
		mesh_overlay = value
		_apply_look()
var mesh_casts_shadow := true:
	set(value):
		mesh_casts_shadow = value
		_apply_look()


## MeshInstance3D interne posé par la dernière génération (null avant la première).
func get_mesh_instance() -> MeshInstance3D:
	return get_node_or_null(NodePath(BastideResultApplier.MESH_NAME)) as MeshInstance3D


func _apply_look() -> void:
	for gi in BastideResultApplier.geometry(self):
		gi.transparency = mesh_transparency
		gi.material_overlay = mesh_overlay
		var cast := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if mesh_casts_shadow and mesh_transparency < 0.5 \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if gi is MultiMeshInstance3D:
			# Les groupes gardent leur réglage (couronnes sans ombre, silhouettes d'ombre seules),
			# sauf pour un fantôme : rien ne porte d'ombre.
			if cast == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				gi.cast_shadow = cast
			elif gi.has_meta(&"cast"):
				gi.cast_shadow = gi.get_meta(&"cast")
		else:
			gi.cast_shadow = cast


## Statistiques de la dernière génération (triangles, durée…).
var last_stats := {}
## Points remarquables de la dernière génération (portes…), espace local.
var last_anchors := {}

# --- Voisinage ------------------------------------------------------------------
# Les structures se voient entre elles : un chemin rejoint la porte d'une maison,
# une clôture s'ouvre là où passe un chemin, des plantes poussent au pied des murs.
# Chaque structure a un « niveau » : quand elle change, seules celles de niveau
# supérieur qui lisent le voisinage sont régénérées (jamais de boucle).
#   0 : maisons · 1 : terrasses (elles se calent sur les maisons) · 2 : chemins,
#   torii (ils rejoignent portes et marches) · 3 : murs (ils s'ouvrent pour les
#   chemins) · 4 : clôtures, massifs · 5 : jardin

const GROUP := &"bastide_structures"
const LEVEL_HOUSE := 0
const LEVEL_TERRACE := 1
const LEVEL_PATH := 2
const LEVEL_WALL := 3
const LEVEL_FENCE := 4
const LEVEL_GARDEN := 5

## Faux pour un aperçu (fantôme) : les autres structures l'ignorent.
var context_enabled := true:
	set(value):
		if context_enabled == value:
			return
		context_enabled = value
		# Dans les deux sens : un voisin qui disparaît (fantôme, suppression) doit
		# aussi être oublié par ceux qui le voyaient (portail qui se referme…).
		_notify_dependents(true)


## Niveau dans le voisinage (voir plus haut). À surcharger.
func context_level() -> int:
	return 0


## Vrai si la génération lit le voisinage. À surcharger.
func uses_context() -> bool:
	return false


## Description de la structure pour ses voisins, en coordonnées monde (à surcharger).
## Clés reconnues : kind, points / footprint (PackedVector3Array), doors
## ([{pos, out, width}]), width, thickness, closed, variant.
func describe() -> Dictionary:
	return {}


## Voisinage vu depuis ce nœud : descriptions des autres structures, ramenées dans
## l'espace local de ce nœud. À appeler sur le thread principal (dans _make_job).
func gather_context() -> BastideGardenContext:
	var entries: Array = []
	if is_inside_tree():
		var to_local := global_transform.affine_inverse()
		for n in get_tree().get_nodes_in_group(GROUP):
			if n == self or not n is BastideStructure:
				continue
			var s := n as BastideStructure
			if not s.context_enabled or s.is_queued_for_deletion() or not s.is_inside_tree():
				continue
			var d := s.describe()
			if d.is_empty():
				continue
			entries.append(BastideGardenContext.transform_entry(d, to_local))
	return BastideGardenContext.from_entries(entries)


func _notify_dependents(force := false) -> void:
	if not is_inside_tree() or (not context_enabled and not force):
		return
	var lvl := context_level()
	for n in get_tree().get_nodes_in_group(GROUP):
		if n != self and n is BastideStructure:
			var s := n as BastideStructure
			if s.uses_context() and s.context_level() > lvl:
				s.queue_rebuild()


## Points en coordonnées monde.
func _to_world(points: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var xf := global_transform
	for p in points:
		out.append(xf * p)
	return out

var _queued := false
var _task_id := -1
## Pose sur le relief à appliquer au prochain résultat (voir _prepare_job).
var _pending_drape := {}
var _dirty_while_running := false
var _fallback_style: BastideStyle


func _enter_tree() -> void:
	add_to_group(GROUP)
	if Engine.is_editor_hint():
		# Déplacer le nœud dans l'éditeur prévient aussi les voisins (chemins, jardin).
		set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_notify_dependents()


func _ready() -> void:
	if curve == null:
		curve = _default_curve()
	if not curve_changed.is_connected(queue_rebuild):
		curve_changed.connect(queue_rebuild)
	queue_rebuild()


func _exit_tree() -> void:
	# Ne jamais laisser un calcul en vol référencer un nœud qui disparaît.
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	# Les voisins se recalculent sans nous (à la frame suivante, nous serons partis).
	if context_enabled and is_inside_tree():
		var lvl := context_level()
		for n in get_tree().get_nodes_in_group(GROUP):
			if n != self and n is BastideStructure and n.uses_context() and n.context_level() > lvl:
				(n as BastideStructure).queue_rebuild()


## Courbe créée quand on ajoute le nœud sans en donner une.
func _default_curve() -> Curve3D:
	return Curve3D.new()


## À surcharger : renvoie un Callable sans argument, exécutable sur n'importe quel
## thread, qui calcule et renvoie un BastideBuildResult. Toutes les données
## nécessaires doivent être copiées ici, sur le thread principal.
func _make_job() -> Callable:
	return func() -> BastideBuildResult: return BastideBuildResult.new()


## Regroupe les demandes : une seule génération à la fois, et une seule relance
## même si la courbe change dix fois pendant un glisser de point.
func queue_rebuild() -> void:
	if not is_inside_tree():
		return
	if _task_id >= 0:
		_dirty_while_running = true
		return
	if _queued:
		return
	_queued = true
	_start_build.call_deferred()


func _start_build() -> void:
	_queued = false
	if not is_inside_tree():
		return
	if not async_build:
		rebuild()
		return
	var job := _prepare_job()
	var self_ref := weakref(self)
	_task_id = WorkerThreadPool.add_task(func() -> void:
		var result := _timed(job)
		var me: Object = self_ref.get_ref()
		if me:
			me.call_deferred(&"_finish_build", result)
	, false, "Bastide : génération")


func _prepare_job() -> Callable:
	var st := get_effective_style()
	# Volets du style et matériaux créés ici, sur le thread principal.
	st.prepare()
	var job := _make_job()
	# Relief : la génération se fait à plat, puis elle est posée sur le sol. La pose
	# se fait sur le thread principal (voir _drape_result) : elle relit les maillages,
	# et une relecture depuis un autre thread attend le serveur de rendu, donc le
	# thread principal, qui peut lui-même attendre ce calcul (_exit_tree).
	_pending_drape = {}
	var field := BastideTerrain.field_for(self)
	var mode := terrain_mode()
	if field != null and mode != BastideDrape.Mode.NONE:
		# Sans échelle : le chantier fait « sortir de terre » une structure en animant
		# son échelle verticale, ce qui ne doit pas changer sa pose sur le sol.
		_pending_drape = {"field": field, "mode": mode, "min_lift": _terrain_min_lift(),
				"xf": Transform3D(global_transform.basis.orthonormalized(), global_transform.origin)}
	return job


func _drape_result(result: BastideBuildResult, drape: Dictionary) -> void:
	if result == null or drape.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	BastideDrape.apply(result, drape["field"], drape["xf"], drape["mode"], drape["min_lift"])
	result.stats["drape_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)


## Comment la structure se pose sur le relief (voir BastideDrape) : par défaut elle
## épouse la pente ; maisons, terrasses et torii restent d'aplomb.
func terrain_mode() -> int:
	return BastideDrape.Mode.FOLLOW


## Hauteur de pose minimale (structures d'aplomb) : -INF si aucune.
func _terrain_min_lift() -> float:
	return -INF


static func _timed(job: Callable) -> BastideBuildResult:
	var t0 := Time.get_ticks_usec()
	var result: BastideBuildResult = job.call()
	if result == null:
		result = BastideBuildResult.new()
	result.stats["build_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	return result


func _finish_build(result: BastideBuildResult) -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	if is_inside_tree():
		_drape_result(result, _pending_drape)
		_apply(result)
	if _dirty_while_running:
		_dirty_while_running = false
		queue_rebuild()


func _apply(result: BastideBuildResult) -> void:
	if result.is_empty():
		BastideResultApplier.clear(self)
		last_stats = {}
		last_anchors = {}
		_notify_dependents()
		return
	BastideResultApplier.apply(self, result, generate_collision, collision_layer)
	_apply_look()
	last_stats = result.stats
	last_anchors = result.anchors
	rebuilt.emit(last_stats)
	_notify_dependents()


func get_effective_style() -> BastideStyle:
	if style:
		return style
	if _fallback_style == null:
		_fallback_style = BastideStyle.create_default()
	return _fallback_style


## Génération immédiate et synchrone (bouton « Régénérer », scripts, tests).
func rebuild() -> void:
	if not is_inside_tree():
		return
	var r := _timed(_prepare_job())
	_drape_result(r, _pending_drape)
	_apply(r)


func _randomize_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var new_seed := rng.randi_range(1, 99999)
	# EditorInterface est récupéré dynamiquement : ce script doit aussi tourner dans un jeu exporté.
	var editor := Engine.get_singleton(&"EditorInterface") if Engine.has_singleton(&"EditorInterface") else null
	if Engine.is_editor_hint() and editor:
		var ur: Object = editor.call(&"get_editor_undo_redo")
		ur.call(&"create_action", "Nouvelle seed")
		ur.call(&"add_do_property", self, &"seed", new_seed)
		ur.call(&"add_undo_property", self, &"seed", seed)
		ur.call(&"commit_action")
	else:
		seed = new_seed
