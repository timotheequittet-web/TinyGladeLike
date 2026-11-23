@tool
class_name BastideWallStyle
extends Resource
## Paramètres d'un mur : matière, proportions, pierres, couronnement, règles d'angles, couleurs.
## Toute modification émet `changed`, ce qui régénère les murs qui utilisent ce style.

## Matière du corps du mur : pierres apparentes partout, ou enduit au-dessus
## d'un soubassement de pierres (muret japonais, mur de jardin…).
enum BodyKind { STONE, PLASTER }

@export_group("Corps du mur")
@export var body_kind: BodyKind = BodyKind.STONE:
	set(value):
		body_kind = value
		emit_changed()
## Épaisseur au sommet du mur.
@export_range(0.2, 4.0, 0.01, "or_greater", "suffix:m") var thickness: float = 0.9:
	set(value):
		thickness = value
		emit_changed()
## Hauteur par défaut (le nœud peut la remplacer).
@export_range(0.5, 20.0, 0.05, "or_greater", "suffix:m") var height: float = 3.2:
	set(value):
		height = value
		emit_changed()
## Fruit : surépaisseur de chaque face au pied du mur.
@export_range(0.0, 0.5, 0.005, "suffix:m") var batter: float = 0.08:
	set(value):
		batter = value
		emit_changed()
## Amplitude du sommet irrégulier.
@export_range(0.0, 2.0, 0.01, "suffix:m") var top_amplitude: float = 0.22:
	set(value):
		top_amplitude = value
		emit_changed()
## Longueur d'onde des ondulations du sommet.
@export_range(0.5, 50.0, 0.1, "suffix:m") var top_wavelength: float = 5.0:
	set(value):
		top_wavelength = value
		emit_changed()
@export_group("Pierres")
## Hauteur moyenne d'une assise.
@export_range(0.1, 2.0, 0.01, "suffix:m") var course_height: float = 0.34:
	set(value):
		course_height = value
		emit_changed()
@export_range(0.1, 3.0, 0.01, "suffix:m") var stone_length_min: float = 0.45:
	set(value):
		stone_length_min = value
		emit_changed()
@export_range(0.1, 3.0, 0.01, "suffix:m") var stone_length_max: float = 0.95:
	set(value):
		stone_length_max = value
		emit_changed()
## Largeur du biseau (et donc du joint) de chaque pierre.
@export_range(0.0, 0.3, 0.005, "suffix:m") var stone_bevel: float = 0.05:
	set(value):
		stone_bevel = value
		emit_changed()
## Relief minimal d'une pierre.
@export_range(0.0, 0.3, 0.001, "suffix:m") var stone_bulge_min: float = 0.012:
	set(value):
		stone_bulge_min = value
		emit_changed()
## Relief maximal d'une pierre.
@export_range(0.0, 0.3, 0.001, "suffix:m") var stone_bulge_max: float = 0.045:
	set(value):
		stone_bulge_max = value
		emit_changed()
@export_group("Enduit et petit toit")
## Corps enduit : hauteur du soubassement en pierres.
@export_range(0.0, 3.0, 0.01, "suffix:m") var plinth_height: float = 0.7:
	set(value):
		plinth_height = value
		emit_changed()
## Corps enduit : couleur de l'enduit.
@export var plaster_color: Color = Color(0.92, 0.89, 0.82):
	set(value):
		plaster_color = value
		emit_changed()
## Seconde teinte d'enduit, mélangée par mur (seed).
@export var plaster_color_alt: Color = Color(0.86, 0.8, 0.68):
	set(value):
		plaster_color_alt = value
		emit_changed()
## Couronne le mur d'un petit toit de tuiles à deux pentes
## (remplace chaperon et créneaux).
@export var cap_roof: bool = false:
	set(value):
		cap_roof = value
		emit_changed()
## Débord du petit toit de chaque côté du mur.
@export_range(0.0, 1.0, 0.01, "suffix:m") var cap_overhang: float = 0.3:
	set(value):
		cap_overhang = value
		emit_changed()
## Pente du petit toit.
@export_range(10.0, 50.0, 0.5, "suffix:°") var cap_pitch: float = 27.0:
	set(value):
		cap_pitch = value
		emit_changed()
## Écart entre deux rangs de tuiles rondes du petit toit.
@export_range(0.1, 1.0, 0.01, "suffix:m") var cap_tile_width: float = 0.26:
	set(value):
		cap_tile_width = value
		emit_changed()
## Couleur des tuiles du petit toit.
@export var cap_color: Color = Color(0.3, 0.32, 0.36):
	set(value):
		cap_color = value
		emit_changed()
## Bois sous le petit toit (chevrons, poutre).
@export var cap_wood_color: Color = Color(0.28, 0.2, 0.15):
	set(value):
		cap_wood_color = value
		emit_changed()
@export_group("Chaperon et créneaux")
## Épaisseur des dalles du chaperon (0 = pas de chaperon).
@export_range(0.0, 1.0, 0.01, "suffix:m") var coping_thickness: float = 0.16:
	set(value):
		coping_thickness = value
		emit_changed()
## Débord du chaperon de chaque côté.
@export_range(0.0, 0.5, 0.005, "suffix:m") var coping_overhang: float = 0.07:
	set(value):
		coping_overhang = value
		emit_changed()
## Ajoute des créneaux au sommet.
@export var crenellations: bool = true:
	set(value):
		crenellations = value
		emit_changed()
@export_range(0.2, 4.0, 0.01, "suffix:m") var merlon_width: float = 0.8:
	set(value):
		merlon_width = value
		emit_changed()
@export_range(0.1, 4.0, 0.01, "suffix:m") var merlon_gap: float = 0.55:
	set(value):
		merlon_gap = value
		emit_changed()
@export_range(0.1, 3.0, 0.01, "suffix:m") var merlon_height: float = 0.6:
	set(value):
		merlon_height = value
		emit_changed()
## Profondeur des merlons par rapport à l'épaisseur du mur.
@export_range(0.2, 1.0, 0.01) var merlon_depth_ratio: float = 0.92:
	set(value):
		merlon_depth_ratio = value
		emit_changed()
## Étirement maximal toléré pour répartir pile les éléments répétés.
@export_range(0.0, 0.5, 0.01) var distribution_tolerance: float = 0.18:
	set(value):
		distribution_tolerance = value
		emit_changed()
@export_group("Angles et extrémités")
## À partir de ce virage, un point du tracé devient un angle net (pierres d'angle).
@export_range(5.0, 90.0, 1.0, "suffix:°") var corner_angle: float = 25.0:
	set(value):
		corner_angle = value
		emit_changed()
## À partir de ce virage, un pilier est inséré dans l'angle.
@export_range(10.0, 180.0, 1.0, "suffix:°") var pillar_angle: float = 70.0:
	set(value):
		pillar_angle = value
		emit_changed()
## Termine les murs ouverts par un pilier.
@export var end_pillars: bool = true:
	set(value):
		end_pillars = value
		emit_changed()
## Largeur des piliers en multiple de l'épaisseur.
@export_range(1.0, 4.0, 0.05) var pillar_width_factor: float = 1.6:
	set(value):
		pillar_width_factor = value
		emit_changed()
@export_range(1.0, 6.0, 0.1) var miter_limit: float = 2.5:
	set(value):
		miter_limit = value
		emit_changed()
@export_group("Tracé")
## Points du tracé plus proches que ça : fusionnés.
@export_range(0.01, 5.0, 0.01, "suffix:m") var min_segment: float = 0.3:
	set(value):
		min_segment = value
		emit_changed()
## Finesse du découpage le long du tracé.
@export_range(0.1, 5.0, 0.05, "suffix:m") var station_spacing: float = 0.5:
	set(value):
		station_spacing = value
		emit_changed()
@export_group("Couleurs")
@export var stone_color: Color = Color(0.64, 0.6, 0.53):
	set(value):
		stone_color = value
		emit_changed()
## Seconde teinte mélangée au hasard.
@export var stone_color_alt: Color = Color(0.56, 0.55, 0.52):
	set(value):
		stone_color_alt = value
		emit_changed()
## Pierres d'angle et chaperon.
@export var quoin_color: Color = Color(0.76, 0.71, 0.62):
	set(value):
		quoin_color = value
		emit_changed()
## Couleur des joints.
@export var mortar_color: Color = Color(0.33, 0.31, 0.28):
	set(value):
		mortar_color = value
		emit_changed()
## Variation de clarté d'une pierre à l'autre.
@export_range(0.0, 0.5, 0.01) var color_variance: float = 0.12:
	set(value):
		color_variance = value
		emit_changed()

