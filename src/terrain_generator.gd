class_name TerrainGenerator
extends Node


func _init(target: Spatial, render_opts: Dictionary, generation_opts: Dictionary):
	_target = target
	_loaded_chunks = {}
	
	## Unpack render options
	_render_distance = render_opts["render_distance"]
	_chunk_size = render_opts["chunk_size"]
	_chunk_density = render_opts["chunk_density"]
	
	## Unpack terrain generation options
	_needs_collider = generation_opts["needs_collider"]
	_chunk_material = generation_opts["chunk_material"]
	_water_material = generation_opts["water_material"]
	_water_level = generation_opts["water_level"]

	## Unpack terrain generation noise options
	_noise_generator = OpenSimplexNoise.new()
	_noise_generator.octaves = generation_opts["noise_octaves"]
	_noise_generator.period = generation_opts["noise_period"]
	_noise_scale = generation_opts["noise_scale"]


func _process(_delta):
	generate()


### Terrain generation ###


func generate() -> void:
	if not _target == null:
		var position = _target.translation
		if position.x < 0: position.x -= _chunk_size
		if position.z < 0: position.z -= _chunk_size
		var chunk_x: int = int(position.x) / int(_chunk_size)
		var chunk_z: int = int(position.z) / int(_chunk_size)
		
		for ix in range(chunk_x - _render_distance, chunk_x + _render_distance + 1):
			for iz in range(chunk_z - _render_distance, chunk_z + _render_distance + 1):
				var chunk_position = Vector2(ix, iz)
				if chunk_position.distance_to(Vector2(chunk_x, chunk_z)) > _render_distance: 
					continue
				if _loaded_chunks.has(make_chunk_key(chunk_position)): 
					continue
				add_chunk(Vector2(ix, iz))
		
		for key in _loaded_chunks:
			var chunk_pos = parse_chunk_key(key)
			if chunk_pos.distance_to(Vector2(chunk_x, chunk_z)) > _render_distance:
				remove_chunk(key)


func add_chunk(chunk_position: Vector2) -> void:
	var position = Vector3(chunk_position.x * _chunk_size, 0, chunk_position.y * _chunk_size)
	
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	
	var needs_water_mesh = false
	var verts = PoolVector3Array()
	var norms = PoolVector3Array()
	var uvs   = PoolVector2Array()
	var inds  = PoolIntArray()
	
	var vert_step = float(_chunk_size) / _chunk_density
	var uv_step   = 1.0 / _chunk_density 
	
	for x in _chunk_density + 1:
		for z in _chunk_density + 1:
			var vert = Vector3(position.x + x * vert_step, 0.0, position.z + z * vert_step)
			var uv = Vector2(1.0 - x * uv_step, 1.0 - z * uv_step)
			
			vert.y = sample_noise(vert.x, vert.z)
			if vert.y < _water_level: needs_water_mesh = true
			
			var top = vert - Vector3(vert.x, sample_noise(vert.x, vert.z + vert_step), vert.z + vert_step)
			var right = vert - Vector3(vert.x + vert_step, sample_noise(vert.x + vert_step, vert.z), vert.z)
			var norm = top.cross(right).normalized()
			
			verts.push_back(vert)
			norms.push_back(norm)
			uvs.push_back(uv)
			
			# Make & index a clockwise face from verts a, b, c, d
			if x < _chunk_density and z < _chunk_density:
				var a = z + x * (_chunk_density + 1)
				var b = a + 1
				var d = (_chunk_density + 1) * (x + 1) + z
				var c = d + 1
				
				inds.push_back(d) 
				inds.push_back(b)
				inds.push_back(a)
				
				inds.push_back(d) 
				inds.push_back(c)
				inds.push_back(b)
	
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX]  = inds
	
	var chunk_mesh = MeshInstance.new()
	chunk_mesh.mesh = Mesh.new()
	chunk_mesh.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	chunk_mesh.mesh.surface_set_material(0, _chunk_material)
	
	if needs_water_mesh:
		var water_mesh = MeshInstance.new()		
		water_mesh.mesh = PlaneMesh.new()
		water_mesh.mesh.surface_set_material(0, _water_material)
		water_mesh.mesh.size = Vector2(_chunk_size, _chunk_size)
		
		water_mesh.translation = Vector3(
				position.x + _chunk_size / 2.0, 
				_water_level, position.z + 
				_chunk_size / 2.0
		)
		
		chunk_mesh.add_child(water_mesh)
	
	if _needs_collider:
		chunk_mesh.create_trimesh_collision()
	
	_loaded_chunks[make_chunk_key(chunk_position)] = chunk_mesh
	call_deferred("add_child", chunk_mesh)


func remove_chunk(key: String) -> void:
	var chunk = _loaded_chunks[key]
	var erased = _loaded_chunks.erase(key)
	if erased: chunk.queue_free()


func make_chunk_key(chunk_position: Vector2) -> String:
	return str(chunk_position.x, ",", chunk_position.y)


func parse_chunk_key(key: String) -> Vector2:
	var arr_vec = key.split(",")
	return Vector2(arr_vec[0], arr_vec[1])


func sample_noise(x: int, z: int) -> float:
	return _noise_generator.get_noise_2d(x, z) * _noise_scale


### Private fields ###


var _target: Spatial
var _loaded_chunks: Dictionary

## Rendering
var _render_distance: int
var _chunk_size: int
var _chunk_density: int

## Terrain generation
var _needs_collider: bool
var _chunk_material: Material
var _water_material: Material
var _water_level: float
var _noise_generator: OpenSimplexNoise
var _noise_scale: float
