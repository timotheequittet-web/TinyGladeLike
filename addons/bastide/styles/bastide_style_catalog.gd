@tool
class_name BastideStyleCatalog
extends RefCounted
## Les styles proposés en jeu, dans l'ordre du sélecteur : nom court, couleur et
## petite icône dessinée (aucune image à fournir). Ajouter un style au jeu, c'est
## ajouter une ligne ici : l'interface en fait une carte de plus.

const ENTRIES := [
	{"path": "res://addons/bastide/styles/presets/japanese_wood.tres", "name": "Japonais", "icon": "pagoda",
		"color": Color(0.74, 0.27, 0.2), "blurb": "bois, tuiles, shoji"},
	{"path": "res://addons/bastide/styles/presets/medieval_stone.tres", "name": "Médiéval", "icon": "tower",
		"color": Color(0.46, 0.5, 0.58), "blurb": "pierre et créneaux"},
	{"path": "res://addons/bastide/styles/presets/burrow_hill.tres", "name": "Terrier", "icon": "burrow",
		"color": Color(0.34, 0.56, 0.24), "blurb": "buttes et portes rondes"},
]

static var _loaded := {}


static func size() -> int:
	return ENTRIES.size()


static func style(i: int) -> BastideStyle:
	var path: String = ENTRIES[i]["path"]
	if not _loaded.has(path):
		_loaded[path] = load(path)
	return _loaded[path]


## Rang d'un style dans le catalogue (comparé par chemin), -1 s'il n'y est pas.
static func index_of(st: BastideStyle) -> int:
	if st == null:
		return -1
	for i in ENTRIES.size():
		if ENTRIES[i]["path"] == st.resource_path:
			return i
	return -1


## Style suivant (dir = 1) ou précédent (dir = -1), en boucle.
static func next(st: BastideStyle, dir := 1) -> BastideStyle:
	var i := index_of(st)
	return style(posmod(i + dir, ENTRIES.size()) if i >= 0 else 0)


## Dessine l'icône `kind` dans `r` : silhouette à l'encre, une touche de couleur.
static func draw_icon(ci: CanvasItem, kind: String, r: Rect2, ink: Color, accent: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.5
	var ground := c.y + s * 0.78
	ci.draw_line(Vector2(c.x - s * 1.05, ground), Vector2(c.x + s * 1.05, ground), Color(ink, 0.55), 2.0, true)
	match kind:
		"pagoda":
			# Toit à bords relevés, poteaux, et un second petit toit.
			var body := Rect2(c.x - s * 0.5, c.y + s * 0.05, s * 1.0, s * 0.73)
			ci.draw_rect(body, Color(0.96, 0.92, 0.82))
			ci.draw_rect(body, ink, false, 1.5)
			for k in 3:
				var x := body.position.x + body.size.x * (0.17 + 0.33 * k)
				ci.draw_line(Vector2(x, body.position.y), Vector2(x, body.end.y), ink, 1.5)
			_roof(ci, c + Vector2(0, s * 0.05), s * 1.0, s * 0.42, accent, ink)
			_roof(ci, c + Vector2(0, -s * 0.38), s * 0.62, s * 0.3, accent, ink)
		"tower":
			# Donjon crénelé, porte en arc, petite meurtrière.
			var w := s * 0.9
			var top := c.y - s * 0.55
			var pts := PackedVector2Array([Vector2(c.x - w * 0.5, ground), Vector2(c.x - w * 0.5, top)])
			var n := 5
			for k in n:
				var x0 := c.x - w * 0.5 + w * k / n
				var x1 := c.x - w * 0.5 + w * (k + 1) / n
				if k % 2 == 0:
					pts.append(Vector2(x0, top - s * 0.2))
					pts.append(Vector2(x1, top - s * 0.2))
				else:
					pts.append(Vector2(x0, top))
					pts.append(Vector2(x1, top))
			pts.append(Vector2(c.x + w * 0.5, top))
			pts.append(Vector2(c.x + w * 0.5, ground))
			ci.draw_colored_polygon(pts, accent.lightened(0.35))
			pts.append(pts[0])
			ci.draw_polyline(pts, ink, 1.5, true)
			var dw := s * 0.18
			var door := PackedVector2Array([Vector2(c.x - dw, ground)])
			for k in 9:
				var a := PI + PI * k / 8.0
				door.append(Vector2(c.x + cos(a) * dw, ground - s * 0.25 + sin(a) * dw))
			door.append(Vector2(c.x + dw, ground))
			ci.draw_colored_polygon(door, ink)
			ci.draw_rect(Rect2(c.x - s * 0.05, top + s * 0.2, s * 0.1, s * 0.22), ink)
		"burrow":
			# Butte d'herbe, porte ronde au bouton doré, petite fenêtre ronde, cheminée.
			var hill := PackedVector2Array()
			for k in 25:
				var t := float(k) / 24.0
				var x := lerpf(-1.05, 1.05, t)
				var y := (1.0 - x * x) * 0.95
				hill.append(Vector2(c.x + x * s, ground - maxf(y, 0.0) * s * 1.05))
			ci.draw_rect(Rect2(c.x + s * 0.32, c.y - s * 0.55, s * 0.16, s * 0.36), Color(0.62, 0.58, 0.52))
			ci.draw_rect(Rect2(c.x + s * 0.32, c.y - s * 0.55, s * 0.16, s * 0.36), ink, false, 1.2)
			ci.draw_colored_polygon(hill, accent.lightened(0.15))
			ci.draw_polyline(hill, ink, 1.5, true)
			var dc := Vector2(c.x - s * 0.08, ground - s * 0.36)
			ci.draw_circle(dc, s * 0.4, Color(0.95, 0.9, 0.78))
			ci.draw_circle(dc, s * 0.32, Color(0.24, 0.5, 0.26).darkened(0.1))
			ci.draw_arc(dc, s * 0.4, 0.0, TAU, 32, ink, 1.5, true)
			ci.draw_circle(dc, s * 0.06, Color(0.9, 0.72, 0.3))
			ci.draw_rect(Rect2(dc.x - s * 0.42, ground - 1.0, s * 0.84, 3.0), accent.lightened(0.15))
			var wc := Vector2(c.x + s * 0.6, ground - s * 0.48)
			ci.draw_circle(wc, s * 0.16, Color(0.75, 0.85, 0.92))
			ci.draw_arc(wc, s * 0.16, 0.0, TAU, 20, ink, 1.3, true)
		_:
			ci.draw_circle(c, s * 0.6, accent)


static func _roof(ci: CanvasItem, base: Vector2, w: float, h: float, accent: Color, ink: Color) -> void:
	var pts := PackedVector2Array([
		Vector2(base.x - w * 0.82, base.y - h * 0.1), Vector2(base.x - w * 0.66, base.y),
		Vector2(base.x + w * 0.66, base.y), Vector2(base.x + w * 0.82, base.y - h * 0.1),
		Vector2(base.x + w * 0.28, base.y - h), Vector2(base.x - w * 0.28, base.y - h)])
	ci.draw_colored_polygon(pts, accent)
	pts.append(pts[0])
	ci.draw_polyline(pts, ink, 1.5, true)
