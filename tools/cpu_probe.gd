extends SceneTree
## Mesure du temps passé dans les scripts à chaque image (outil de développement),
## sans rendu : on coupe le _process d'un nœud à la fois et on compare.
##   godot --headless --path . -s tools/cpu_probe.gd

var scene: Node
var site: BastideBuildSite


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	scene = (load("res://demos/04_runtime/runtime_demo.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	site = scene.get_node("Chantier")
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while not _all_built(n0) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	await _frames(60)
	for k in 4:
		print("tout (série %d) : %.2f ms de scripts par image" % [k, await _measure()])
	for n in scene.get_children():
		if not (n.is_processing() or n.is_physics_processing()):
			continue
		n.process_mode = Node.PROCESS_MODE_DISABLED
		await _frames(5)
		print("sans %s : %.2f ms" % [n.name, await _measure()])
		n.process_mode = Node.PROCESS_MODE_INHERIT
	print("tout, à la fin : %.2f ms" % await _measure())
	quit()


func _measure() -> float:
	var total := 0.0
	var n := 120
	for i in n:
		await process_frame
		total += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	return total / n


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _all_built(n: int) -> bool:
	if site.ids().size() < n:
		return false
	for id in site.ids():
		var node := site.node_of(id)
		if node == null or node.last_stats.is_empty():
			return false
	return site.garden != null and not site.garden.last_stats.is_empty()
