extends Camera3D
## Caméra libre pour les démos.
## Clic droit maintenu + souris : regarder. ZQSD / WASD : avancer (touches physiques,
## donc ça marche en AZERTY comme en QWERTY). A/E : descendre/monter. Maj : plus vite.
## Clic gauche : lance une boule pour tester les collisions.

@export var speed := 8.0
@export var mouse_sensitivity := 0.0025
@export var ball_speed := 22.0

var _yaw := 0.0
var _pitch := 0.0
var _looking := false


func _ready() -> void:
	var e := global_transform.basis.get_euler()
	_pitch = e.x
	_yaw = e.y


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_throw_ball()
	elif event is InputEventMouseMotion and _looking:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - mm.relative.y * mouse_sensitivity, -1.5, 1.5)
		rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	# Touches physiques (position QWERTY) : W = Z en AZERTY, A = Q, etc.
	if Input.is_physical_key_pressed(KEY_W): dir -= basis.z
	if Input.is_physical_key_pressed(KEY_S): dir += basis.z
	if Input.is_physical_key_pressed(KEY_A): dir -= basis.x
	if Input.is_physical_key_pressed(KEY_D): dir += basis.x
	if Input.is_physical_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): dir -= Vector3.UP
	if dir != Vector3.ZERO:
		var s := speed * (3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		global_position += dir.normalized() * s * delta


func _throw_ball() -> void:
	var body := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.3, 0.25)
	sm.material = mat
	mesh.mesh = sm
	body.add_child(mesh)
	get_tree().current_scene.add_child(body)
	body.global_position = global_position - global_transform.basis.z * 1.0
	body.linear_velocity = -global_transform.basis.z * ball_speed
	get_tree().create_timer(12.0).timeout.connect(body.queue_free)
