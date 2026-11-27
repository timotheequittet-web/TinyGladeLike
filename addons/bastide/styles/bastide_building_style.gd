@tool
class_name BastideBuildingStyle
extends Resource
## Paramètres d'un bâtiment : étages, murs, ouvertures, décor et couleurs.
## Les pierres du soubassement et des chaînes d'angle reprennent les couleurs du style de mur.

## Construction des façades : maçonnerie enduite (chaînes d'angle, bandeaux de
## pierre) ou ossature bois (poteaux et poutres apparents, panneaux d'enduit).
enum FacadeKind { MASONRY, TIMBER }
## Fenêtres à la française (vitres, croisillons, volets) ou à claire-voie (lattes
## de bois verticales devant un écran de papier).
enum WindowKind { CASEMENT, LATTICE }
## Porte battante en planches, ou porte coulissante à claire-voie.
enum DoorKind { PLANK, SLIDING }
## Forme d'habitation : maison à murs et toit, ou terrier creusé dans une butte
## herbeuse (porte et fenêtres rondes, voir BastideBurrowBuilder).
enum Form { HOUSE, BURROW }

@export var form: Form = Form.HOUSE:
	set(value):
		form = value
		emit_changed()

@export_group("Construction")
@export var facade_kind: FacadeKind = FacadeKind.MASONRY:
	set(value):
		facade_kind = value
		emit_changed()
@export var window_kind: WindowKind = WindowKind.CASEMENT:
	set(value):
		window_kind = value
		emit_changed()
@export var door_kind: DoorKind = DoorKind.PLANK:
	set(value):
		door_kind = value
		emit_changed()

@export_group("Volumes")
## Nombre d'étages par défaut (le nœud peut le remplacer).
@export_range(1, 6, 1) var floors: int = 2:
	set(value):
		floors = value
		emit_changed()
## Hauteur d'un étage.
@export_range(2.0, 6.0, 0.05, "suffix:m") var floor_height: float = 2.9:
	set(value):
		floor_height = value
		emit_changed()
## Surhauteur des murs au-dessus du dernier étage, sous le toit.
@export_range(0.0, 2.0, 0.05, "suffix:m") var knee_height: float = 0.35:
	set(value):
		knee_height = value
		emit_changed()
## Épaisseur des murs.
@export_range(0.15, 1.5, 0.01, "suffix:m") var wall_thickness: float = 0.42:
	set(value):
		wall_thickness = value
		emit_changed()
@export_group("Contour")
## Côtés plus courts que ça : fusionnés.
@export_range(0.3, 5.0, 0.05, "suffix:m") var min_edge: float = 1.2:
	set(value):
		min_edge = value
		emit_changed()
## Redresse les angles presque droits.
@export var square_corners: bool = true:
	set(value):
		square_corners = value
		emit_changed()
## Écart maximal toléré pour redresser un angle.
@export_range(0.0, 40.0, 0.5, "suffix:°") var square_tolerance: float = 18.0:
	set(value):
		square_tolerance = value
		emit_changed()
@export_group("Façades")
## Hauteur du soubassement en pierre (0 = aucun).
@export_range(0.0, 2.0, 0.01, "suffix:m") var plinth_height: float = 0.6:
	set(value):
		plinth_height = value
		emit_changed()
## Saillie du soubassement.
@export_range(0.0, 0.3, 0.005, "suffix:m") var plinth_protrusion: float = 0.05:
	set(value):
		plinth_protrusion = value
		emit_changed()
## Chaînes d'angle en pierre sur les angles saillants.
@export var quoins: bool = true:
	set(value):
		quoins = value
		emit_changed()
## Bandeau de pierre entre les étages.
@export var string_courses: bool = true:
	set(value):
		string_courses = value
		emit_changed()
## Distance minimale entre un angle et une ouverture.
@export_range(0.2, 3.0, 0.05, "suffix:m") var corner_margin: float = 0.85:
	set(value):
		corner_margin = value
		emit_changed()
## Largeur visée d'une travée (une fenêtre par travée).
@export_range(1.2, 8.0, 0.05, "suffix:m") var bay_width: float = 2.6:
	set(value):
		bay_width = value
		emit_changed()
@export_group("Fenêtres")
@export_range(0.3, 3.0, 0.01, "suffix:m") var window_width: float = 0.85:
	set(value):
		window_width = value
		emit_changed()
@export_range(0.3, 3.0, 0.01, "suffix:m") var window_height: float = 1.25:
	set(value):
		window_height = value
		emit_changed()
## Hauteur de l'appui au-dessus du plancher.
@export_range(0.0, 2.0, 0.01, "suffix:m") var sill_height: float = 0.9:
	set(value):
		sill_height = value
		emit_changed()
## Probabilité qu'une fenêtre ait des volets (tirée par bâtiment).
@export_range(0.0, 1.0, 0.01) var shutter_chance: float = 0.8:
	set(value):
		shutter_chance = value
		emit_changed()
## Probabilité d'une jardinière sous une fenêtre.
@export_range(0.0, 1.0, 0.01) var flower_box_chance: float = 0.3:
	set(value):
		flower_box_chance = value
		emit_changed()
## Petite fenêtre dans les grands pignons.
@export var attic_windows: bool = true:
	set(value):
		attic_windows = value
		emit_changed()
@export_group("Porte")
@export_range(0.6, 3.0, 0.01, "suffix:m") var door_width: float = 1.15:
	set(value):
		door_width = value
		emit_changed()
## Hauteur sous la naissance de l'arc.
@export_range(1.5, 4.0, 0.01, "suffix:m") var door_height: float = 2.05:
	set(value):
		door_height = value
		emit_changed()
## Porte cintrée (arc en plein cintre).
@export var arched_door: bool = true:
	set(value):
		arched_door = value
		emit_changed()
@export_group("Ossature bois")
## Section des poteaux.
@export_range(0.08, 0.5, 0.01, "suffix:m") var post_width: float = 0.2:
	set(value):
		post_width = value
		emit_changed()
## Hauteur des poutres horizontales (sablière, poutre d'étage, lisse basse).
@export_range(0.05, 0.5, 0.01, "suffix:m") var beam_height: float = 0.17:
	set(value):
		beam_height = value
		emit_changed()
## Bois de l'ossature.
@export var timber_color: Color = Color(0.3, 0.21, 0.15):
	set(value):
		timber_color = value
		emit_changed()
## Bardage bas en planches au rez-de-chaussée (0 = aucun).
@export_range(0.0, 2.0, 0.01, "suffix:m") var wainscot_height: float = 0.0:
	set(value):
		wainscot_height = value
		emit_changed()
## Couleur du bardage (bois brûlé, sombre).
@export var wainscot_color: Color = Color(0.2, 0.16, 0.13):
	set(value):
		wainscot_color = value
		emit_changed()
## Papier des fenêtres à claire-voie.
@export var paper_color: Color = Color(0.96, 0.93, 0.84):
	set(value):
		paper_color = value
		emit_changed()
## Écart entre deux lattes d'une claire-voie.
@export_range(0.04, 0.3, 0.005, "suffix:m") var lattice_spacing: float = 0.1:
	set(value):
		lattice_spacing = value
		emit_changed()
## Auvent de tuiles entre le rez-de-chaussée et l'étage.
@export var pent_roof: bool = false:
	set(value):
		pent_roof = value
		emit_changed()
## Un auvent à chaque étage (tours à étages, yagura), pas seulement au premier.
@export var pent_every_floor: bool = false:
	set(value):
		pent_every_floor = value
		emit_changed()
## Profondeur de l'auvent.
@export_range(0.3, 2.0, 0.01, "suffix:m") var pent_depth: float = 0.75:
	set(value):
		pent_depth = value
		emit_changed()
## Pente de l'auvent.
@export_range(10.0, 45.0, 0.5, "suffix:°") var pent_pitch: float = 24.0:
	set(value):
		pent_pitch = value
		emit_changed()
## Rideau de tissu (noren) devant la porte, une couleur tirée par bâtiment.
## Vide : pas de rideau.
@export var noren_colors: PackedColorArray = PackedColorArray():
	set(value):
		noren_colors = value
		emit_changed()
@export_group("Terrier")
## Hauteur d'une butte (au sommet, pour une butte de taille moyenne).
@export_range(1.8, 6.0, 0.05, "suffix:m") var mound_height: float = 3.2:
	set(value):
		mound_height = value
		emit_changed()
## Largeur visée d'une butte : un long tracé donne plusieurs buttes côte à côte,
## chacune avec sa porte.
@export_range(5.0, 16.0, 0.1, "suffix:m") var burrow_width: float = 8.5:
	set(value):
		burrow_width = value
		emit_changed()
## Couleurs des portes rondes (une par butte, tirée par la seed).
@export var door_colors: PackedColorArray = PackedColorArray([Color(0.22, 0.4, 0.22), Color(0.2, 0.33, 0.52),
		Color(0.6, 0.2, 0.15), Color(0.82, 0.62, 0.2)]):
	set(value):
		door_colors = value
		emit_changed()

@export_group("Couleurs")
## Enduit des murs.
@export var plaster_color: Color = Color(0.93, 0.87, 0.75):
	set(value):
		plaster_color = value
		emit_changed()
## Seconde teinte d'enduit, mélangée par bâtiment.
@export var plaster_color_alt: Color = Color(0.89, 0.8, 0.66):
	set(value):
		plaster_color_alt = value
		emit_changed()
## Intérieur, vu par les fenêtres.
@export var interior_color: Color = Color(0.16, 0.13, 0.11):
	set(value):
		interior_color = value
		emit_changed()
## Huisseries, planches de rive.
@export var wood_color: Color = Color(0.36, 0.25, 0.17):
	set(value):
		wood_color = value
		emit_changed()
@export var door_color: Color = Color(0.45, 0.28, 0.16):
	set(value):
		door_color = value
		emit_changed()
@export var glass_color: Color = Color(0.2, 0.27, 0.33):
	set(value):
		glass_color = value
		emit_changed()
## Couleurs de volets possibles (une par bâtiment, tirée par la seed).
@export var shutter_colors: PackedColorArray = PackedColorArray([Color(0.3, 0.45, 0.58), Color(0.33, 0.5, 0.36), Color(0.62, 0.27, 0.22), Color(0.78, 0.6, 0.3)]):
	set(value):
		shutter_colors = value
		emit_changed()
@export var flower_colors: PackedColorArray = PackedColorArray([Color(0.86, 0.25, 0.3), Color(0.95, 0.75, 0.25), Color(0.85, 0.45, 0.7), Color(0.95, 0.95, 0.9)]):
	set(value):
		flower_colors = value
		emit_changed()
