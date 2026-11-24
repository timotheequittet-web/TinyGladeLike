@tool
@icon("res://addons/bastide/editor/icons/bastide_garden.svg")
class_name BastideGarden
extends BastideStructure
## Jardin automatique : ajoute ce nœud une fois dans la scène, il décore toutes les
## structures Bastide autour de lui. Bande de galets au pied des maisons, touffes aux
## angles, petit érable dans les angles rentrants, plantes basses le long des
## façades, herbes et fougères au pied des murs et des clôtures, touffes au bord des
## chemins. Il se met à jour dès qu'une structure change.
##
## Sa courbe ne sert pas. Densité, couleurs et galets : volet Garden du style.

func context_level() -> int:
	return 3


func uses_context() -> bool:
	return true


func _default_curve() -> Curve3D:
	return Curve3D.new()


func _make_job() -> Callable:
	var st := get_effective_style()
	var ctx := gather_context()
	var s := seed
	return func() -> BastideBuildResult: return BastidePlantingMesher.build_garden(ctx, s, st)
