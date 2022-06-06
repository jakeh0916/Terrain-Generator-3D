extends Node

export (int) var render_distance = 16
export (int) var chunk_size = 64
export (int) var chunk_density = 16

export (bool) var needs_collider = false
export (Material) var chunk_material = null
export (Material) var water_material = null
export (float) var water_level = 0
export (int) var noise_octaves = 9
export (int) var noise_period = 1500
export (int) var noise_scale = 1500


func _ready():
	var target = $SimplePlayer
	var render_opts = {
		"render_distance": render_distance,
		"chunk_size": chunk_size,
		"chunk_density": chunk_density
	}
	var terrain_opts = {
		"needs_collider": needs_collider,
		"chunk_material": chunk_material,
		"water_material": water_material,
		"water_level": water_level,
		"noise_octaves": noise_octaves,
		"noise_period": noise_period,
		"noise_scale": noise_scale
	}
	
	var terrain_generator = TerrainGenerator.new(target, render_opts, terrain_opts)
	add_child(terrain_generator)
