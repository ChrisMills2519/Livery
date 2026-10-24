extends SceneTree

## Headless verification for the dressed stable yard.
##
##   godot --headless --path . --script res://tools/check_yard_props.gd
##
## Checks that the old medieval loose props are gone, that every new prop is
## seated on the ground (or on the surface it is stacked/hung from), that each
## large prop has a collider matching its visual bounds, and that no prop runs
## into the stable shell, the paddock fences or the feed trough.

const STABLE := "res://scenes/stable.tscn"
const YARD_EXPECTED := 32
const COLLIDERS_EXPECTED := 19
const OLD_NODES := [
	"Props", "HayBale1", "HayBale2", "HayBale3", "Barrel1", "Barrel2",
	"Crate1", "Crate2", "Cart", "Bench", "Well",
]
const COLLIDING := [
	"HayRoundA", "HayRoundB", "HaySquare", "BarrelA", "BarrelB", "CrateA",
	"CrateB", "Wheelbarrow", "Bench", "Well", "WaterTrough", "MountingBlock",
	"HitchingPost", "SaddleRack", "MuckTub", "Signpost", "LanternA", "LanternB",
	"Firewood",
]
const GROUND_TOLERANCE := 0.02
const FENCE_HEIGHT := 1.32

var _failures: Array[String] = []


func _initialize() -> void:
	await _run()
	if _failures.is_empty():
		print("YARD PROPS CHECK: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("  FAIL: ", failure)
		print("YARD PROPS CHECK: FAIL (%d)" % _failures.size())
		quit(1)


func _run() -> void:
	var packed := load(STABLE) as PackedScene
	if packed == null:
		_check(false, "%s loads" % STABLE)
		return
	var stable := packed.instantiate() as Node3D
	root.add_child(stable)
	await process_frame
	await process_frame

	for old in OLD_NODES:
		_check(stable.get_node_or_null(old) == null, "the old prop '%s' is gone" % old)

	var yard := stable.get_node_or_null("YardProps") as Node3D
	_check(yard != null, "stable.tscn instances the generated yard props")
	if yard == null:
		stable.queue_free()
		return
	_check(yard.get_child_count() == YARD_EXPECTED,
		"the yard has %d props (got %d)" % [YARD_EXPECTED, yard.get_child_count()])

	var stable_shell := AABB(Vector3(-11.47, 0.0, -26.95), Vector3(8.94, 3.97, 3.9))
	var feed_trough := AABB(Vector3(2.4, 0.0, -22.85), Vector3(2.0, 0.5, 0.7))
	var fences := [
		AABB(Vector3(1.0, 0.0, -28.15), Vector3(10.0, FENCE_HEIGHT, 0.3)),
		AABB(Vector3(1.0, 0.0, -20.15), Vector3(10.0, FENCE_HEIGHT, 0.3)),
		AABB(Vector3(0.85, 0.0, -28.0), Vector3(0.3, FENCE_HEIGHT, 8.0)),
		AABB(Vector3(10.85, 0.0, -28.0), Vector3(0.3, FENCE_HEIGHT, 8.0)),
	]

	var colliders := 0
	var names := {}
	for slot in yard.get_children():
		var slot3d := slot as Node3D
		_check(slot3d != null, "prop '%s' is a Node3D" % String(slot.name))
		if slot3d == null:
			continue
		names[String(slot.name)] = true
		var model := slot.get_node_or_null("Model") as Node3D
		_check(model != null, "prop '%s' has a model" % String(slot.name))
		if model == null:
			continue

		var bounds := _aabb_of(model, Transform3D.IDENTITY)
		_check(
			absf(bounds.position.y) <= GROUND_TOLERANCE,
			"prop '%s' sits on its slot surface (base %+.3f m)" % [String(slot.name), bounds.position.y]
		)

		var body := slot.get_node_or_null("Body") as StaticBody3D
		if body != null:
			colliders += 1
			var shape_node := body.get_node_or_null("Shape") as CollisionShape3D
			_check(shape_node != null, "prop '%s' collider has a shape" % String(slot.name))
			if shape_node != null and shape_node.shape is BoxShape3D:
				var box := (shape_node.shape as BoxShape3D).size
				var expected := Vector3(
					maxf(0.05, bounds.size.x - 0.02),
					maxf(0.05, bounds.size.y - 0.02),
					maxf(0.05, bounds.size.z - 0.02)
				)
				_check(
					box.distance_to(expected) <= 0.02,
					"prop '%s' collider size matches its visual (got %s, want %s)" % [String(slot.name), box, expected]
				)
				_check(
					(shape_node.position - bounds.get_center()).length() <= 0.02,
					"prop '%s' collider is centred on the visual" % String(slot.name)
				)

		var world := _aabb_of(slot3d, Transform3D.IDENTITY).grow(-0.02)
		_check(
			not world.intersects(stable_shell),
			"prop '%s' does not clip the stable shell" % String(slot.name)
		)
		_check(
			not world.intersects(feed_trough),
			"prop '%s' does not clip the feed trough" % String(slot.name)
		)
		for fence in fences:
			if world.intersects(fence):
				_check(false, "prop '%s' overlaps the paddock fence" % String(slot.name))
				break

	_check(colliders == COLLIDERS_EXPECTED,
		"the yard has %d colliders (got %d)" % [COLLIDERS_EXPECTED, colliders])
	for wanted in COLLIDING:
		_check(names.has(wanted), "expected prop '%s' is present" % wanted)
		var node := yard.get_node_or_null(wanted)
		_check(node != null and node.get_node_or_null("Body") != null,
			"prop '%s' is solid" % wanted)

	var trough := stable.get_node_or_null("FeedTrough")
	_check(trough != null, "the gameplay feed trough is still in the stable")
	if trough != null:
		_check(trough.get_node_or_null("TroughCollision/Shape") != null,
			"the feed trough keeps its collision")

	stable.queue_free()
	await process_frame


func _aabb_of(root: Node, xform: Transform3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect(root, xform, boxes)
	if boxes.is_empty():
		return AABB()
	var out := boxes[0]
	for i in range(1, boxes.size()):
		out = out.merge(boxes[i])
	return out


func _collect(node: Node, xform: Transform3D, boxes: Array[AABB]) -> void:
	var x := xform
	if node is Node3D:
		x = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			boxes.append(x * mesh_instance.mesh.get_aabb())
	for child in node.get_children():
		_collect(child, x, boxes)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
