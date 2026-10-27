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
const YARD_PATH := "res://scenes/stable_yard_props.tscn"
const COURSE_PATH := "res://scenes/arena_course.tscn"
const ARENA_FENCE_PATH := "res://scenes/arena_fence.tscn"
const TURNOUT_PATH := "res://scenes/turnout_paddock.tscn"

## The turnout field between the lane and the arena rail.  Walloped on three
## sides with the arena fence module, with a gate gap facing the arena spur.
const TURNOUT_MIN := Vector2(-13.0, 4.0)
const TURNOUT_MAX := Vector2(-4.0, 20.0)
const TURNOUT_GATE_MIN_X := -10.0
const TURNOUT_GATE_MAX_X := -6.5
const TURNOUT_FENCE_HEIGHT := 1.32

const SPLIT := "res://Models/split/"
const PROPS := "res://Models/props/"
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

## Species keys used by the forest belts. The prop-library trees are authored at
## real-world scale with their origin on the ground, so the scales here are close
## to 1 (5-9 m trees).
const TREES := {
	"a": PROPS + "trees/tree_oak_02.glb",
	"b": PROPS + "trees/tree_birch.glb",
	"c": PROPS + "trees/tree_apple.glb",
	"d": PROPS + "trees/tree_pine_01.glb",
	"e": PROPS + "trees/tree_willow.glb",
	"f": PROPS + "trees/tree_oak_01.glb",
	"g": PROPS + "trees/tree_oak_03.glb",
	"h": PROPS + "trees/tree_pine_02.glb",
	"autumn": PROPS + "trees/tree_oak_autumn.glb",
	"dead": PROPS + "trees/tree_dead.glb",
	"sapling": PROPS + "trees/tree_sapling.glb",
}

## Nature scatter from the prop library, again real-world scale.
const NATURE := {
	"n0": PROPS + "nature/grass_tuft.glb",
	"n1": PROPS + "nature/grass_tuft_small.glb",
	"n2": PROPS + "nature/rock_cluster_01.glb",
	"n3": PROPS + "nature/rock_cluster_02.glb",
	"n4": PROPS + "nature/flower_patch.glb",
	"n5": PROPS + "nature/reeds.glb",
	"n6": PROPS + "bushes/bush_round.glb",
	"n7": PROPS + "bushes/bush_large.glb",
	"n8": PROPS + "nature/mushroom_cluster.glb",
	"n9": PROPS + "trees/tree_stump.glb",
	"n10": PROPS + "trees/fallen_log.glb",
	"n11": PROPS + "bushes/bush_flower.glb",
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

## Working stable yard, replacing the old medieval loose props.  Positions keep
## the yard's door, mount anchor, feed trough and path clear.  `lift` raises a
## prop (stacked crate, blanket on the rack, hanging net); `collide` adds a
## measured box collider so the player cannot walk through the big items.
const YARD_LAYOUT := [
	# Hay and feed stored along the yard's west boundary, clear of the working
	# square and of the lane that arrives from the south.  These used to stand in
	# the middle of the yard between the paddock and the well.
	{"name": "HayRoundA", "asset": "stable/hay_round.glb", "pos": Vector3(-13.8, 0.0, -16.4), "yaw": 12.0, "collide": true},
	{"name": "HayRoundB", "asset": "stable/hay_round.glb", "pos": Vector3(-14.3, 0.0, -17.9), "yaw": 74.0, "collide": true},
	{"name": "HaySquare", "asset": "stable/hay_square.glb", "pos": Vector3(-13.2, 0.0, -19.0), "yaw": -18.0, "collide": true},
	{"name": "BarrelA", "asset": "yard/barrel.glb", "pos": Vector3(-12.6, 0.0, -16.6), "yaw": 0.0, "collide": true},
	{"name": "BarrelB", "asset": "yard/barrel.glb", "pos": Vector3(-12.4, 0.0, -17.4), "yaw": 40.0, "collide": true},
	# Crates and the barrow below the feed store, still against the west wall.
	{"name": "CrateA", "asset": "yard/crate.glb", "pos": Vector3(-13.9, 0.0, -20.8), "yaw": 12.0, "collide": true},
	{"name": "CrateB", "asset": "yard/crate.glb", "pos": Vector3(-13.85, 0.0, -20.85), "yaw": 32.0, "lift": 0.64, "collide": true},
	{"name": "Wheelbarrow", "asset": "yard/wheelbarrow.glb", "pos": Vector3(-14.2, 0.0, -22.2), "yaw": -38.0, "collide": true},
	{"name": "Bench", "asset": "yard/bench.glb", "pos": Vector3(-9.8, 0.0, -20.7), "yaw": 90.0, "collide": true},
	{"name": "Well", "asset": "yard/well.glb", "pos": Vector3(12.9, 0.0, -17.8), "yaw": 15.0, "scale": 0.9, "collide": true},
	# Stable kit: trough, mounting block, hitching post, saddle rack and tools.
	{"name": "WaterTrough", "asset": "stable/water_trough.glb", "pos": Vector3(6.4, 0.0, -22.3), "yaw": 90.0, "collide": true},
	{"name": "MountingBlock", "asset": "stable/mounting_block.glb", "pos": Vector3(-8.6, 0.0, -21.9), "yaw": 90.0, "collide": true},
	{"name": "HitchingPost", "asset": "stable/hitching_post.glb", "pos": Vector3(-3.5, 0.0, -21.7), "yaw": 0.0, "collide": true},
	{"name": "SaddleRack", "asset": "stable/saddle_rack.glb", "pos": Vector3(-12.15, 0.0, -22.75), "yaw": 90.0, "collide": true},
	{"name": "SaddleBlanket", "asset": "stable/saddle_blanket.glb", "pos": Vector3(-12.15, 0.0, -22.75), "yaw": 90.0, "lift": 0.70},
	{"name": "GroomingTote", "asset": "stable/grooming_tote.glb", "pos": Vector3(-11.75, 0.0, -22.05), "yaw": 20.0},
	{"name": "FeedBucket", "asset": "stable/feed_bucket.glb", "pos": Vector3(-5.5, 0.0, -22.55), "yaw": 0.0},
	{"name": "WaterBucket", "asset": "stable/water_bucket.glb", "pos": Vector3(-4.95, 0.0, -22.4), "yaw": 35.0},
	{"name": "Carrots", "asset": "stable/carrot_bunch.glb", "pos": Vector3(-5.45, 0.0, -22.55), "yaw": 0.0, "lift": 0.30},
	{"name": "FeedSack", "asset": "stable/feed_sack.glb", "pos": Vector3(-6.3, 0.0, -22.2), "yaw": 25.0},
	{"name": "Pitchfork", "asset": "stable/pitchfork.glb", "pos": Vector3(-2.3, 0.0, -24.35), "yaw": 90.0},
	{"name": "Broom", "asset": "stable/broom.glb", "pos": Vector3(-2.3, 0.0, -22.65), "yaw": 85.0},
	{"name": "MuckTub", "asset": "stable/muck_tub.glb", "pos": Vector3(-8.9, 0.0, -19.85), "yaw": 0.0, "collide": true},
	{"name": "HayNet", "asset": "stable/hay_net.glb", "pos": Vector3(-2.12, 0.0, -23.85), "yaw": 0.0, "lift": 1.55},
	{"name": "LeadRope", "asset": "stable/lead_rope.glb", "pos": Vector3(-3.0, 0.0, -21.9), "yaw": 0.0, "lift": 1.0},
	# Yard dressing and the path to the gate.
	{"name": "Signpost", "asset": "yard/signpost.glb", "pos": Vector3(-14.1, 0.0, -15.2), "yaw": -20.0, "scale": 0.85, "collide": true},
	{"name": "LanternA", "asset": "yard/lantern_post.glb", "pos": Vector3(-10.3, 0.0, -19.2), "yaw": 0.0, "collide": true},
	{"name": "LanternB", "asset": "yard/lantern_post.glb", "pos": Vector3(14.9, 0.0, -20.6), "yaw": 0.0, "collide": true},
	{"name": "PlanterA", "asset": "yard/flower_planter.glb", "pos": Vector3(-1.6, 0.0, -21.7), "yaw": 0.0},
	{"name": "PlanterB", "asset": "yard/flower_planter.glb", "pos": Vector3(-12.0, 0.0, -20.2), "yaw": 0.0},
	{"name": "AppleBasket", "asset": "yard/apple_basket.glb", "pos": Vector3(-5.9, 0.0, -20.9), "yaw": 0.0},
	{"name": "Firewood", "asset": "yard/firewood_stack.glb", "pos": Vector3(-12.25, 0.0, -24.2), "yaw": 90.0, "collide": true},
]

var _measured := {}


func _initialize() -> void:
	print("=== BUILD SCENERY ===")
	_build_forest()
	_build_nature()
	_build_yard()
	_build_arena_fence()
	_build_turnout()
	_build_course()
	print("=== DONE ===")
	quit(0)


func _build_forest() -> void:
	var items: Array = []
	# North belt, behind the stable.
	items.append_array(_zone("North", [
		["h", -46.0, -50.0, 15.0, 1.05],
		["b", -34.0, -48.0, 70.0, 1.05],
		["e", -20.0, -52.0, 120.0, 1.05],
		["d", -8.0, -47.0, 200.0, 1.15],
		["h", 4.0, -52.0, 250.0, 1.00],
		["c", 16.0, -49.0, 320.0, 1.00],
		["f", 28.0, -51.0, 40.0, 1.05],
		["d", 38.0, -47.0, 160.0, 1.10],
		["g", 46.0, -53.0, 90.0, 1.20],
	], TREES))
	# West belt, outside the wide arena rail at x = -50.
	items.append_array(_zone("West", [
		["h", -57.0, -28.0, 30.0, 1.00],
		["a", -59.0, -14.0, 100.0, 1.10],
		["f", -56.0, 0.0, 190.0, 1.05],
		["a", -61.0, 12.0, 270.0, 1.10],
		["d", -55.0, 24.0, 340.0, 1.15],
	], TREES))
	# East grove, beyond the training ground.
	items.append_array(_zone("East", [
		["h", 66.0, -26.0, 60.0, 1.05],
		["a", 72.0, -14.0, 130.0, 1.10],
		["f", 64.0, -2.0, 200.0, 1.05],
		["h", 76.0, 8.0, 270.0, 1.10],
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
		["autumn", 16.0, -22.0, 45.0, 1.00],
		["dead", -16.0, -36.0, 135.0, 1.00],
		["sapling", 20.0, 22.0, 225.0, 1.20],
	], TREES))
	# Middle ground.  The belts above sit 50-75 m out, which is why the site used
	# to read as one clump of props on a lawn: nothing framed the eye between the
	# 15 m the camera can see and the horizon.  These sit 8-35 m away.
	items.append_array(_zone("Midground", [
		# Behind the stable and paddock; they read over the roofs from the yard.
		["a", -14.0, -33.0, 20.0, 1.05],
		["f", -4.0, -35.0, 95.0, 1.10],
		["b", 5.0, -33.0, 160.0, 1.00],
		["h", 13.0, -36.0, 250.0, 1.10],
		# The yard approach between the arena rail and the lane.
		["c", -11.0, -6.0, 40.0, 1.00],
		["autumn", -13.0, 2.0, 310.0, 1.00],
		# The lane's east verge, on the walk to the showground gate.
		["d", 9.0, 12.0, 15.0, 1.00],
		["g", 10.0, 20.0, 200.0, 1.05],
		# Framing the schooling ground.
		["b", 17.0, -17.5, 130.0, 1.00],
		["a", 18.0, 18.0, 260.0, 1.10],
		["f", 58.0, 2.0, 60.0, 1.05],
		# A loose orchard in the south meadow.
		["c", 12.0, 30.0, 10.0, 1.10],
		["c", 20.0, 26.0, 70.0, 1.05],
		["c", 27.0, 30.0, 190.0, 1.10],
		["autumn", 24.0, 20.0, 300.0, 1.00],
		# The house garden, either side of the new drive.
		["b", 33.5, -27.4, 35.0, 1.00],
		["g", 40.8, -27.2, 220.0, 1.05],
		["d", 34.0, -38.0, 120.0, 1.15],
		["a", 43.0, -37.0, 280.0, 1.10],
	], TREES))
	_build_scene(FOREST_PATH, "Forest", items)


func _build_nature() -> void:
	var items: Array = []
	# Verge dressing follows the lane, which now bends west to meet the stable
	# door instead of running dead straight into the paddock fence.
	items.append_array(_zone("Path", [
		["n0", -7.6, -8.0, 0.0, 1.4],
		["n4", -1.4, -5.0, 60.0, 1.0],
		["n5", 3.2, 2.0, 120.0, 1.1],
		["n0", -3.6, 12.0, 180.0, 1.3],
		["n4", 3.4, 16.0, 240.0, 1.1],
		["n8", -3.4, 21.0, 300.0, 1.0],
	], NATURE))
	items.append_array(_zone("Yard", [
		["n6", -11.5, -28.5, 30.0, 1.0],
		["n2", 11.5, -29.0, 90.0, 1.0],
		["n9", -11.5, -15.5, 150.0, 1.0],
		["n1", 11.8, -15.2, 210.0, 1.6],
	], NATURE))
	items.append_array(_zone("Paddock", [
		["n10", -0.6, -27.0, 0.0, 1.0],
		["n11", 12.2, -24.0, 100.0, 1.0],
		["n10", 12.2, -21.0, 200.0, 1.0],
		["n11", -0.6, -22.0, 260.0, 1.0],
	], NATURE))
	items.append_array(_zone("ArenaEdge", [
		["n3", -53.5, -14.0, 45.0, 1.0],
		["n6", -54.0, 0.0, 135.0, 1.0],
		["n2", -53.5, 14.0, 225.0, 1.0],
		["n9", -53.0, 30.0, 315.0, 1.0],
	], NATURE))
	items.append_array(_zone("TrainingEdge", [
		["n0", 16.0, -12.0, 20.0, 1.3],
		["n5", 16.0, 2.0, 110.0, 1.1],
		["n4", 16.0, 12.0, 200.0, 1.0],
		["n7", 54.0, -13.0, 290.0, 1.0],
	], NATURE))
	# Hedge lines are the cheapest way to bound open ground: they stop the eye at
	# 10-20 m and turn bare grass into fields.
	items.append_array(_zone("Hedgerows", [
		# The lane's east verge, on the way to the showground gate.
		["n7", 4.4, 10.0, 0.0, 1.1],
		["n6", 4.6, 13.0, 40.0, 1.4],
		["n7", 4.3, 16.0, 90.0, 1.2],
		["n6", 4.7, 19.0, 135.0, 1.5],
		["n7", 4.4, 22.0, 180.0, 1.1],
		# The turnout field's south boundary.
		["n7", -12.0, 21.3, 20.0, 1.2],
		["n6", -9.3, 21.6, 70.0, 1.5],
		["n7", -6.6, 21.2, 110.0, 1.2],
		["n6", -4.6, 21.5, 160.0, 1.4],
		# Between the house drive and the schooling ground.
		["n7", 20.0, -20.0, 15.0, 1.2],
		["n6", 23.5, -20.4, 55.0, 1.5],
		["n7", 27.0, -20.0, 95.0, 1.2],
		["n6", 30.5, -20.5, 140.0, 1.4],
		# The house frontage: flowering hedges and beds either side of the door.
		["n11", 33.6, -25.8, 30.0, 1.3],
		["n11", 40.4, -25.6, 80.0, 1.2],
		["n4", 33.9, -29.6, 20.0, 1.1],
		["n4", 40.1, -29.4, 140.0, 1.0],
	], NATURE))
	# The south meadow, west of the orchard.
	items.append_array(_zone("Meadow", [
		["n0", 10.0, 24.0, 10.0, 1.3],
		["n4", 14.0, 28.0, 70.0, 1.0],
		["n1", 22.0, 32.0, 130.0, 1.5],
		["n4", 28.0, 24.0, 190.0, 1.1],
		["n6", 31.0, 29.0, 250.0, 1.2],
		["n0", 16.0, 19.0, 310.0, 1.2],
		["n3", 33.0, 33.0, 20.0, 1.0],
		["n1", 26.0, 17.0, 280.0, 1.3],
	], NATURE))
	_build_scene(NATURE_PATH, "NatureProps", items)


## Writes the stable yard dressing as its own scene so stable.tscn only holds
## one instance.  Colliders are measured from the same AABB used to seat the
## prop, so a prop can never float or have a mismatched collision box.
func _build_yard() -> void:
	var root := Node3D.new()
	root.name = "YardProps"
	var colliders := 0
	for row in YARD_LAYOUT:
		var slot := Node3D.new()
		slot.name = String(row["name"])
		slot.position = (row["pos"] as Vector3) + Vector3(0.0, float(row.get("lift", 0.0)), 0.0)
		root.add_child(slot)
		slot.owner = root

		var inst := _make_instance(
			PROPS + String(row["asset"]),
			Vector3.ZERO,
			float(row["yaw"]),
			float(row.get("scale", 1.0))
		)
		if inst == null:
			root.free()
			return
		inst.name = "Model"
		slot.add_child(inst)
		inst.owner = root

		if bool(row.get("collide", false)):
			var bounds := _aabb_of(inst)
			var body := StaticBody3D.new()
			body.name = "Body"
			slot.add_child(body)
			body.owner = root
			var size := Vector3(
				maxf(0.05, bounds.size.x - 0.02),
				maxf(0.05, bounds.size.y - 0.02),
				maxf(0.05, bounds.size.z - 0.02)
			)
			_add_collision_box(body, root, "Shape", size, bounds.get_center())
			colliders += 1

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed for %s (error %d)" % [YARD_PATH, err])
		root.free()
		quit(1)
		return
	err = ResourceSaver.save(packed, YARD_PATH)
	if err != OK:
		push_error("save failed for %s (error %d)" % [YARD_PATH, err])
		root.free()
		quit(1)
		return
	print("  wrote %s (%d props, %d colliders)" % [YARD_PATH, YARD_LAYOUT.size(), colliders])
	root.free()


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


## Builds the turnout field as its own scene: three fenced runs with a gate gap
## facing the arena spur, an open gate leaf, a water trough and a hay ring.
## Fence modules come from the same measured model the arena uses, so the two
## paddocks on the site read as one hand.
func _build_turnout() -> void:
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
		push_error("turnout fence module has no length")
		quit(1)
		return

	var root := Node3D.new()
	root.name = "TurnoutPaddock"

	var body := StaticBody3D.new()
	body.name = "TurnoutCollision"
	root.add_child(body)
	body.owner = root

	# start x, start z, end x, end z, label, runs along X.
	var runs := [
		[TURNOUT_MIN.x, TURNOUT_MAX.y, TURNOUT_MAX.x, TURNOUT_MAX.y, "South", true],
		[TURNOUT_MIN.x, TURNOUT_MIN.y, TURNOUT_MIN.x, TURNOUT_MAX.y, "West", false],
		[TURNOUT_MAX.x, TURNOUT_MIN.y, TURNOUT_MAX.x, TURNOUT_MAX.y, "East", false],
		[TURNOUT_MIN.x, TURNOUT_MIN.y, TURNOUT_GATE_MIN_X, TURNOUT_MIN.y, "NorthWest", true],
		[TURNOUT_GATE_MAX_X, TURNOUT_MIN.y, TURNOUT_MAX.x, TURNOUT_MIN.y, "NorthEast", true],
	]
	var modules := 0
	for row in runs:
		var a := Vector2(float(row[0]), float(row[1]))
		var b := Vector2(float(row[2]), float(row[3]))
		var label := String(row[4])
		var horizontal := bool(row[5])
		var span := b - a
		var length := span.length()
		var count := maxi(1, ceili(length / module_length))
		var step := length / float(count)
		var dir := span / length
		for i in range(count):
			var centre := a + dir * (step * (i + 0.5))
			var inst := _make_instance(
				ARENA_FENCE_MODEL,
				Vector3(centre.x, 0.0, centre.y),
				0.0 if horizontal else 90.0,
				ARENA_FENCE_SCALE
			)
			if inst == null:
				root.free()
				return
			inst.name = "Fence%s%d" % [label, i]
			root.add_child(inst)
			inst.owner = root
			modules += 1
		var mid := (a + b) * 0.5
		var centre_y := TURNOUT_FENCE_HEIGHT * 0.5
		if horizontal:
			_add_collision_box(body, root, "%sShape" % label,
				Vector3(length + 0.3, TURNOUT_FENCE_HEIGHT, 0.30),
				Vector3(mid.x, centre_y, mid.y))
		else:
			_add_collision_box(body, root, "%sShape" % label,
				Vector3(0.30, TURNOUT_FENCE_HEIGHT, length + 0.3),
				Vector3(mid.x, centre_y, mid.y))

	# A five-bar gate standing open against the west edge of the gap, so the
	# field can be entered from the arena spur without a gate script.
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.34, 0.24, 0.14, 1.0)
	wood.roughness = 0.9
	for i in range(3):
		var rail := MeshInstance3D.new()
		rail.name = "GateRail%d" % i
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(0.07, 0.09, 2.90)
		rail.mesh = rail_mesh
		rail.material_override = wood
		rail.position = Vector3(TURNOUT_GATE_MIN_X - 0.05, 0.34 + i * 0.32, TURNOUT_MIN.y + 1.55)
		root.add_child(rail)
		rail.owner = root
	for i in range(2):
		var stile := MeshInstance3D.new()
		stile.name = "GateStile%d" % i
		var stile_mesh := BoxMesh.new()
		stile_mesh.size = Vector3(0.09, 1.10, 0.09)
		stile.mesh = stile_mesh
		stile.material_override = wood
		stile.position = Vector3(
			TURNOUT_GATE_MIN_X - 0.05,
			0.55,
			TURNOUT_MIN.y + 0.12 + i * 2.86
		)
		root.add_child(stile)
		stile.owner = root

	# Field furniture: a trough and a hay ring in the far corner, away from the
	# gate and the hedge line.
	var trough_slot := Node3D.new()
	trough_slot.name = "WaterTrough"
	trough_slot.position = Vector3(-11.4, 0.0, 17.2)
	root.add_child(trough_slot)
	trough_slot.owner = root
	var trough := _make_instance(PROPS + "stable/water_trough.glb", Vector3.ZERO, 90.0, 1.0)
	if trough == null:
		root.free()
		return
	trough.name = "Model"
	trough_slot.add_child(trough)
	trough.owner = root
	var trough_bounds := _aabb_of(trough)
	var trough_body := StaticBody3D.new()
	trough_body.name = "Body"
	trough_slot.add_child(trough_body)
	trough_body.owner = root
	_add_collision_box(trough_body, root, "Shape",
		Vector3(
			maxf(0.05, trough_bounds.size.x - 0.02),
			maxf(0.05, trough_bounds.size.y - 0.02),
			maxf(0.05, trough_bounds.size.z - 0.02)
		),
		trough_bounds.get_center())

	var hay := _make_instance(PROPS + "stable/hay_round.glb", Vector3(-6.4, 0.0, 17.0), 20.0, 1.0)
	if hay == null:
		root.free()
		return
	hay.name = "HayRing"
	root.add_child(hay)
	hay.owner = root

	var scene := PackedScene.new()
	var err := scene.pack(root)
	if err != OK:
		push_error("pack failed for %s (error %d)" % [TURNOUT_PATH, err])
		root.free()
		quit(1)
		return
	err = ResourceSaver.save(scene, TURNOUT_PATH)
	if err != OK:
		push_error("save failed for %s (error %d)" % [TURNOUT_PATH, err])
		root.free()
		quit(1)
		return
	print("  wrote %s (%d fence modules, %d runs)" % [TURNOUT_PATH, modules, runs.size()])
	root.free()


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
