extends Spatial
class_name Chunk

var chunk_pos: Vector2

func _init(_chunk_pos: Vector2, land_mi: MeshInstance, water_mi: MeshInstance, sb: StaticBody):
	chunk_pos = _chunk_pos
	if not land_mi == null: add_child(land_mi)
	if not water_mi == null: add_child(water_mi)
	if not sb == null: add_child(sb)
