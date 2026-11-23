@tool
class_name BastideRoofStyle
extends Resource
## Paramètres des toits calculés par squelette droit : pente, débord, tuiles, décor.

## HIP : croupes ; GABLE : pignons ; IRIMOYA : croupe en bas, petit pignon en haut
## (toit japonais « irimoya »).
enum RoofType { HIP, GABLE, IRIMOYA }
## Tuiles plates en rangs décalés, ou tuiles rondes (côtes qui descendent la pente).
enum TileKind { FLAT, ROUND }
## Faîtage en tuiles faîtières, ou faîtage maçonné haut avec épis aux bouts.
enum RidgeKind { CAPS, STACKED }

@export_group("Forme")
## Croupes : tous les côtés sont des pans. Pignons : les bouts étroits deviennent des murs triangulaires.
## Irimoya : croupes jusqu'à mi-hauteur, puis petits pignons en bois.
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
## Irimoya : part de la hauteur couverte par la croupe avant le pignon.
@export_range(0.2, 0.85, 0.01) var irimoya_ratio: float = 0.5:
	set(value):
		irimoya_ratio = value
		emit_changed()
## Bords relevés : hauteur dont le bord du débord remonte (0 = pans plats).
@export_range(0.0, 1.0, 0.01, "suffix:m") var eave_curve: float = 0.0:
	set(value):
		eave_curve = value
		emit_changed()
## Bords relevés : surcroît aux angles saillants (1 = deux fois plus haut).
@export_range(0.0, 3.0, 0.05) var corner_lift: float = 0.0:
	set(value):
		corner_lift = value
		emit_changed()
## Chevrons apparents sous le débord.
@export var rafters: bool = false:
	set(value):
		rafters = value
		emit_changed()
@export_group("Tuiles")
@export var tile_kind: TileKind = TileKind.FLAT:
	set(value):
		tile_kind = value
		emit_changed()

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
@export var ridge_kind: RidgeKind = RidgeKind.CAPS:
	set(value):
		ridge_kind = value
		emit_changed()
## Faîtage maçonné : hauteur au-dessus du faîte.
@export_range(0.1, 1.0, 0.01, "suffix:m") var ridge_height: float = 0.4:
	set(value):
		ridge_height = value
		emit_changed()
## Faîtage maçonné, épis et arêtiers.
@export var ridge_color: Color = Color(0.25, 0.26, 0.29):
	set(value):
		ridge_color = value
		emit_changed()
## Petits pignons du toit irimoya (bois).
@export var gable_color: Color = Color(0.32, 0.23, 0.17):
	set(value):
		gable_color = value
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
