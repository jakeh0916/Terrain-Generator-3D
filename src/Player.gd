extends KinematicBody

# SIMPLE FIRST PERSON - Player & Camera Controller Class

const GRAV = 20
const MAX_Y_SPEED = 50.0
const ACCEL = 10.0

export (float) var look_sens  = 0.1
export (float) var walk_speed = 3.0
export (float) var jump_force = 10.0

var vclip = true
var lin_vel = Vector3()
var look_buffer = Vector2()

var cam_pivot

var app

func _ready():
	app = get_tree().root.get_child(0)
	app.get_node("MainMenu/VBoxContainer/SpeedSlider").value = walk_speed
	app.get_node("MainMenu/VBoxContainer/SensSlider").value = look_sens
	app.get_node("MainMenu/VBoxContainer/SpeedSlider").hint_tooltip = str("Current Value: ", walk_speed)
	app.get_node("MainMenu/VBoxContainer/SensSlider").hint_tooltip = str("Current Value: ", look_sens)
	cam_pivot = $CamOffset/Camera
	pass

func _physics_process(delta):
	if Input.is_action_just_pressed("v"): vclip = not vclip
	
	# Calculate linear velocity xz
	var move_buffer = Input.get_axis("down", "up") * Vector3.FORWARD + Input.get_axis("left", "right") * Vector3.RIGHT
	move_buffer = move_buffer.normalized().rotated(Vector3.UP, cam_pivot.rotation.y)
	var target_speed = walk_speed
	if Input.is_action_pressed("sprint") or vclip: target_speed = walk_speed * 2
	var lin_vel_xz = lerp(lin_vel, move_buffer * target_speed, delta * ACCEL)
	lin_vel = Vector3(lin_vel_xz.x, lin_vel.y, lin_vel_xz.z)
	
	# Handle y-velocity
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			lin_vel.y = jump_force
		else: lin_vel.y = -0.1
	else: lin_vel.y -= GRAV * delta
	lin_vel.y = clamp(lin_vel.y, -MAX_Y_SPEED, MAX_Y_SPEED)
	
	if vclip: 
		lin_vel.y = 0.0
		if Input.is_action_pressed("sprint"): lin_vel.y -= walk_speed * 2
		if Input.is_action_pressed("jump"): lin_vel.y += walk_speed * 2
	
	# Transform player
	move_and_slide_with_snap(lin_vel, Vector3.UP * -0.1, Vector3.UP)
	
	# Update Look
	if not look_buffer == Vector2.ZERO:
		cam_pivot.rotation.y -= look_buffer.x * delta * look_sens
		cam_pivot.rotation.x -= look_buffer.y * delta * look_sens
		cam_pivot.rotation.x = clamp(cam_pivot.rotation.x, - PI/2, PI/2)
		look_buffer = Vector2.ZERO

func _input(event):
	if event is InputEventMouseMotion:
		if not app.is_menu_open():
			look_buffer += event.relative

func _on_SpeedSlider_value_changed(value):
	app.get_node("MainMenu/VBoxContainer/SpeedSlider").hint_tooltip = str("Current Value: ", value)
	walk_speed = value
func _on_SensSlider_value_changed(value):
	app.get_node("MainMenu/VBoxContainer/SensSlider").hint_tooltip = str("Current Value: ", look_sens)
	look_sens = value
