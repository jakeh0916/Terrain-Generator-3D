extends Node
class_name TerrainGeneratorAsync

var worker
var worker_is_busy
var target = null
var loaded_chunks

## Rendering
var chunk_size
var chunk_density
var render_distance

## Terrain
var chunk_material
var water_material
var water_level
var noise
var noise_scale

func _init(target_node: Spatial, render_opts: Dictionary, terrain_opts: Dictionary):
	target = target_node
	loaded_chunks = {}
	
	## Unpack render options
	render_distance = render_opts["render_distance"]
	chunk_size = render_opts["chunk_size"]
	chunk_density = render_opts["chunk_density"]
	
	## Unpack terrain options
	chunk_material = terrain_opts["chunk_material"]
	water_material = terrain_opts["water_material"]
	water_level = terrain_opts["water_level"]

	## Unpack terrain noise options
	noise = OpenSimplexNoise.new()
	noise.octaves = terrain_opts["noise_octaves"]
	noise.period = terrain_opts["noise_period"]
	noise_scale = terrain_opts["noise_scale"]
	
	worker = Thread.new()

func _process(_delta):
	if not target == null and not worker.is_active() and not worker_is_busy:
		worker.start(self, "update_chunks", [target.translation, worker])
		worker_is_busy = true

func ready_worker(thread):
	thread.wait_to_finish()
	worker_is_busy = false

## Chunk Handling



func update_chunks(arr: Array):
	var position = arr[0]
	if position.x < 0: position.x -= chunk_size
	if position.z < 0: position.z -= chunk_size
	var chunk_x: int = int(position.x) / chunk_size
	var chunk_z: int = int(position.z) / chunk_size
	
	for ix in range(chunk_x - render_distance, chunk_x + render_distance + 1):
		for iz in range(chunk_z - render_distance, chunk_z + render_distance + 1):
			if Vector2(ix, iz).distance_to(Vector2(chunk_x, chunk_z)) <= render_distance:
				make_chunk(Vector2(ix, iz))
	for key in loaded_chunks:
		if loaded_chunks[key].chunk_position.distance_to(Vector2(chunk_x, chunk_z)) > render_distance:
			free_chunk(key)
	call_deferred("ready_worker", arr[1])

func make_chunk(chunk_position: Vector2):
	var key = make_chunk_key(chunk_position)
	if loaded_chunks.has(key): return

	var position = Vector3(chunk_position.x * chunk_size, 0, chunk_position.y * chunk_size)
	var chunk_mesh = make_chunk_mesh(position)
	var chunk_collider = make_chunk_collider(chunk_mesh)
	
	var chunk = Chunk.new(chunk_position, chunk_mesh, chunk_collider)
	loaded_chunks[key] = chunk
	call_deferred("add_child", chunk)

func free_chunk(key: String):
	var chunk = loaded_chunks[key]
	var erased = loaded_chunks.erase(key)
	if erased: chunk.queue_free()

func make_chunk_mesh(position: Vector3) -> MeshInstance:
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	
	var needs_water_mesh = false
	var verts = PoolVector3Array()
	var norms = PoolVector3Array()
	var uvs   = PoolVector2Array()
	var inds  = PoolIntArray()
	
	var vert_step = float(chunk_size) / chunk_density
	var uv_step   = 1.0 / chunk_density 
	
	for x in chunk_density + 1:
		for z in chunk_density + 1:
			var vert = Vector3(position.x + x * vert_step, 0.0, position.z + z * vert_step)
			var uv = Vector2(1.0 - x * uv_step, 1.0 - z * uv_step)
			
			vert.y = sample_noise(vert.x, vert.z)
			if vert.y < water_level: needs_water_mesh = true
			
			var top = vert - Vector3(vert.x, sample_noise(vert.x, vert.z + vert_step), vert.z + vert_step)
			var right = vert - Vector3(vert.x + vert_step, sample_noise(vert.x + vert_step, vert.z), vert.z)
			var norm = top.cross(right).normalized()
			
			verts.push_back(vert)
			norms.push_back(norm)
			uvs.push_back(uv)
			
			# Make & index a clockwise face from verts a, b, c, d
			if x < chunk_density and z < chunk_density:
				var a = z + x * (chunk_density + 1)
				var b = a + 1
				var d = (chunk_density + 1) * (x + 1) + z
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
	mesh_instance.mesh.surface_set_material(0, chunk_material)
	
	if needs_water_mesh: mesh_instance.add_child(make_water_mesh(position))
	return mesh_instance

func make_water_mesh(position: Vector3) -> MeshInstance:
	var mesh_instance = MeshInstance.new()
	mesh_instance.mesh = PlaneMesh.new()
	mesh_instance.mesh.size = Vector2(chunk_size, chunk_size)
	mesh_instance.translation = Vector3(position.x + chunk_size / 2, water_level, position.z + chunk_size / 2)
	mesh_instance.mesh.surface_set_material(0, water_material)
	return mesh_instance

func make_chunk_collider(mesh_instance: MeshInstance) -> StaticBody:
	var static_body = StaticBody.new()
	var collision_shape = CollisionShape.new()
	collision_shape.shape = mesh_instance.mesh.create_trimesh_shape()
	static_body.add_child(collision_shape)
	return static_body

func sample_noise(x: int, z: int) -> float:
	return noise.get_noise_2d(x, z) * noise_scale

func make_chunk_key(chunk_position: Vector2) -> String:
	return str(chunk_position.x, ",", chunk_position.y)
