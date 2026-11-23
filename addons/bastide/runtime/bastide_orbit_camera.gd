class_name BastideOrbitCamera
extends Camera3D
## Caméra douce de construction : elle tourne autour d'un point au sol et tous ses
## mouvements sont amortis (rien ne saute, rien ne secoue).
##
## Plus on s'approche, plus elle se baisse pour regarder les maisons à hauteur
## d'homme ; plus on s'éloigne, plus elle se relève pour voir le plan d'ensemble.
##
## Commandes : clic droit ou molette maintenus + souris : tourner autour ;
## molette : zoomer vers le point visé ; ZQSD / WASD (touches physiques) ou
## flèches : glisser ; A/E (Q/E en QWERTY) : tourner ; F : recentrer.

@export var target := Vector3.ZERO
@export_range(3.0, 200.0) var distance := 34.0
@export_range(2.0, 50.0) var min_distance := 6.0
@export_range(10.0, 300.0) var max_distance := 90.0
## Angle en degrés : vue rasante quand on est près, vue plongeante quand on est loin.
@export var pitch_near := -12.0
@export var pitch_far := -48.0
@export var yaw_degrees := 0.0
## Rayon autour de l'origine dans lequel le point visé reste.
@export var bounds_radius := 80.0
## Réactivité de l'amortissement (plus grand = plus vif).
@export var smoothing := 7.0
@export var rotate_speed := 0.0045
@export var pan_speed := 0.9
## Hauteur du sol pour viser la souris (zoom vers le curseur).
@export var ground_height := 0.0

var _goal_target := Vector3.ZERO
var _goal_distance := 34.0
var _goal_yaw := 0.0
var _goal_pitch_offset := 0.0
var _yaw := 0.0
var _pitch_offset := 0.0
var _orbiting := false


func _ready() -> void:
	_goal_target = target
	_goal_distance = distance
	_goal_yaw = deg_to_rad(yaw_degrees)
	_yaw = _goal_yaw
	_update_transform()


## Recentre doucement la caméra (sans couper).
func focus(point: Vector3, dist := -1.0) -> void:
	_goal_target = Vector3(point.x, ground_height, point.z)
	if dist > 0.0:
		_goal_distance = clampf(dist, min_distance, max_distance)


## Glisse doucement vers un point de vue (angle en degrés). `glide` : réactivité
## temporaire, plus petite = vol plus lent (une arrivée en douceur au lancement).
func glide_to(point: Vector3, dist: float, yaw_deg: float, glide := -1.0) -> void:
	focus(point, dist)
	_goal_yaw = deg_to_rad(yaw_deg)
	if glide > 0.0:
		var normal := smoothing
		smoothing = glide
		var tw := create_tween()
		tw.tween_interval(1.0)
		tw.tween_property(self, "smoothing", normal, 3.0).set_trans(Tween.TRANS_SINE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = mb.pressed
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_zoom(0.86 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.86, mb.position)
	elif event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_goal_yaw -= mm.relative.x * rotate_speed
		_goal_pitch_offset = clampf(_goal_pitch_offset - mm.relative.y * rotate_speed * 0.5, -0.45, 0.45)
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / (event as InputEventMagnifyGesture).factor, get_viewport().get_mouse_position())
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		_pan(Vector2(pg.delta.x, pg.delta.y) * 0.02 * _goal_distance)
	elif event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_F:
			focus(Vector3.ZERO, 34.0)


## Zoom vers le point du sol sous la souris : ce qu'on regarde reste sous le curseur.
func _zoom(factor: float, screen_pos: Vector2) -> void:
	var new_dist := clampf(_goal_distance * factor, min_distance, max_distance)
	var real := new_dist / _goal_distance
	var hit: Variant = ground_point(screen_pos)
	if hit != null and real < 1.0:
		var p: Vector3 = hit
		_goal_target = _goal_target.lerp(Vector3(p.x, ground_height, p.z), (1.0 - real) * 0.6)
	_goal_distance = new_dist


func _pan(screen_delta: Vector2) -> void:
	var right := Vector3(cos(_goal_yaw), 0, -sin(_goal_yaw))
	var fwd := Vector3(-sin(_goal_yaw), 0, -cos(_goal_yaw))
	_goal_target += right * screen_delta.x - fwd * screen_delta.y


func _process(delta: float) -> void:
	# Clavier : touches physiques (ZQSD en AZERTY = WASD en QWERTY).
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1
	if not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_META):
		if move != Vector2.ZERO:
			_pan(move.normalized() * pan_speed * _goal_distance * delta)
		if Input.is_physical_key_pressed(KEY_Q): _goal_yaw += 1.4 * delta
		if Input.is_physical_key_pressed(KEY_E): _goal_yaw -= 1.4 * delta
	var flat := Vector2(_goal_target.x, _goal_target.z)
	if flat.length() > bounds_radius:
		flat = flat.normalized() * bounds_radius
		_goal_target = Vector3(flat.x, _goal_target.y, flat.y)

	var k := 1.0 - exp(-smoothing * delta)
	target = target.lerp(_goal_target, k)
	distance = lerpf(distance, _goal_distance, k)
	_yaw = lerpf(_yaw, _goal_yaw, k)
	_pitch_offset = lerpf(_pitch_offset, _goal_pitch_offset, k)
	_update_transform()


func _update_transform() -> void:
	var t := inverse_lerp(min_distance, max_distance, distance)
	t = clampf(t, 0.0, 1.0)
	t = t * (2.0 - t)  # monte vite au début, puis se stabilise
	var pitch := deg_to_rad(lerpf(pitch_near, pitch_far, t)) + _pitch_offset
	pitch = clampf(pitch, deg_to_rad(-80.0), deg_to_rad(-6.0))
	var basis_ := Basis.from_euler(Vector3(pitch, _yaw, 0.0))
	# On vise un peu au-dessus du sol quand on est près, pour voir les toits.
	var aim := target + Vector3(0, lerpf(1.6, 0.0, t), 0)
	global_transform = Transform3D(basis_, aim + basis_.z * distance)


## Point du sol (plan horizontal à ground_height) sous une position d'écran, ou null.
func ground_point(screen_pos: Vector2) -> Variant:
	var origin := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)
	return Plane(Vector3.UP, ground_height).intersects_ray(origin, dir)
