class_name BastideBuildTool
extends Node3D
## Construction en jeu à la souris, façon Tiny Glade.
##
## - Mode MUR : maintiens le clic et dessine un chemin au sol. Le mur pousse en
##   direct sous forme de fantôme ; relâche pour le poser. Revenir près du point de
##   départ ferme l'enceinte.
## - Mode MAISON : maintiens le clic et tire un rectangle. Si le rectangle chevauche
##   une maison existante, il s'y ajoute (maison en L, en T, en U…).
## - Mode CHEMIN : dessine un chemin ; près d'une porte il la rejoint, près d'un
##   autre chemin il s'y raccorde.
## - Mode TORII : un torii fantôme suit la souris et se cale sur les chemins ; clic
##   pour le poser.
## - Mode PLANTES : dessine un massif, ou clique pour planter un arbre.
## - Mode TERRASSE : tire un rectangle ; contre une maison, il devient un engawa
##   collé à la façade (jamais devant la porte). Isolée, la terrasse a un
##   garde-corps et ses marches donnent vers la caméra.
## - Mode ÉTANG (touche J) : fais le tour d'une zone ; la rive s'arrondit toute
##   seule, le sol se creuse, l'eau reste à plat sur la pente. V : étang de jardin,
##   source chaude (onsen) ou mare sauvage.
## - Variantes du mode MUR (touche V) : muret à petit toit, muret de pierres sèches,
##   clôture de bambou.
## - Clic sur une structure : la sélectionne. Des poignées apparaissent : on tire
##   un angle, un côté de maison ou un point de mur pour retoucher ; clic droit sur
##   une poignée de mur : retire ce point.
## - Suppr : supprimer ; R : autre variation ; G : silhouette de la maison (petite
##   maison, kura, tour…) ; + / − (ou Page haut/bas) : étages ;
##   Ctrl+Z / Ctrl+Y : annuler / rétablir ; Échap : annuler le tracé ou désélectionner.
##
## Le style appliqué est `style` : il vaut pour les nouvelles structures et, via
## set_style(), pour la structure sélectionnée.
##
## Le nœud ne contient aucune règle de génération : il fabrique des records et les
## confie au BastideBuildSite, qui fait le reste.

enum Mode { WALL, HOUSE, PATH, TORII, PLANTS, TERRACE, FOREST, POND, FARM }
## Variantes du mode MUR.
enum WallVariant { ROOFED, DRY_STONE, BAMBOO }

signal mode_changed(mode: Mode)
signal variant_changed(variant: WallVariant)
signal forest_kind_changed(kind: int)
signal pond_kind_changed(kind: int)
signal farm_kind_changed(kind: int)
signal selection_changed(id: int)
## Une structure vient d'être posée ou retirée (pour jouer un son, par exemple).
signal placed(kind: String)
signal removed(kind: String)
signal edited()
## Texte d'aide adapté à ce que fait le joueur.
signal hint_changed(text: String)
signal history_changed(can_undo: bool, can_redo: bool)

@export var site: BastideBuildSite
@export var camera: Camera3D
@export var mode := Mode.WALL:
	set(value):
		if mode == value:
			return
		cancel_draft()
		mode = value
		mode_changed.emit(mode)
		_emit_hint()
@export var style: BastideStyle
## Variante des murs tracés en mode MUR.
@export var wall_variant := WallVariant.ROOFED:
	set(value):
		if wall_variant == value:
			return
		cancel_draft()
		wall_variant = value
		variant_changed.emit(wall_variant)
		_emit_hint()
## Sorte des forêts tracées en mode FORÊT (essences, voir BastideForestBuilder.Kind).
@export var forest_kind := BastideForestBuilder.Kind.MIXED:
	set(value):
		if forest_kind == value:
			return
		cancel_draft()
		forest_kind = value
		forest_kind_changed.emit(int(forest_kind))
		_emit_hint()
## Surface minimale d'une forêt (m²).
@export var forest_min_area := 60.0
## Sorte des étangs tracés en mode ÉTANG (voir BastidePondBuilder.Kind).
@export var pond_kind := BastidePondBuilder.Kind.GARDEN:
	set(value):
		if pond_kind == value:
			return
		cancel_draft()
		pond_kind = value
		pond_kind_changed.emit(int(pond_kind))
		_emit_hint()
## Surface minimale d'un étang (m²).
@export var pond_min_area := 6.0
## Sorte des champs tracés en mode CHAMP (voir BastideFarmBuilder.Kind).
@export var farm_kind := BastideFarmBuilder.Kind.VEGETABLE:
	set(value):
		if farm_kind == value:
			return
		cancel_draft()
		farm_kind = value
		farm_kind_changed.emit(int(farm_kind))
		_emit_hint()
## Surface minimale d'un champ (m²).
@export var farm_min_area := 10.0
## Hauteur des murets posés (0 = celle du style).
@export var wall_height := 1.9
## Hauteur du sol (plan de construction).
@export var ground_height := 0.0
## Couches de collision du terrain : si non nul, on vise le relief au lieu du plan.
@export_flags_3d_physics var ground_mask := 0
## Pas d'arrondi des dimensions des maisons.
@export var house_snap := 0.5
@export var house_min_side := 4.0
@export var house_max_side := 22.0
## Plus grand côté d'une terrasse.
@export var terrace_max_side := 12.0
## Longueur minimale d'un mur.
@export var wall_min_length := 1.5
## Transparence de l'aperçu fantôme.
@export_range(0.0, 1.0) var ghost_transparency := 0.45
@export var ink_color := Color(1.0, 0.96, 0.86, 0.8)

const HANDLE_SHADER := preload("res://addons/bastide/runtime/bastide_handle.gdshader")
const HIGHLIGHT_SHADER := preload("res://addons/bastide/runtime/bastide_highlight.gdshader")
const INK_SHADER := preload("res://addons/bastide/runtime/bastide_ground_ink.gdshader")
const DRAG_THRESHOLD := 6.0
## Distance (le long du tracé) au-delà de laquelle un muret tracé ne bouge plus.
const FREEZE_DIST := 4.0
const HANDLE_PICK_RADIUS := 17.0

enum _State { IDLE, PRESSING, DRAWING, DRAGGING }
var _state := _State.IDLE
var _press_screen := Vector2.ZERO
var _press_ground := Vector3.ZERO
var _undo := UndoRedo.new()

# Tracé en cours.
var _draft: BastideStructure
var _draft_rec := {}
var _raw := PackedVector3Array()
# Début du tracé déjà figé (points de contrôle qui ne bougent plus) et l'indice
# du point brut où reprend la partie encore libre.
var _frozen := PackedVector3Array()
var _frozen_at := 0
var _merge_id := -1

# Sélection, survol, poignées.
var selected := -1
var _hover := -1
var _handles: Array = []  # [{pos, kind, index}]
var _handle_nodes: Array[MeshInstance3D] = []
var _hover_handle := -1
var _drag_handle := {}
var _drag_before := {}
var _drag_start_ground := Vector3.ZERO
var _drag_start_points := PackedVector3Array()

var _ink: MeshInstance3D
var _ink_mesh := ImmediateMesh.new()
var _cursor: MeshInstance3D
var _mat_hover: ShaderMaterial
var _mat_selected: ShaderMaterial
var _ghost_overlay: ShaderMaterial
var _torii_snapped := false
var _terrace_engawa := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if style == null:
		style = BastideStyle.create_default()
	_mat_hover = ShaderMaterial.new()
	_mat_hover.shader = HIGHLIGHT_SHADER
	_mat_hover.set_shader_parameter("strength", 0.25)
	_mat_selected = ShaderMaterial.new()
	_mat_selected.shader = HIGHLIGHT_SHADER
	_mat_selected.set_shader_parameter("strength", 0.5)
	_ghost_overlay = ShaderMaterial.new()
	_ghost_overlay.shader = HIGHLIGHT_SHADER
	_ghost_overlay.set_shader_parameter("strength", 0.5)
	_ghost_overlay.set_shader_parameter("color", Color(0.85, 0.93, 1.0))

	_ink = MeshInstance3D.new()
	_ink.name = "Trace"
	_ink.mesh = _ink_mesh
	_ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ink_mat := ShaderMaterial.new()
	ink_mat.shader = INK_SHADER
	ink_mat.set_shader_parameter("color", ink_color)
	_ink.material_override = ink_mat
	_ink.top_level = true
	add_child(_ink)

	_cursor = MeshInstance3D.new()
	_cursor.name = "Curseur"
	_cursor.top_level = true
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.5
	ring.rings = 32
	ring.ring_segments = 6
	var cursor_mat := StandardMaterial3D.new()
	cursor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cursor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cursor_mat.albedo_color = Color(ink_color, 0.55)
	ring.material = cursor_mat
	_cursor.mesh = ring
	_cursor.scale = Vector3(1, 0.15, 1)
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cursor)
	_cursor.visible = false

	if site:
		site.structure_removed.connect(func(id: int) -> void:
			if id == selected:
				select(-1)
			if id == _hover:
				_hover = -1)
	_emit_hint.call_deferred()


# --- API pour l'interface -------------------------------------------------------

func undo() -> void:
	cancel_draft()
	if _undo.has_undo():
		_undo.undo()
		_after_history()


func redo() -> void:
	cancel_draft()
	if _undo.has_redo():
		_undo.redo()
		_after_history()


func can_undo() -> bool:
	return _undo.has_undo()


func can_redo() -> bool:
	return _undo.has_redo()


## Oublie tout l'historique (après un chargement, par exemple).
func clear_history() -> void:
	_undo.clear_history()
	history_changed.emit(false, false)


func select(id: int) -> void:
	if selected == id:
		return
	var old := site.node_of(selected) if site and selected >= 0 else null
	selected = id
	_refresh_look(old)
	_refresh_look(site.node_of(selected) if selected >= 0 else null)
	_rebuild_handles()
	selection_changed.emit(selected)
	_emit_hint()


func delete_selected() -> void:
	if selected < 0 or not site.has(selected):
		return
	var id := selected
	var before: Dictionary = site.get_record(id)
	_commit("Supprimer", [[id, before, null]], true)
	removed.emit(before["kind"])


## Nouvelle variation (seed) pour la structure sélectionnée.
func reroll_selected() -> void:
	if selected < 0 or not site.has(selected):
		return
	var before: Dictionary = site.get_record(selected)
	var after := before.duplicate(true)
	after["seed"] = _rng.randi_range(1, 99999)
	_commit("Variation", [[selected, before, after]], true)
	edited.emit()


## Ajoute (ou retire) des étages à la maison sélectionnée.
func change_floors(delta: int) -> void:
	if selected < 0 or not site.has(selected):
		return
	var before: Dictionary = site.get_record(selected)
	if before["kind"] != "house":
		return
	var node := site.node_of(selected)
	var current := int(before.get("floors", 0))
	if current <= 0:
		current = node.get_effective_style().get_building_style().floors if node else 2
	var f := clampi(current + delta, 1, 4)
	if f == current:
		return
	var after := before.duplicate(true)
	after["floors"] = f
	_commit("Étages", [[selected, before, after]], true)
	edited.emit()


## Silhouette suivante pour la maison sélectionnée (automatique, grande maison,
## petite maison, kura, tour).
func cycle_silhouette() -> void:
	if selected < 0 or not site.has(selected):
		return
	var before: Dictionary = site.get_record(selected)
	if before["kind"] != "house":
		return
	var cur := int(before.get("shape", BastideSilhouette.Kind.AUTO))
	var i := BastideSilhouette.CYCLE.find(cur)
	var after := before.duplicate(true)
	after["shape"] = BastideSilhouette.CYCLE[(i + 1) % BastideSilhouette.CYCLE.size()]
	# Les étages suivent la nouvelle silhouette.
	after["floors"] = 0
	_commit("Silhouette", [[selected, before, after]], true)
	edited.emit()


## Nom de la silhouette de la maison sélectionnée ("" si ce n'en est pas une).
func selected_silhouette_name() -> String:
	if selected < 0 or not site.has(selected) or site.get_record(selected)["kind"] != "house":
		return ""
	var node := site.node_of(selected) as BastideBuilding
	if node == null:
		return ""
	var shape := int(site.get_record(selected).get("shape", 0))
	var name: String = BastideSilhouette.NAMES[node.resolved_silhouette()]
	return name + (" (auto)" if shape == BastideSilhouette.Kind.AUTO else "")


## Change le style des prochaines constructions et de la structure sélectionnée.
func set_style(new_style: BastideStyle) -> void:
	style = new_style
	if selected >= 0 and site.has(selected):
		var before: Dictionary = site.get_record(selected)
		if before.get("style", "") != new_style.resource_path:
			var after := before.duplicate(true)
			after["style"] = new_style.resource_path
			_commit("Style", [[selected, before, after]], true)
			edited.emit()


## Applique un style à tout le chantier d'un coup (une seule annulation).
func set_style_everywhere(new_style: BastideStyle) -> void:
	style = new_style
	var changes := []
	for id in site.ids():
		var before: Dictionary = site.get_record(id)
		if before.get("style", "") != new_style.resource_path:
			var after := before.duplicate(true)
			after["style"] = new_style.resource_path
			changes.append([id, before, after])
	if not changes.is_empty():
		_commit("Style partout", changes, true)
		edited.emit()


## Retire tout (une seule annulation suffit à tout ramener).
func clear_all() -> void:
	cancel_draft()
	var changes := []
	for id in site.ids():
		changes.append([id, site.get_record(id), null])
	if not changes.is_empty():
		_commit("Tout retirer", changes, true)
		removed.emit("all")


## Sorte de forêt suivante (et passe en mode FORÊT).
func cycle_forest_kind() -> void:
	mode = Mode.FOREST
	forest_kind = ((int(forest_kind) + 1) % BastideForestBuilder.Kind.size()) as BastideForestBuilder.Kind


## Sorte d'étang suivante (et passe en mode ÉTANG).
func cycle_pond_kind() -> void:
	mode = Mode.POND
	pond_kind = ((int(pond_kind) + 1) % BastidePondBuilder.Kind.size()) as BastidePondBuilder.Kind


## Sorte de champ suivante (et passe en mode CHAMP).
func cycle_farm_kind() -> void:
	mode = Mode.FARM
	farm_kind = ((int(farm_kind) + 1) % BastideFarmBuilder.Kind.size()) as BastideFarmBuilder.Kind


## Variante suivante du mode MUR (et passe en mode MUR).
func cycle_wall_variant() -> void:
	mode = Mode.WALL
	wall_variant = ((int(wall_variant) + 1) % 3) as WallVariant


func cancel_draft() -> void:
	if _draft:
		_draft.queue_free()
		_draft = null
	if _merge_id >= 0 and site.node_of(_merge_id):
		site.node_of(_merge_id).visible = true
	_merge_id = -1
	_raw.clear()
	_ink_mesh.clear_surfaces()
	if _state == _State.DRAWING or _state == _State.PRESSING:
		_state = _State.IDLE
	_emit_hint()


# --- Entrées --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if site == null or camera == null:
		return
	if event is InputEventMouseMotion:
		_on_motion((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_press(mb.position)
			else:
				_on_release(mb.position)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _hover_handle >= 0:
			_delete_handle_point(_handles[_hover_handle])
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		_on_key(event as InputEventKey)


func _on_key(k: InputEventKey) -> void:
	if k.echo:
		return
	var ctrl := k.ctrl_pressed or k.meta_pressed
	var handled := true
	if ctrl:
		# Raccourcis selon la lettre imprimée sur la touche (AZERTY comme QWERTY).
		match k.keycode:
			KEY_Z:
				if k.shift_pressed: redo()
				else: undo()
			KEY_Y:
				redo()
			_:
				handled = false
	else:
		match k.physical_keycode:
			KEY_ESCAPE:
				if _draft or _state == _State.DRAWING:
					cancel_draft()
				else:
					select(-1)
			KEY_DELETE, KEY_BACKSPACE:
				delete_selected()
			KEY_PAGEUP, KEY_KP_ADD, KEY_EQUAL:
				change_floors(1)
			KEY_PAGEDOWN, KEY_KP_SUBTRACT, KEY_MINUS, KEY_6:
				change_floors(-1)
			KEY_1, KEY_KP_1:
				mode = Mode.WALL
			KEY_2, KEY_KP_2:
				mode = Mode.HOUSE
			KEY_3, KEY_KP_3:
				mode = Mode.PATH
			KEY_4, KEY_KP_4:
				mode = Mode.TORII
			KEY_5, KEY_KP_5:
				mode = Mode.PLANTS
			_:
				if k.keycode == KEY_T:
					mode = Mode.TERRACE
				elif k.keycode == KEY_B:
					mode = Mode.FOREST
				elif k.keycode == KEY_J:
					mode = Mode.POND
				elif k.keycode == KEY_H:
					mode = Mode.FARM
				elif k.keycode == KEY_R:
					reroll_selected()
				elif k.keycode == KEY_G:
					cycle_silhouette()
				elif k.keycode == KEY_V:
					if mode == Mode.FOREST:
						cycle_forest_kind()
					elif mode == Mode.POND:
						cycle_pond_kind()
					elif mode == Mode.FARM:
						cycle_farm_kind()
					else:
						cycle_wall_variant()
				else:
					handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _on_press(screen: Vector2) -> void:
	if _hover_handle >= 0:
		_start_handle_drag(screen)
		return
	var g: Variant = _ground(screen)
	if g == null:
		return
	_state = _State.PRESSING
	_press_screen = screen
	_press_ground = g


func _on_motion(screen: Vector2) -> void:
	var g: Variant = _ground(screen)
	match _state:
		_State.IDLE:
			_update_hover(screen)
			_update_cursor(g)
			if mode == Mode.TORII:
				if g != null and _hover < 0 and _hover_handle < 0:
					_torii_preview(g)
				elif _draft:
					cancel_draft()
		_State.PRESSING:
			if mode == Mode.TORII:
				if g != null:
					_torii_preview(g)
			elif screen.distance_to(_press_screen) > DRAG_THRESHOLD and g != null:
				_start_draw()
				_continue_draw(g)
		_State.DRAWING:
			if g != null:
				_continue_draw(g)
		_State.DRAGGING:
			if g != null:
				_continue_handle_drag(g)


func _on_release(screen: Vector2) -> void:
	match _state:
		_State.PRESSING:
			_state = _State.IDLE
			_update_hover(screen)
			if _hover < 0 and mode == Mode.TORII and _draft:
				_place_draft()
			elif _hover < 0 and mode == Mode.PLANTS:
				_plant_tree(_press_ground)
			else:
				# Simple clic : sélection.
				select(_hover)
		_State.DRAWING:
			_finish_draw()
		_State.DRAGGING:
			_finish_handle_drag()
	_state = _State.IDLE


# --- Tracé ----------------------------------------------------------------------

func _start_draw() -> void:
	_state = _State.DRAWING
	select(-1)
	_set_hover(-1)
	_cursor.visible = false
	_raw = PackedVector3Array([_press_ground])
	_frozen = PackedVector3Array()
	_frozen_at = 0
	_draft_rec = _new_record(_draw_kind())
	_merge_id = -1
	_emit_hint()


## Genre de structure tracée dans le mode courant.
func _draw_kind() -> String:
	match mode:
		Mode.HOUSE:
			return "house"
		Mode.PATH:
			return "path"
		Mode.TORII:
			return "torii"
		Mode.PLANTS:
			return "plants"
		Mode.TERRACE:
			return "terrace"
		Mode.FOREST:
			return "forest"
		Mode.POND:
			return "pond"
		Mode.FARM:
			return "farm"
	return "wall" if wall_variant == WallVariant.ROOFED else "fence"


func _new_record(kind: String) -> Dictionary:
	var rec := {
		"kind": kind,
		"points": PackedVector3Array(),
		"closed": false,
		"seed": _rng.randi_range(1, 99999),
		"floors": 0,
		"height": wall_height if kind == "wall" else 0.0,
		"style": style.resource_path,
	}
	if kind == "fence":
		rec["variant"] = 1 if wall_variant == WallVariant.BAMBOO else 0
	if kind == "terrace":
		rec["entry"] = -1
	if kind == "forest":
		rec["forest_kind"] = int(forest_kind)
		rec["closed"] = true
	if kind == "pond":
		rec["pond_kind"] = int(pond_kind)
		rec["closed"] = true
	if kind == "farm":
		rec["farm_kind"] = int(farm_kind)
		rec["closed"] = true
	return rec


func _continue_draw(g: Vector3) -> void:
	if _draft_rec["kind"] == "house":
		_draw_house(g)
	elif _draft_rec["kind"] == "terrace":
		_draw_terrace(g)
	else:
		_draw_wall(g)


func _draw_wall(g: Vector3) -> void:
	if _raw[_raw.size() - 1].distance_to(g) > 0.3:
		_raw.append(g)
	# Seule la fin du tracé (les derniers mètres) est re-simplifiée à chaque
	# mouvement : ce qui est loin derrière la souris est figé et ne tremble plus.
	var simple := _simplified_tail(g)
	if _freeze_behind(simple):
		simple = _simplified_tail(g)
	var control := _frozen.slice(0, maxi(_frozen.size() - 1, 0))
	control.append_array(simple)
	var total := BastideStroke.length(control)
	# Revenir près du départ ferme l'enceinte (murs et clôtures seulement).
	var closable: bool = _draft_rec["kind"] == "wall" or _draft_rec["kind"] == "fence"
	var closed := closable and total > 10.0 and g.distance_to(_raw[0]) < 1.6 and control.size() >= 4
	if closed:
		control.remove_at(control.size() - 1)
	if _draft_rec["kind"] in ["pond", "farm"]:
		# Un étang (ou un champ) est une zone : on montre déjà sa rive arrondie, telle qu'elle sera.
		_draft_rec["points"] = control
		_draft_rec["closed"] = true
		var shore := PackedVector3Array()
		if control.size() >= 3:
			for q in BastidePondShape.outline(control, int(_draft_rec["seed"])):
				shore.append(Vector3(q.x, 0.0, q.y))
		if shore.size() >= 3:
			_draw_ink(shore, true)
		else:
			_draw_ink(BastideStroke.wall_path(control, false, 0.6), false)
		return
	if _draft_rec["kind"] == "forest":
		# Une forêt est toujours une zone : le contour se referme tout seul. Elle
		# n'apparaît qu'au relâcher (des centaines d'arbres : pas de fantôme en direct).
		_draft_rec["points"] = control
		_draft_rec["closed"] = true
		_draw_ink(BastideStroke.wall_path(control, control.size() >= 3, 0.6), control.size() >= 3)
		return
	_draft_rec["points"] = control
	_draft_rec["closed"] = closed
	_draw_ink(BastideStroke.wall_path(control, closed, 0.4), closed)
	if total >= wall_min_length:
		_update_draft()


func _simplified_tail(g: Vector3) -> PackedVector3Array:
	var tail := _raw.slice(_frozen_at)
	if tail[tail.size() - 1].distance_to(g) > 0.05:
		tail.append(g)
	return BastideStroke.simplify(tail, 0.28)


## Fige les points de contrôle intérieurs de la partie libre qui sont à plus de
## FREEZE_DIST mètres (le long du tracé) derrière la souris. Vrai si un point a été figé.
func _freeze_behind(simple: PackedVector3Array) -> bool:
	if simple.size() < 3:
		return false
	var n := _raw.size()
	var remain := PackedFloat32Array()
	remain.resize(n)
	var acc := 0.0
	for i in range(n - 1, -1, -1):
		if i < n - 1:
			acc += _raw[i].distance_to(_raw[i + 1])
		remain[i] = acc
	var changed := false
	var j := _frozen_at
	for k in range(1, simple.size() - 1):
		while j < n and _raw[j] != simple[k]:
			j += 1
		if j >= n or remain[j] < FREEZE_DIST:
			break
		if _frozen.is_empty():
			_frozen.append(simple[0])
		_frozen.append(simple[k])
		_frozen_at = j
		changed = true
	return changed


func _draw_house(g: Vector3) -> void:
	var right := camera.global_transform.basis.x
	var rect := BastideStroke.rectangle(_press_ground, g, right, house_snap, house_min_side)
	rect = _clamp_rect(rect)
	# Chevauche une maison existante ? On s'aligne dessus et on fusionne.
	var target := _overlapping_house(rect)
	var pts := rect
	if target >= 0:
		var house: Dictionary = site.get_record(target)
		var hp: PackedVector3Array = house["points"]
		var edge := hp[1] - hp[0]
		rect = _clamp_rect(BastideStroke.rectangle(_press_ground, g, edge, house_snap, house_min_side))
		var merged := BastideStroke.union(hp, rect)
		if merged.size() >= 4:
			pts = merged
		else:
			target = -1
			pts = rect
	if target != _merge_id:
		if _merge_id >= 0 and site.node_of(_merge_id):
			site.node_of(_merge_id).visible = true
		_merge_id = target
		if _merge_id >= 0:
			site.node_of(_merge_id).visible = false
			_draft_rec["seed"] = site.get_record(_merge_id)["seed"]
			_draft_rec["floors"] = site.get_record(_merge_id)["floors"]
			_draft_rec["shape"] = site.get_record(_merge_id).get("shape", 0)
			_draft_rec["style"] = site.get_record(_merge_id)["style"]
		else:
			_draft_rec["style"] = style.resource_path
		_emit_hint()
	_draft_rec["points"] = pts
	_draw_ink(pts, true)
	_update_draft()


## Terrasse : rectangle tiré à la souris, aligné sur la façade la plus proche ;
## collé contre elle, il devient un engawa.
func _draw_terrace(g: Vector3) -> void:
	var pts := terrace_rect(_press_ground, g)
	var engawa := BastideTerraceRules.house_side(pts, site.context()) >= 0
	if engawa != _terrace_engawa:
		_terrace_engawa = engawa
		_emit_hint()
	_draft_rec["points"] = pts
	_draft_rec["entry"] = -1 if engawa else _entry_toward_camera(pts)
	_draw_ink(pts, true)
	_update_draft()


## Rectangle de terrasse entre deux points du sol, déjà redressé et collé à une
## maison s'il y a lieu.
func terrace_rect(a: Vector3, b: Vector3) -> PackedVector3Array:
	var ctx := site.context()
	var axis := BastideTerraceRules.facade_axis(a, ctx)
	if axis == Vector3.ZERO:
		axis = camera.global_transform.basis.x
	var rect := BastideStroke.rectangle(a, b, axis, 0.25, 1.5)
	var u := rect[1] - rect[0]
	var v := rect[3] - rect[0]
	if u.length() > terrace_max_side:
		u = u.normalized() * terrace_max_side
	if v.length() > terrace_max_side:
		v = v.normalized() * terrace_max_side
	rect = PackedVector3Array([rect[0], rect[0] + u, rect[0] + u + v, rect[0] + v])
	rect = BastideTerraceRules.snap_to_house(BastideStroke.ensure_direct(rect), ctx)["points"]
	return BastideTerraceRules.fit_rect(rect)


## Côté du rectangle qui regarde le plus vers la caméra (pour les marches).
func _entry_toward_camera(rect: PackedVector3Array) -> int:
	var to_cam := site.to_local(camera.global_position) - BastideStroke.centroid(rect)
	to_cam.y = 0.0
	var best := 0
	var best_dot := -INF
	for i in 4:
		var d := BastideTerraceRules.side_normal(rect, i).dot(to_cam.normalized())
		if d > best_dot:
			best_dot = d
			best = i
	return best


func _clamp_rect(rect: PackedVector3Array) -> PackedVector3Array:
	# Côtés bornés : on raccourcit depuis le premier coin.
	var a := rect[0]
	var u := rect[1] - a
	var v := rect[3] - a
	if u.length() > house_max_side:
		u = u.normalized() * house_max_side
	if v.length() > house_max_side:
		v = v.normalized() * house_max_side
	return PackedVector3Array([a, a + u, a + u + v, a + v])


func _overlapping_house(rect: PackedVector3Array) -> int:
	for id in site.ids():
		var r: Dictionary = site.get_record(id)
		if r["kind"] == "house" and BastideStroke.overlaps(r["points"], rect, 1.0):
			return id
	return -1


func _update_draft() -> void:
	if _draft == null:
		_draft = site.make_node(_draft_rec)
		_draft.name = "Fantome"
		# Un fantôme voit ses voisins (il se raccorde aux portes…) mais eux l'ignorent.
		_draft.context_enabled = false
		_draft.mesh_transparency = ghost_transparency
		_draft.mesh_overlay = _ghost_overlay
		_draft.mesh_casts_shadow = false
		site.add_child(_draft)
	site.configure(_draft, _draft_rec)


func _finish_draw() -> void:
	_state = _State.IDLE
	_ink_mesh.clear_surfaces()
	var rec := _draft_rec
	var pts: PackedVector3Array = rec.get("points", PackedVector3Array())
	if rec.get("kind") in ["forest", "pond", "farm"]:
		var min_area: float = {"forest": forest_min_area, "pond": pond_min_area, "farm": farm_min_area}[rec.get("kind")]
		if pts.size() >= 3 and absf(BastideStroke.signed_area(pts)) >= min_area:
			rec["points"] = BastideStroke.ensure_direct(pts)
			_update_draft()
			_draft.mesh_transparency = 0.0
			_draft.mesh_overlay = null
			_draft.mesh_casts_shadow = true
			_draft.context_enabled = true
			_place_draft()
		else:
			cancel_draft()
		_emit_hint()
		return
	var ok := _draft != null and pts.size() >= 2
	if rec.get("kind") != "house" and BastideStroke.length(pts, rec["closed"]) < wall_min_length:
		ok = false
	if not ok:
		cancel_draft()
		return
	if _merge_id >= 0:
		# Agrandit la maison existante : une seule structure, un seul retour arrière.
		var id := _merge_id
		var before: Dictionary = site.get_record(id)
		var after := before.duplicate(true)
		after["points"] = pts
		_commit("Agrandir la maison", [[id, before, after]], true)
		var target := site.node_of(id)
		var draft := _draft
		_draft = null
		_merge_id = -1
		# On garde le fantôme jusqu'à ce que la maison agrandie soit prête : pas de trou.
		target.rebuilt.connect(func(_s: Dictionary) -> void:
			target.visible = true
			if is_instance_valid(draft):
				draft.queue_free(), CONNECT_ONE_SHOT)
		placed.emit("house")
	else:
		_place_draft()
		return
	_emit_hint()


## Le fantôme devient une vraie structure (sans régénération).
func _place_draft() -> void:
	var rec := _draft_rec
	var id := site.new_id()
	site.adopt(id, _draft, rec)
	_draft = null
	# Déjà posé : l'action n'est pas rejouée maintenant, seulement à l'annulation.
	_commit("Construire", [[id, null, rec]], false)
	placed.emit(rec["kind"])
	if mode == Mode.TORII:
		# On enchaîne : le prochain torii suit déjà la souris.
		_emit_hint()
	else:
		select(id)
	_emit_hint()


## Torii fantôme sous la souris, calé sur le chemin le plus proche.
func _torii_preview(g: Vector3) -> void:
	var gs := style.get_garden_style()
	var res := BastideGardenRules.place_torii(g, site.context(), gs.path_width, camera.global_transform.basis.x)
	if _draft != null and _draft_rec.get("kind") != "torii":
		cancel_draft()
	if _draft == null:
		_draft_rec = _new_record("torii")
	_draft_rec["points"] = res["points"]
	_torii_snapped = res["snapped"]
	_update_draft()
	_emit_hint()


## Clic en mode PLANTES : un arbre.
func _plant_tree(g: Vector3) -> void:
	var rec := _new_record("plants")
	rec["points"] = PackedVector3Array([g])
	var id := site.new_id()
	_commit("Planter un arbre", [[id, null, rec]], true)
	placed.emit("plants")
	_emit_hint()


# --- Poignées -------------------------------------------------------------------

func _rebuild_handles() -> void:
	_handles.clear()
	if selected >= 0 and site.has(selected):
		var r: Dictionary = site.get_record(selected)
		var pts: PackedVector3Array = r["points"]
		for i in pts.size():
			_handles.append({"pos": pts[i], "kind": "corner" if r["kind"] in ["house", "terrace"] else "point", "index": i})
		if r["kind"] in ["house", "terrace"]:
			for i in pts.size():
				var mid := (pts[i] + pts[(i + 1) % pts.size()]) * 0.5
				_handles.append({"pos": mid, "kind": "edge", "index": i})
	while _handle_nodes.size() < _handles.size():
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		mi.mesh = q
		var mat := ShaderMaterial.new()
		mat.shader = HANDLE_SHADER
		mat.render_priority = 10
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		add_child(mi)
		_handle_nodes.append(mi)
	for i in _handle_nodes.size():
		var mi := _handle_nodes[i]
		if i < _handles.size():
			var h: Dictionary = _handles[i]
			mi.visible = true
			mi.global_position = _lift(h["pos"]) + Vector3(0, 0.25, 0)
			var mat := mi.material_override as ShaderMaterial
			mat.set_shader_parameter("pixel_size", 16.0 if h["kind"] == "edge" else 26.0)
			mat.set_shader_parameter("hover", 1.0 if i == _hover_handle else 0.0)
			if h["kind"] == "edge":
				mat.set_shader_parameter("fill_color", Color(1, 0.98, 0.94, 0.15))
		else:
			mi.visible = false
	if _hover_handle >= _handles.size():
		_hover_handle = -1


func _handle_under(screen: Vector2) -> int:
	var best := -1
	var best_d := HANDLE_PICK_RADIUS
	for i in _handles.size():
		var world := _lift(_handles[i]["pos"]) + Vector3(0, 0.25, 0)
		if camera.is_position_behind(world):
			continue
		var d := camera.unproject_position(world).distance_to(screen)
		# Les angles passent avant les milieux de côtés.
		if _handles[i]["kind"] == "edge":
			d += 4.0
		if d < best_d:
			best_d = d
			best = i
	return best


func _start_handle_drag(screen: Vector2) -> void:
	var g: Variant = _ground(screen)
	if g == null:
		return
	_state = _State.DRAGGING
	_drag_handle = _handles[_hover_handle]
	_drag_before = site.get_record(selected)
	_drag_start_ground = g
	_drag_start_points = _drag_before["points"]
	_cursor.visible = false
	_emit_hint()


func _continue_handle_drag(g: Vector3) -> void:
	if not site.has(selected):
		return
	var rec: Dictionary = site.get_record(selected)
	var pts := _drag_start_points.duplicate()
	var i: int = _drag_handle["index"]
	if rec["kind"] == "terrace" and _drag_handle["kind"] == "corner":
		# Un rectangle reste un rectangle : on tire l'angle, l'angle opposé reste en place.
		var opp := pts[(i + 2) % 4]
		var axis := pts[1] - pts[0]
		var r := BastideStroke.ensure_direct(BastideStroke.rectangle(opp, g, axis, 0.25, 1.2))
		pts = BastideTerraceRules.fit_rect(BastideTerraceRules.snap_to_house(r, site.context())["points"])
		rec["points"] = pts
		site.apply_record(selected, rec, false)
		_rebuild_handles()
		return
	match _drag_handle["kind"]:
		"point":
			pts[i] = g
		"corner":
			pts[i] = _snap_corner(pts, i, g)
		"edge":
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			var dir := (b - a).normalized()
			var normal := Vector3(dir.z, 0, -dir.x)
			var push := snappedf((g - _drag_start_ground).dot(normal), house_snap * 0.5)
			pts[i] = a + normal * push
			pts[(i + 1) % pts.size()] = b + normal * push
	if rec["kind"] == "torii" and pts.size() >= 2:
		pts = BastideGardenRules.fit_torii(pts[0], pts[1])
	rec["points"] = pts
	site.apply_record(selected, rec, false)
	_rebuild_handles()


## Un angle tiré reste d'équerre avec ses voisins quand on en est proche.
func _snap_corner(pts: PackedVector3Array, i: int, g: Vector3) -> Vector3:
	var n := pts.size()
	var prev := pts[(i - 1 + n) % n]
	var next := pts[(i + 1) % n]
	var out := g
	# Projette sur les deux droites « d'équerre » qui passent par les voisins.
	for anchor: Vector3 in [prev, next]:
		var other: Vector3 = pts[(i - 2 + n) % n] if anchor == prev else pts[(i + 2) % n]
		var axis := (anchor - other)
		axis.y = 0
		if axis.length() < 0.01:
			continue
		axis = axis.normalized()
		var perp := Vector3(-axis.z, 0, axis.x)
		var off := (out - anchor).dot(axis)
		if absf(off) < 0.6:
			out -= axis * off
		var off2 := (out - anchor).dot(perp)
		if absf(off2) < 0.6:
			out -= perp * off2
	return out


func _finish_handle_drag() -> void:
	_state = _State.IDLE
	if not site.has(selected):
		return
	var after: Dictionary = site.get_record(selected)
	if after["points"] != _drag_before["points"]:
		_commit("Retoucher", [[selected, _drag_before, after]], false)
		var node := site.node_of(selected)
		if node:
			site.apply_record(selected, after, true)  # petit tassement
		edited.emit()
	_emit_hint()


func _delete_handle_point(h: Dictionary) -> void:
	if h["kind"] == "edge" or not site.has(selected):
		return
	var before: Dictionary = site.get_record(selected)
	var pts: PackedVector3Array = before["points"]
	var min_pts := 2
	match String(before["kind"]):
		"house":
			min_pts = 4
		"torii", "terrace":
			return
		"plants":
			min_pts = 1
	if pts.size() <= min_pts:
		return
	var after := before.duplicate(true)
	var np := pts.duplicate()
	np.remove_at(h["index"])
	after["points"] = np
	_commit("Retirer un point", [[selected, before, after]], true)
	edited.emit()


# --- Survol et apparence ------------------------------------------------------

func _update_hover(screen: Vector2) -> void:
	var hh := _handle_under(screen)
	if hh != _hover_handle:
		_hover_handle = hh
		_rebuild_handles()
		_emit_hint()
	if _hover_handle >= 0:
		_set_hover(-1)
		return
	_set_hover(_structure_under(screen))


func _set_hover(id: int) -> void:
	if id == _hover:
		return
	var old := site.node_of(_hover) if _hover >= 0 else null
	_hover = id
	_refresh_look(old)
	_refresh_look(site.node_of(_hover) if _hover >= 0 else null)
	_emit_hint()


func _refresh_look(node: BastideStructure) -> void:
	if node == null or not is_instance_valid(node):
		return
	var id := site.id_of(node)
	if id < 0:
		return
	if id == selected:
		node.mesh_overlay = _mat_selected
	elif id == _hover:
		node.mesh_overlay = _mat_hover
	else:
		node.mesh_overlay = null


func _structure_under(screen: Vector2) -> int:
	var from := camera.project_ray_origin(screen)
	var to := from + camera.project_ray_normal(screen) * 500.0
	var q := PhysicsRayQueryParameters3D.create(from, to, site.structure_layer)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return -1
	return site.id_of(hit["collider"])


func _update_cursor(g: Variant) -> void:
	_cursor.visible = g != null and _hover < 0 and _hover_handle < 0
	if g != null:
		_cursor.global_position = _lift(g as Vector3) + Vector3(0, 0.03, 0)
		var s := 1.6 if mode == Mode.HOUSE or mode == Mode.TERRACE else (0.0 if mode == Mode.TORII else 1.0)
		_cursor.scale = Vector3(maxf(s, 0.01), 0.15, maxf(s, 0.01))
		_cursor.visible = _cursor.visible and mode != Mode.TORII


func _ground(screen: Vector2) -> Variant:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if ground_mask != 0:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 1000.0, ground_mask)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			return _flat(site.to_local(hit["position"]))
	var field := BastideTerrain.field_for(site)
	if field:
		var th: Variant = field.raycast(from, dir, 400.0)
		return _flat(site.to_local(th)) if th != null else null
	var p: Variant = Plane(Vector3.UP, ground_height).intersects_ray(from, dir)
	if p == null:
		return null
	# Pas de tracé à l'horizon : on reste dans un rayon raisonnable autour de la caméra.
	if (p as Vector3).distance_to(from) > 400.0:
		return null
	return site.to_local(p)


## Trait lumineux au sol sous le tracé en cours.
## Les tracés sont enregistrés à plat (y = 0 dans le chantier) : le relief est
## appliqué à la génération. Pour l'affichage (curseur, encre, poignées), on remonte
## sur le sol.
func _flat(local: Vector3) -> Vector3:
	return Vector3(local.x, 0.0, local.z)


func _lift(local: Vector3) -> Vector3:
	var w := site.to_global(_flat(local))
	var field := BastideTerrain.field_for(site)
	if field:
		w.y += field.height(w.x, w.z)
	return w


func _draw_ink(pts: PackedVector3Array, closed: bool) -> void:
	_ink_mesh.clear_surfaces()
	if pts.size() < 2:
		return
	var path := pts.duplicate()
	if closed:
		path.append(pts[0])
	var w := 0.22
	_ink_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var dist := 0.0
	for i in path.size():
		var p := _lift(path[i]) + Vector3(0, 0.06, 0)
		var a := path[maxi(i - 1, 0)]
		var b := path[mini(i + 1, path.size() - 1)]
		var t := (b - a)
		t.y = 0
		t = t.normalized() if t.length() > 1e-4 else Vector3.RIGHT
		var side := Vector3(-t.z, 0, t.x) * w
		if i > 0:
			dist += path[i].distance_to(path[i - 1])
		_ink_mesh.surface_set_color(Color(1, 1, 1, 1))
		_ink_mesh.surface_set_uv(Vector2(dist, 0))
		_ink_mesh.surface_add_vertex(p - side)
		_ink_mesh.surface_set_uv(Vector2(dist, 1))
		_ink_mesh.surface_add_vertex(p + side)
	_ink_mesh.surface_end()


# --- Historique -----------------------------------------------------------------

## changes : [[id, avant (ou null), après (ou null)], …]. execute = false quand le
## changement est déjà visible (tracé adopté, poignée relâchée).
func _commit(label: String, changes: Array, execute: bool) -> void:
	_undo.create_action(label)
	for c: Array in changes:
		_undo.add_do_method(site.apply_record.bind(c[0], c[2], true))
	for c: Array in changes:
		_undo.add_undo_method(site.apply_record.bind(c[0], c[1], true))
	_undo.add_do_method(_after_history)
	_undo.add_undo_method(_after_history)
	_undo.commit_action(execute)
	_after_history()


func _after_history() -> void:
	if selected >= 0 and not site.has(selected):
		select(-1)
	else:
		_refresh_look(site.node_of(selected) if selected >= 0 else null)
		_rebuild_handles()
	history_changed.emit(_undo.has_undo(), _undo.has_redo())


func _emit_hint() -> void:
	hint_changed.emit(current_hint())


func current_hint() -> String:
	match _state:
		_State.DRAWING:
			if mode == Mode.PATH:
				return "Dessine le chemin  ·  près d'une porte, il la rejoint tout seul"
			if mode == Mode.PLANTS:
				return "Dessine le massif, relâche pour le planter"
			if mode == Mode.WALL:
				if _draft_rec.get("closed", false):
					return "Relâche pour fermer l'enceinte"
				return "Dessine le tracé, relâche pour le poser"
			if mode == Mode.FOREST:
				return "Fais le tour de la forêt, relâche pour la planter"
			if mode == Mode.POND:
				return "Fais le tour de l'étang, relâche pour le creuser"
			if mode == Mode.FARM:
				return "Fais le tour du champ, relâche pour le cultiver"
			if mode == Mode.TERRACE:
				if _terrace_engawa:
					return "Relâche : un engawa le long de la façade"
				return "Tire la terrasse  ·  contre une maison, elle devient un engawa"
			if _merge_id >= 0:
				return "Relâche pour agrandir la maison"
			return "Tire pour donner sa taille à la maison"
		_State.DRAGGING:
			return "Glisse pour retoucher"
	if _hover_handle >= 0:
		var h: Dictionary = _handles[_hover_handle]
		if h["kind"] == "edge":
			return "Tire ce côté pour pousser le mur"
		if h["kind"] == "point":
			return "Tire ce point pour courber le muret  ·  clic droit : le retirer"
		return "Tire cet angle  ·  clic droit : le retirer"
	if mode == Mode.TORII and _draft and _hover < 0:
		if _torii_snapped:
			return "Clic : poser le torii sur le chemin"
		return "Clic : poser le torii  ·  approche-le d'un chemin pour l'y aligner"
	if selected >= 0 and site.has(selected):
		var kind: String = site.get_record(selected)["kind"]
		if kind == "house":
			return "%s  ·  G : autre silhouette  ·  + / − : étages  ·  R : autre variation  ·  Suppr : retirer" % selected_silhouette_name().capitalize()
		return "Poignées : retoucher  ·  R : autre variation  ·  Suppr : retirer"
	if _hover >= 0:
		return "Clic : sélectionner"
	match mode:
		Mode.WALL:
			var names := ["muret à petit toit", "muret de pierres sèches", "clôture de bambou"]
			return "Maintiens le clic et dessine un %s  ·  V : changer" % names[int(wall_variant)]
		Mode.PATH:
			return "Maintiens le clic et dessine un chemin  ·  pars d'une porte ou d'un autre chemin"
		Mode.TORII:
			return "Approche la souris d'un chemin pour y poser un torii"
		Mode.PLANTS:
			return "Dessine un massif  ·  ou clique pour planter un arbre"
		Mode.TERRACE:
			return "Maintiens le clic et tire une terrasse  ·  contre une maison : un engawa"
		Mode.FOREST:
			var fnames := ["forêt mêlée", "forêt de cèdres", "chênaie", "érables d'automne", "cerisiers", "pinède"]
			return "Maintiens le clic et fais le tour d'une %s  ·  V : changer" % fnames[int(forest_kind)]
		Mode.FARM:
			var fnames2 := ["potager", "rizière en terrasses", "champ de thé"]
			return "Maintiens le clic et fais le tour d'un %s  ·  sur une pente : des terrasses  ·  V : changer" % fnames2[int(farm_kind)] \
					if int(farm_kind) != 1 else "Maintiens le clic et fais le tour d'une rizière  ·  sur une pente : des terrasses  ·  V : changer"
		Mode.POND:
			var pnames := ["étang de jardin", "source chaude", "mare sauvage"]
			return "Maintiens le clic et fais le tour d'un %s  ·  un chemin qui le traverse aura son pont  ·  V : changer" % pnames[int(pond_kind)] \
					if int(pond_kind) != 1 else "Maintiens le clic et fais le tour d'une source chaude  ·  V : changer"
	return "Maintiens le clic et tire un rectangle  ·  par-dessus une maison : l'agrandir"
