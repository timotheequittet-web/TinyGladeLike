@tool
@icon("res://addons/bastide/editor/icons/bastide_wall.svg")
class_name BastideWall
extends Path3D
## Mur procédural qui suit sa propre courbe.
##
## Dans l'éditeur : ajoute un nœud BastideWall, puis place des points avec les outils
## de Path3D (barre d'outils du viewport). Le mur se régénère à chaque modification.
## Un point sans poignées fait un angle net ; tire les poignées pour courber le mur.
## Coche « closed » sur la Curve3D pour fermer une enceinte.
##
## En jeu : appelle set_points() pour construire un mur à partir de points calculés.

signal rebuilt(stats: Dictionary)

## Style du mur. Vide : style « médiéval pierre » par défaut.
@export var style: BastideStyle:
	set(value):
		if style and style.changed.is_connected(queue_rebuild):
			style.changed.disconnect(queue_rebuild)
		style = value
		if style:
			style.changed.connect(queue_rebuild)
		queue_rebuild()

## Graine de variation : même seed = même mur, au caillou près.
@export var seed := 1:
	set(value):
		seed = value
		queue_rebuild()

## Hauteur du mur. 0 = hauteur du style.
@export_range(0.0, 20.0, 0.05, "or_greater", "suffix:m") var height := 0.0:
	set(value):
		height = value
		queue_rebuild()

## Génère sur un thread de fond : l'éditeur et le jeu ne figent pas pendant un
## glisser de point, le mur se met à jour dès que le calcul est prêt.
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

## Statistiques de la dernière génération (pierres, triangles, durée…).
var last_stats := {}

var _queued := false
var _task_id := -1
var _dirty_while_running := false
var _points_override := PackedVector3Array()
var _closed_override := false
var _use_override := false
var _fallback_style: BastideStyle


func _ready() -> void:
	if curve == null:
		curve = Curve3D.new()
	if not curve_changed.is_connected(queue_rebuild):
		curve_changed.connect(queue_rebuild)
	queue_rebuild()


func _exit_tree() -> void:
	# Ne jamais laisser un calcul en vol référencer un nœud qui disparaît.
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


## Construit le mur à partir de points (espace local), sans passer par la courbe.
## Prévu pour la construction en jeu ; appeler clear_points() pour revenir à la courbe.
func set_points(points: PackedVector3Array, closed := false) -> void:
	_points_override = points
	_closed_override = closed
	_use_override = true
	queue_rebuild()


func clear_points() -> void:
	_use_override = false
	queue_rebuild()


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
	var st := get_effective_style()
	st.get_material()  # créé ici, sur le thread principal
	var spec := build_spec()
	var with_collision := generate_collision
	var self_ref := weakref(self)
	_task_id = WorkerThreadPool.add_task(func() -> void:
		var result := _compute(spec, st, with_collision)
		var me: Object = self_ref.get_ref()
		if me:
			me.call_deferred(&"_finish_build", result)
	, false, "Bastide : génération de mur")


func _finish_build(result: BastideBuildResult) -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	if is_inside_tree():
		_apply(result)
	if _dirty_while_running:
		_dirty_while_running = false
		queue_rebuild()


## Calcul pur (aucun accès à l'arbre de scène) : peut tourner sur n'importe quel thread.
static func _compute(spec: BastideWallSpec, st: BastideStyle, with_collision: bool) -> BastideBuildResult:
	var t0 := Time.get_ticks_usec()
	var layout := BastideWallGenerator.generate(spec, st)
	var result: BastideBuildResult
	if layout.is_empty():
		result = BastideBuildResult.new()
	else:
		result = BastideWallMesher.build(layout, st, with_collision)
	result.stats["build_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	return result


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


func build_spec() -> BastideWallSpec:
	var st := get_effective_style()
	var pts: PackedVector3Array
	var closed := false
	if _use_override:
		pts = _points_override
		closed = _closed_override
	elif curve:
		pts = BastideWallSpec.points_from_curve(curve, st.get_wall_style().station_spacing)
		closed = curve.closed
	return BastideWallSpec.from_points(pts, closed, seed, height)


## Génération immédiate et synchrone (bouton « Régénérer », scripts, tests).
func rebuild() -> void:
	if not is_inside_tree():
		return
	_apply(_compute(build_spec(), get_effective_style(), generate_collision))


func _randomize_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var new_seed := rng.randi_range(1, 99999)
	# EditorInterface est récupéré dynamiquement : ce script doit aussi tourner dans un jeu exporté.
	var editor := Engine.get_singleton(&"EditorInterface") if Engine.has_singleton(&"EditorInterface") else null
	if Engine.is_editor_hint() and editor:
		var ur: Object = editor.call(&"get_editor_undo_redo")
		ur.call(&"create_action", "Nouvelle seed du mur")
		ur.call(&"add_do_property", self, &"seed", new_seed)
		ur.call(&"add_undo_property", self, &"seed", seed)
		ur.call(&"commit_action")
	else:
		seed = new_seed
