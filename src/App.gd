extends Node

export (int) var render_distance = 16
export (int) var chunk_size = 256
export (int) var chunk_density = 24

# Chunk/water materials for demos
export (Material) var misty_hills_cmat = null
export (Material) var misty_hills_wmat = null
export (Material) var mesa_cmat = null
export (Material) var mesa_wmat = null

# Demo terrain #1 - Misty hills
onready var misty_hills_demo = {
	"needs_collider": false,
	"chunk_material": misty_hills_cmat,
	"water_material": misty_hills_wmat,
	"water_level": 0,
	"noise_octaves": 9,
	"noise_period": 1500,
	"noise_scale": 1500
}

# Demo terrain #2 - Mesa
onready var mesa_demo = {
	"needs_collider": false,
	"chunk_material": mesa_cmat,
	"water_material": mesa_wmat,
	"water_level": -INF,
	"noise_octaves": 6,
	"noise_period": 3000,
	"noise_scale": 800
}


func _ready():
	var target = $SimplePlayer
	var render_opts = {
		"render_distance": render_distance,
		"chunk_size": chunk_size,
		"chunk_density": chunk_density
	}
	var generation_opts = misty_hills_demo
	
	var terrain_generator = TerrainGeneratorAsync.new(target, render_opts, generation_opts)
	add_child(terrain_generator)
