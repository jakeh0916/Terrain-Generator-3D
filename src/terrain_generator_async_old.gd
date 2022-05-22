class_name TerrainGeneratorAsync_Old
extends TerrainGenerator


func _init(target: Spatial, render_opts: Dictionary, generation_opts: Dictionary).(target, render_opts, generation_opts):
	_worker = Thread.new()
	_mutex = Mutex.new()
	_is_busy = false


func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		if _is_busy:
			while not _mutex.try_lock() == OK: continue
			_quit_request = true
			_mutex.unlock()
			
			_worker.wait_to_finish()


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
				var chunk_pos = Vector2(ix, iz)
				if chunk_pos.distance_to(Vector2(chunk_x, chunk_z)) <= _render_distance:
					if _chunk_queue.has(chunk_pos) or _loaded_chunks.has(make_chunk_key(chunk_pos)): 
						continue
					_chunk_queue.push_back(Vector2(ix, iz))
		
		for key in _loaded_chunks:
			var chunk_pos = parse_chunk_key(key)
			if chunk_pos.distance_to(Vector2(chunk_x, chunk_z)) > _render_distance:
				remove_chunk(key)
		
		if _chunk_queue.size() >= CHUNK_QUEUE_MAX:
			_is_busy = true
			_worker.start(self, "add_queued_chunks", [_worker, _chunk_queue])


func add_queued_chunks(worker_data):
	for chunk_position in worker_data[1]:
		while not _mutex.try_lock() == OK: continue
		var quit_request = _quit_request
		_mutex.unlock()
		
		if quit_request: 
			return
		
		add_chunk(chunk_position)
	call_deferred("make_worker_ready", worker_data[0])


func make_worker_ready(thread):
	thread.wait_to_finish()
	_chunk_queue = []
	_is_busy = false


##################
# Private fields #
##################


const CHUNK_QUEUE_MAX := 1
var _chunk_queue: Array

var _worker: Thread
var _mutex: Mutex
var _is_busy: bool
var _quit_request: bool
