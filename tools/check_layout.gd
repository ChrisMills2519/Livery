extends SceneTree

## Headless verification for the main level's layout.
##
##   godot --headless --path . --script res://tools/check_layout.gd
##
## The site plan is spread over three files: the paint in
## tools/build_ground_control.py, the dressing in tools/build_scenery.gd and the
## fixtures in scenes/main.tscn.  This check is what keeps them agreed.
##
## It asserts that every station the player can use stands on its own painted
## ground, that no yard prop is left standing on grass, that the lane really
## joins the yard to the arena gate, the schooling ground and the showground
## gate, that the house drive reaches the front door, that no two destinations
## share a doorstep, and that the showground's return spawn still lands at the
## gate the player left from.

const MAIN := "res://scenes/main.tscn"
const ARENA_SCENE := "res://scenes/competition_arena.tscn"
const MATERIAL := "res://resources/materials/terrain_blend.tres"

## The arena's east gate, kept in step with tools/build_ground_control.py's wear
## patch and ARENA_MAX in tools/build_scenery.gd.
const ARENA_GATE := Vector3(-15.0, 0.0, -1.5)
## Where the lane meets the schooling sand.
const SCHOOL_ENTRANCE := Vector3(15.0, 0.0, 10.0)
## Centre of the turnout field (it should stay grass).
const TURNOUT_CENTRE := Vector3(-8.5, 0.0, 12.0)

const DIRT_MIN := 0.35
const LANE_MIN := 0.50
const DOOR_GAP := 6.0
const RETURN_GAP := 6.0
const HORSE_STABLE_RANGE := 12.0

var _control: Image
var _centre := Vector2.ZERO
var _extent := Vector2.ONE
var _failures: Array[String] = []


func _initialize() -> void:
	await _run()
	if _failures.is_empty():
		print("LAYOUT CHECK: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("  FAIL: ", failure)
		print("LAYOUT CHECK: FAIL (%d)" % _failures.size())
		quit(1)


func _run() -> void:
	if not _bind_control():
		return
	var packed := load(MAIN) as PackedScene
	if packed == null:
		_check(false, "%s loads" % MAIN)
		return
	var main := packed.instantiate() as Node3D
	if main == null:
		_check(false, "%s is a Node3D scene" % MAIN)
		return
	root.add_child(main)
	await process_frame
	await process_frame

	_check_stations(main)
	_check_yard_props(main)
	_check_grooming_mat(main)
	_check_lanes()
	_check_doors(main)

	var arch := main.get_node_or_null("ShowgroundArch") as Node3D
	_check(arch != null, "the showground arch is on the level")
	var gate := main.get_node_or_null("ShowgroundGate") as Node3D
	var front_door := main.get_node_or_null("FrontDoor") as Node3D
	var stable_anchor := main.get_node_or_null("Stable/UseAnchor") as Node3D
	var horse := main.get_node_or_null("Horse") as Node3D
	if horse != null and stable_anchor != null:
		var gap := Vector2(horse.global_position.x, horse.global_position.z).distance_to(
			Vector2(stable_anchor.global_position.x, stable_anchor.global_position.z)
		)
		_check(
			gap <= HORSE_STABLE_RANGE,
			"the horse starts within %.0f m of the stable door (got %.1f m)" % [HORSE_STABLE_RANGE, gap]
		)
	if arch != null and gate != null:
		_check(
			Vector2(arch.global_position.x, arch.global_position.z).distance_to(
				Vector2(gate.global_position.x, gate.global_position.z)
			) < 0.5,
			"the showground gate stands under the arch"
		)
	if arch != null and front_door != null:
		_check(
			Vector2(arch.global_position.x, arch.global_position.z).distance_to(
				Vector2(front_door.global_position.x, front_door.global_position.z)
			) > DOOR_GAP,
			"the showground gate and the front door are separate places"
		)
	if arch != null:
		var away := Vector2(arch.global_position.x, arch.global_position.z).distance_to(
			Vector2(ARENA_GATE.x, ARENA_GATE.z)
		)
		_check(
			away > DOOR_GAP,
			"the showground gate no longer sits on the arena gate (got %.1f m)" % away
		)

	_check_turnout(main)
	_check_showground_return(arch)

	main.queue_free()
	await process_frame


# --- paint sampling ---------------------------------------------------------

func _bind_control() -> bool:
	var mat := load(MATERIAL) as ShaderMaterial
	if mat == null:
		_check(false, "%s loads" % MATERIAL)
		return false
	var tex := mat.get_shader_parameter("control_map") as Texture2D
	if tex == null:
		_check(false, "the terrain material has no control map")
		return false
	_control = tex.get_image()
	if _control == null:
		_check(false, "cannot read the control map image")
		return false
	_centre = mat.get_shader_parameter("control_center") as Vector2
	_extent = mat.get_shader_parameter("control_size") as Vector2
	return true


func _sample(world: Vector3) -> Color:
	var local := (Vector2(world.x, world.z) - (_centre - _extent * 0.5)) / _extent
	var x := clampi(int(local.x * _control.get_width()), 0, _control.get_width() - 1)
	var y := clampi(int(local.y * _control.get_height()), 0, _control.get_height() - 1)
	return _control.get_pixel(x, y)


## Dirt plus gravel: the ground the player is meant to stand on.
func _hard(world: Vector3) -> float:
	var c := _sample(world)
	return c.r + c.g


# --- stations and props -----------------------------------------------------

func _check_stations(main: Node3D) -> void:
	var stations := {
		"stable door": "Stable/UseAnchor",
		"stable stall": "Stable/HorseStall",
		"feed trough": "Stable/FeedTrough",
		"feed store": "Stable/FeedStore",
		"grooming bay": "GroomingBay/HorseAnchor",
		"groomer's spot": "GroomingBay/GroomerAnchor",
		"mounting block": "Stable/YardProps/MountingBlock",
		"hitching post": "Stable/YardProps/HitchingPost",
		"water trough": "Stable/YardProps/WaterTrough",
		"house front door": "FrontDoor",
		"showground gate": "ShowgroundGate",
		"player start": "Player",
		"horse start": "Horse",
	}
	for label in stations.keys():
		var node := main.get_node_or_null(String(stations[label])) as Node3D
		if node == null:
			_check(false, "the level has a %s" % label)
			continue
		_check_dirt(label, node.global_position)
	_check_dirt("arena gate", ARENA_GATE)
	_check_dirt("school entrance", SCHOOL_ENTRANCE)


func _check_dirt(label: String, world: Vector3) -> void:
	var weight := _hard(world)
	if weight < DIRT_MIN:
		_failures.append(
			"%s stands on grass (paint %.2f at %.1f, %.1f)" % [label, weight, world.x, world.z]
		)
		return
	print("  %-18s paint %.2f" % [label, weight])


func _check_yard_props(main: Node3D) -> void:
	var yard := main.get_node_or_null("Stable/YardProps") as Node3D
	if yard == null:
		_check(false, "the yard has generated props")
		return
	var on_grass := 0
	var on_lane := 0
	for slot in yard.get_children():
		var slot3d := slot as Node3D
		if slot3d == null:
			continue
		var model := slot3d.get_node_or_null("Model") as Node3D
		if model == null:
			continue
		var at := model.global_position
		var c := _sample(at)
		if c.r + c.g < 0.30:
			on_grass += 1
			_failures.append(
				"yard prop '%s' stands on grass (paint %.2f at %.1f, %.1f)"
				% [String(slot.name), c.r + c.g, at.x, at.z]
			)
		if c.g > 0.35:
			on_lane += 1
			_failures.append(
				"yard prop '%s' stands in the lane (gravel %.2f at %.1f, %.1f)"
				% [String(slot.name), c.g, at.x, at.z]
			)
	if on_grass == 0 and on_lane == 0:
		print("  yard props      %d on hardstanding, none in the lane" % yard.get_child_count())


func _check_grooming_mat(main: Node3D) -> void:
	var bay := main.get_node_or_null("GroomingBay") as Node3D
	if bay == null:
		_check(false, "the level has a grooming bay")
		return
	# The mat is 3.2 x 2.4 m, built in grooming_bay.gd at local (0, 0.025, 0.2).
	var corners := [
		Vector3(-1.6, 0.0, -1.0),
		Vector3(1.6, 0.0, -1.0),
		Vector3(-1.6, 0.0, 1.4),
		Vector3(1.6, 0.0, 1.4),
		Vector3(0.0, 0.0, 0.2),
	]
	for corner in corners:
		var world: Vector3 = bay.global_transform * (corner as Vector3)
		var ground := _sample(world)
		if ground.r < 0.30:
			_failures.append(
				"the grooming mat corner (%.1f, %.1f) is not on the yard (dirt %.2f, gravel %.2f)"
				% [world.x, world.z, ground.r, ground.g]
			)
			return
	print("  grooming mat    fully on hardstanding")


# --- routes -----------------------------------------------------------------

func _check_lanes() -> void:
	var lanes := {
		"lane spine": [
			Vector3(0.0, 0.0, 26.0),
			Vector3(0.0, 0.0, 8.0),
			Vector3(-4.0, 0.0, -2.0),
			Vector3(-5.0, 0.0, -13.0),
		],
		"arena spur": [Vector3(-4.0, 0.0, -1.5), Vector3(-15.5, 0.0, -1.5)],
		"school spur": [Vector3(0.0, 0.0, 8.0), Vector3(15.0, 0.0, 10.0)],
		"house drive": [
			Vector3(16.0, 0.0, -27.0),
			Vector3(26.0, 0.0, -29.0),
			Vector3(37.0, 0.0, -31.0),
		],
	}
	for lane_name in lanes.keys():
		var points: Array = lanes[lane_name]
		var worst := 1.0
		var worst_at := Vector3.ZERO
		for i in range(points.size() - 1):
			var a: Vector3 = points[i]
			var b: Vector3 = points[i + 1]
			var steps := maxi(2, int(ceil(a.distance_to(b))))
			for step in range(steps + 1):
				var t := float(step) / float(steps)
				var at := a.lerp(b, t)
				# The painted ends feather out, so judge the run itself.
				if t <= 0.02 or t >= 0.98:
					continue
				var weight := _hard(at)
				if weight < worst:
					worst = weight
					worst_at = at
		if worst < LANE_MIN:
			_failures.append(
				"%s is not continuous (paint %.2f at %.1f, %.1f)"
				% [lane_name, worst, worst_at.x, worst_at.z]
			)
		else:
			print("  %-14s continuous, worst paint %.2f" % [lane_name, worst])


func _check_doors(main: Node3D) -> void:
	var doors: Array[String] = []
	for child in main.get_children():
		if child is Node3D and child.get_script() != null:
			var path := String((child as Node).get_script().resource_path)
			if path.ends_with("scene_door.gd"):
				doors.append(String(child.name))
	_check(doors.size() >= 2, "the level has both its destination doors")
	for i in range(doors.size()):
		for j in range(i + 1, doors.size()):
			var a := main.get_node_or_null(doors[i]) as Node3D
			var b := main.get_node_or_null(doors[j]) as Node3D
			if a == null or b == null:
				continue
			var gap := Vector2(a.global_position.x, a.global_position.z).distance_to(
				Vector2(b.global_position.x, b.global_position.z)
			)
			_check(
				gap > DOOR_GAP,
				"%s and %s do not share a doorstep (got %.1f m)" % [doors[i], doors[j], gap]
			)


func _check_turnout(main: Node3D) -> void:
	var paddock := main.get_node_or_null("TurnoutPaddock") as Node3D
	if paddock == null:
		_check(false, "the level has its turnout field")
		return
	var ground := _sample(TURNOUT_CENTRE)
	_check(
		ground.r + ground.g < 0.25,
		"the turnout field stays grass (paint %.2f)" % (ground.r + ground.g)
	)
	_check(paddock.get_child_count() > 5, "the turnout field is fenced and dressed")
	print("  turnout field   %d nodes" % paddock.get_child_count())


## The showground's exit drops the player back at the gate they left from.  A
## moved gate with a stale spawn is the classic way to land in a hedge.
func _check_showground_return(arch: Node3D) -> void:
	var packed := load(ARENA_SCENE) as PackedScene
	if packed == null:
		_check(false, "%s loads" % ARENA_SCENE)
		return
	var arena := packed.instantiate() as Node3D
	if arena == null:
		_check(false, "%s is a Node3D scene" % ARENA_SCENE)
		return
	var door := arena.get_node_or_null("ExitDoor") as Node3D
	if door == null:
		_check(false, "the showground has an exit door")
		arena.free()
		return
	var spawn: Vector3 = door.get("spawn_position")
	if arch != null:
		var gap := Vector2(spawn.x, spawn.z).distance_to(
			Vector2(arch.global_position.x, arch.global_position.z)
		)
		_check(
			gap <= RETURN_GAP,
			"the showground returns the player to its gate (spawn %.1f m away)" % gap
		)
	_check_dirt("showground return", spawn)
	arena.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
