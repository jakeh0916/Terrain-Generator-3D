extends Node
class_name Chunk

var chunk_position

func _init(_chunk_position: Vector2, chunk_mesh: MeshInstance, chunk_collider: StaticBody):
	chunk_position = _chunk_position
	add_child(chunk_mesh)
	add_child(chunk_collider)
