extends SceneTree

## Deterministic scenery generator for the rebuilt main scene.
##
## Run with:
##     godot --headless --path . --script res://tools/build_scenery.gd
##
## The split GLBs in Models/split/ keep the source scene's transforms on their
## root node, so every asset is offset from the origin and (for the trees) sunk
## by roughly half its height. Instancing them as-is looks broken. This tool
## measures each asset's real AABB in Godot and bakes
##
##     P(pos, yaw, scale) * T(-centre.x, -min.y, -centre.z) * B
##
## into the instance transform, where B is the GLB root's own baked transform.
## That keeps the source orientation (Z-up assets stay upright), centres the
## footprint on the node origin and puts the base exactly on y = 0.
##
## The output .tscn files are ordinary static scenes: after generation they can
## be edited by hand in the editor. Re-running this tool overwrites them.

const FOREST_PATH := "res://scenes/forest.tscn"
const NATURE_PATH := "res://scenes/nature_props.tscn"
const COURSE_PATH := "res://scenes/arena_course.tscn"
const ARENA_FENCE_PATH := "res://scenes/arena_fence.tscn"

const SPLIT := "res://Models/split/"
const ARENA_FENCE_MODEL := "res://Models/medieval_village/fence_713fa0e6.glb"
const ARENA_FENCE_SCALE := 4.0
const ARENA_COLLISION_HEIGHT := 1.32
const ARENA_COLLISION_DEPTH := 0.30
# The arena grew from 20 x 40 m to 35 x 70 m (about 3x the area). The east
# rail stays at x = -15 so the existing gate, stable yard and path still line up.
const ARENA_MIN := Vector2(-50.0, -35.0)
const ARENA_MAX := Vector2(-15.0, 35.0)
const GATE_MIN_Z := -5.0
const GATE_MAX_Z := 2.0

# --- asset keys -------------------------------------------------------------

const TREES := {
	"a": SPLIT + "lowpoly_trees/00_Object_2.glb",
	"b": SPLIT + "lowpoly_trees/01_Object_3.glb",
	"c": SPLIT + "lowpoly_trees/02_Object_4.glb",
	"d": SPLIT + "lowpoly_trees/03_Object_5.glb",
	"e": SPLIT + "lowpoly_trees/04_Object_6.glb",
	"f": SPLIT + "lowpoly_trees/05_Object_7.glb",
	"g": SPLIT + "lowpoly_trees/06_Object_8.glb",
	"h": SPLIT + "lowpoly_trees/07_Object_9.glb",
}

const NATURE := {
	"n0": SPLIT + "low_poly_nature_assets_1/00_default.glb",
	"n1": SPLIT + "low_poly_nature_assets_1/01_default1.glb",
	"n2": SPLIT + "low_poly_nature_assets_1/02_default10.glb",
	"n3": SPLIT + "low_poly_nature_assets_1/03_default11.glb",
	"n4": SPLIT + "low_poly_nature_assets_1/04_default2.glb",
	"n5": SPLIT + "low_poly_nature_assets_1/05_default3.glb",
	"n6": SPLIT + "low_poly_nature_assets_1/06_default4.glb",
	"n7": SPLIT + "low_poly_nature_assets_1/07_default5.glb",
	"n8": SPLIT + "low_poly_nature_assets_1/08_default6.glb",
	"n9": SPLIT + "low_poly_nature_assets_1/09_default7.glb",
	"n10": SPLIT + "low_poly_nature_assets_1/10_default8.glb",
	"n11": SPLIT + "low_poly_nature_assets_1/11_default9.glb",
}

const JUMPING := {
	"cavaletti": SPLIT + "show_jumping____horse_jumping_obstacles/00_Barrier1.glb",
	"barrier": SPLIT + "show_jumping____horse_jumping_obstacles/01_Barrier2.glb",
	"jump": SPLIT + "show_jumping____horse_jumping_obstacles/02_BarrierEvery3D.glb",
}

const FENCES := {
	"cone_a": SPLIT + "horse_riding_obstacles_box_1_to_10_wooden_fence/00_Cone_obstacle_A1.glb",
	"cone_b": SPLIT + "horse_riding_obstacles_box_1_to_10_wooden_fence/01_Cone_obstacle_B2.glb",
	"fence_long": SPLIT + "horse_riding_obstacles_box_1_to_10_wooden_fence/02_Fence_1.glb",
	"fence_cross": SPLIT + "horse_riding_obstacles_box_1_to_10_wooden_fence/03_Fence_2.glb",
	"box_1": SPLIT + "horse_riding_obstacles_box_1_to_10_wooden_fence/05_No_1_Box.glb",
	"box_2": SPLIT + "horse_riding_obstacles_box_1_to_10_wooden_fence/06_No_2_Box.glb",
	"box_3": SPLIT + "horse_riding_obstacles_box_1_to_10_wooden_fence/07_No_3_Box.glb",
}

var _measured := {}


func _initialize() -> void:
	print("=== BUILD SCENERY ===")
	_build_forest()
	_build_nature()
	_build_arena_fence()
	_build_course()
	print("=== DONE ===")
	quit(0)


func _build_forest() -> void:
	var items: Array = []
	# North belt, behind the stable.
	items.append_array(_zone("North", [
		["h", -46.0, -50.0, 15.0, 1.15],
		["a", -34.0, -48.0, 70.0, 1.05],
		["f", -20.0, -52.0, 120.0, 1.10],
		["d", -8.0, -47.0, 200.0, 1.15],
		["h", 4.0, -52.0, 250.0, 1.05],
		["a", 16.0, -49.0, 320.0, 1.00],
		["f", 28.0, -51.0, 40.0, 1.15],
		["d", 38.0, -47.0, 160.0, 1.10],
		["g", 46.0, -53.0, 90.0, 1.25],
	], TREES))
	# West belt, outside the wide arena rail at x = -50.
	items.append_array(_zone("West", [
		["h", -57.0, -28.0, 30.0, 1.00],
		["a", -59.0, -14.0, 100.0, 1.10],
		["f", -56.0, 0.0, 190.0, 1.00],
		["a", -61.0, 12.0, 270.0, 1.05],
		["d", -55.0, 24.0, 340.0, 1.15],
	], TREES))
	# East grove, beyond the training ground.
	items.append_array(_zone("East", [
		["h", 66.0, -26.0, 60.0, 1.00],
		["a", 72.0, -14.0, 130.0, 1.10],
		["f", 64.0, -2.0, 200.0, 1.00],
		["h", 76.0, 8.0, 270.0, 1.05],
		["d", 68.0, 16.0, 20.0, 1.15],
		["a", 74.0, 26.0, 90.0, 1.00],
	], TREES))
	# South belt.
	items.append_array(_zone("South", [
		["f", -46.0, 36.0, 10.0, 1.05],
		["h", -30.0, 40.0, 80.0, 1.00],
		["a", -14.0, 34.0, 150.0, 1.05],
		["d", 2.0, 38.0, 220.0, 1.10],
		["f", 16.0, 33.0, 290.0, 1.00],
		["h", 32.0, 40.0, 0.0, 1.05],
		["d", 44.0, 35.0, 70.0, 1.00],
	], TREES))
	# Small near-field accents framing the yard and path.
	items.append_array(_zone("Accent", [
		["b", 16.0, -22.0, 45.0, 1.20],
		["c", -16.0, -36.0, 135.0, 1.30],
		["e", 20.0, 22.0, 225.0, 1.40],
	], TREES))
	_build_scene(FOREST_PATH, "Forest", items)


func _build_nature() -> void:
	var items: Array = []
	items.append_array(_zone("Path", [
		["n0", -2.7, -17.0, 0.0, 12.0],
		["n4", 2.7, -14.0, 60.0, 12.0],
		["n5", -2.8, -10.0, 120.0, 10.0],
		["n0", 2.8, -7.0, 180.0, 12.0],
		["n4", -2.7, -3.0, 240.0, 12.0],
		["n8", 2.7, 2.0, 300.0, 12.0],
	], NATURE))
	items.append_array(_zone("Yard", [
		["n6", -11.5, -28.5, 30.0, 12.0],
		["n2", 11.5, -29.0, 90.0, 11.0],
		["n9", -11.5, -15.5, 150.0, 12.0],
		["n1", 11.8, -15.2, 210.0, 12.0],
	], NATURE))
	items.append_array(_zone("Paddock", [
		["n10", -0.6, -27.0, 0.0, 10.0],
		["n11", 12.2, -24.0, 100.0, 10.0],
		["n10", 12.2, -21.0, 200.0, 10.0],
		["n11", -0.6, -22.0, 260.0, 10.0],
	], NATURE))
	items.append_array(_zone("ArenaEdge", [
		["n3", -53.5, -14.0, 45.0, 12.0],
		["n6", -54.0, 0.0, 135.0, 12.0],
		["n2", -53.5, 14.0, 225.0, 12.0],
		["n9", -53.0, 30.0, 315.0, 12.0],
	], NATURE))
	items.append_array(_zone("TrainingEdge", [
		["n0", 16.0, -12.0, 20.0, 12.0],
		["n5", 16.0, 2.0, 110.0, 12.0],
		["n4", 16.0, 12.0, 200.0, 11.0],
		["n7", 54.0, -13.0, 290.0, 11.0],
	], NATURE))
	_build_scene(NATURE_PATH, "NatureProps", items)


## Builds the enlarged arena rail from the fence module's measured length.
## Modules butt together (a tiny overlap) and the east run skips the gate span.
func _build_arena_fence() -> void:
	var packed := load(ARENA_FENCE_MODEL) as PackedScene
	if packed == null:
		push_error("cannot load arena fence model")
		quit(1)
		return
	var probe := packed.instantiate() as Node3D
	if probe == null:
		push_error("cannot instantiate arena fence model")
		quit(1)
		return
	var module_length := _aabb_of(probe).size.x * ARENA_FENCE_SCALE
	probe.free()
	if module_length <= 0.001:
		push_error("arena fence module has no length")
		quit(1)
		return

	var width := ARENA_MAX.x - ARENA_MIN.x
	var depth := ARENA_MAX.y - ARENA_MIN.y
	var nx := maxi(1, ceili(width / module_length))
	var nz := maxi(1, ceili(depth / module_length))
	var step_x := width / float(nx)
	var step_z := depth / float(nz)

	var root := Node3D.new()
	root.name = "ArenaFence"

	for side in range(2):
		var z := ARENA_MIN.y if side == 0 else ARENA_MAX.y
		for i in range(nx):
			var x := ARENA_MIN.x + (i + 0.5) * step_x
			var inst := _make_instance(ARENA_FENCE_MODEL, Vector3(x, 0.0, z), 0.0, ARENA_FENCE_SCALE)
			if inst == null:
				root.free()
				return
			inst.name = "ArenaFence%s%d" % ["N" if side == 0 else "S", i]
			root.add_child(inst)
			inst.owner = root

	var gate_start := INF
	var gate_end := -INF
	for side in range(2):
		var x := ARENA_MIN.x if side == 0 else ARENA_MAX.x
		for i in range(nz):
			var z := ARENA_MIN.y + (i + 0.5) * step_z
			if side == 1 and z > GATE_MIN_Z and z < GATE_MAX_Z:
				gate_start = minf(gate_start, z - step_z * 0.5)
				gate_end = maxf(gate_end, z + step_z * 0.5)
				continue
			var inst := _make_instance(ARENA_FENCE_MODEL, Vector3(x, 0.0, z), 90.0, ARENA_FENCE_SCALE)
			if inst == null:
				root.free()
				return
			inst.name = "ArenaFence%s%d" % ["W" if side == 0 else "E", i]
			root.add_child(inst)
			inst.owner = root

	var body := StaticBody3D.new()
	body.name = "ArenaCollision"
	root.add_child(body)
	body.owner = root
	var mitre := ARENA_COLLISION_DEPTH
	_add_collision_box(body, root, "NorthShape",
		Vector3(width + mitre, ARENA_COLLISION_HEIGHT, mitre),
		Vector3((ARENA_MIN.x + ARENA_MAX.x) * 0.5, ARENA_COLLISION_HEIGHT * 0.5, ARENA_MIN.y))
	_add_collision_box(body, root, "SouthShape",
		Vector3(width + mitre, ARENA_COLLISION_HEIGHT, mitre),
		Vector3((ARENA_MIN.x + ARENA_MAX.x) * 0.5, ARENA_COLLISION_HEIGHT * 0.5, ARENA_MAX.y))
	_add_collision_box(body, root, "WestShape",
		Vector3(mitre, ARENA_COLLISION_HEIGHT, depth + mitre),
		Vector3(ARENA_MIN.x, ARENA_COLLISION_HEIGHT * 0.5, (ARENA_MIN.y + ARENA_MAX.y) * 0.5))
	if gate_start == INF or gate_end == -INF:
		gate_start = ARENA_MIN.y
		gate_end = ARENA_MAX.y
	var north_len := gate_start - ARENA_MIN.y
	var south_len := ARENA_MAX.y - gate_end
	if north_len > 0.01:
		_add_collision_box(body, root, "EastShapeNorth",
			Vector3(mitre, ARENA_COLLISION_HEIGHT, north_len + mitre),
			Vector3(ARENA_MAX.x, ARENA_COLLISION_HEIGHT * 0.5, ARENA_MIN.y + north_len * 0.5))
	if south_len > 0.01:
		_add_collision_box(body, root, "EastShapeSouth",
			Vector3(mitre, ARENA_COLLISION_HEIGHT, south_len + mitre),
			Vector3(ARENA_MAX.x, ARENA_COLLISION_HEIGHT * 0.5, gate_end + south_len * 0.5))

	var scene := PackedScene.new()
	var err := scene.pack(root)
	if err != OK:
		push_error("pack failed for %s (error %d)" % [ARENA_FENCE_PATH, err])
		root.free()
		quit(1)
		return
	err = ResourceSaver.save(scene, ARENA_FENCE_PATH)
	if err != OK:
		push_error("save failed for %s (error %d)" % [ARENA_FENCE_PATH, err])
		root.free()
		quit(1)
		return
	print("  wrote %s (%d fence modules)" % [ARENA_FENCE_PATH, nx * 2 + nz * 2])
	root.free()


func _add_collision_box(body: StaticBody3D, owner_root: Node, shape_name: String, size: Vector3, pos: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var node := CollisionShape3D.new()
	node.name = shape_name
	node.shape = shape
	node.position = pos
	body.add_child(node)
	node.owner = owner_root


func _build_course() -> void:
	push_warning("arena_course.tscn is hand-authored; skipping generated course")


## Turn a compact table into full item dictionaries with resolved asset paths.
func _zone(group: String, rows: Array, assets: Dictionary) -> Array:
	var out: Array = []
	for i in range(rows.size()):
		var row: Array = rows[i]
		var key := String(row[0])
		if not assets.has(key):
			push_error("unknown asset key '%s'" % key)
			quit(1)
			return []
		var display_name := "Prop_%02d" % (i + 1)
		if row.size() == 6:
			display_name = String(row[1])
		var offset := 1 if row.size() == 6 else 0
		out.append({
			"group": group,
			"name": display_name,
			"asset": assets[key],
			"pos": Vector3(float(row[1 + offset]), 0.0, float(row[2 + offset])),
			"yaw": float(row[3 + offset]),
			"scale": float(row[4 + offset]),
		})
	return out


func _build_scene(out_path: String, root_name: String, items: Array) -> void:
	var root := Node3D.new()
	root.name = root_name
	var groups := {}
	for item in items:
		var parent: Node3D = root
		var group_name := String(item["group"])
		if group_name != "":
			if not groups.has(group_name):
				var group := Node3D.new()
				group.name = group_name
				root.add_child(group)
				group.owner = root
				groups[group_name] = group
			parent = groups[group_name]
		var inst := _make_instance(
			String(item["asset"]),
			item["pos"] as Vector3,
			float(item["yaw"]),
			float(item["scale"])
		)
		if inst == null:
			root.free()
			return
		inst.name = String(item["name"])
		parent.add_child(inst)
		inst.owner = root

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed for %s (error %d)" % [out_path, err])
		root.free()
		quit(1)
		return
	err = ResourceSaver.save(packed, out_path)
	if err != OK:
		push_error("save failed for %s (error %d)" % [out_path, err])
		root.free()
		quit(1)
		return
	print("  wrote %s (%d props)" % [out_path, items.size()])
	root.free()


func _make_instance(asset_path: String, pos: Vector3, yaw_deg: float, s: float) -> Node3D:
	var packed := load(asset_path) as PackedScene
	if packed == null:
		push_error("cannot load " + asset_path)
		quit(1)
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		push_error("cannot instantiate " + asset_path)
		quit(1)
		return null
	var baked := inst.transform
	var bounds := _aabb_of(inst)
	if bounds.size.y <= 0.0001:
		push_error("empty bounds for " + asset_path)
		quit(1)
		return null
	if not _measured.has(asset_path):
		_measured[asset_path] = true
		print("  measure %-28s size=%s" % [asset_path.get_file(), str(bounds.size)])

	var centre := bounds.get_center()
	var normalise := Vector3(-centre.x, -bounds.position.y, -centre.z)
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3(s, s, s))
	inst.transform = Transform3D(basis, pos) * Transform3D(Basis(), normalise) * baked
	return inst


## AABB of every MeshInstance3D under node, in the space the node's own
## transform lives in (i.e. the baked root transform is included).
func _aabb_of(root: Node) -> AABB:
	var boxes: Array = []
	_walk_aabb(root, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB()
	var out: AABB = boxes[0]
	for i in range(1, boxes.size()):
		out = out.merge(boxes[i])
	return out


func _walk_aabb(node: Node, xform: Transform3D, boxes: Array) -> void:
	var x := xform
	if node is Node3D:
		x = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			boxes.append(x * mi.mesh.get_aabb())
	for child in node.get_children():
		_walk_aabb(child, x, boxes)
