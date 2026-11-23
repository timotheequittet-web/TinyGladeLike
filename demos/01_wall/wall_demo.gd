extends Node3D
## Démo de l'étape 1 : quelques murs, une interface pour changer la seed,
## et l'affichage du temps de génération.

@onready var _walls: Array[BastideWall] = []
@onready var _seed_box: SpinBox = %SeedBox
@onready var _stats: Label = %Stats


func _ready() -> void:
	for n in find_children("*", "BastideWall", true, false):
		_walls.append(n as BastideWall)
		(n as BastideWall).rebuilt.connect(_on_rebuilt.bind(n))
	_seed_box.value_changed.connect(_on_seed_changed)
	%RandomButton.pressed.connect(func() -> void: _seed_box.value = randi_range(1, 9999))
	_refresh_stats()


func _on_seed_changed(value: float) -> void:
	for i in _walls.size():
		_walls[i].seed = int(value) + i * 101


func _on_rebuilt(_stats_dict: Dictionary, _wall: BastideWall) -> void:
	_refresh_stats.call_deferred()


func _refresh_stats() -> void:
	var lines: PackedStringArray = []
	for w in _walls:
		if w.last_stats.is_empty():
			continue
		lines.append("%s : %s m, %d pierres, %d triangles, %s ms" % [
			w.name, w.last_stats.length_m, w.last_stats.stones, w.last_stats.triangles, w.last_stats.build_ms])
	_stats.text = "\n".join(lines)
