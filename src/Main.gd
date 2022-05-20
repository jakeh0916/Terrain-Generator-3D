extends Node

# World
export (int, 1, 256) var chunk_size: int    # Width of a chunk in units
export (int, 1, 32) var chunk_density: int # Faces per chunk
var _water_level: float
var _noise_params: Array     # Values passed to OpenSimplexNoise for noise generation
var _noise_generators: Array # OpenSimplexNoise objects for layering noise
var _presets: Dictionary     # Preset generation values stored in res://presets.json
var _last_preset: String

# Rendering
var _loaded_chunks: Dictionary = Dictionary()
var _cached_chunks: Dictionary = Dictionary()
export (int, 0, 48) var render_distance = 8 # Render radius in chunks
const _CHUNK_CACHING_SCALE = 2.0 # Multiplied by render distance for caching distance
var _do_chunk_caching = false

# Material
export (Shader) var chunk_shader
export (Shader) var water_shader
export (Texture) var simple_noise
var _chunk_material: ShaderMaterial
var _water_material: ShaderMaterial

# Player
onready var _player = $Player

# Chunk class
class Chunk extends Spatial:
	
	var chunk_pos: Vector2
	
	func _init(_chunk_pos: Vector2, land_mi: MeshInstance, water_mi: MeshInstance, sb: StaticBody):
		chunk_pos = _chunk_pos
		if not land_mi == null: add_child(land_mi)
		if not water_mi == null: add_child(water_mi)
		if not sb == null: add_child(sb)

# Menu
var _menu_open

##################
### PROCESSING ###
##################

func _ready():
	_init_menu_and_load_presets()
	try_load_preset("default")

func _process(_delta):
	if not _player == null:
		update_chunks(_player.translation)
	if Input.is_action_just_pressed("toggle_fullscreen"):
		OS.window_fullscreen = not OS.window_fullscreen
	if Input.is_action_just_pressed("pause"): 
		_toggle_menu()

func _notification(n):
	if n == NOTIFICATION_PREDELETE: 
		free_all_cached_chunks()

#############
### MENUS ###
#############

func is_menu_open():
	return _menu_open

func _init_menu_and_load_presets():
	_menu_open = false
	$MainMenu.visible = false
	$MainMenu/VBoxContainer/RDSlider.value = render_distance
	$MainMenu/VBoxContainer/CSSlider.value = chunk_size
	$MainMenu/VBoxContainer/CDSlider.value = chunk_density
	$MainMenu/VBoxContainer/ChunkCaching.pressed = _do_chunk_caching
	$MainMenu/VBoxContainer/RDSlider.hint_tooltip = str("Current Value: ", render_distance)
	$MainMenu/VBoxContainer/CSSlider.hint_tooltip = str("Current Value: ", chunk_size)
	$MainMenu/VBoxContainer/CDSlider.hint_tooltip = str("Current Value: ", chunk_density)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	var presets_file = File.new()
	if not presets_file.file_exists("res://presets.json"):
		print("FATAL: Cannot find presets file in res://presets.json!")
		get_tree().quit()
	presets_file.open("res://presets.json", File.READ)
	var data_json = JSON.parse(presets_file.get_as_text())
	_presets = data_json.result
	presets_file.close()
	
	# Add buttons for presets
	var button_container = $MainMenu/VBoxContainer
	var button_start = $MainMenu/VBoxContainer/HSeparator
	for key in _presets:
		var preset_button = Button.new()
		preset_button.text = key
		preset_button.connect("pressed", self, "try_load_preset", [key])
		button_container.add_child_below_node(button_start, preset_button)

func _toggle_menu():
	if _menu_open:
		_menu_open = false
		$MainMenu.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		_menu_open = true
		$MainMenu.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

##################
### WORLD INIT ###
##################

func try_load_preset(preset_name: String):
	_last_preset = preset_name
	var ok = _init_world_generator(preset_name)
	if not ok:
		print("FATAL: Cannot find preset or preset is invalid!")
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
		_chunk_material.set_shader_param(color_param, array_to_color(preset["chunk_layer_colors"][i]))
	_chunk_material.set_shader_param("num_midlines", num_midlines)
	_chunk_material.set_shader_param("noise_offset", simple_noise)
	_chunk_material.set_shader_param("noise_scale", preset["chunk_layer_noise"])
	
	# Set up water material
	_water_material = ShaderMaterial.new()
	_water_material.shader = water_shader
	_water_material.set_shader_param("main_color", array_to_color(preset["water_color_fill"]))
	_water_material.set_shader_param("intersection_color", array_to_color(preset["water_color_foam"]))
	_water_material.set_shader_param("foam_movement", preset["water_foam_movement"])
	_water_material.set_shader_param("displ_tex", simple_noise)
	
	# Initialize noise generators
	setup_noise_generators()
	
	# Initialize player
	_player.translation = Vector3(0, 50, 0)
	
	# Initialize the world
	update_chunks(_player.translation, true)
	return true

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
		if _do_chunk_caching: rdist *= _CHUNK_CACHING_SCALE
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
		if dist > render_distance * _CHUNK_CACHING_SCALE:
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
	static_body.translation = Vector3(pos.x + chunk_size / 2.0, pos.y, pos.z + chunk_size / 2.0)
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
	_noise_generators = Array()
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
		y += ng.get_noise_2d(x, z) * _noise_params[i][0]
		i += 1
	return y

###############
### GENERAL ###
###############

func array_to_color(arr: Array) -> Color:
	if arr.size() < 3: return Color.black
	return Color(arr[0], arr[1], arr[2])

func _on_Reload_pressed():
	try_load_preset(_last_preset)
func _on_Leave_pressed():
	get_tree().quit()
func _on_RDSlider_value_changed(value):
	$MainMenu/VBoxContainer/RDSlider.hint_tooltip = str("Current Value: ", value)
	render_distance = int(value)
func _on_CSSlider_value_changed(value):
	$MainMenu/VBoxContainer/CSSlider.hint_tooltip = str("Current Value: ", value)
	chunk_size = int(value)
func _on_CDSlider_value_changed(value):
	$MainMenu/VBoxContainer/CDSlider.hint_tooltip = str("Current Value: ", value)
	chunk_density = int(value)
func _on_CheckBox_toggled(button_pressed):
	_do_chunk_caching = button_pressed
