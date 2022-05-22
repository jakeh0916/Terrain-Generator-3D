class_name TerrainGeneratorAsync
extends TerrainGenerator


func _init(target: Spatial, render_opts: Dictionary, generation_opts: Dictionary).(target, render_opts, generation_opts):
	_worker = Thread.new()
	_is_busy = false
	_halt = false


func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		if _worker.is_active():
			_halt = true
			_worker.wait_to_finish()


######################
# Terrain generation #
######################


func generate():
	if _is_busy: 
		return
	.generate()
	
	var queued_actions = _add_queue.size() + _remove_queue.size()
	if queued_actions >= MAX_QUEUE:
		_worker.start(self, "do_queued_actions_async", [_worker])
		_is_busy = true


func add_chunk(chunk_position: Vector2) -> void:
	if not _add_queue.has(chunk_position): 
		_add_queue.push_back(chunk_position)


func remove_chunk(key: String) -> void:
	if not _remove_queue.has(key):
		_remove_queue.push_back(key)


func do_queued_actions_async(worker_data):
	for chunk_position in _add_queue:
		if _halt: return
		.add_chunk(chunk_position)
	for key in _remove_queue:
		if _halt: return
		.remove_chunk(key)
	_add_queue.clear()
	_remove_queue.clear()
	call_deferred("make_worker_ready", worker_data[0])


func make_worker_ready(thread):
	if thread.is_active():
		thread.wait_to_finish()
	_is_busy = false


##################
# Private fields #
##################


const MAX_QUEUE = 32
var _add_queue: Array
var _remove_queue: Array

var _worker: Thread
var _is_busy: bool
var _halt: bool
