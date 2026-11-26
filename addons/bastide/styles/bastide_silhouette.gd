@tool
class_name BastideSilhouette
extends RefCounted
## Silhouettes de bâtiment : le même style (bois japonais, pierre médiévale…)
## décliné en volumes différents. Une silhouette ne remplace pas le style : elle en
## fait une variante (étages, ouvertures, auvents, toit), ce qui garde l'unité du
## hameau tout en cassant la répétition.
##
## AUTO choisit d'après le tracé : une petite base carrée fait une tour, un petit
## rectangle une petite maison ou un entrepôt (kura), le reste une grande maison.
## Le choix est stable (même tracé, même graine → même silhouette), donc un futur
## village généré tout seul aura naturellement ses tours et ses granges.

enum Kind { AUTO, HOUSE, SMALL, KURA, TOWER }

const NAMES := {Kind.AUTO: "automatique", Kind.HOUSE: "grande maison", Kind.SMALL: "petite maison",
	Kind.KURA: "kura (entrepôt)", Kind.TOWER: "tour"}

## Ordre du cycle de la touche G.
const CYCLE := [Kind.AUTO, Kind.HOUSE, Kind.SMALL, Kind.KURA, Kind.TOWER]

## Seuils du choix automatique (m²).
const TOWER_MAX_AREA := 22.0
const SMALL_MAX_AREA := 34.0

static var _cache := {}
static var _rev := {}


## Silhouette retenue pour un contour (angles dans le plan, ordre quelconque).
static func resolve(kind: int, footprint: PackedVector2Array, seed: int) -> int:
	if kind != Kind.AUTO:
		return kind
	if footprint.size() != 4:
		return Kind.HOUSE
	var a := footprint[0].distance_to(footprint[1])
	var b := footprint[1].distance_to(footprint[2])
	var short := minf(a, b)
	var long := maxf(a, b)
	if short < 0.5:
		return Kind.HOUSE
	var area := absf(BastidePolygon.signed_area(footprint)) if footprint.size() >= 3 else a * b
	var ratio := long / short
	if area <= TOWER_MAX_AREA and ratio <= 1.35:
		return Kind.TOWER
	if area <= SMALL_MAX_AREA:
		return Kind.KURA if ratio >= 1.35 and BastideRng.randf_at(seed, "kura") < 0.5 else Kind.SMALL
	return Kind.HOUSE


## Les maisons d'habitation ont un foyer (fumée) ; le kura et la tour non.
static func has_hearth(kind: int) -> bool:
	return kind != Kind.KURA and kind != Kind.TOWER


## Variante du style pour une silhouette (en cache ; à appeler sur le thread principal).
static func style_for(base: BastideStyle, kind: int) -> BastideStyle:
	if base == null or kind == Kind.HOUSE or kind == Kind.AUTO:
		return base
	# Le style de base peut être retouché (éditeur) : un compteur de version, tenu à
	# jour par son signal « changed », invalide les variantes.
	var bid := base.get_instance_id()
	if not _rev.has(bid):
		_rev[bid] = 0
		base.changed.connect(func() -> void: _rev[bid] = int(_rev.get(bid, 0)) + 1)
	var key := "%d:%d:%d" % [bid, kind, _rev[bid]]
	if _cache.has(key):
		return _cache[key]
	var v := base.duplicate(false) as BastideStyle
	var bs := base.get_building_style().duplicate() as BastideBuildingStyle
	var rs := base.get_roof_style().duplicate() as BastideRoofStyle
	_shape(kind, bs, rs, base.get_building_style())
	v.building = bs
	v.roof = rs
	v.prepare()
	_cache[key] = v
	return v


static func _shape(kind: int, bs: BastideBuildingStyle, rs: BastideRoofStyle, ref: BastideBuildingStyle) -> void:
	var japanese := ref.facade_kind == BastideBuildingStyle.FacadeKind.TIMBER
	match kind:
		Kind.SMALL:
			# Un seul niveau, toit qui descend bas : la maison de paysan.
			bs.floors = 1
			bs.floor_height = ref.floor_height * 1.04
			bs.knee_height = ref.knee_height + 0.2
			bs.bay_width = ref.bay_width + 0.3
			bs.pent_roof = false
			rs.pitch = rs.pitch + 3.0
			rs.overhang = rs.overhang * 0.9
		Kind.KURA:
			# Entrepôt : murs blancs épais, peu d'ouvertures, petites fenêtres hautes,
			# soubassement de pierre haut et bardage sombre en pied.
			bs.floors = 2
			bs.floor_height = ref.floor_height * 0.92
			bs.wall_thickness = ref.wall_thickness + 0.15
			bs.window_width = minf(ref.window_width, 0.7)
			bs.window_height = minf(ref.window_height, 0.66)
			bs.sill_height = ref.sill_height + 0.45
			bs.bay_width = ref.bay_width + 1.6
			bs.corner_margin = ref.corner_margin + 0.3
			bs.plinth_height = ref.plinth_height + 0.35
			bs.shutter_chance = 0.0
			bs.flower_box_chance = 0.0
			bs.attic_windows = false
			bs.door_width = minf(ref.door_width, 1.25)
			bs.pent_roof = false
			bs.noren_colors = PackedColorArray()
			bs.plaster_color = Color(0.97, 0.96, 0.93)
			bs.plaster_color_alt = Color(0.94, 0.93, 0.89)
			if japanese:
				bs.wainscot_height = 1.15
				bs.wainscot_color = Color(0.13, 0.12, 0.11)
				bs.post_width = ref.post_width * 0.8
			rs.roof_type = BastideRoofStyle.RoofType.GABLE
			rs.pitch = rs.pitch + 4.0
			rs.overhang = rs.overhang * 0.6
			rs.corner_lift = rs.corner_lift * 0.3
			rs.eave_curve = rs.eave_curve * 0.5
			rs.chimney_chance = 0.0
		Kind.TOWER:
			# Tour à étages (yagura) : base carrée, un auvent par étage sur le style
			# japonais, toit en pavillon relevé aux angles.
			bs.floors = 3
			bs.floor_height = ref.floor_height * 0.92
			bs.bay_width = maxf(ref.bay_width - 0.4, 1.6)
			bs.corner_margin = maxf(ref.corner_margin - 0.15, 0.45)
			bs.window_width = ref.window_width * 0.85
			bs.attic_windows = false
			bs.flower_box_chance = 0.0
			bs.pent_every_floor = ref.pent_roof
			bs.pent_depth = ref.pent_depth * 0.9
			rs.roof_type = BastideRoofStyle.RoofType.HIP
			rs.pitch = rs.pitch + (6.0 if japanese else 12.0)
			rs.corner_lift = rs.corner_lift * 1.3
			rs.overhang = rs.overhang * (1.1 if japanese else 0.8)
			rs.chimney_chance = 0.0
