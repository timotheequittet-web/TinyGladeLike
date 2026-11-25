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
##
## Promenade (P) : on descend à hauteur d'homme et on marche au clavier, le regard
## à la souris (clic droit maintenu). Les troncs, murs et maisons arrêtent le pas ;
## on monte d'une marche sur les terrasses. P ou Échap pour remonter.

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

## Promenade à hauteur d'homme.
signal walking_changed(on: bool)
@export var eye_height := 1.65
@export var walk_speed := 3.2
@export var run_speed := 7.0
@export var walk_fov := 68.0
var walking := false
var _walk_pos := Vector3.ZERO
var _walk_vel := Vector3.ZERO
var _walk_pitch := 0.0
var _goal_walk_pitch := 0.0
var _bob := 0.0
var _orbit_fov := 75.0
var _eye_y := 0.0


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
	if event is InputEventKey and event.pressed and not event.echo:
		var kk := event as InputEventKey
		if kk.physical_keycode == KEY_P and not kk.ctrl_pressed:
			set_walking(not walking)
			get_viewport().set_input_as_handled()
			return
		if walking and kk.keycode == KEY_ESCAPE:
			set_walking(false)
			get_viewport().set_input_as_handled()
			return
	if walking:
		_walk_input(event)
		return
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
	if walking:
		_walk(delta)
		return
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


# --- Promenade -------------------------------------------------------------------

## Descend marcher là où l'on regarde (ou remonte en vue d'ensemble).
func set_walking(on: bool) -> void:
	if on == walking:
		return
	walking = on
	if on:
		_orbit_fov = fov
		_walk_pos = Vector3(target.x, ground_height, target.z)
		_walk_pos = _free_spot(_walk_pos)
		_eye_y = _floor_at(_walk_pos)
		_walk_vel = Vector3.ZERO
		_walk_pitch = -0.05
		_goal_walk_pitch = -0.05
		_orbiting = false
		var tw := create_tween()
		tw.tween_property(self, "fov", walk_fov, 0.6).set_trans(Tween.TRANS_SINE)
	else:
		# On reprend la vue d'en haut, centrée sur l'endroit où l'on s'est arrêté.
		_goal_target = Vector3(_walk_pos.x, ground_height, _walk_pos.z)
		target = _goal_target
		distance = min_distance
		_goal_distance = maxf(min_distance, 16.0)
		_goal_pitch_offset = 0.0
		_pitch_offset = 0.0
		var tw := create_tween()
		tw.tween_property(self, "fov", _orbit_fov, 0.6).set_trans(Tween.TRANS_SINE)
	walking_changed.emit(on)


func _walk_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Molette arrière : on remonte en vue d'ensemble.
			set_walking(false)
	elif event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_goal_yaw -= mm.relative.x * rotate_speed * 0.8
		_goal_walk_pitch = clampf(_goal_walk_pitch - mm.relative.y * rotate_speed * 0.6, -1.2, 1.1)


func _walk(delta: float) -> void:
	var move := Vector2.ZERO
	if not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_META):
		if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y += 1
		if Input.is_physical_key_pressed(KEY_A): move.x -= 1
		if Input.is_physical_key_pressed(KEY_D): move.x += 1
		if Input.is_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_Q): _goal_yaw += 1.6 * delta
		if Input.is_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_E): _goal_yaw -= 1.6 * delta
	var speed := run_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var want := Vector3.ZERO
	if move != Vector2.ZERO:
		move = move.normalized()
		want = (right * move.x - fwd * move.y) * speed
	# Pas amortis : on démarre et on s'arrête en douceur.
	_walk_vel = _walk_vel.lerp(want, 1.0 - exp(-8.0 * delta))
	var step := _slide(_walk_pos, _walk_vel * delta)
	_walk_pos += step
	var flat := Vector2(_walk_pos.x, _walk_pos.z)
	if flat.length() > bounds_radius + 30.0:
		flat = flat.normalized() * (bounds_radius + 30.0)
		_walk_pos = Vector3(flat.x, _walk_pos.y, flat.y)
	var floor_y := _floor_at(_walk_pos)
	_eye_y = lerpf(_eye_y, floor_y, 1.0 - exp(-10.0 * delta))
	# Léger balancement de la marche, proportionnel à la vitesse.
	var v := _walk_vel.length()
	_bob += delta * v * 2.1
	var bob := sin(_bob) * 0.035 * clampf(v / walk_speed, 0.0, 1.5)

	var k := 1.0 - exp(-smoothing * 1.6 * delta)
	_yaw = lerpf(_yaw, _goal_yaw, k)
	_walk_pitch = lerpf(_walk_pitch, _goal_walk_pitch, k)
	var eye := Vector3(_walk_pos.x, _eye_y + eye_height + bob, _walk_pos.z)
	global_transform = Transform3D(Basis.from_euler(Vector3(_walk_pitch, _yaw, 0.0)), eye)
	# La vue d'ensemble suit le promeneur, pour remonter au bon endroit.
	target = Vector3(_walk_pos.x, ground_height, _walk_pos.z)
	_goal_target = target


## Déplacement qui glisse le long des obstacles (troncs, murs, maisons).
func _slide(from: Vector3, step: Vector3) -> Vector3:
	if step.length_squared() < 1e-8 or not is_inside_tree():
		return step
	var space := get_world_3d().direct_space_state
	var out := step
	for i in 2:
		var len := out.length()
		if len < 1e-5:
			break
		var dir := out / len
		var hit := Vector3.ZERO
		var normal := Vector3.ZERO
		var found := false
		# Deux hauteurs : genoux et poitrine, pour ne buter ni sur une marche ni sous un toit.
		for h: float in [0.7, 1.3]:
			var o := Vector3(from.x, _eye_y + h, from.z)
			var q := PhysicsRayQueryParameters3D.create(o, o + dir * (len + 0.35))
			var r := space.intersect_ray(q)
			if not r.is_empty():
				var n: Vector3 = r["normal"]
				n.y = 0.0
				if n.length_squared() > 0.01:
					found = true
					normal = n.normalized()
					hit = r["position"]
					break
		if not found:
			return out
		# On garde la part du pas qui longe l'obstacle.
		out = out - normal * out.dot(normal)
	return out


## Hauteur du sol sous le promeneur : on monte une marche (40 cm) mais pas un toit.
func _floor_at(p: Vector3) -> float:
	if not is_inside_tree():
		return ground_height
	var space := get_world_3d().direct_space_state
	var top := _eye_y + 0.45
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, top, p.z), Vector3(p.x, ground_height - 1.0, p.z))
	var r := space.intersect_ray(q)
	if r.is_empty():
		return ground_height
	var y: float = (r["position"] as Vector3).y
	if (r["normal"] as Vector3).y < 0.6:
		return _eye_y
	return maxf(y, ground_height)


## Si l'on descend dans un mur ou un tronc, on se décale vers la place libre la plus proche.
func _free_spot(p: Vector3) -> Vector3:
	if not is_inside_tree():
		return p
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	for ring in 12:
		var r := ring * 0.8
		var n := 1 if ring == 0 else 8 + ring * 2
		for i in n:
			var a := TAU * i / n
			var c := p + Vector3(cos(a) * r, 1.0, sin(a) * r)
			q.transform = Transform3D(Basis.IDENTITY, c)
			if space.intersect_shape(q, 1).is_empty():
				return Vector3(c.x, p.y, c.z)
	return p
