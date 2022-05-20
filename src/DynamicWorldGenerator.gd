extends Node
class_name DynamicWorldGenerator

# World
export (int) var chunk_size: int         # Width of a chunk in units
export (int) var chunk_density: int      # Faces per chunk
var _water_level: float
var _noise_params: Array     # Values passed to OpenSimplexNoise for noise generation
var _noise_generators: Array # OpenSimplexNoise objects for layering noise

# Rendering
var _loaded_chunks: Dictionary = Dictionary()
var _cached_chunks: Dictionary = Dictionary()
export (int, 0, 64) var render_distance = 8 # Render radius in chunks
const _RENDER_CACHING_SCALE = 2.0 # Multiplied by render distance for caching distance

# Material
export (Shader) var chunk_shader
export (Shader) var water_shader
export (Texture) var simple_noise
var _chunk_material: ShaderMaterial
var _water_material: ShaderMaterial

# Player
var _player: Spatial = null
export (NodePath) var player_path = null

# Presets
var _presets = {
	"default": {
		"noise_params": [
			# Scale, octaves, period, persist
			[25.0, 1.0, 64.0, 0.8],
			[1.0, 1.0, 128.0, 0.9],
			[1.0, 3.0, 24.0, 0.1]
		],
		"chunk_layer_noise": 5,
		"chunk_layer_midlines": [3.5, 7],
		"chunk_layer_colors": [
			Color(1, 0.878431, 0.666667), 
			Color(0.423529, 0.631373, 0.513726), 
			Color(0.407843, 0.862745, 0.160784)
		],
		"water_level": 0.0,
		"water_foam_movement": 1.0,
		"water_color_fill": Color(0.203922, 1, 1),
		"water_color_foam": Color(1, 1, 1)
	},
}

##################
### PROCESSING ###
##################

func _ready():
	if not _init_world_generator("default"):
		print("ERROR: Preset not found or invalid!")
		get_tree().quit()

func _init_world_generator(preset_name: String) -> bool:
	var preset = _presets[preset_name]
	if preset == null: return false
	
	# Get preset parameters
	_water_level   = preset["water_level"]
	_noise_params  = preset["noise_params"]
	
	# Check chunk parameters are valid
	var num_midlines = preset["chunk_layer_midlines"].size()
	if not num_midlines == preset["chunk_layer_colors"].size() - 1: 
		return false
	if num_midlines < 1: 
		return false
	
	# Set up chunk material
	_chunk_material = ShaderMaterial.new()
	_chunk_material.shader = chunk_shader
	for i in num_midlines + 1:
		var midline_param = str("midline_", i)
		var color_param = str("color_", i)
		if i < num_midlines:
			_chunk_material.set_shader_param(midline_param, preset["chunk_layer_midlines"][i])
		_chunk_material.set_shader_param(color_param, Color(preset["chunk_layer_colors"][i]))
	_chunk_material.set_shader_param("num_midlines", num_midlines)
	_chunk_material.set_shader_param("noise_offset", simple_noise)
	_chunk_material.set_shader_param("noise_scale", preset["chunk_layer_noise"])
	
	# Set up water material
	_water_material = ShaderMaterial.new()
	_water_material.shader = water_shader
	_water_material.set_shader_param("main_color", preset["water_color_fill"])
	_water_material.set_shader_param("intersection_color", preset["water_color_foam"])
	_water_material.set_shader_param("foam_movement", preset["water_foam_movement"])
	_water_material.set_shader_param("displ_tex", simple_noise)
	
	# Initialize noise generators
	setup_noise_generators()
	
	# Initialize player
	if _player == null:
		_player = get_node(player_path)
	_player.translation = Vector3(0, 50, 0)
	
	# Initialize the world
	update_chunks(_player.translation, true)
	return true

func _process(_delta):
	update_chunks(_player.translation)

func _notification(n):
	if n == NOTIFICATION_PREDELETE: 
		free_all_cached_chunks()

#######################
### CHUNK RENDERING ###
#######################

# Based on player position, render chunks in a circle with radius
# of render_distance. If a chunk is loaded *outside* of this radius,
# drop it from the scene tree and "cache" it. If a cached chunk is outside
# of render_distance * _RENDER_DIST_CACHING_FACTOR, then free the chunk.
func update_chunks(pos: Vector3, initial_load: bool = false):
	if pos.x < 0: pos.x -= chunk_size
	if pos.z < 0: pos.z -= chunk_size
	var chunk_x: int = int(pos.x) / chunk_size
	var chunk_z: int = int(pos.z) / chunk_size
	
	# On initial load, clear all chunks loaded/cached. Additionally,
	# increase render distance in order to preload chunks to the cache
	var rdist = render_distance
	if initial_load: 
		rdist *= _RENDER_CACHING_SCALE
		free_all_chunks()
	
	# Determine & load all chunks in render distance
	for ix in range(chunk_x - rdist, chunk_x + rdist + 1):
		for iz in range(chunk_z - rdist, chunk_z + rdist + 1):
			if Vector2(chunk_x, chunk_z).distance_to(Vector2(ix, iz)) <= rdist:
				var _key = load_chunk(Vector2(ix, iz))
	
	# Iterate over loaded chunks & cache any that are too far away
	for key in _loaded_chunks:
		var dist = _loaded_chunks[key].chunk_pos.distance_to(Vector2(chunk_x, chunk_z))
		if dist > render_distance:
			var _success = cache_chunk(key)
	
	# Iterate over cached chunks & free any that are too far away
	for key in _cached_chunks:
		var dist = _cached_chunks[key].chunk_pos.distance_to(Vector2(chunk_x, chunk_z))
		if dist > render_distance * _RENDER_CACHING_SCALE:
			var _success = free_chunk(key)

func load_chunk(chunk_pos: Vector2) -> String:
	var key = get_chunk_key(chunk_pos)
	
	# If chunk is loaded -> do nothing
	if _loaded_chunks.has(key): 
		return key
	
	# If chunk is cached -> uncache & return it
	if _cached_chunks.has(key): 
		var chunk = _cached_chunks[key]
		var _found = _cached_chunks.erase(key)
		_loaded_chunks[key] = chunk
		add_child(chunk)
		return key
	
	# If chunk is not loaded or cached -> it must be created
	var pos = Vector3(chunk_pos.x * chunk_size, 0, chunk_pos.y * chunk_size)
	var mesh_data = create_heightmap_mesh(pos) 
	var land_mesh = mesh_data["mesh_instance"]
	var water_mesh = null
	if mesh_data["needs_water_mesh"]: water_mesh = create_water_mesh(pos)
	var static_body = create_heightmap_collider(pos, mesh_data["heights"])
	
	# Construct & name chunk
	var chunk = Chunk.new(chunk_pos, land_mesh, water_mesh, static_body)
	chunk.name = key
	
	# Add chunk to loaded chunks & return
	_loaded_chunks[key] = chunk
	add_child(chunk)
	return key

func cache_chunk(key: String) -> bool:
	var chunk = _loaded_chunks[key]
	var found = _loaded_chunks.erase(key)
	if not found: return false
	
	_cached_chunks[key] = chunk
	remove_child(chunk)
	return true

func free_chunk(key: String) -> bool:
	var chunk = _cached_chunks[key]
	var found = _cached_chunks.erase(key)
	if not found: return false
	
	chunk.queue_free()
	return true

func free_all_chunks():
	for key in _loaded_chunks:
		var obj = _loaded_chunks[key]
		if not obj == null: obj.queue_free()
	_loaded_chunks.clear()
	free_all_cached_chunks()

func free_all_cached_chunks():
	for key in _cached_chunks:
		var obj = _cached_chunks[key]
		if not obj == null: obj.queue_free()
	_cached_chunks.clear()

###########################################
### HELPER FUNCTIONS FOR CHUNK CREATION ###
###########################################

# Makes a heightmap mesh and returns a dictionary containing
# the mesh (as a MeshInstance) and a PoolRealArray of heights,
# which is used later to create the collider & static body
func create_heightmap_mesh(pos: Vector3) -> Dictionary:
	# Set up pools for verts and uvs
	var verts = PoolVector3Array()
	var norms = PoolVector3Array()
	var uvs = PoolVector2Array()
	var heights = PoolRealArray()
	var vert_width = float(chunk_size) / float(chunk_density)
	var uv_width = 1.0 / float(chunk_density)
	
	# Heightmaps that don't dip below the water level
	# do not need to create a water mesh
	var needs_water_mesh = false
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_chunk_material)
	
	# Compose chunk verts and index them
	for ix in chunk_density + 1:
		for iz in chunk_density + 1:
			var vert = Vector3(pos.x + ix * vert_width, pos.y, pos.z + iz * vert_width)
			var uv = Vector2(1.0 - ix * uv_width, 1.0 - iz * uv_width)
			
			# Sample noise generator for height
			vert.y = sample_noise(vert.x, vert.z)
			
			# Record height for collider generation
			heights.push_back(vert.y) 
			
			# Determine if water mesh is needed
			if (vert.y < _water_level):
				needs_water_mesh = true
			
			# Calculate normal
			var top = vert - Vector3(vert.x, sample_noise(vert.x, vert.z + vert_width), vert.z + vert_width)
			var right = vert - Vector3(vert.x + vert_width, sample_noise(vert.x + vert_width, vert.z), vert.z)
			var norm = top.cross(right).normalized()
			
			verts.push_back(vert)
			norms.push_back(norm)
			uvs.push_back(uv)
			
			# Compose this face from the relevant verts and index them
			if ix < chunk_density and iz < chunk_density:
				var a = iz + ix * (chunk_density + 1)
				var b = a + 1
				var d = (chunk_density + 1) * (ix + 1) + iz
				var c = d + 1
				
				# Index triangle #1
				st.add_index(d) 
				st.add_index(b)
				st.add_index(a)
				
				# Index triangle #2
				st.add_index(d) 
				st.add_index(c)
				st.add_index(b)
	
	# Add mesh data & commit
	for i in verts.size():
		st.add_uv(uvs[i])
		st.add_normal(norms[i])
		st.add_vertex(verts[i])
	var mesh = Mesh.new()
	st.commit(mesh)
	
	var mesh_instance = MeshInstance.new()
	mesh_instance.mesh = mesh
	
	return {
		"mesh_instance": mesh_instance,
		"heights": heights,
		"needs_water_mesh": needs_water_mesh
	}

func create_water_mesh(pos: Vector3) -> MeshInstance:
	# Set up pools for verts and uvs
	var verts = PoolVector3Array()
	var norms = PoolVector3Array()
	var uvs = PoolVector2Array()
	var vert_width = float(chunk_size) / float(chunk_density)
	var uv_width = 1.0 / float(chunk_density)

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_water_material)
	
	# Compose chunk verts and index them
	for ix in chunk_density + 1:
		for iz in chunk_density + 1:
			var vert = Vector3(pos.x + ix * vert_width, _water_level, pos.z + iz * vert_width)
			var norm = Vector3.UP
			var uv = Vector2(1.0 - ix * uv_width, 1.0 - iz * uv_width)
			
			verts.push_back(vert)
			norms.push_back(norm)
			uvs.push_back(uv)
			
			# Compose this face from the relevant verts and index them
			if ix < chunk_density and iz < chunk_density:
				var a = iz + ix * (chunk_density + 1)
				var b = a + 1
				var d = (chunk_density + 1) * (ix + 1) + iz
				var c = d + 1
				
				# Index triangle #1
				st.add_index(d) 
				st.add_index(b)
				st.add_index(a)
				
				# Index triangle #2
				st.add_index(d) 
				st.add_index(c)
				st.add_index(b)
	
	# Add mesh data & commit
	for i in verts.size():
		st.add_uv(uvs[i])
		st.add_normal(norms[i])
		st.add_vertex(verts[i])
	var mesh = Mesh.new()
	st.commit(mesh)
	
	var mesh_instance = MeshInstance.new()
	mesh_instance.mesh = mesh
	
	return mesh_instance

func create_heightmap_collider(pos: Vector3, heights: PoolRealArray) -> StaticBody:
	var height_map = HeightMapShape.new()
	height_map.map_width = chunk_density + 1
	height_map.map_depth = chunk_density + 1
	height_map.set_map_data(heights)
	
	var collision_shape = CollisionShape.new()
	collision_shape.shape = height_map
	
	var static_body = StaticBody.new()
	static_body.translation = Vector3(pos.x + chunk_size / 2, pos.y, pos.z + chunk_size /2)
	static_body.rotation_degrees = Vector3(0, 90, 0)
	var scale = float(chunk_size) / float(chunk_density)
	static_body.scale = Vector3(-scale, 1, scale)
	static_body.add_child(collision_shape)
	
	return static_body

# "Chunk keys" are used to reference chunks in the _loaded and _cached
# dictionaries. Also used as the name of the instanced chunk.
func get_chunk_key(chunk_pos: Vector2) -> String:
	return str(chunk_pos.x, ',', chunk_pos.y)

########################
### NOISE GENERATION ###
########################

func setup_noise_generators():
	for params in _noise_params:
		var ng = OpenSimplexNoise.new()
		ng.seed = randi()
		ng.octaves = params[1]
		ng.period = params[2]
		ng.persistence = params[3]
		_noise_generators.push_back(ng)

# Sample layered noise using multiple OpenSimplexNoise
# objects. Layered noise is made additively, and in general
# is pretty low quality... But it does work at least.
func sample_noise(x: float, z: float) -> float:
	var y = 0.0
	var i = 0
	for ng in _noise_generators:
		y += ng.get_noise_2d(x, z) * _noise_params[0][0]
		i += 1
	return y
