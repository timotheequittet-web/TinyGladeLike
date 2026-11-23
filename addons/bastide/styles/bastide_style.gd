@tool
class_name BastideStyle
extends Resource
## Un style complet : c'est ce qu'on glisse dans l'inspecteur d'un mur ou d'un bâtiment.
##
## Volets : murs, bâtiments, toits, abords (décor à venir). Chaque volet décrit à la
## fois des proportions, des couleurs et des règles (quelles pièces poser : créneaux
## ou petit toit, fenêtres à croisillons ou à claire-voie…). Changer de style sur un
## nœud change donc toute son architecture, pas seulement ses couleurs.
##
## Les matériaux sont rangés par rôle : corps (pierre, enduit), bois, toit, vitres,
## papier. Chaque rôle vide reçoit un matériau procédural fourni par l'addon.
## Le futur mode kit ajoutera ici une table « pièce sémantique → scène .glb ».

const STONE_SHADER := preload("res://addons/bastide/shaders/bastide_stone.gdshader")
const WOOD_SHADER := preload("res://addons/bastide/shaders/bastide_wood.gdshader")

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

@export var garden: BastideGardenStyle:
	set(value):
		if garden and garden.changed.is_connected(emit_changed):
			garden.changed.disconnect(emit_changed)
		garden = value
		if garden:
			garden.changed.connect(emit_changed)
		emit_changed()

@export_group("Matériaux")
## Matériau des murs. Vide : shader pierre procédural fourni par l'addon.
@export var material: Material:
	set(value):
		material = value
		emit_changed()

## Matériau des toits. Vide : celui des murs s'il est donné, sinon le shader pierre réglé pour des tuiles.
@export var roof_material: Material:
	set(value):
		roof_material = value
		emit_changed()

## Matériau du bois (huisseries, ossature, volets, chevrons). Vide : shader bois de l'addon.
@export var wood_material: Material:
	set(value):
		wood_material = value
		emit_changed()

## Matériau des vitres. Vide : verre sombre et brillant fourni par l'addon.
@export var glass_material: Material:
	set(value):
		glass_material = value
		emit_changed()

## Matériau du papier des claire-voies. Vide : papier mat, légèrement lumineux.
@export var paper_material: Material:
	set(value):
		paper_material = value
		emit_changed()

var _default_material: Material
var _default_roof: Material
var _default_glass: Material
var _default_wood: Material
var _default_paper: Material


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


func get_garden_style() -> BastideGardenStyle:
	if garden == null:
		garden = BastideGardenStyle.new()
	return garden


func get_wood_material() -> Material:
	if wood_material:
		return wood_material
	if _default_wood == null:
		var m := ShaderMaterial.new()
		m.shader = WOOD_SHADER
		_default_wood = m
	return _default_wood


func get_paper_material() -> Material:
	if paper_material:
		return paper_material
	if _default_paper == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 1.0
		m.emission_enabled = true
		m.emission = Color(1.0, 0.86, 0.62)
		m.emission_energy_multiplier = 0.18
		_default_paper = m
	return _default_paper


## Matériau des toits : le matériau du style s'il est donné, sinon le shader pierre
## réglé pour des tuiles (moins de grain, presque pas de mousse).
func get_roof_material() -> Material:
	if roof_material:
		return roof_material
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
	s.garden = BastideGardenStyle.new()
	return s


## Tous les matériaux et volets créés d'un coup, sur le thread principal (avant une
## génération en arrière-plan qui ne doit rien créer de partagé).
func prepare() -> void:
	get_wall_style()
	get_building_style()
	get_roof_style()
	get_garden_style()
	get_material()
	get_roof_material()
	get_glass_material()
	get_wood_material()
	get_paper_material()
