extends Camera

const ACCEL = 10.0
export (float) var look_sens  = 0.1
export (float) var speed = 60.0

var lin_vel = Vector3()
var look_buffer = Vector2()

func _physics_process(delta):
	var move_buffer = Input.get_axis("down", "up") * Vector3.FORWARD + Input.get_axis("left", "right") * Vector3.RIGHT
	move_buffer = move_buffer.normalized().rotated(Vector3.UP, rotation.y)
	var lin_vel_xz = lerp(lin_vel, move_buffer * speed, delta * ACCEL)
	lin_vel = Vector3(lin_vel_xz.x, lin_vel.y, lin_vel_xz.z)
	
	lin_vel.y = 0.0
	if Input.is_action_pressed("sprint"): lin_vel.y -= speed
	if Input.is_action_pressed("jump"): lin_vel.y += speed
	
	translation += lin_vel * delta
	
	if not look_buffer == Vector2.ZERO:
		rotation.y -= look_buffer.x * delta * look_sens
		rotation.x -= look_buffer.y * delta * look_sens
		rotation.x = clamp(rotation.x, - PI/2, PI/2)
		look_buffer = Vector2.ZERO

func _input(event):
	if event is InputEventMouseMotion:
		look_buffer += event.relative
