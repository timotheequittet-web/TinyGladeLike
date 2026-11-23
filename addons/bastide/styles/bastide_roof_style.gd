@tool
class_name BastideRoofStyle
extends Resource
## Paramètres des toits calculés par squelette droit : pente, débord, tuiles, décor.

enum RoofType { HIP, GABLE }

@export_group("Forme")
## Croupes : tous les côtés sont des pans. Pignons : les bouts étroits deviennent des murs triangulaires.
@export var roof_type: RoofType = RoofType.GABLE:
	set(value):
		roof_type = value
		emit_changed()
## Pente des pans.
@export_range(10.0, 70.0, 0.5, "suffix:°") var pitch: float = 42.0:
	set(value):
		pitch = value
		emit_changed()
## Débord du toit au-delà des murs.
@export_range(0.0, 2.0, 0.01, "suffix:m") var overhang: float = 0.45:
	set(value):
		overhang = value
		emit_changed()
## Épaisseur visible du toit (planche de rive).
@export_range(0.05, 1.0, 0.01, "suffix:m") var thickness: float = 0.2:
	set(value):
		thickness = value
		emit_changed()
@export_group("Tuiles")
## Hauteur d'un rang de tuiles, mesurée le long de la pente.
@export_range(0.1, 2.0, 0.01, "suffix:m") var tile_row: float = 0.36:
	set(value):
		tile_row = value
		emit_changed()
## Largeur d'une tuile (0 = pas de découpe en tuiles).
@export_range(0.1, 2.0, 0.01, "suffix:m") var tile_width: float = 0.42:
	set(value):
		tile_width = value
		emit_changed()
## Ressaut entre deux rangs.
@export_range(0.0, 0.3, 0.005, "suffix:m") var tile_thickness: float = 0.05:
	set(value):
		tile_thickness = value
		emit_changed()
## Tuiles faîtières sur les faîtages, arêtiers et noues.
@export var ridge_caps: bool = true:
	set(value):
		ridge_caps = value
		emit_changed()
@export_group("Cheminée")
## Probabilité d'une cheminée (tirée par bâtiment).
@export_range(0.0, 1.0, 0.01) var chimney_chance: float = 0.7:
	set(value):
		chimney_chance = value
		emit_changed()
@export_group("Couleurs")
## Couleurs de toit possibles (une par bâtiment, tirée par la seed).
@export var roof_colors: PackedColorArray = PackedColorArray([Color(0.66, 0.32, 0.22), Color(0.36, 0.42, 0.5), Color(0.55, 0.38, 0.3)]):
	set(value):
		roof_colors = value
		emit_changed()
## Variation de clarté d'une tuile à l'autre.
@export_range(0.0, 0.5, 0.01) var tile_variance: float = 0.07:
	set(value):
		tile_variance = value
		emit_changed()
## Dessous du débord et planches de rive.
@export var underside_color: Color = Color(0.3, 0.21, 0.15):
	set(value):
		underside_color = value
		emit_changed()
