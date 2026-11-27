## Rendu allégé pour les parties scriptées : le rendu logiciel des conteneurs de
## test est très lent avec l'herbe dense et le brouillard volumétrique. Les parties
## vérifient la construction, pas l'ambiance (voir ambiance_shots.gd pour ça).
## FULL_RENDER=1 garde le rendu complet. En headless, la fenêtre par défaut est
## trop petite pour les clics simulés : on lui donne la taille des captures.
static func apply(scene: Node) -> void:
	var gfx := scene.get_node_or_null("Graphismes") as BastideGraphics
	if gfx:
		gfx.auto_apply = false
	if DisplayServer.get_name() == "headless":
		scene.get_tree().root.size = Vector2i(1600, 900)
		return
	if OS.has_environment("FULL_RENDER"):
		return
	var env := (scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	env.glow_enabled = false
	env.volumetric_fog_enabled = false
	env.ssil_enabled = false
	env.ssao_enabled = false
	env.sdfgi_enabled = false
	var grass := scene.get_node_or_null("Herbe")
	if grass is Node3D:
		(grass as Node3D).visible = false
	var cam := scene.get_node_or_null("Camera") as Camera3D
	if cam and cam.attributes is CameraAttributesPractical:
		(cam.attributes as CameraAttributesPractical).dof_blur_far_enabled = false
