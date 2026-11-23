extends SceneTree
## Captures de la démo (outil de développement).
##   godot --path . -s tools/screenshot.gd -- <dossier_sortie> [scène]
## Prend plusieurs vues prédéfinies et enregistre des PNG.

var _wall_views := [
	["vue_generale", Vector3(-6, 13, 34), Vector3(-22, 0, 0)],
	["enceinte", Vector3(-24, 7, 4), Vector3(-18, -125, 0)],
	["mur_courbe", Vector3(10, 4.5, 21), Vector3(-12, 20, 0)],
	["tour_ronde", Vector3(19, 6, 2), Vector3(-15, 45, 0)],
	["detail_pilier", Vector3(-10.5, 3.6, 16.5), Vector3(-12, 25, 0)],
]


var _building_views := [
	["etape2_vue_generale", Vector3(2, 19, 44), Vector3(-24, 0, 0)],
	["etape2_maison", Vector3(-9, 5, 10), Vector3(-10, -40, 0)],
	["etape2_ferme_en_l", Vector3(8, 14, 12), Vector3(-38, 25, 0)],
	["etape2_manoir_en_u", Vector3(-8, 8, 38), Vector3(-14, 0, 0)],
	["etape2_biscornue", Vector3(29, 6, 26), Vector3(-10, 40, 0)],
	["etape2_toits", Vector3(4, 26, 8), Vector3(-62, -20, 0)],
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "/tmp/shots"
	var scene_path: String = args[1] if args.size() > 1 else "res://demos/01_wall/wall_demo.tscn"
	var views: Array = _building_views if scene_path.contains("02_building") else _wall_views
	var scene: Node = (load(scene_path) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	var ui := scene.get_node_or_null("Interface") as CanvasLayer
	# Laisse le temps aux générations en arrière-plan de se terminer.
	for i in 30:
		await process_frame
	await create_timer(1.5).timeout
	var cam := scene.get_node("Camera") as Camera3D
	cam.set_process(false)
	cam.set_process_unhandled_input(false)
	for v in views:
		if ui:
			ui.visible = (v[0] as String).ends_with("vue_generale")
		cam.position = v[1]
		cam.rotation_degrees = v[2]
		for i in 12:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join(v[0] + ".png"))
		print("capture ", v[0])
	quit()
