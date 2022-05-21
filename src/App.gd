extends Node

export (int) var render_distance = 16
export (int) var chunk_size = 64
export (int) var chunk_density = 16

export (Material) var chunk_material = null
export (Material) var water_material = null
export (float) var water_level = 0
export (int) var noise_octaves = 9
export (int) var noise_period = 120
export (int) var noise_scale = 50

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
		"noise_octaves": noise_octaves,
		"noise_period": noise_period,
		"noise_scale": noise_scale
	}
	
	var terrain_generator = TerrainGenerator.new(target, render_opts, terrain_opts)
	add_child(terrain_generator)

func _process(_delta):
	if Input.is_action_just_pressed("toggle_fullscreen"):
		OS.window_fullscreen = not OS.window_fullscreen
	if Input.is_action_just_pressed("pause"): get_tree().quit()
