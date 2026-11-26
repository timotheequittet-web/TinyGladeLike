class_name BastideGraphics
extends Node
## Réglages graphiques du jeu : quatre niveaux (Bas, Moyen, Haut, Ultra) qui règlent
## l'herbe, les ombres, les effets d'écran, la résolution de rendu, l'anticrénelage,
## les distances de détail et la limite d'images par seconde. Le choix est gardé
## dans user://bastide_graphics.cfg.
##
## En jeu : F3 affiche le compteur (images/s, temps d'image, triangles, appels de
## dessin), F4 passe au niveau suivant. Quand la fenêtre n'a pas le focus, le jeu
## ralentit à 15 images/s pour ne pas chauffer pour rien.

signal changed(preset: int)

enum Preset { BAS, MOYEN, HAUT, ULTRA }
const NAMES := ["Bas", "Moyen", "Haut", "Ultra"]
const SAVE_PATH := "user://bastide_graphics.cfg"

## Valeurs de chaque niveau.
##  grass/grass_radius : densité et étendue de l'herbe ; shadow_* : ombres du soleil ;
##  scale : part de la résolution rendue en 3D (agrandie par FSR) ; msaa : 0, 2, 4 ;
##  detail : multiplicateur des distances où les détails apparaissent ;
##  fps : limite d'images par seconde (0 = celle de l'écran).
const PRESETS := [
	{"grass": 0.35, "grass_radius": 0.6, "shadow_distance": 70.0, "shadow_splits": 2, "shadow_size": 2048,
		"shadow_soft": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, "ssao": false, "ssil": false,
		"volumetric_fog": false, "glow": true, "dof": false, "msaa": 0, "fxaa": true, "scale": 0.7,
		"detail": 0.5, "fps": 60},
	{"grass": 0.6, "grass_radius": 0.8, "shadow_distance": 110.0, "shadow_splits": 4, "shadow_size": 2048,
		"shadow_soft": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "ssao": true, "ssil": false,
		"volumetric_fog": false, "glow": true, "dof": true, "msaa": 0, "fxaa": true, "scale": 0.85,
		"detail": 0.75, "fps": 60},
	# Haut : l'éclairage indirect SSIL (cher pour un effet discret) est réservé à Ultra.
	{"grass": 1.0, "grass_radius": 1.0, "shadow_distance": 150.0, "shadow_splits": 4, "shadow_size": 4096,
		"shadow_soft": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "ssao": true, "ssil": false,
		"volumetric_fog": true, "glow": true, "dof": true, "msaa": 2, "fxaa": false, "scale": 1.0,
		"detail": 1.0, "fps": 60},
	# Ultra : plus de détail au loin et l'éclairage indirect, mais sans les réglages
	# qui coûtent beaucoup pour peu (MSAA x4 sur le feuillage, ombres très douces).
	{"grass": 1.2, "grass_radius": 1.15, "shadow_distance": 180.0, "shadow_splits": 4, "shadow_size": 4096,
		"shadow_soft": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, "ssao": true, "ssil": true,
		"volumetric_fog": true, "glow": true, "dof": true, "msaa": 2, "fxaa": false, "scale": 1.0,
		"detail": 1.3, "fps": 0},
]

## Multiplicateur courant des distances de détail (lu par les générateurs : forêts,
## plantations, décor). 1 = Haut.
static var detail := 1.0

@export var preset := Preset.HAUT
## Lit le niveau sauvegardé au démarrage (sinon, garde `preset`).
@export var load_saved := true
## Applique le niveau au démarrage (les parties scriptées de test le coupent).
@export var auto_apply := true
@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export var grass: BastideGrass
@export var camera: Camera3D
@export var show_stats := false:
	set(v):
		show_stats = v
		if _stats:
			_stats.visible = v

var _layer: CanvasLayer
var _stats: Label
var _toast: Label
var _stats_timer := 0.0
var _fps_cap := 60
var _range_timer := 0.0
## Mesure du vrai temps des scripts : un petit nœud passe en tout premier à
## chaque image et note l'heure, ce nœud-ci passe en tout dernier. Le moniteur
## TIME_PROCESS de Godot compte aussi l'attente de la carte graphique, il
## gonfle donc dès que l'image est limitée par le GPU.
var _script_start := 0
var _script_ms := 0.0


class _ScriptClock extends Node:
	var owner_gfx: Node
	func _process(_delta: float) -> void:
		owner_gfx.set("_script_start", Time.get_ticks_usec())


func _ready() -> void:
	if load_saved:
		var cfg := ConfigFile.new()
		if cfg.load(SAVE_PATH) == OK:
			preset = clampi(int(cfg.get_value("graphismes", "niveau", preset)), 0, PRESETS.size() - 1) as Preset
			show_stats = bool(cfg.get_value("graphismes", "compteur", show_stats))
	_build_overlay()
	process_priority = 1 << 30
	var clock := _ScriptClock.new()
	clock.name = "HorlogeScripts"
	clock.owner_gfx = self
	clock.process_priority = -(1 << 30)
	add_child(clock)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	(func() -> void:
		if auto_apply:
			apply(preset, false)).call_deferred()


func _notification(what: int) -> void:
	# Fenêtre en arrière-plan : on ralentit pour ne pas chauffer.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Engine.max_fps = 15
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Engine.max_fps = _fps_cap


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_F3:
		show_stats = not show_stats
		_save()
		get_viewport().set_input_as_handled()
	elif k.physical_keycode == KEY_F4:
		apply((preset + 1) % PRESETS.size())
		get_viewport().set_input_as_handled()


## Applique un niveau (Preset) à la scène.
func apply(p: int, announce := true) -> void:
	preset = clampi(p, 0, PRESETS.size() - 1) as Preset
	var q: Dictionary = PRESETS[preset]
	detail = q["detail"]
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if float(q["scale"]) < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = q["scale"]
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X][int(q["msaa"])]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q["fxaa"] else Viewport.SCREEN_SPACE_AA_DISABLED
	# Les distances de détail automatiques des maillages suivent le niveau.
	vp.mesh_lod_threshold = 1.0 / float(q["detail"])
	RenderingServer.directional_shadow_atlas_set_size(int(q["shadow_size"]), true)
	# Occlusion ambiante : demi-résolution sauf en Ultra.
	var ultra := preset == Preset.ULTRA
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH if ultra else RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
			not ultra, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_HIGH if ultra else RenderingServer.ENV_SSIL_QUALITY_MEDIUM,
			not ultra, 0.5, 4, 50.0, 300.0)
	RenderingServer.directional_soft_shadow_filter_set_quality(q["shadow_soft"])
	RenderingServer.positional_soft_shadow_filter_set_quality(q["shadow_soft"])
	if sun:
		sun.directional_shadow_max_distance = q["shadow_distance"]
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if int(q["shadow_splits"]) == 2 \
				else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	var env := world_environment.environment if world_environment else null
	if env:
		env.ssao_enabled = q["ssao"]
		env.ssil_enabled = q["ssil"]
		env.volumetric_fog_enabled = q["volumetric_fog"]
		env.glow_enabled = q["glow"]
	if camera and camera.attributes is CameraAttributesPractical:
		(camera.attributes as CameraAttributesPractical).dof_blur_far_enabled = q["dof"]
	if grass:
		grass.set_quality(q["grass"], q["grass_radius"])
	scale_ranges(get_tree().root)
	_fps_cap = q["fps"]
	Engine.max_fps = _fps_cap
	_save()
	changed.emit(preset)
	if announce:
		_show_toast("Graphismes : %s" % NAMES[preset])


## Met les distances d'affichage (visibility_range) de tout ce qui est sous `n` à
## l'échelle de `detail`. La valeur d'origine est gardée en méta ; si quelqu'un a
## changé la distance depuis (construction refaite), elle devient la nouvelle origine.
static func scale_ranges(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		var cur := Vector2(g.visibility_range_begin, g.visibility_range_end)
		if cur != Vector2.ZERO or g.has_meta(&"vis_base"):
			var base: Vector2 = g.get_meta(&"vis_base", cur)
			var last: Vector2 = g.get_meta(&"vis_last", cur)
			if not cur.is_equal_approx(last):
				base = cur
			var want := base * detail
			if not want.is_equal_approx(cur):
				g.visibility_range_begin = want.x
				g.visibility_range_end = want.y
			g.set_meta(&"vis_base", base)
			g.set_meta(&"vis_last", want)
	for c in n.get_children(true):
		scale_ranges(c)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphismes", "niveau", int(preset))
	cfg.set_value("graphismes", "compteur", show_stats)
	cfg.save(SAVE_PATH)


func _process(delta: float) -> void:
	if _script_start > 0:
		var ms := (Time.get_ticks_usec() - _script_start) / 1000.0
		_script_ms = lerpf(_script_ms, ms, 0.1) if _script_ms > 0.0 else ms
	# Les constructions refaites remettent leurs distances d'affichage : on les
	# remet à l'échelle du niveau de temps en temps (peu coûteux).
	_range_timer -= delta
	if _range_timer <= 0.0:
		_range_timer = 1.5
		scale_ranges(get_tree().root)
	if not show_stats:
		return
	_stats_timer -= delta
	if _stats_timer > 0.0:
		return
	_stats_timer = 0.5
	var rid := get_viewport().get_viewport_rid()
	var tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objs := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
	var script_ms := _script_ms + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_stats.text = "%s · %d i/s\ncarte graphique %.1f ms · rendu %.1f ms · scripts %.1f ms\n%s triangles · %d appels · %d objets\n[F3 compteur · F4 niveau]" % [
		NAMES[preset], int(fps), gpu, cpu, script_ms, _millions(tris), int(calls), int(objs)]


static func _millions(n: float) -> String:
	if n >= 1e6:
		return "%.2f M" % (n / 1e6)
	return "%d k" % int(n / 1000.0)


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	_stats = Label.new()
	_stats.position = Vector2(16, 12)
	_stats.add_theme_font_size_override("font_size", 15)
	_stats.add_theme_color_override("font_color", Color(1, 0.97, 0.9))
	_stats.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.06, 0.9))
	_stats.add_theme_constant_override("outline_size", 5)
	_stats.visible = show_stats
	_layer.add_child(_stats)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-120, 70)
	_toast.size = Vector2(240, 30)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_color", Color(1, 0.97, 0.9))
	_toast.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.06, 0.9))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.modulate.a = 0.0
	_layer.add_child(_toast)


func _show_toast(text: String) -> void:
	_toast.text = text
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.2)
	tw.tween_interval(1.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)
