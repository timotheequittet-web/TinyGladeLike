extends Node3D
## Démo des étapes 4 à 6 : construire soi-même, en jeu, à la souris.
##
## Le hameau de départ sort de terre au lancement ; ensuite, à toi : dessine des
## murets, tire des maisons, agrandis-les en L, trace des chemins, pose des torii,
## plante des massifs et des arbres, pose des terrasses et des engawa, retouche
## avec les poignées. Un muret traversé par un chemin s'ouvre en portail. Le jardin
## (galets, plantes au pied des murs) pousse tout seul.
## L'interface est construite ici, en code, pour rester légère et discrète.

const JAPANESE := preload("res://addons/bastide/styles/presets/japanese_wood.tres")
const MEDIEVAL := preload("res://addons/bastide/styles/presets/medieval_stone.tres")
const SAVE_PATH := "user://bastide_chantier.json"

@onready var site: BastideBuildSite = $Chantier
@onready var tool: BastideBuildTool = $Outil
@onready var camera: BastideOrbitCamera = $Camera
@onready var ambience: Node = $Ambiance

var _ui: CanvasLayer
var _hint: Label
var _hint_tween: Tween
var _mode_buttons := {}
var _variant_buttons := {}
var _variant_panel: PanelContainer
var _forest_buttons := {}
var _forest_panel: PanelContainer
var _style_buttons := {}
var _undo_btn: Button
var _redo_btn: Button
var _sel_panel: PanelContainer
var _floor_box: HBoxContainer
var _toast: Label
var _ui_visible := true


## Hameau de départ (coordonnées du chantier = monde).
func _starting_village() -> Array:
	var j := JAPANESE.resource_path
	return [
		{"kind": "house", "seed": 12, "floors": 2, "style": j, "door": 2,
			"points": [[-9, 0, -6], [1, 0, -6], [1, 0, 0], [-9, 0, 0]]},
		{"kind": "house", "seed": 31, "floors": 1, "style": j, "door": 2,
			"points": [[6, 0, -11], [14, 0, -11], [14, 0, 3], [9, 0, 3], [9, 0, -5], [6, 0, -5]]},
		# Le grand muret à petit toit : le chemin le traverse, un portail s'y ouvre.
		{"kind": "wall", "seed": 4, "height": 1.9, "style": j, "closed": false,
			"points": [[-13, 0, -1], [-13.5, 0, 5], [-10, 0, 8.5], [-4, 0, 9], [2, 0, 9], [7, 0, 8.4], [10.5, 0, 6.5]]},
		# Engawa le long de la façade de la grande maison, à gauche de la porte.
		{"kind": "terrace", "seed": 8, "style": j, "entry": -1,
			"points": [[-8.7, 0, 0.3], [-4.6, 0, 0.3], [-4.6, 0, 1.8], [-8.7, 0, 1.8]]},
		# Le chemin qui monte vers le hameau, et sa branche vers la seconde maison.
		{"kind": "path", "seed": 5, "style": j,
			"points": [[-1, 0, 26], [0.5, 0, 18], [-0.6, 0, 11], [-2.2, 0, 5], [-4, 0, 2.6]]},
		{"kind": "path", "seed": 6, "style": j,
			"points": [[-1.6, 0, 6.6], [3, 0, 6.4], [8, 0, 5.6], [11.5, 0, 4.8]]},
		{"kind": "torii", "seed": 2, "style": j, "points": [[-1.7, 0, 15.3], [1.35, 0, 14.6]]},
		# Clôture de bambou entre les deux maisons : elle s'ouvre pour le chemin.
		{"kind": "fence", "seed": 3, "variant": 1, "style": j, "closed": false,
			"points": [[3.6, 0, -9], [3.4, 0, -2], [3.8, 0, 3], [3.4, 0, 8.6]]},
		# Muret de pierres sèches au bord du pré.
		{"kind": "fence", "seed": 9, "variant": 0, "style": j, "closed": false,
			"points": [[-5, 0, 17], [-10, 0, 15.5], [-14.5, 0, 12], [-17, 0, 7]]},
		{"kind": "plants", "seed": 21, "style": j, "points": [[5, 0, 12.5], [8.5, 0, 11.5], [12, 0, 9]]},
		{"kind": "plants", "seed": 14, "style": j, "points": [[-9.8, 0, 4.4]]},
		{"kind": "plants", "seed": 27, "style": j, "points": [[4.2, 0, 16.5]]},
		{"kind": "plants", "seed": 33, "style": j, "points": [[-11.5, 0, -4.5]]},
		# Terrasse au bord de l'étang, et le chemin qui y mène.
		{"kind": "terrace", "seed": 17, "style": j, "entry": -1,
			"points": [[-22.8, 0, 13.8], [-18.8, 0, 13.8], [-18.8, 0, 16.8], [-22.8, 0, 16.8]]},
		{"kind": "path", "seed": 19, "style": j,
			"points": [[0.3, 0, 20], [-6, 0, 20.8], [-12, 0, 19.2], [-16.8, 0, 16.4]]},
		# La forêt mêlée qui ferme le hameau au nord (arbres d'Onsen) : on peut s'y promener.
		{"kind": "forest", "seed": 41, "style": j, "closed": true, "forest_kind": 0,
			"points": [[-34, 0, -16], [-12, 0, -15], [4, 0, -17], [22, 0, -16], [36, 0, -20], [38, 0, -44], [10, 0, -52], [-20, 0, -50], [-38, 0, -38]]},
	]


func _ready() -> void:
	_build_ui()
	tool.style = JAPANESE
	site.garden_style = JAPANESE
	tool.hint_changed.connect(_show_hint)
	tool.mode_changed.connect(func(_m: int) -> void: _refresh_mode())
	tool.variant_changed.connect(func(_v: int) -> void: _refresh_mode())
	tool.forest_kind_changed.connect(func(_k: int) -> void: _refresh_mode())
	tool.selection_changed.connect(func(_id: int) -> void: _refresh_selection())
	tool.history_changed.connect(func(u: bool, r: bool) -> void:
		_undo_btn.disabled = not u
		_redo_btn.disabled = not r)
	tool.placed.connect(func(_k: String) -> void: ambience.play_place())
	tool.edited.connect(func() -> void: ambience.play_edit())
	tool.removed.connect(func(_k: String) -> void: ambience.play_remove())
	site.structure_changed.connect(func(_id: int) -> void: _refresh_selection())
	_refresh_mode()
	_refresh_selection()
	_undo_btn.disabled = true
	_redo_btn.disabled = true
	# Arrivée en douceur : la caméra descend vers le hameau pendant qu'il sort de terre.
	camera.glide_to(Vector3(-1, 0, -1), 30.0, 14.0, 0.9)
	# Le hameau sort de terre, une maison après l'autre.
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		var data := _starting_village()
		for i in data.size():
			data[i]["id"] = i + 1
		site.from_data(data, true, 0.3))
	_show_hint(tool.current_hint())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.physical_keycode == KEY_H:
			_ui_visible = not _ui_visible
			for c in _ui.get_children():
				var tw := create_tween()
				tw.tween_property(c, "modulate:a", 1.0 if _ui_visible else 0.0, 0.3)
		elif (k.ctrl_pressed or k.meta_pressed) and k.keycode == KEY_S:
			_save()
		elif (k.ctrl_pressed or k.meta_pressed) and (k.keycode == KEY_O or k.keycode == KEY_L):
			_load()


# --- Sauvegarde -----------------------------------------------------------------

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		_toast_msg("Impossible d'enregistrer")
		return
	f.store_string(JSON.stringify(site.to_data(), "\t"))
	_toast_msg("Hameau enregistré")


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_toast_msg("Aucun hameau enregistré pour l'instant")
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Array:
		_toast_msg("Fichier illisible")
		return
	tool.select(-1)
	site.from_data(data, true, 0.25)
	tool.clear_history()
	_toast_msg("Hameau rechargé")


# --- Interface ------------------------------------------------------------------

const INK := Color(0.24, 0.2, 0.17)
const PAPER := Color(0.98, 0.96, 0.91, 0.84)
const ACCENT := Color(0.78, 0.3, 0.2)


func _panel_style(alpha := 0.84) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PAPER, alpha)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0.2, 0.15, 0.1, 0.12)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 3)
	return sb


func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0)
	normal.set_corner_radius_all(11)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.55)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(ACCENT, 0.16)
	pressed.border_color = Color(ACCENT, 0.55)
	pressed.set_border_width_all(1)
	var disabled := normal.duplicate() as StyleBoxFlat
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_pressed_color", "Button", ACCENT.darkened(0.2))
	t.set_color("font_hover_pressed_color", "Button", ACCENT.darkened(0.2))
	t.set_color("font_disabled_color", "Button", Color(INK, 0.3))
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", _panel_style())
	return t


func _button(parent: Control, text: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _sep(parent: Control) -> void:
	var s := VSeparator.new()
	var sb := StyleBoxLine.new()
	sb.color = Color(INK, 0.15)
	sb.vertical = true
	s.add_theme_stylebox_override("separator", sb)
	parent.add_child(s)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "Interface"
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	_ui.add_child(root)

	# Barre d'outils, en bas au centre.
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE, 22)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	bar.add_child(hb)
	_mode_buttons[BastideBuildTool.Mode.WALL] = _button(hb, "Muret  1", func() -> void: tool.mode = BastideBuildTool.Mode.WALL, true)
	_mode_buttons[BastideBuildTool.Mode.HOUSE] = _button(hb, "Maison  2", func() -> void: tool.mode = BastideBuildTool.Mode.HOUSE, true)
	_mode_buttons[BastideBuildTool.Mode.PATH] = _button(hb, "Chemin  3", func() -> void: tool.mode = BastideBuildTool.Mode.PATH, true)
	_mode_buttons[BastideBuildTool.Mode.TORII] = _button(hb, "Torii  4", func() -> void: tool.mode = BastideBuildTool.Mode.TORII, true)
	_mode_buttons[BastideBuildTool.Mode.PLANTS] = _button(hb, "Plantes  5", func() -> void: tool.mode = BastideBuildTool.Mode.PLANTS, true)
	_mode_buttons[BastideBuildTool.Mode.TERRACE] = _button(hb, "Terrasse  T", func() -> void: tool.mode = BastideBuildTool.Mode.TERRACE, true)
	_mode_buttons[BastideBuildTool.Mode.FOREST] = _button(hb, "Forêt  B", func() -> void: tool.mode = BastideBuildTool.Mode.FOREST, true)
	_sep(hb)
	_style_buttons[JAPANESE] = _button(hb, "Japonais", func() -> void: _pick_style(JAPANESE), true)
	_style_buttons[MEDIEVAL] = _button(hb, "Médiéval", func() -> void: _pick_style(MEDIEVAL), true)
	_sep(hb)
	_undo_btn = _button(hb, "Annuler", tool.undo)
	_redo_btn = _button(hb, "Rétablir", tool.redo)

	# Variantes du muret (touche V), juste au-dessus quand le mode Muret est actif.
	_variant_panel = PanelContainer.new()
	_variant_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE, 84)
	_variant_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_variant_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_variant_panel)
	var vhb := HBoxContainer.new()
	vhb.add_theme_constant_override("separation", 4)
	_variant_panel.add_child(vhb)
	_variant_buttons[BastideBuildTool.WallVariant.ROOFED] = _button(vhb, "Muret à petit toit",
			func() -> void: tool.wall_variant = BastideBuildTool.WallVariant.ROOFED, true)
	_variant_buttons[BastideBuildTool.WallVariant.DRY_STONE] = _button(vhb, "Pierres sèches",
			func() -> void: tool.wall_variant = BastideBuildTool.WallVariant.DRY_STONE, true)
	_variant_buttons[BastideBuildTool.WallVariant.BAMBOO] = _button(vhb, "Bambou",
			func() -> void: tool.wall_variant = BastideBuildTool.WallVariant.BAMBOO, true)

	# Sortes de forêt (touche V en mode Forêt), au même endroit.
	_forest_panel = PanelContainer.new()
	_forest_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE, 84)
	_forest_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_forest_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_forest_panel)
	var fhb := HBoxContainer.new()
	fhb.add_theme_constant_override("separation", 4)
	_forest_panel.add_child(fhb)
	var fnames := ["Mêlée", "Cèdres", "Chênaie", "Érables", "Cerisiers", "Pinède"]
	for k in fnames.size():
		_forest_buttons[k] = _button(fhb, fnames[k], func() -> void: tool.forest_kind = k as BastideForestBuilder.Kind, true)

	# Panneau de la structure sélectionnée, juste au-dessus.
	_sel_panel = PanelContainer.new()
	_sel_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE, 84)
	_sel_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sel_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_sel_panel)
	var shb := HBoxContainer.new()
	shb.add_theme_constant_override("separation", 4)
	_sel_panel.add_child(shb)
	_floor_box = HBoxContainer.new()
	shb.add_child(_floor_box)
	_button(_floor_box, "Étage −", func() -> void: tool.change_floors(-1))
	_button(_floor_box, "Étage +", func() -> void: tool.change_floors(1))
	_button(shb, "Autre variation  R", tool.reroll_selected)
	_button(shb, "Retirer", tool.delete_selected)

	# Aide contextuelle, au-dessus de tout le reste.
	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE, 140)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(1, 0.98, 0.94))
	_hint.add_theme_color_override("font_shadow_color", Color(0.15, 0.1, 0.05, 0.55))
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	_hint.add_theme_constant_override("shadow_outline_size", 6)
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint)

	# Titre discret et rappel des commandes de la caméra.
	var title := Label.new()
	title.position = Vector2(26, 20)
	title.text = "Bastide · hameau de campagne"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.98, 0.94))
	title.add_theme_color_override("font_shadow_color", Color(0.15, 0.1, 0.05, 0.5))
	title.add_theme_constant_override("shadow_outline_size", 6)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)
	var keys := Label.new()
	keys.position = Vector2(28, 54)
	keys.text = "Clic droit + souris : tourner   ·   molette : zoomer\nZQSD : glisser   ·   A / E : pivoter   ·   F : recentrer\n1 à 5, T, B : outils   ·   V : variante (muret, forêt)\nCtrl+S / Ctrl+O : enregistrer / recharger   ·   M : son   ·   H : masquer"
	keys.add_theme_font_size_override("font_size", 13)
	keys.add_theme_color_override("font_color", Color(1, 0.98, 0.94, 0.85))
	keys.add_theme_color_override("font_shadow_color", Color(0.15, 0.1, 0.05, 0.5))
	keys.add_theme_constant_override("shadow_outline_size", 5)
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(keys)

	# Petit bouton « tout retirer », en haut à droite.
	var tr := PanelContainer.new()
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 18)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(tr)
	_button(tr, "Tout retirer", tool.clear_all)

	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_SIZE, 26)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", Color(1, 0.98, 0.94))
	_toast.add_theme_color_override("font_shadow_color", Color(0.15, 0.1, 0.05, 0.55))
	_toast.add_theme_constant_override("shadow_outline_size", 6)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)


func _pick_style(st: BastideStyle) -> void:
	tool.set_style(st)
	_refresh_style_buttons()


func _refresh_style_buttons() -> void:
	for st: BastideStyle in _style_buttons:
		(_style_buttons[st] as Button).set_pressed_no_signal(st == tool.style)


func _refresh_mode() -> void:
	for m: int in _mode_buttons:
		(_mode_buttons[m] as Button).set_pressed_no_signal(m == tool.mode)
	for v: int in _variant_buttons:
		(_variant_buttons[v] as Button).set_pressed_no_signal(v == tool.wall_variant)
	for k: int in _forest_buttons:
		(_forest_buttons[k] as Button).set_pressed_no_signal(k == int(tool.forest_kind))
	_refresh_style_buttons()
	_refresh_selection()


func _refresh_selection() -> void:
	var has := tool.selected >= 0 and site.has(tool.selected)
	# Le panneau des variantes cède la place à celui de la sélection.
	var show_variants := tool.mode == BastideBuildTool.Mode.WALL and not has
	var tv := create_tween()
	tv.tween_property(_variant_panel, "modulate:a", 1.0 if show_variants else 0.0, 0.25)
	_variant_panel.mouse_filter = Control.MOUSE_FILTER_STOP if show_variants else Control.MOUSE_FILTER_IGNORE
	for b in _variant_panel.find_children("*", "Button", true, false):
		(b as Button).disabled = not show_variants
	var show_forests := tool.mode == BastideBuildTool.Mode.FOREST and not has
	var tf := create_tween()
	tf.tween_property(_forest_panel, "modulate:a", 1.0 if show_forests else 0.0, 0.25)
	_forest_panel.mouse_filter = Control.MOUSE_FILTER_STOP if show_forests else Control.MOUSE_FILTER_IGNORE
	for b in _forest_panel.find_children("*", "Button", true, false):
		(b as Button).disabled = not show_forests
	var tw := create_tween()
	tw.tween_property(_sel_panel, "modulate:a", 1.0 if has else 0.0, 0.25)
	_sel_panel.mouse_filter = Control.MOUSE_FILTER_STOP if has else Control.MOUSE_FILTER_IGNORE
	for b in _sel_panel.find_children("*", "Button", true, false):
		(b as Button).disabled = not has
	if has:
		var rec: Dictionary = site.get_record(tool.selected)
		_floor_box.visible = rec["kind"] == "house"
		# Le style de la structure sélectionnée s'affiche dans la barre.
		var st := site.style_of(rec)
		if st:
			for s: BastideStyle in _style_buttons:
				(_style_buttons[s] as Button).set_pressed_no_signal(s.resource_path == st.resource_path)
	else:
		_refresh_style_buttons()


func _show_hint(text: String) -> void:
	if _hint.text == text:
		return
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.12)
	_hint_tween.tween_callback(func() -> void: _hint.text = text)
	_hint_tween.tween_property(_hint, "modulate:a", 1.0, 0.25)


func _toast_msg(text: String) -> void:
	_toast.text = text
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.6)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.6)
