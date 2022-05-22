extends TerrainGenerator
class_name TerrainGeneratorThreaded

var worker
var worker_is_busy = false

func _init(target_node: Spatial, render_opts: Dictionary, terrain_opts: Dictionary).(target_node, render_opts, terrain_opts):
	worker = Thread.new()

func ready_worker(thread):
	thread.wait_to_finish()
	worker_is_busy = false

func generate():
	if not target == null and not worker.is_active() and not worker_is_busy:
		worker.start(self, "generate_delegated", [target.translation, worker])
		worker_is_busy = true

func generate_delegated(worker_data: Array):
	var position = worker_data[0]
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
	call_deferred("ready_worker", worker_data[1])

func make_chunk(chunk_position: Vector2):
	var key = make_chunk_key(chunk_position)
	if loaded_chunks.has(key): return

	var position = Vector3(chunk_position.x * chunk_size, 0, chunk_position.y * chunk_size)
	var chunk_mesh = make_chunk_mesh(position)
	var chunk_collider = make_chunk_collider(chunk_mesh)
	
	var chunk = Chunk.new(chunk_position, chunk_mesh, chunk_collider)
	loaded_chunks[key] = chunk
	call_deferred("add_child", chunk)
