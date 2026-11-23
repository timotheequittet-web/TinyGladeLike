@tool
class_name BastideStyle
extends Resource
## Un style complet : c'est ce qu'on glisse dans l'inspecteur d'un mur ou d'un bâtiment.
## Volets : murs (étape 1), bâtiments et toits (étape 2) ; le kit viendra s'ajouter ici.

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

@export var building: BastideBuildingStyle:
	set(value):
		if building and building.changed.is_connected(emit_changed):
			building.changed.disconnect(emit_changed)
		building = value
		if building:
			building.changed.connect(emit_changed)
		emit_changed()

@export var roof: BastideRoofStyle:
	set(value):
		if roof and roof.changed.is_connected(emit_changed):
			roof.changed.disconnect(emit_changed)
		roof = value
		if roof:
			roof.changed.connect(emit_changed)
		emit_changed()

## Matériau des murs. Vide : shader pierre procédural fourni par l'addon.
@export var material: Material:
	set(value):
		material = value
		emit_changed()

## Matériau des vitres. Vide : verre sombre et brillant fourni par l'addon.
@export var glass_material: Material:
	set(value):
		glass_material = value
		emit_changed()

var _default_material: Material
var _default_roof: Material
var _default_glass: Material


func get_wall_style() -> BastideWallStyle:
	if wall == null:
		wall = BastideWallStyle.new()
	return wall


func get_building_style() -> BastideBuildingStyle:
	if building == null:
		building = BastideBuildingStyle.new()
	return building


func get_roof_style() -> BastideRoofStyle:
	if roof == null:
		roof = BastideRoofStyle.new()
	return roof


## Matériau des toits : le matériau du style s'il est donné, sinon le shader pierre
## réglé pour des tuiles (moins de grain, presque pas de mousse).
func get_roof_material() -> Material:
	if material:
		return material
	if _default_roof == null:
		var m := ShaderMaterial.new()
		m.shader = STONE_SHADER
		m.set_shader_parameter(&"grain_strength", 0.12)
		m.set_shader_parameter(&"blotch_strength", 0.16)
		m.set_shader_parameter(&"moss_amount", 0.12)
		m.set_shader_parameter(&"roughness_value", 0.8)
		_default_roof = m
	return _default_roof


func get_glass_material() -> Material:
	if glass_material:
		return glass_material
	if _default_glass == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.08
		m.metallic = 0.35
		m.metallic_specular = 0.8
		_default_glass = m
	return _default_glass


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
	s.building = BastideBuildingStyle.new()
	s.roof = BastideRoofStyle.new()
	return s
