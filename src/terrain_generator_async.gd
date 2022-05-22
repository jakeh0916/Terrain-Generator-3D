class_name TerrainGeneratorAsync
extends TerrainGenerator


func _init(target: Spatial, render_opts: Dictionary, generation_opts: Dictionary).(target, render_opts, generation_opts):
	_worker = Thread.new()
	_is_busy = false


######################
# Terrain generation #
######################


func generate():
	if not _target == null and not _is_busy:
		var position = _target.translation
		if position.x < 0: position.x -= _chunk_size
		if position.z < 0: position.z -= _chunk_size
		var chunk_x: int = int(position.x) / _chunk_size
		var chunk_z: int = int(position.z) / _chunk_size
		
		for ix in range(chunk_x - _render_distance, chunk_x + _render_distance + 1):
			for iz in range(chunk_z - _render_distance, chunk_z + _render_distance + 1):
				if Vector2(ix, iz).distance_to(Vector2(chunk_x, chunk_z)) <= _render_distance:
					if _chunk_queue.has(Vector2(ix, iz)) or _loaded_chunks.has(make_chunk_key(Vector2(ix, iz))): continue
					_chunk_queue.push_back(Vector2(ix, iz))
		
		for key in _loaded_chunks:
			if _loaded_chunks[key].chunk_position.distance_to(Vector2(chunk_x, chunk_z)) > _render_distance:
				free_chunk(key)
		
		if _chunk_queue.size() >= CHUNK_QUEUE_MAX:
			_worker.start(self, "make_chunk_queue", [_worker, _chunk_queue])
			_is_busy = true


func make_chunk_queue(worker_data):
	for chunk_position in worker_data[1]:
		make_chunk(chunk_position)
	call_deferred("make_worker_ready", worker_data[0])


func make_worker_ready(thread):
	thread.wait_to_finish()
	_chunk_queue = []
	_is_busy = false


##################
# Private fields #
##################


const CHUNK_QUEUE_MAX := 64
var _chunk_queue: Array

var _worker: Thread
var _is_busy: bool


