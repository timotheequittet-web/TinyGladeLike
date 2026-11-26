@tool
class_name BastideGardenStyle
extends Resource
## Abords et décor d'un style : sol, chemins, clôtures, végétation, torii, lanternes.
##
## Les nœuds de décor (BastidePath, BastideTorii, BastideFence, BastidePlanting,
## BastideGarden) lisent leurs couleurs et proportions ici : changer de style change
## aussi le jardin (pas japonais et lanternes de pierre, ou chemin de terre et
## clôture de bois).

enum FenceKind { STONE, BAMBOO }

@export_group("Sol")
@export var ground_color: Color = Color(0.42, 0.55, 0.3):
	set(value):
		ground_color = value
		emit_changed()
## Chemins, cours en terre battue ou gravier.
@export var path_color: Color = Color(0.62, 0.57, 0.47):
	set(value):
		path_color = value
		emit_changed()
## Largeur d'un chemin.
@export_range(0.6, 4.0, 0.05, "suffix:m") var path_width: float = 1.5:
	set(value):
		path_width = value
		emit_changed()
## Pas japonais (tobi-ishi) : grandes pierres plates posées dans le gravier.
@export var stepping_stones := true:
	set(value):
		stepping_stones = value
		emit_changed()
@export var stepping_stone_color: Color = Color(0.55, 0.54, 0.5):
	set(value):
		stepping_stone_color = value
		emit_changed()
## Bordure de petites pierres rondes de chaque côté des chemins.
@export var path_edging := true:
	set(value):
		path_edging = value
		emit_changed()
@export var edging_color: Color = Color(0.5, 0.49, 0.45):
	set(value):
		edging_color = value
		emit_changed()
## Bande de galets au pied des maisons (là où tombe la pluie du toit).
@export var drip_edge := true:
	set(value):
		drip_edge = value
		emit_changed()
@export var pebble_color: Color = Color(0.36, 0.36, 0.36):
	set(value):
		pebble_color = value
		emit_changed()

@export_group("Clôtures")
@export_range(0.3, 1.5, 0.05, "suffix:m") var stone_fence_height: float = 0.65:
	set(value):
		stone_fence_height = value
		emit_changed()
@export var fence_stone_color: Color = Color(0.55, 0.53, 0.48):
	set(value):
		fence_stone_color = value
		emit_changed()
@export_range(0.5, 2.5, 0.05, "suffix:m") var bamboo_fence_height: float = 1.1:
	set(value):
		bamboo_fence_height = value
		emit_changed()
@export var bamboo_color: Color = Color(0.74, 0.66, 0.42):
	set(value):
		bamboo_color = value
		emit_changed()
## Liens de corde noire aux croisements.
@export var cord_color: Color = Color(0.1, 0.09, 0.08):
	set(value):
		cord_color = value
		emit_changed()

@export_group("Végétation")
@export var foliage_colors: PackedColorArray = PackedColorArray([Color(0.3, 0.45, 0.22), Color(0.38, 0.5, 0.25)]):
	set(value):
		foliage_colors = value
		emit_changed()
@export var blossom_colors: PackedColorArray = PackedColorArray([Color(0.95, 0.75, 0.8)]):
	set(value):
		blossom_colors = value
		emit_changed()
## Têtes d'hortensias, fleurs des massifs.
@export var flower_colors: PackedColorArray = PackedColorArray([Color(0.45, 0.55, 0.85), Color(0.62, 0.5, 0.82), Color(0.9, 0.62, 0.75)]):
	set(value):
		flower_colors = value
		emit_changed()
## Érables (momiji).
@export var maple_colors: PackedColorArray = PackedColorArray([Color(0.78, 0.2, 0.12), Color(0.86, 0.36, 0.14), Color(0.68, 0.14, 0.12)]):
	set(value):
		maple_colors = value
		emit_changed()
## Herbes (hakone) et fougères.
@export var grass_colors: PackedColorArray = PackedColorArray([Color(0.55, 0.62, 0.27), Color(0.68, 0.66, 0.3)]):
	set(value):
		grass_colors = value
		emit_changed()
@export var trunk_color: Color = Color(0.3, 0.24, 0.2):
	set(value):
		trunk_color = value
		emit_changed()
## Plantes qui poussent toutes seules au pied des murs, des maisons et des clôtures.
@export_range(0.0, 2.0, 0.05) var plant_density: float = 1.0:
	set(value):
		plant_density = value
		emit_changed()
## Espèces d'arbres proposées (poids) : érable, cerisier, pin taillé.
@export var tree_weights := Vector3(0.45, 0.3, 0.25):
	set(value):
		tree_weights = value
		emit_changed()

## Arbres et plantes du kit nature (modèles d'Onsen à couronnes peintes) à la place
## des arbres, hortensias et fougères dessinés par l'addon.
@export var kit_plants := true:
	set(value):
		kit_plants = value
		emit_changed()

@export_group("Édifices")
## Torii, portiques : couleur principale (vermillon au Japon).
@export var gate_color: Color = Color(0.78, 0.24, 0.14):
	set(value):
		gate_color = value
		emit_changed()
## Poutre du haut et bas des piliers.
@export var gate_top_color: Color = Color(0.11, 0.1, 0.1):
	set(value):
		gate_top_color = value
		emit_changed()
## Lanternes de pierre (tōrō) aux bouts des chemins.
@export var lanterns := true:
	set(value):
		lanterns = value
		emit_changed()
@export var lantern_color: Color = Color(0.6, 0.59, 0.55):
	set(value):
		lantern_color = value
		emit_changed()

@export_group("Terrasses")
## Hauteur du plancher des terrasses et des engawa.
@export_range(0.2, 1.2, 0.01, "suffix:m") var terrace_height: float = 0.45:
	set(value):
		terrace_height = value
		emit_changed()
## Planches du plancher (cèdre patiné).
@export var terrace_color: Color = Color(0.64, 0.52, 0.38):
	set(value):
		terrace_color = value
		emit_changed()
## Poteaux, poutres, garde-corps.
@export var terrace_frame_color: Color = Color(0.33, 0.25, 0.19):
	set(value):
		terrace_frame_color = value
		emit_changed()
## Garde-corps autour des terrasses isolées (jamais sur un engawa).
@export var terrace_railing := true:
	set(value):
		terrace_railing = value
		emit_changed()
## Boules de bronze (giboshi) en tête des poteaux d'angle du garde-corps.
@export var giboshi := true:
	set(value):
		giboshi = value
		emit_changed()
@export var giboshi_color: Color = Color(0.36, 0.45, 0.38):
	set(value):
		giboshi_color = value
		emit_changed()
## Petits détails de vie : une paire de geta sur la pierre de seuil, parfois.
@export var terrace_details := true:
	set(value):
		terrace_details = value
		emit_changed()
