extends Node

export (int) var render_distance = 16
export (int) var chunk_size = 64
export (int) var chunk_density = 16

export (Material) var chunk_material
export (Material) var water_material
export (float) var water_level = 0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	var target = $Camera
	var render_opts = {
		"render_distance": render_distance,
		"chunk_size": chunk_size,
		"chunk_density": chunk_density
	}
	var terrain_opts = {
		"chunk_material": chunk_material,
		"water_material": water_material,
		"water_level": water_level,
		"noise_octaves": 9,
		"noise_period": 120,
		"noise_scale": 50
	}
	var terrain_generator = TerrainGenerator.new(target, render_opts, terrain_opts)
	add_child(terrain_generator)

func _process(_delta):
	if Input.is_action_just_pressed("toggle_fullscreen"):
		OS.window_fullscreen = not OS.window_fullscreen
	if Input.is_action_just_pressed("pause"): get_tree().quit()
