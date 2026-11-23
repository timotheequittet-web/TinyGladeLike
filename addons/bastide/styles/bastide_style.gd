@tool
class_name BastideStyle
extends Resource
## Un style complet : c'est ce qu'on glisse dans l'inspecteur d'un mur ou d'un bâtiment.
## À l'étape 1, seul le volet « mur » existe ; bâtiments, toits et kit viendront s'ajouter ici.

const STONE_SHADER := preload("res://addons/bastide/shaders/bastide_stone.gdshader")

@export var display_name := "Médiéval pierre"

@export var wall: BastideWallStyle:
	set(value):
		if wall and wall.changed.is_connected(emit_changed):
			wall.changed.disconnect(emit_changed)
		wall = value
		if wall:
			wall.changed.connect(emit_changed)
		emit_changed()

## Matériau des murs. Vide : shader pierre procédural fourni par l'addon.
@export var material: Material:
	set(value):
		material = value
		emit_changed()

var _default_material: Material


func get_wall_style() -> BastideWallStyle:
	if wall == null:
		wall = BastideWallStyle.new()
	return wall


func get_material() -> Material:
	if material:
		return material
	if _default_material == null:
		var m := ShaderMaterial.new()
		m.shader = STONE_SHADER
		_default_material = m
	return _default_material


## Style par défaut quand un mur n'en a pas.
static func create_default() -> BastideStyle:
	var s := BastideStyle.new()
	s.wall = BastideWallStyle.new()
	return s
