@tool
class_name BastideGardenStyle
extends Resource
## Abords et décor d'un style : sol, chemins, végétation, petits édifices (torii…).
##
## Réservé à l'étape « décor » : seules les couleurs de sol servent déjà (scènes de
## démo). Les futurs nœuds de décor (torii, lanternes, plantes, dallages) liront
## leurs couleurs et proportions ici, pour qu'un changement de style les suive aussi.

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
@export_group("Végétation")
@export var foliage_colors: PackedColorArray = PackedColorArray([Color(0.3, 0.45, 0.22), Color(0.38, 0.5, 0.25)]):
	set(value):
		foliage_colors = value
		emit_changed()
@export var blossom_colors: PackedColorArray = PackedColorArray([Color(0.95, 0.75, 0.8)]):
	set(value):
		blossom_colors = value
		emit_changed()
@export_group("Édifices")
## Torii, portiques : couleur principale (vermillon au Japon).
@export var gate_color: Color = Color(0.78, 0.24, 0.14):
	set(value):
		gate_color = value
		emit_changed()
