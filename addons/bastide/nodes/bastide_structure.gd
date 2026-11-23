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

## Statistiques de la dernière génération (triangles, durée…).
var last_stats := {}

var _queued := false
var _task_id := -1
var _dirty_while_running := false
var _fallback_style: BastideStyle


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
	st.get_wall_style()
	st.get_building_style()
	st.get_roof_style()
	st.get_material()
	st.get_roof_material()
	st.get_glass_material()
	return _make_job()


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
		_apply(result)
	if _dirty_while_running:
		_dirty_while_running = false
		queue_rebuild()


func _apply(result: BastideBuildResult) -> void:
	if result.is_empty():
		BastideResultApplier.clear(self)
		last_stats = {}
		return
	BastideResultApplier.apply(self, result, generate_collision, collision_layer)
	last_stats = result.stats
	rebuilt.emit(last_stats)


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
	_apply(_timed(_prepare_job()))


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
