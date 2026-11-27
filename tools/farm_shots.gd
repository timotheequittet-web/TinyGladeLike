extends SceneTree
## Captures des cultures (outil de développement) : un potager près du hameau, une
## rizière en terrasses sur la pente la plus forte des environs, un champ de thé.
## Les emplacements sont cherchés tout seuls (place libre, pente voulue).
##   godot --path . -s tools/farm_shots.gd -- <dossier_sortie> [préfixe]

var out_dir := "/tmp/shots"
var prefix := "champ"
var scene: Node
var cam: BastideOrbitCamera
var site: BastideBuildSite
var terrain: BastideTerrain
const J := "res://addons/bastide/styles/presets/japanese_wood.tres"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		prefix = args[1]
	_run.call_deferred()


func _run() -> void:
	scene = (load("res://demos/04_runtime/runtime_demo.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	cam = scene.get_node("Camera")
	site = scene.get_node("Chantier")
	terrain = scene.get_node("Terrain")
	var n0: int = scene.call("_starting_village").size()
	var t0 := Time.get_ticks_msec()
	while (site.ids().size() < n0 or not _all_built()) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	await _wait(2.0)
	(scene.get_node("Interface") as CanvasLayer).visible = false
	if OS.has_environment("NO_GLOW"):
		(scene.get_node("WorldEnvironment") as WorldEnvironment).environment.glow_enabled = false
	var placed: Array[Vector2] = []
	var veg := _find(Vector2(9, 6.5), 12.0, 30.0, 0.0, 0.08, placed)
	var rice := _find(Vector2(12, 9), 18.0, 36.0, 0.05, 0.4, placed)
	var tea := _find(Vector2(11, 8), 16.0, 36.0, 0.02, 0.25, placed)
	print("potager ", veg, "  rizière ", rice, "  thé ", tea)
	var kinds := [[veg, 0, Vector2(9, 6.5)], [rice, 1, Vector2(12, 9)], [tea, 2, Vector2(11, 8)]]
	for i in kinds.size():
		var c: Vector3 = kinds[i][0]
		if c == Vector3.INF:
			continue
		site.apply_record(910 + i, {"kind": "farm", "seed": 71 + i, "style": J, "closed": true, "farm_kind": kinds[i][1],
			"points": _rect(c, kinds[i][2])}, false)
	await _wait(8.0)
	var names := ["potager", "riziere", "the"]
	for i in kinds.size():
		var c: Vector3 = kinds[i][0]
		if c == Vector3.INF:
			continue
		var node := site.node_of(910 + i)
		print(names[i], " ", node.last_stats if node else {})
		cam.glide_to(c, 26.0, [210.0, 85.0, 135.0][i])
		await _wait(3.0)
		await _shot(names[i] + "_haut")
		var a := deg_to_rad(35.0 + i * 50.0)
		var from := c + Vector3(sin(a), 0, cos(a)) * 9.0
		_walk_at(from, c, -0.12)
		await _wait(2.5)
		await _shot(names[i] + "_pres")
		cam.set_walking(false)
		if node and node.last_anchors.has("shed"):
			var sh: Vector2 = node.last_anchors["shed"]
			var shed := node.to_global(Vector3(sh.x, 0, sh.y))
			var away := (c - shed).normalized()
			_walk_at(shed + away * 4.5 + Vector3(away.z, 0, -away.x) * 1.5, shed, -0.1)
			await _wait(2.5)
			await _shot(names[i] + "_cabane")
			cam.set_walking(false)
	quit()


## Contour arrondi d'un champ de taille `size` (demi-axes) autour de c.
func _rect(c: Vector3, size: Vector2) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for k in 16:
		var a := TAU * k / 16.0
		var x := signf(cos(a)) * pow(absf(cos(a)), 0.5) * size.x
		var z := signf(sin(a)) * pow(absf(sin(a)), 0.5) * size.y
		pts.append(c + Vector3(x, 0, z))
	return pts


## Un emplacement libre pour un champ de demi-taille `half`, entre deux rayons du
## centre, avec une pente moyenne entre lo et hi (la plus forte possible).
func _find(half: Vector2, r0: float, r1: float, lo: float, hi: float, placed: Array[Vector2]) -> Vector3:
	var ctx := site.context()
	var field := terrain.field
	var best := Vector3.INF
	var best_score := -INF
	var rad := half.length() + 1.5
	var woods: Array[PackedVector2Array] = []
	for id in site.ids():
		var rec: Dictionary = site.get_record(id)
		if rec.get("kind") == "forest":
			var wp := PackedVector2Array()
			for p: Vector3 in rec["points"]:
				wp.append(Vector2(p.x, p.z))
			woods.append(wp)
	for ri in 12:
		var r := lerpf(r0, r1, ri / 11.0)
		for ai in 36:
			var a := TAU * ai / 36.0
			var c := Vector2(cos(a), sin(a)) * r
			var ok := true
			for p in placed:
				if p.distance_to(c) < rad * 2.0:
					ok = false
			for k in 24:
				if not ok:
					break
				var b := TAU * k / 24.0
				for f: float in [0.0, 0.5, 1.0]:
					var q := c + Vector2(cos(b) * half.x, sin(b) * half.y) * f
					if ctx.blocked(q, 1.5) or field.water_level(q.x, q.y) > -INF:
						ok = false
						break
					for wp in woods:
						if Geometry2D.is_point_in_polygon(q, wp) or BastidePondShape.signed_distance(q, wp) < 4.0:
							ok = false
			if not ok:
				continue
			var s := field.slope(c.x, c.y)
			if s < lo or s > hi:
				continue
			var score := s - r * 0.002 if hi > 0.2 else -s - r * 0.01
			if score > best_score:
				best_score = score
				best = Vector3(c.x, 0, c.y)
	if best != Vector3.INF:
		placed.append(Vector2(best.x, best.z))
	return best


func _walk_at(p: Vector3, look: Vector3, pitch: float) -> void:
	if cam.walking:
		cam.set_walking(false)
	cam.target = p
	cam.focus(p)
	cam.set_walking(true)
	var d := look - p
	var yaw := atan2(-d.x, -d.z)
	cam.set("_goal_yaw", yaw)
	cam.set("_yaw", yaw)
	cam.set("_goal_walk_pitch", pitch)
	cam.set("_walk_pitch", pitch)


func _all_built() -> bool:
	for id in site.ids():
		var node := site.node_of(id)
		if node == null or node.last_stats.is_empty():
			return false
	return true


func _wait(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < sec * 1000.0:
		await process_frame


func _shot(shot_name: String) -> void:
	for i in 6:
		await process_frame
	if DisplayServer.get_name() == "headless":
		return
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [prefix, shot_name]))
	print("capture ", shot_name)
