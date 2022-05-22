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
	_make_collider = generation_opts["make_collider"] 
	_chunk_material = generation_opts["chunk_material"]
	_water_material = generation_opts["water_material"]
	_water_level = generation_opts["water_level"]

	## Unpack terrain generation noise options
	_noise_generator = OpenSimplexNoise.new()
	_noise_generator.octaves = generation_opts["noise_octaves"]
	_noise_generator.period = generation_opts["noise_period"]
	_noise_scale = generation_opts["noise_scale"]


func _physics_process(delta):
	generate()


######################
# Terrain generation #
######################


func generate() -> void:
	if not _target == null:
		var position = _target.translation
		if position.x < 0: position.x -= _chunk_size
		if position.z < 0: position.z -= _chunk_size
		var chunk_x: int = int(position.x) / _chunk_size
		var chunk_z: int = int(position.z) / _chunk_size
		
		for ix in range(chunk_x - _render_distance, chunk_x + _render_distance + 1):
			for iz in range(chunk_z - _render_distance, chunk_z + _render_distance + 1):
				if Vector2(ix, iz).distance_to(Vector2(chunk_x, chunk_z)) <= _render_distance:
					make_chunk(Vector2(ix, iz))
		
		for key in _loaded_chunks:
			if _loaded_chunks[key].chunk_position.distance_to(Vector2(chunk_x, chunk_z)) > _render_distance:
				free_chunk(key)


func make_chunk(chunk_position: Vector2) -> void:
	var key = make_chunk_key(chunk_position)
	if _loaded_chunks.has(key): return

	var position = Vector3(chunk_position.x * _chunk_size, 0, chunk_position.y * _chunk_size)
	var chunk_mesh = make_chunk_mesh(position)
	var chunk_collider = null if not _make_collider else make_chunk_collider(chunk_mesh)
	
	var chunk = Chunk.new(chunk_position, chunk_mesh, chunk_collider)
	_loaded_chunks[key] = chunk
	call_deferred("add_child", chunk)


func free_chunk(key: String) -> void:
	var chunk = _loaded_chunks[key]
	var erased = _loaded_chunks.erase(key)
	if erased: chunk.queue_free()


func make_chunk_mesh(position: Vector3) -> MeshInstance:
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
	
	var mesh_instance = MeshInstance.new()
	mesh_instance.mesh = Mesh.new()
	mesh_instance.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh_instance.mesh.surface_set_material(0, _chunk_material)
	
	if needs_water_mesh: mesh_instance.add_child(make_water_mesh(position))
	return mesh_instance


func make_water_mesh(position: Vector3) -> MeshInstance:
	var mesh_instance = MeshInstance.new()
	mesh_instance.translation = Vector3(position.x + _chunk_size / 2.0, _water_level, position.z + _chunk_size / 2.0)
	mesh_instance.mesh = PlaneMesh.new()
	mesh_instance.mesh.surface_set_material(0, _water_material)
	mesh_instance.mesh.size = Vector2(_chunk_size, _chunk_size)
	return mesh_instance


func make_chunk_collider(mesh_instance: MeshInstance) -> StaticBody:
	var collision_shape = CollisionShape.new()
	collision_shape.shape = mesh_instance.mesh.create_trimesh_shape()
	var static_body = StaticBody.new()
	static_body.add_child(collision_shape)
	return static_body


func make_chunk_key(chunk_position: Vector2) -> String:
	return str(chunk_position.x, ",", chunk_position.y)


func sample_noise(x: int, z: int) -> float:
	return _noise_generator.get_noise_2d(x, z) * _noise_scale


##################
# Private fields #
##################


var _target: Spatial
var _loaded_chunks: Dictionary

## Rendering
var _render_distance: int
var _chunk_size: int
var _chunk_density: int

## Terrain generation
var _make_collider: bool
var _chunk_material: Material
var _water_material: Material
var _water_level: float
var _noise_generator: OpenSimplexNoise
var _noise_scale: float


################
# Chunk struct #
################


class Chunk extends Node:
	func _init(chunk_pos: Vector2, chunk_mesh: MeshInstance, chunk_collider: StaticBody):
		chunk_position = chunk_pos
		if not chunk_mesh == null: add_child(chunk_mesh)
		if not chunk_collider == null: add_child(chunk_collider)
	
	var chunk_position: Vector2
