extends Node3D
## Démo de l'étape 3 : deux hameaux identiques côte à côte, l'un en style
## « médiéval pierre », l'autre en « japonais traditionnel bois ». Les boutons
## changent le style de tout un hameau d'un coup : c'est la même propriété `style`
## qu'on change dans l'inspecteur, sur un nœud ou sur plusieurs à la fois.

const MEDIEVAL := preload("res://addons/bastide/styles/presets/medieval_stone.tres")
const JAPANESE := preload("res://addons/bastide/styles/presets/japanese_wood.tres")

var _structures := {}  # nom du hameau -> Array[BastideStructure]
@onready var _seed_box: SpinBox = %SeedBox
@onready var _stats: Label = %Stats


func _ready() -> void:
	for group_name in ["Medieval", "Japonais"]:
		var list: Array[BastideStructure] = []
		for n in get_node(group_name).find_children("*", "BastideStructure", true, false):
			list.append(n as BastideStructure)
			(n as BastideStructure).rebuilt.connect(func(_s: Dictionary) -> void: _refresh_stats.call_deferred())
		_structures[group_name] = list
	%SideBySide.pressed.connect(func() -> void: _set_styles(MEDIEVAL, JAPANESE))
	%AllMedieval.pressed.connect(func() -> void: _set_styles(MEDIEVAL, MEDIEVAL))
	%AllJapanese.pressed.connect(func() -> void: _set_styles(JAPANESE, JAPANESE))
	%Swap.pressed.connect(func() -> void: _set_styles(_style_of("Japonais"), _style_of("Medieval")))
	_seed_box.value_changed.connect(_on_seed_changed)
	%RandomButton.pressed.connect(func() -> void: _seed_box.value = randi_range(1, 9999))
	_refresh_stats()


func _style_of(group_name: String) -> BastideStyle:
	var list: Array = _structures[group_name]
	return (list[0] as BastideStructure).style if not list.is_empty() else MEDIEVAL


func _set_styles(left: BastideStyle, right: BastideStyle) -> void:
	for s: BastideStructure in _structures["Medieval"]:
		s.style = left
	for s: BastideStructure in _structures["Japonais"]:
		s.style = right


func _on_seed_changed(value: float) -> void:
	for group_name in _structures:
		var i := 0
		for s: BastideStructure in _structures[group_name]:
			# Même seed des deux côtés : seule l'architecture change.
			s.seed = int(value) + i * 101
			i += 1


func _refresh_stats() -> void:
	var lines: PackedStringArray = []
	for group_name in _structures:
		var tris := 0
		var ms := 0.0
		for s: BastideStructure in _structures[group_name]:
			tris += int(s.last_stats.get("triangles", 0))
			ms = maxf(ms, float(s.last_stats.get("build_ms", 0.0)))
		var st := _style_of(group_name)
		lines.append("%s : style « %s », %d triangles, génération la plus longue %.0f ms" % [
			"Gauche" if group_name == "Medieval" else "Droite", st.display_name, tris, ms])
	_stats.text = "\n".join(lines)
