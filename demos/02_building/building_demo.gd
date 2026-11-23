extends Node3D
## Démo de l'étape 2 : un petit hameau de bâtiments sur contour, avec une interface
## pour changer la seed, le nombre d'étages et la forme des toits.

var _buildings: Array[BastideBuilding] = []
@onready var _seed_box: SpinBox = %SeedBox
@onready var _floors_box: SpinBox = %FloorsBox
@onready var _roof_choice: OptionButton = %RoofChoice
@onready var _stats: Label = %Stats


func _ready() -> void:
	for n in find_children("*", "BastideBuilding", true, false):
		_buildings.append(n as BastideBuilding)
		(n as BastideBuilding).rebuilt.connect(_on_rebuilt.bind(n))
	_seed_box.value_changed.connect(_on_seed_changed)
	%RandomButton.pressed.connect(func() -> void: _seed_box.value = randi_range(1, 9999))
	_floors_box.value_changed.connect(_on_floors_changed)
	_roof_choice.item_selected.connect(_on_roof_changed)
	_refresh_stats()


func _on_seed_changed(value: float) -> void:
	for i in _buildings.size():
		_buildings[i].seed = int(value) + i * 101


func _on_floors_changed(value: float) -> void:
	for b in _buildings:
		b.floors = int(value) if value > 0 else int(b.get_meta(&"demo_floors", 0))


func _on_roof_changed(index: int) -> void:
	for b in _buildings:
		b.roof = index if index > 0 else int(b.get_meta(&"demo_roof", 0))


func _on_rebuilt(_stats_dict: Dictionary, _b: BastideBuilding) -> void:
	_refresh_stats.call_deferred()


func _refresh_stats() -> void:
	var lines: PackedStringArray = []
	for b in _buildings:
		var s := b.last_stats
		if s.is_empty():
			continue
		lines.append("%s : %d fenêtres, toit %s, %d triangles, %s ms" % [
			b.name, s.windows, s.roof, s.triangles, s.build_ms])
	_stats.text = "\n".join(lines)
