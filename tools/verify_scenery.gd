extends SceneTree

## Verifies the rebuilt scenery and main scene.
##
## Run with:
##     godot --headless --path . --script res://tools/verify_scenery.gd
##
## Exits with status 1 if any prop floats above / sinks below the ground plane,
## if a scene is missing, or if main.tscn still references the merged GLBs.

const SCENES := {
	"res://scenes/forest.tscn": 30,
	"res://scenes/nature_props.tscn": 22,
	"res://scenes/arena_course.tscn": 21,
}
const BASE_TOLERANCE := 0.02
const GROUND_SNAP := 0.001

var _ok := true


func _initialize() -> void:
	print("=== VERIFY SCENERY ===")
	var total_props := 0
	var total_tris := 0
	for path in SCENES.keys():
		var scene := load(path) as PackedScene
		if scene == null:
			_fail("cannot load " + path)
			continue
		var inst := scene.instantiate()
		var props := 0
		var tris := 0
		var meshes := 0
		var worst := 0.0
		var worst_name := ""
		for prop in _props_of(inst):
			props += 1
			if not (prop as Node).has_method("reset_jump"):
				var bounds := _aabb_of(prop, Transform3D.IDENTITY)
				var base := bounds.position.y
				if absf(base) > absf(worst):
					worst = base
					worst_name = String(prop.name)
			var count := _count_meshes(prop)
			meshes += int(count.meshes)
			tris += int(count.tris)
		print("  %-32s props=%d meshes=%d tris=%d worst_base=%+.4f (%s)" % [
			path.get_file(), props, meshes, tris, worst, worst_name
		])
		if props != int(SCENES[path]):
			_fail("%s: expected %d props, found %d" % [path.get_file(), SCENES[path], props])
		if absf(worst) > BASE_TOLERANCE:
			_fail("%s: %s base is %+.4f m off the ground" % [path.get_file(), worst_name, worst])
		total_props += props
		total_tris += tris
		inst.free()
	print("  total props=%d tris=%d" % [total_props, total_tris])
	if total_tris > 600000:
		_fail("triangle budget exceeded: %d > 600000" % total_tris)

	_check_main_scene()
	print("=== %s ===" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _check_main_scene() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("cannot load res://scenes/main.tscn")
		return
	var main := packed.instantiate()
	for required in ["Forest", "NatureProps", "ArenaCourse", "Stable", "ArenaFence", "Terrain", "Horse", "Player"]:
		if main.get_node_or_null(required) == null:
			_fail("main.tscn is missing node '%s'" % required)
	for retired in ["Trees", "Nature"]:
		if main.get_node_or_null(retired) != null:
			_fail("main.tscn still has the merged-GLB node '%s'" % retired)
	print("  main.tscn nodes: " + str(main.get_children().size()))
	main.free()


## Props are instanced GLB scenes; generated group nodes are plain Node3Ds
## with an empty scene_file_path. Only one grouping level is used.
func _props_of(root: Node) -> Array:
	var out: Array = []
	_collect_props(root, out)
	return out


func _collect_props(node: Node, out: Array) -> void:
	for child in node.get_children():
		if String(child.scene_file_path) != "":
			out.append(child)
		else:
			_collect_props(child, out)


func _aabb_of(root: Node, xform: Transform3D) -> AABB:
	var boxes: Array = []
	_walk(root, xform, boxes)
	if boxes.is_empty():
		return AABB()
	var out: AABB = boxes[0]
	for i in range(1, boxes.size()):
		out = out.merge(boxes[i])
	return out


func _walk(node: Node, xform: Transform3D, boxes: Array) -> void:
	var x := xform
	if node is Node3D:
		x = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			boxes.append(x * mi.mesh.get_aabb())
	for child in node.get_children():
		_walk(child, x, boxes)


func _count_meshes(root: Node) -> Dictionary:
	var meshes := 0
	var tris := 0
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh != null:
			meshes += 1
			tris += mi.mesh.get_faces().size() / 3
	for child in root.get_children():
		var sub := _count_meshes(child)
		meshes += int(sub.meshes)
		tris += int(sub.tris)
	return {"meshes": meshes, "tris": tris}


func _fail(message: String) -> void:
	_ok = false
	print("  FAIL: " + message)
