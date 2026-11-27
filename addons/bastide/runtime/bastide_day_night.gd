class_name BastideDayNight
extends Node
## Cycle jour/nuit : le soleil traverse le ciel, la lumière, le ciel, la brume et
## l'exposition suivent l'heure ; la nuit, la lune prend le relais (lumière bleutée
## et douce) et les lanternes, les shoji et les vitres s'allument (BastideGlow).
##
## Un seul DirectionalLight3D sert au soleil et à la lune (une seule ombre portée :
## rien de plus à calculer la nuit). Les couleurs viennent d'une suite de moments
## de la journée, interpolés en douceur.
##
## En jeu : N passe au moment suivant (aube, midi, soir, nuit) en faisant défiler
## les heures ; Maj + N arrête ou relance l'écoulement du temps.

## Annonce à afficher (« Nuit · 21 h 30 ») quand on change de moment ou de rythme.
signal announced(text: String)

@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
## Heure de départ (0-24). 17,2 : la lumière dorée de fin d'après-midi.
@export_range(0.0, 24.0, 0.05) var hour := 17.2
## Durée d'une journée complète, en minutes réelles.
@export var day_minutes := 16.0
## Le temps s'écoule tout seul.
@export var running := true
## Heure du lever et du coucher du soleil.
@export var sunrise := 5.5
@export var sunset := 18.5
## Hauteur du soleil à midi (degrés).
@export var max_elevation := 58.0
## Hauteur de la lune (degrés).
@export var moon_elevation := 42.0
@export var keyboard := true

## Moments où l'on saute avec N.
const STOPS := [[6.3, "Aube"], [12.0, "Midi"], [17.2, "Soir"], [21.5, "Nuit"]]

## Moments de référence : heure, puis réglages. lum = énergie de la lumière
## directionnelle (soleil ou lune), night = obscurité, lamps = lanternes allumées.
const KEYS := [
	{"h": 0.0, "light": Color(0.58, 0.68, 1.0), "lum": 0.32, "top": Color(0.015, 0.03, 0.075), "horizon": Color(0.06, 0.09, 0.17),
		"ground": Color(0.05, 0.07, 0.11), "bottom": Color(0.015, 0.02, 0.03), "amb": 0.55, "fog": Color(0.16, 0.2, 0.34),
		"fog_d": 0.0034, "vol": Color(0.45, 0.55, 0.85), "exp": 1.35, "glow": 1.15, "night": 1.0, "lamps": 1.0},
	{"h": 4.6, "light": Color(0.58, 0.68, 1.0), "lum": 0.28, "top": Color(0.02, 0.035, 0.09), "horizon": Color(0.08, 0.1, 0.2),
		"ground": Color(0.06, 0.08, 0.12), "bottom": Color(0.02, 0.02, 0.03), "amb": 0.55, "fog": Color(0.18, 0.22, 0.36),
		"fog_d": 0.0042, "vol": Color(0.5, 0.58, 0.85), "exp": 1.35, "glow": 1.1, "night": 1.0, "lamps": 1.0},
	{"h": 5.45, "light": Color(1.0, 0.55, 0.45), "lum": 0.05, "top": Color(0.12, 0.15, 0.3), "horizon": Color(0.62, 0.42, 0.42),
		"ground": Color(0.3, 0.25, 0.26), "bottom": Color(0.06, 0.06, 0.07), "amb": 0.5, "fog": Color(0.6, 0.48, 0.5),
		"fog_d": 0.0055, "vol": Color(0.85, 0.72, 0.72), "exp": 1.25, "glow": 1.0, "night": 0.6, "lamps": 0.85},
	{"h": 6.5, "light": Color(1.0, 0.66, 0.46), "lum": 1.0, "top": Color(0.34, 0.45, 0.66), "horizon": Color(1.0, 0.72, 0.56),
		"ground": Color(0.78, 0.62, 0.5), "bottom": Color(0.24, 0.24, 0.2), "amb": 0.65, "fog": Color(1.0, 0.78, 0.66),
		"fog_d": 0.0048, "vol": Color(1.0, 0.86, 0.78), "exp": 1.12, "glow": 0.85, "night": 0.1, "lamps": 0.25},
	{"h": 8.5, "light": Color(1.0, 0.9, 0.78), "lum": 1.75, "top": Color(0.4, 0.6, 0.86), "horizon": Color(0.86, 0.86, 0.82),
		"ground": Color(0.8, 0.74, 0.6), "bottom": Color(0.3, 0.32, 0.24), "amb": 0.78, "fog": Color(0.92, 0.9, 0.86),
		"fog_d": 0.0026, "vol": Color(1.0, 0.95, 0.9), "exp": 1.04, "glow": 0.7, "night": 0.0, "lamps": 0.0},
	{"h": 13.0, "light": Color(1.0, 0.95, 0.88), "lum": 2.05, "top": Color(0.36, 0.56, 0.86), "horizon": Color(0.82, 0.86, 0.9),
		"ground": Color(0.8, 0.76, 0.62), "bottom": Color(0.32, 0.33, 0.24), "amb": 0.8, "fog": Color(0.88, 0.9, 0.92),
		"fog_d": 0.0022, "vol": Color(1.0, 0.97, 0.93), "exp": 1.0, "glow": 0.65, "night": 0.0, "lamps": 0.0},
	# L'ambiance d'origine de la démo : fin d'après-midi dorée.
	{"h": 17.2, "light": Color(1.0, 0.78, 0.55), "lum": 1.9, "top": Color(0.46, 0.6, 0.8), "horizon": Color(1.0, 0.8, 0.6),
		"ground": Color(0.92, 0.76, 0.56), "bottom": Color(0.32, 0.33, 0.24), "amb": 0.75, "fog": Color(1.0, 0.82, 0.62),
		"fog_d": 0.0028, "vol": Color(1.0, 0.88, 0.74), "exp": 1.08, "glow": 0.75, "night": 0.0, "lamps": 0.3},
	{"h": 18.3, "light": Color(1.0, 0.55, 0.32), "lum": 1.0, "top": Color(0.3, 0.34, 0.55), "horizon": Color(1.0, 0.56, 0.36),
		"ground": Color(0.75, 0.5, 0.38), "bottom": Color(0.2, 0.18, 0.16), "amb": 0.6, "fog": Color(0.95, 0.6, 0.45),
		"fog_d": 0.0032, "vol": Color(1.0, 0.75, 0.6), "exp": 1.14, "glow": 0.9, "night": 0.3, "lamps": 0.9},
	{"h": 18.75, "light": Color(0.9, 0.5, 0.45), "lum": 0.04, "top": Color(0.14, 0.16, 0.36), "horizon": Color(0.7, 0.38, 0.36),
		"ground": Color(0.32, 0.24, 0.26), "bottom": Color(0.08, 0.07, 0.08), "amb": 0.5, "fog": Color(0.55, 0.38, 0.42),
		"fog_d": 0.0034, "vol": Color(0.8, 0.62, 0.66), "exp": 1.25, "glow": 1.0, "night": 0.6, "lamps": 1.0},
	{"h": 20.0, "light": Color(0.58, 0.68, 1.0), "lum": 0.26, "top": Color(0.03, 0.05, 0.13), "horizon": Color(0.12, 0.13, 0.25),
		"ground": Color(0.08, 0.09, 0.14), "bottom": Color(0.02, 0.02, 0.03), "amb": 0.55, "fog": Color(0.2, 0.22, 0.38),
		"fog_d": 0.0032, "vol": Color(0.5, 0.56, 0.85), "exp": 1.35, "glow": 1.15, "night": 0.95, "lamps": 1.0},
]

var _sun_yaw := 0.0
var _target := -1.0
var _sky: ProceduralSkyMaterial
var _sun_fog_energy := 1.6
var _sky_hour := -100.0


func _ready() -> void:
	if sun:
		# L'orientation de départ du soleil (celle de la scène) correspond à 17 h 12.
		_sun_yaw = sun.rotation.y
		_sun_fog_energy = sun.light_volumetric_fog_energy
	var env := _env()
	if env and env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		# Copie : le ciel de la scène reste intact dans l'éditeur.
		_sky = (env.sky.sky_material as ProceduralSkyMaterial).duplicate()
		env.sky.sky_material = _sky
		# Le ciel (et la lumière ambiante qu'il donne) se recalcule par petits bouts.
		env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	_apply()


func _env() -> Environment:
	return world_environment.environment if world_environment else null


func _unhandled_input(event: InputEvent) -> void:
	if not keyboard:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.physical_keycode != KEY_N or k.ctrl_pressed or k.meta_pressed:
		return
	if k.shift_pressed:
		running = not running
		_target = -1.0
		announced.emit("Temps %s · %s" % ["qui passe" if running else "arrêté", clock_text()])
	else:
		skip_to_next()
	get_viewport().set_input_as_handled()


## Fait défiler les heures jusqu'au moment suivant (aube, midi, soir, nuit).
func skip_to_next() -> void:
	var from := _target if _target >= 0.0 else hour
	for s: Array in STOPS:
		if float(s[0]) > from + 0.25:
			_go(float(s[0]), s[1])
			return
	_go(float(STOPS[0][0]), STOPS[0][1])


func _go(h: float, name: String) -> void:
	_target = h
	announced.emit("%s · %s" % [name, _fmt(h)])


func _process(delta: float) -> void:
	if _target >= 0.0:
		# Défilement rapide : environ quatre heures par seconde, ralenti à l'arrivée.
		var left := fposmod(_target - hour, 24.0)
		var step := minf(left, delta * clampf(left * 2.5, 0.6, 4.0))
		hour = fposmod(hour + step, 24.0)
		if left - step < 0.005:
			hour = _target
			_target = -1.0
	elif running and day_minutes > 0.0:
		hour = fposmod(hour + delta * 24.0 / (day_minutes * 60.0), 24.0)
	_apply()


## L'heure lisible (« 17 h 12 »).
func clock_text() -> String:
	return _fmt(hour)


static func _fmt(h: float) -> String:
	var m := int(round(h * 60.0)) % (24 * 60)
	return "%d h %02d" % [m / 60, m % 60]


## Réglages interpolés à l'heure `h` (cyclique).
static func sample(h: float) -> Dictionary:
	h = fposmod(h, 24.0)
	var n := KEYS.size()
	var i := n - 1
	for k in n:
		if float(KEYS[k]["h"]) <= h:
			i = k
	var a: Dictionary = KEYS[i]
	var b: Dictionary = KEYS[(i + 1) % n]
	var ha: float = a["h"]
	var hb: float = b["h"] if i + 1 < n else float(b["h"]) + 24.0
	var t := clampf((h - ha) / maxf(hb - ha, 0.001), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var out := {}
	for key in a:
		if key == "h":
			continue
		var va: Variant = a[key]
		var vb: Variant = b[key]
		out[key] = (va as Color).lerp(vb, t) if va is Color else lerpf(va, vb, t)
	return out


## Le soleil est-il levé (sinon la lumière directionnelle est la lune) ?
func sun_up() -> bool:
	return hour > sunrise - 0.05 and hour < sunset + 0.3


func _apply() -> void:
	var s := sample(hour)
	if sun:
		if sun_up():
			var day_t := clampf((hour - sunrise) / (sunset - sunrise), 0.0, 1.0)
			# Toujours un peu au-dessus de l'horizon : la lumière rase reste dorée.
			var elev := maxf(sin(day_t * PI) * max_elevation, 2.0)
			# D'est en ouest : 180° de course, calée pour que 17 h 12 garde la scène d'origine.
			var at_start := clampf((17.2 - sunrise) / (sunset - sunrise), 0.0, 1.0)
			var yaw := _sun_yaw + (day_t - at_start) * PI
			sun.rotation = Vector3(-deg_to_rad(elev), yaw, 0.0)
		else:
			sun.rotation = Vector3(-deg_to_rad(moon_elevation), _sun_yaw + PI * 0.8, 0.0)
		sun.light_color = s["light"]
		sun.light_energy = s["lum"]
		sun.light_volumetric_fog_energy = _sun_fog_energy * (0.35 if not sun_up() else 1.0)
		sun.visible = float(s["lum"]) > 0.01
	var env := _env()
	if env:
		env.ambient_light_energy = s["amb"]
		env.fog_light_color = s["fog"]
		env.fog_density = s["fog_d"]
		env.volumetric_fog_albedo = s["vol"]
		env.tonemap_exposure = s["exp"]
		env.glow_intensity = s["glow"]
		# La nuit, le halo des lanternes s'étale un peu plus (seuil plus bas).
		env.glow_hdr_threshold = lerpf(0.95, 0.75, float(s["night"]))
	# Le ciel n'est retouché que toutes les quelques minutes de jeu : chaque
	# retouche recalcule ses reflets et sa lumière ambiante.
	if _sky and absf(hour - _sky_hour) > 0.04:
		_sky_hour = hour
		_sky.sky_top_color = s["top"]
		_sky.sky_horizon_color = s["horizon"]
		_sky.ground_horizon_color = s["ground"]
		_sky.ground_bottom_color = s["bottom"]
		# Disque du soleil le jour, petite lune pâle la nuit.
		_sky.sun_angle_max = 32.0 if sun_up() else 6.0
	BastideGlow.set_state(s["night"], s["lamps"])
