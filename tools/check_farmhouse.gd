extends SceneTree

## Headless verification for the farmhouse interior.
##
##   godot --headless --path . --script res://tools/check_farmhouse.gd
##
## Covers what a walkthrough would catch: floors under every room on both
## storeys, doorways that are actually open while the wall beside them is not,
## window openings open to the outside, a stair that can be walked, furniture
## in every room, and sitting / resting through the player's own API.

const SCENE := "res://scenes/farmhouse.tscn"

const GROUND := 0.0
const UPPER := 2.72

# room name, centre x, centre z, floor base
const ROOMS := [
	["sitting", -2.05, -2.25, GROUND],
	["kitchen", -2.05, 2.25, GROUND],
	["hall", 3.45, 0.0, GROUND],
	["study", 3.45, -3.35, GROUND],
	["boot", 3.45, 3.35, GROUND],
	["main_bed", -2.05, -2.25, UPPER],
	["second_bed", -2.05, 2.25, UPPER],
	["landing", 3.45, -3.35, UPPER],
	["bath", 3.45, 3.35, UPPER],
	["gallery", 3.20, 0.60, UPPER],
]

# Interior doorways.  "axis" is the direction the wall runs, "plane" is the
# other coordinate: a z-wall sits at x = plane, an x-wall at z = plane.
const DOORS := [
	["sitting_hall", "z", 1.40, -0.60, GROUND, 2.05],
	["kitchen_hall", "z", 1.40, 1.00, GROUND, 2.05],
	["sitting_kitchen", "x", 0.00, -2.20, GROUND, 2.30],
	["study_hall", "x", -2.20, 2.50, GROUND, 2.05],
	["boot_hall", "x", 2.20, 4.20, GROUND, 2.05],
	["main_bed", "z", 1.40, -1.30, UPPER, UPPER + 2.05],
	["second_bed", "z", 1.40, 0.60, UPPER, UPPER + 2.05],
	["bath", "x", 2.20, 4.20, UPPER, UPPER + 2.05],
]

# Windows. axis, plane, centre, sill, head
const WINDOWS := [
	["x", -4.50, -3.95, 0.95, 2.10],
	["x", -4.50, -1.35, 0.95, 2.10],
	["x", -4.50, 4.15, 0.95, 2.10],
	["x", 4.50, -4.35, 1.10, 2.10],
	["z", -5.50, -1.05, 0.95, 2.10],
	["z", -5.50, 2.65, 1.05, 2.10],
	["z", 5.50, -3.50, 1.15, 2.10],
	["z", 5.50, 0.10, 1.20, 2.10],
	["z", 5.50, 3.30, 1.20, 2.10],
	["x", -4.50, -3.85, 3.67, 4.67],
	["x", -4.50, -1.25, 3.67, 4.67],
	["x", -4.50, 4.15, 3.67, 4.67],
	["x", 4.50, -3.90, 3.67, 4.67],
	["x", 4.50, 4.35, 3.87, 4.57],
	["z", -5.50, -1.20, 3.67, 4.67],
	["z", -5.50, 2.40, 3.67, 4.67],
	["z", 5.50, 0.90, 3.67, 4.67],
	["z", 5.50, -3.40, 3.67, 4.67],
]

# Furniture must be present in every room.  name, min x, min z, max x, max z.
# Points that must be inside a wall on both storeys.
const SOLID := [
	["z", 1.40, 3.60, GROUND],
	["z", 1.40, -3.50, GROUND],
	["x", 0.00, -4.40, GROUND],
	["x", -2.20, 3.60, GROUND],
	["x", 2.20, 2.20, GROUND],
	["z", 1.40, 3.60, UPPER],
	["x", 2.20, 2.20, UPPER],
	["z", -5.50, -3.60, GROUND],
	["x", -4.50, 0.90, GROUND],
]

const FURNISHED := [
	["sitting", -5.5, -4.5, 1.4, 0.0, 3],
	["kitchen", -5.5, 0.0, 1.4, 4.5, 4],
	["hall", 1.4, -2.2, 5.5, 2.2, 2],
	["study", 1.4, -4.5, 5.5, -2.2, 2],
	["boot", 1.4, 2.2, 5.5, 4.5, 2],
	["main_bed", -5.5, -4.5, 1.4, 0.0, 3],
	["second_bed", -5.5, 0.0, 1.4, 4.5, 3],
	["bath", 1.4, 2.2, 5.5, 4.5, 3],
	["landing", 1.4, -4.5, 5.5, -2.2, 1],
]

var _failures: Array[String] = []
var _world: Node3D
var _player: CharacterBody3D
var _space: PhysicsDirectSpaceState3D


func _initialize() -> void:
	await _run()
	if _failures.is_empty():
		print("FARMHOUSE CHECK: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("  FAIL: ", failure)
		print("FARMHOUSE CHECK: FAIL (%d)" % _failures.size())
		quit(1)


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		_check(false, "farmhouse scene loads")
		return
	_world = packed.instantiate() as Node3D
	root.add_child(_world)
	await _frames(20)
	_space = _world.get_world_3d().direct_space_state
	_player = _world.get_node_or_null("Player") as CharacterBody3D
	_check(_player != null, "the scene has a player")
	if _player == null:
		return
	_check(_player.global_position.y < 0.2, "the player starts on the ground floor (y %.2f)" % _player.global_position.y)

	var exit_door := _world.get_node_or_null("FrontDoorExit")
	_check(exit_door != null, "the front door has an exit link")
	if exit_door != null:
		_check(
			String(exit_door.get("target_scene")) == "res://scenes/main.tscn",
			"the front door exit returns to main.tscn"
		)

	_check_rooms()
	_check_doors()
	_check_solid_walls()
	_check_windows()
	_check_stairs()
	_check_furniture()
	_check_lighting()
	await _check_seats()
	await _check_stair_guards()
	await _check_walking_up()


# --- shell ------------------------------------------------------------------

func _check_rooms() -> void:
	for room in ROOMS:
		var centre := Vector3(room[1], room[3] + 2.2, room[2])
		var hit := _ray(centre, centre - Vector3.UP * (2.6))
		if hit.is_empty():
			_check(false, "%s has a floor" % room[0])
			continue
		var floor_y: float = (hit["position"] as Vector3).y
		_check(absf(floor_y - float(room[3])) < 0.06, "%s floor is at %.2f (got %.2f)" % [room[0], room[3], floor_y])


func _check_doors() -> void:
	for door in DOORS:
		var axis: String = door[1]
		var plane: float = door[2]
		var centre: float = door[3]
		var base: float = door[4]
		var head: float = door[5]
		var y := (base + head) * 0.5
		var inside := Vector3(plane - 1.2, y, centre) if axis == "z" else Vector3(centre, y, plane - 1.2)
		var outside := Vector3(plane + 1.2, y, centre) if axis == "z" else Vector3(centre, y, plane + 1.2)
		# Walls and furniture both count here: nothing may block a doorway.
		_check(_ray(inside, outside, 5).is_empty(), "doorway %s is open" % door[0])




func _check_solid_walls() -> void:
	for wall in SOLID:
		var axis: String = wall[0]
		var plane: float = wall[1]
		var along: float = wall[2]
		var y: float = float(wall[3]) + 1.2
		var a := Vector3(plane - 1.2, y, along) if axis == "z" else Vector3(along, y, plane - 1.2)
		var b := Vector3(plane + 1.2, y, along) if axis == "z" else Vector3(along, y, plane + 1.2)
		_check(not _ray(a, b).is_empty(), "wall %s at %.2f/%.2f is solid" % [axis, plane, along])


func _check_windows() -> void:
	for window in WINDOWS:
		var axis: String = window[0]
		var plane: float = window[1]
		var centre: float = window[2]
		var y := (float(window[3]) + float(window[4])) * 0.5
		var outside := Vector3(plane + 1.5, y, centre) if axis == "z" else Vector3(centre, y, plane + 1.5)
		var inside := Vector3(plane - 1.5, y, centre) if axis == "z" else Vector3(centre, y, plane - 1.5)
		var label := "%s window at %.1f/%.1f" % [axis, plane, centre]
		_check(_ray(outside, inside, 5).is_empty(), "%s is open to the outside" % label)


func _check_stairs() -> void:
	# Lower flight: south along the east wall, floor to LANDING.
	for i in range(6):
		var t := (float(i) + 0.5) / 6.0
		var z := lerpf(0.85, -1.14, t)
		var expected := 1.088 * t
		var hit := _ray(Vector3(4.85, expected + 1.2, z), Vector3(4.85, expected - 0.4, z))
		if hit.is_empty():
			_check(false, "lower flight has a surface at z %.2f" % z)
			continue
		var y: float = (hit["position"] as Vector3).y
		_check(absf(y - expected) < 0.16, "lower flight rises at z %.2f (expected %.2f, got %.2f)" % [z, expected, y])

	var landing := _ray(Vector3(4.85, 2.4, -1.65), Vector3(4.85, 0.6, -1.65))
	if landing.is_empty():
		_check(false, "the quarter landing has a floor")
	else:
		var y: float = (landing["position"] as Vector3).y
		_check(absf(y - 1.088) < 0.06, "the quarter landing is at 1.09 (got %.2f)" % y)

	# Upper flight: west along the south wall, LANDING to the first floor.
	for i in range(6):
		var t := (float(i) + 0.5) / 6.0
		var x := lerpf(4.35, 2.36, t)
		var expected := lerpf(1.088, UPPER, t)
		var hit := _ray(Vector3(x, expected + 1.2, -1.64), Vector3(x, expected - 0.4, -1.64))
		if hit.is_empty():
			_check(false, "upper flight has a surface at x %.2f" % x)
			continue
		var y: float = (hit["position"] as Vector3).y
		_check(absf(y - expected) < 0.16, "upper flight rises at x %.2f (expected %.2f, got %.2f)" % [x, expected, y])

	var top := _ray(Vector3(2.0, UPPER + 1.2, -1.64), Vector3(2.0, UPPER - 0.4, -1.64))
	if top.is_empty():
		_check(false, "the top of the stairs opens onto a landing")
	else:
		var y: float = (top["position"] as Vector3).y
		_check(absf(y - UPPER) < 0.06, "the top landing is at first-floor height (got %.2f)" % y)


## The gallery edges around the well have to stop a player, not just look like
## rails: walk at each one and stay on the floor.
func _check_stair_guards() -> void:
	# Walk south into the well edge from the gallery.
	_player.global_position = Vector3(4.00, UPPER + 0.05, -0.60)
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	await _frames(4)
	Input.action_press("move_forward")
	await _wait_ms(1400)
	Input.action_release("move_forward")
	await _frames(4)
	_check(_player.global_position.y > UPPER - 0.2, "the gallery rail stops a walk into the stairwell (y %.2f)" % _player.global_position.y)
	_check(_player.global_position.z > -1.18, "the gallery rail holds at the well edge (z %.2f)" % _player.global_position.z)

	# Walk east into the lower flight's well edge.
	_player.global_position = Vector3(3.60, UPPER + 0.05, -0.60)
	_player.rotation.y = -PI * 0.5
	_player.velocity = Vector3.ZERO
	await _frames(4)
	Input.action_press("move_forward")
	await _wait_ms(1400)
	Input.action_release("move_forward")
	await _frames(4)
	_check(_player.global_position.y > UPPER - 0.2, "the gallery rail holds along the east edge (y %.2f)" % _player.global_position.y)

	# The open side of the lower flight has to stop a walk from the hall, not
	# just look like a handrail.
	_player.global_position = Vector3(3.40, 0.05, 0.20)
	_player.rotation.y = -PI * 0.5
	_player.velocity = Vector3.ZERO
	await _frames(4)
	Input.action_press("move_forward")
	await _wait_ms(1600)
	Input.action_release("move_forward")
	await _frames(4)
	_check(_player.global_position.x < 4.15, "the stair handrail stops a walk into the flight (x %.2f)" % _player.global_position.x)
	_check(_player.global_position.y < 0.2, "the stair handrail does not lift the player onto the flight (y %.2f)" % _player.global_position.y)

	# Furniture is solid too: walk at the sofa from the open floor south of it.
	_player.global_position = Vector3(-1.85, 0.05, -3.90)
	_player.rotation.y = PI
	_player.velocity = Vector3.ZERO
	await _frames(4)
	Input.action_press("move_forward")
	await _wait_ms(1200)
	Input.action_release("move_forward")
	await _frames(4)
	_check(_player.global_position.z < -3.40, "the sofa stops a walk through it (z %.2f)" % _player.global_position.z)

	# The study door sits under the high end of the upper flight; the way to it
	# has to be walkable, not just open to a ray.
	_player.global_position = Vector3(2.50, 0.05, -0.60)
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	await _frames(4)
	Input.action_press("move_forward")
	await _wait_ms(1800)
	Input.action_release("move_forward")
	await _frames(4)
	_check(_player.global_position.z < -2.30, "the study can be walked into under the stair (z %.2f)" % _player.global_position.z)


# --- contents ---------------------------------------------------------------

func _check_furniture() -> void:
	var furniture := _world.get_node_or_null("Furniture")
	_check(furniture != null, "the scene has a furniture group")
	if furniture == null:
		return
	var counts := {}
	for entry in FURNISHED:
		counts[entry[0]] = 0
	for child in furniture.get_children():
		var node := child as Node3D
		if node == null:
			continue
		var position := node.global_position
		for entry in FURNISHED:
			if position.x >= float(entry[1]) - 0.4 and position.x <= float(entry[3]) + 0.4 and position.z >= float(entry[2]) - 0.4 and position.z <= float(entry[4]) + 0.4:
				if absf(position.y - (UPPER if entry[0] in ["main_bed", "second_bed", "bath", "landing"] else GROUND)) < 0.6:
					counts[entry[0]] = int(counts[entry[0]]) + 1
					break
	for entry in FURNISHED:
		var count: int = counts[entry[0]]
		_check(count >= int(entry[5]), "%s is furnished (%d pieces)" % [entry[0], count])


func _check_lighting() -> void:
	var lights := 0
	for child in _world.get_node("Lighting").get_children():
		if child is OmniLight3D:
			lights += 1
	_check(lights >= 10, "every room has a lamp (%d lamps)" % lights)
	_check(_world.get_node_or_null("Lighting/WorldEnvironment") != null, "the scene has an environment")


# --- sitting and resting ----------------------------------------------------

func _check_seats() -> void:
	var spots := get_nodes_in_group("interior_spot")
	_check(spots.size() >= 10, "there are seats to use (%d spots)" % spots.size())
	if spots.is_empty():
		return

	var sofa: Node3D = null
	var bed: Node3D = null
	for spot in spots:
		if String(spot.name) == "SofaSeat":
			sofa = spot
		if String(spot.name) == "MainBedRest":
			bed = spot
	_check(sofa != null and bed != null, "the sofa and the main bed are seats")
	if sofa == null:
		return

	# Sit on the sofa through the spot's own input handler.
	_player.global_position = sofa.global_position + Vector3(0.85, -0.40, 0.0)
	_player.velocity = Vector3.ZERO
	await _frames(4)
	sofa.call("_process", 0.1)
	sofa.call("_unhandled_input", _action("interact"))
	await _frames(2)
	_check(bool(_player.get("seated")), "pressing E on the sofa sits the player")
	var camera := _player.get_node("CameraPivot/Camera3D") as Camera3D
	var eye_y := sofa.global_position.y + float(sofa.get("eye_height"))
	_check(absf(camera.global_position.y - eye_y) < 0.15, "the seated camera sits at eye height (%.2f vs %.2f)" % [camera.global_position.y, eye_y])
	_check(not bool(_player.get("controls_enabled")), "sitting locks movement")

	sofa.call("_unhandled_input", _action("interact"))
	await _frames(2)
	_check(not bool(_player.get("seated")), "pressing E again stands the player up")
	_check(bool(_player.get("controls_enabled")), "standing restores movement")

	# Lying on the bed runs the rest fade.
	_player.global_position = bed.global_position + Vector3(1.0, -0.55, 0.0)
	_player.velocity = Vector3.ZERO
	await _frames(4)
	bed.call("_process", 0.1)
	bed.call("_unhandled_input", _action("interact"))
	await _frames(2)
	_check(bool(_player.get("seated")), "the bed accepts a lie-down")
	var fade := bed.get("_fade") as ColorRect
	await _wait_ms(1800)
	if fade == null:
		_check(false, "the bed has a fade layer")
	else:
		_check(fade.modulate.a > 0.25, "resting dims the room (alpha %.2f)" % fade.modulate.a)
	await _wait_ms(1400)
	bed.call("_unhandled_input", _action("interact"))
	await _frames(2)
	_check(not bool(_player.get("seated")), "the player gets up after resting")


func _check_walking_up() -> void:
	# Walk up the way a player would: in from the hall, up the lower flight to
	# the turn, then a quarter turn west and up onto the gallery.
	_player.global_position = Vector3(4.85, 0.05, 1.55)
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	await _frames(4)
	Input.action_press("move_forward")
	await _wait_ms(2400)
	Input.action_release("move_forward")
	await _frames(4)
	var turn := _player.global_position
	print("climbed the lower flight to x=%.2f y=%.2f z=%.2f" % [turn.x, turn.y, turn.z])
	_check(turn.y > 0.9, "the foot of the stairs is walked into from the hall (y %.2f)" % turn.y)

	_player.rotation.y = PI * 0.5
	await _frames(2)
	Input.action_press("move_forward")
	await _wait_ms(2600)
	Input.action_release("move_forward")
	await _frames(4)
	var top := _player.global_position
	print("walked over the landing to x=%.2f y=%.2f z=%.2f" % [top.x, top.y, top.z])
	_check(top.y > UPPER - 0.25, "the upper flight reaches the first floor (y %.2f)" % top.y)
	_check(top.x < 2.6, "the top of the stairs walks off onto the landing (x %.2f)" % top.x)

	# And back down, turning the other way.
	_player.rotation.y = -PI * 0.5
	await _frames(2)
	Input.action_press("move_forward")
	await _wait_ms(2600)
	Input.action_release("move_forward")
	await _frames(2)
	_player.rotation.y = PI
	await _frames(2)
	Input.action_press("move_forward")
	await _wait_ms(2400)
	Input.action_release("move_forward")
	await _frames(4)
	var bottom := _player.global_position
	print("walked back down to x=%.2f y=%.2f z=%.2f" % [bottom.x, bottom.y, bottom.z])
	_check(bottom.y < 0.2, "the stairs can be walked back down (y %.2f)" % bottom.y)


# --- helpers ----------------------------------------------------------------

func _ray(from: Vector3, to: Vector3, mask := 1) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.collide_with_areas = false
	return _space.intersect_ray(query)


func _action(action_name: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	event.strength = 1.0
	return event


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _wait_ms(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		await process_frame


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
		print("  FAIL: ", label)
	else:
		print("  ok: ", label)
