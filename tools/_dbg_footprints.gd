extends SceneTree

var _trail: Node3D
var _frame := 0


func _initialize() -> void:
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	_trail = world.get_node("Footprints") as Node3D


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame != 5:
		return false
	print("next before clear: ", _trail.call("next_slot"), " count ", _trail.call("stamped_count"))
	_trail.call("clear")
	print("next after clear: ", _trail.call("next_slot"))
	_trail.call("stamp", Vector3(1.0, 0.0, 2.0), 0.4, 0, Vector2(0.13, 0.16), 0.8)
	print("next after stamp: ", _trail.call("next_slot"), " count ", _trail.call("stamped_count"))
	print("slot0: ", _trail.call("get_slot", 0))
	print("slot1: ", _trail.call("get_slot", 1))
	var mm: MultiMesh = (_trail.get_node("FootprintMesh") as MultiMeshInstance3D).multimesh
	print("mm count ", mm.instance_count, " transform_format ", mm.transform_format, " custom ", mm.use_custom_data)
	print("mm raw 0: ", mm.get_instance_transform(0))
	print("mm raw 1: ", mm.get_instance_transform(1))
	quit(0)
	return true
