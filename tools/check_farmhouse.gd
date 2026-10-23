extends SceneTree

## Headless verification for the enlarged farmhouse interior.
##
##   godot --headless --path . --script res://tools/check_farmhouse.gd
##
## Covers the 3x floor areas, floors under every room on both storeys, wide
## cased openings with no door leaves, window openings open to the outside, a
## stair that can be walked both ways, furniture in every room, sitting and
## resting through the player's own API, and an indoor camera that never ends
## up inside a wall or furniture.

const SCENE := "res://scenes/farmhouse.tscn"

const GROUND := 0.0
const UPPER := 3.12

# room name, centre x, centre z, floor base, old floor area
const ROOMS := [
	["sitting", -3.55, -3.90, GROUND, 31.05],
	["kitchen", -3.55, 3.90, GROUND, 31.05],
	["hall", 5.98, 0.00, GROUND, 18.04],
	["study", 5.98, -5.80, GROUND, 9.43],
	["boot", 5.98, 5.80, GROUND, 9.43],
	["main_bed", -3.55, -3.90, UPPER, 31.05],
	["second_bed", -3.55, 3.90, UPPER, 31.05],
	["landing", 5.98, -5.80, UPPER, 9.43],
	["bath", 5.98, 5.80, UPPER, 9.43],
	["gallery", 5.98, 0.00, UPPER, 18.04],
]

# Points that must be inside a wall on both storeys.
const SOLID := [
	["z", 2.43, 3.00, GROUND],
	["z", 2.43, -3.00, GROUND],
	["x", 0.00, -8.00, GROUND],
	["x", 0.00, 1.00, GROUND],
	["x", -3.81, 7.00, GROUND],
	["x", -3.81, 5.00, GROUND],
	["x", 3.81, 7.00, GROUND],
	["x", 3.81, 5.00, GROUND],
	["z", 2.43, 3.00, UPPER],
	["z", 2.43, -3.00, UPPER],
	["x", 3.81, 5.00, UPPER],
	["x", -7.79, 0.00, GROUND],
	["x", 7.79, 0.00, GROUND],
	["z", -9.53, 0.00, GROUND],
	["z", 9.53, 0.00, GROUND],
]

# Furniture must be present in every room.  name, min x, min z, max x, max z,
# minimum pieces, floor.
const FURNISHED := [
	["sitting", -9.53, -7.79, 2.43, 0.0, 10, GROUND],
	["kitchen", -9.53, 0.0, 2.43, 7.79, 20, GROUND],
	["hall", 2.43, -3.81, 9.53, 3.81, 5, GROUND],
	["study", 2.43, -7.79, 9.53, -3.81, 7, GROUND],
	["boot", 2.43, 3.81, 9.53, 7.79, 6, GROUND],
	["main_bed", -9.53, -7.79, 2.43, 0.0, 15, UPPER],
	["second_bed", -9.53, 0.0, 2.43, 7.79, 12, UPPER],
	["bath", 2.43, 3.81, 9.53, 7.79, 8, UPPER],
	["landing", 2.43, -7.79, 9.53, -3.81, 8, UPPER],
	["gallery", 2.43, -3.81, 9.53, 3.81, 5, UPPER],
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

	_check_areas()
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
	await _check_camera()


# --- shell ------------------------------------------------------------------

func _check_areas() -> void:
	var rooms: Array = _world.get_meta("rooms", [])
	_check(rooms.size() == ROOMS.size(), "the scene publishes all ten room rectangles")
	for entry in rooms:
		var name := String(entry["name"])
		var found := false
		for room in ROOMS:
			if String(room[0]) != name:
				continue
			found = true
			var min2: Array = entry["min"]
			var max2: Array = entry["max"]
			var area := (float(max2[0]) - float(min2[0])) * (float(max2[1]) - float(min2[1]))
			var old: float = float(room[4])
			_check(area >= old * 2.9, "%s is %.1f m² (%.2fx its old %.1f m²)" % [name, area, area / old, old])
		_check(found, "%s has an area entry" % name)


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
	# The whole point of this change: there must be no interior leaves left.
	var leaves := get_nodes_in_group("interior_door")
	_check(leaves.is_empty(), "there are no interior door leaves (%d found)" % leaves.size())
	var furniture := _world.get_node_or_null("Furniture")
	if furniture != null:
		var swings := 0
		for child in furniture.get_children():
			if String(child.name).contains("Swing"):
				swings += 1
		_check(swings == 0, "no swing-door nodes remain (%d found)" % swings)

	for door in _world.get_meta("doors", []):
		if bool(door.get("leaf", false)):
			continue
		var axis: String = door["axis"]
		var plane: float = door["plane"]
		var centre: float = door["centre"]
		var base: float = door["base"]
		var head: float = door["head"]
		var y := (base + head) * 0.5
		var inside := Vector3(plane - 1.2, y, centre) if axis == "z" else Vector3(centre, y, plane - 1.2)
		var outside := Vector3(plane + 1.2, y, centre) if axis == "z" else Vector3(centre, y, plane + 1.2)
		_check(_ray(inside, outside, 5).is_empty(), "opening %s is clear" % door["name"])
		# A single centre ray misses furniture standing in the opening.  Sweep a
		# player-sized capsule along the centre line instead.  Furniture may
		# legitimately narrow one edge of a wide opening; the centre must stay
		# walkable.
		_check(
			_door_lane_clear(axis, plane, centre, base),
			"opening %s is wide enough to walk through" % door["name"]
		)


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
	for window in _world.get_meta("windows", []):
		var axis: String = window["axis"]
		var plane: float = window["plane"]
		var centre: float = window["centre"]
		var y := (float(window["sill"]) + float(window["head"])) * 0.5
		var outside := Vector3(plane + 1.5, y, centre) if axis == "z" else Vector3(centre, y, plane + 1.5)
		var inside := Vector3(plane - 1.5, y, centre) if axis == "z" else Vector3(centre, y, plane - 1.5)
		var label := "%s window at %.1f/%.1f" % [axis, plane, centre]
		_check(_ray(outside, inside, 5).is_empty(), "%s is open to the outside" % label)


func _check_stairs() -> void:
	# Lower flight: south along the east wall, floor to the quarter landing.
	for i in range(6):
		var t := (float(i) + 0.5) / 6.0
		var z := lerpf(0.60, -2.55, t)
		var expected := 1.2847 * t
		var hit := _ray(Vector3(8.78, expected + 1.2, z), Vector3(8.78, expected - 0.5, z))
		if hit.is_empty():
			_check(false, "lower flight has a surface at z %.2f" % z)
			continue
		var y: float = (hit["position"] as Vector3).y
		_check(absf(y - expected) < 0.16, "lower flight rises at z %.2f (expected %.2f, got %.2f)" % [z, expected, y])

	var landing := _ray(Vector3(8.78, 2.6, -3.15), Vector3(8.78, 0.6, -3.15))
	if landing.is_empty():
		_check(false, "the quarter landing has a floor")
	else:
		var y: float = (landing["position"] as Vector3).y
		_check(absf(y - 1.2847) < 0.06, "the quarter landing is at 1.28 (got %.2f)" % y)

	# Upper flight: west along the south wall, landing to the first floor.
	for i in range(6):
		var t := (float(i) + 0.5) / 6.0
		var x := lerpf(8.18, 4.58, t)
		var expected := lerpf(1.2847, UPPER, t)
		var hit := _ray(Vector3(x, expected + 1.2, -3.15), Vector3(x, expected - 0.5, -3.15))
		if hit.is_empty():
			_check(false, "upper flight has a surface at x %.2f" % x)
			continue
		var y: float = (hit["position"] as Vector3).y
		_check(absf(y - expected) < 0.16, "upper flight rises at x %.2f (expected %.2f, got %.2f)" % [x, expected, y])

	var top := _ray(Vector3(4.00, UPPER + 1.2, -3.15), Vector3(4.00, UPPER - 0.4, -3.15))
	if top.is_empty():
		_check(false, "the top of the stairs opens onto a landing")
	else:
		var y: float = (top["position"] as Vector3).y
		_check(absf(y - UPPER) < 0.06, "the top landing is at first-floor height (got %.2f)" % y)


## The gallery edges around the well have to stop a player, not just look like
## rails: walk at each one and stay on the floor.
func _check_stair_guards() -> void:
	# Walk south into the well edge from the gallery.
	_player.global_position = Vector3(6.50, UPPER + 0.05, -1.40)
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	await _frames(4)
	Input.action_press("move_forward")
	await _wait_ms(1200)
	Input.action_release("move_forward")
	await _frames(4)
	_check(_player.global_position.y > UPPER - 0.2, "the gallery rail stops a walk into the stairwell (y %.2f)" % _player.global_position.y)
	_check(_player.global_position.z > -2.40, "the gallery rail holds at the well edge (z %.2f)" % _player.global_position.z)

	# Walk east into the lower flight's well edge.
	_player.global_position = Vector3(7.20, UPPER + 0.05, -1.40)
	_player.rotation.y = -PI * 0.5
	_player.velocity = Vector3.ZERO
	await _frames(4)
	Input.action_press("move_forward")
	await _wait_ms(1200)
	Input.action_release("move_forward")
	await _frames(4)
	_check(_player.global_position.y > UPPER - 0.2, "the gallery rail holds along the east edge (y %.2f)" % _player.global_position.y)
	_check(_player.global_position.x < 8.05, "the gallery rail holds at the east well edge (x %.2f)" % _player.global_position.x)

	# The open side of the lower flight has to stop a walk from the hall.
	_player.global_position = Vector3(7.20, 0.05, 0.20)
	_player.rotation.y = -PI * 0.5
	_player.velocity = Vector3.ZERO
	await _frames(4)
	Input.action_press("move_forward")
	await _wait_ms(1400)
	Input.action_release("move_forward")
	await _frames(4)
	_check(_player.global_position.x < 8.10, "the stair handrail stops a walk into the flight (x %.2f)" % _player.global_position.x)
	_check(_player.global_position.y < 0.2, "the stair handrail does not lift the player onto the flight (y %.2f)" % _player.global_position.y)

	# Furniture is solid too: walk at the sofa from the open floor north of it.
	_player.global_position = Vector3(-3.75, 0.05, -1.80)
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	await _frames(4)
	Input.action_press("move_forward")
	await _wait_ms(1200)
	Input.action_release("move_forward")
	await _frames(4)
	_check(_player.global_position.z > -2.70, "the sofa stops a walk through it (z %.2f)" % _player.global_position.z)

	# The study opening is clear and walkable.
	_player.global_position = Vector3(3.40, 0.05, -1.20)
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	await _frames(4)
	Input.action_press("move_forward")
	await _wait_ms(1800)
	Input.action_release("move_forward")
	await _frames(4)
	_check(_player.global_position.z < -4.10, "the study can be walked into through its wide opening (z %.2f)" % _player.global_position.z)


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
			if position.x >= float(entry[1]) - 0.25 and position.x <= float(entry[3]) + 0.25 and position.z >= float(entry[2]) - 0.25 and position.z <= float(entry[4]) + 0.25:
				if absf(position.y - float(entry[6])) < 0.6:
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
	_check(lights >= 13, "every room has a lamp (%d lamps)" % lights)
	_check(_world.get_node_or_null("Lighting/WorldEnvironment") != null, "the scene has an environment")


# --- sitting and resting ----------------------------------------------------

func _check_seats() -> void:
	var spots := get_nodes_in_group("interior_spot")
	_check(spots.size() >= 15, "there are seats to use (%d spots)" % spots.size())
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
	_player.global_position = Vector3(8.78, 0.05, 2.40)
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	await _frames(4)
	Input.action_press("move_forward")
	await _wait_ms(3600)
	Input.action_release("move_forward")
	await _frames(4)
	var turn := _player.global_position
	print("climbed the lower flight to x=%.2f y=%.2f z=%.2f" % [turn.x, turn.y, turn.z])
	_check(turn.y > 1.0, "the foot of the stairs is walked into from the hall (y %.2f)" % turn.y)

	_player.rotation.y = PI * 0.5
	await _frames(2)
	Input.action_press("move_forward")
	await _wait_ms(3600)
	Input.action_release("move_forward")
	await _frames(4)
	var top := _player.global_position
	print("walked over the landing to x=%.2f y=%.2f z=%.2f" % [top.x, top.y, top.z])
	_check(top.y > UPPER - 0.25, "the upper flight reaches the first floor (y %.2f)" % top.y)
	_check(top.x < 5.0, "the top of the stairs walks off onto the landing (x %.2f)" % top.x)

	# And back down, turning the other way.
	_player.rotation.y = -PI * 0.5
	await _frames(2)
	Input.action_press("move_forward")
	await _wait_ms(3600)
	Input.action_release("move_forward")
	await _frames(2)
	_player.rotation.y = PI
	await _frames(2)
	Input.action_press("move_forward")
	await _wait_ms(3600)
	Input.action_release("move_forward")
	await _frames(4)
	var bottom := _player.global_position
	print("walked back down to x=%.2f y=%.2f z=%.2f" % [bottom.x, bottom.y, bottom.z])
	_check(bottom.y < 0.2, "the stairs can be walked back down (y %.2f)" % bottom.y)


# --- indoor camera ----------------------------------------------------------

func _check_camera() -> void:
	var spots := [
		Vector3(-3.50, 0.05, -5.90),
		Vector3(-4.20, 0.05, 6.80),
		Vector3(5.80, 0.05, 1.00),
		Vector3(-3.50, UPPER + 0.05, -3.90),
		Vector3(5.80, UPPER + 0.05, 5.00),
	]
	var pivot := _player.get_node("CameraPivot") as Node3D
	var camera := _player.get_node("CameraPivot/Camera3D") as Camera3D
	var checked := 0
	var inside := 0
	for spot in spots:
		_player.global_position = spot
		_player.velocity = Vector3.ZERO
		for yaw in [0.0, 90.0, 180.0, 270.0]:
			_player.rotation.y = deg_to_rad(float(yaw))
			pivot.rotation.x = deg_to_rad(-10.0)
			await _wait_ms(450)
			var from := pivot.global_position
			var to := camera.global_position
			var distance := from.distance_to(to)
			checked += 1
			if distance < 0.30:
				inside += 1
				print("  camera too close at %s yaw %s: %.2f" % [spot, yaw, distance])
			var hit := _ray(from, to, 5)
			if not hit.is_empty() and from.distance_to(hit["position"]) < distance - 0.18:
				inside += 1
				print("  camera clipped at %s yaw %s: %.2f" % [spot, yaw, distance])
	_check(checked > 0, "the camera was sampled (%d views)" % checked)
	_check(inside == 0, "the indoor camera never enters walls or furniture (%d bad of %d)" % [inside, checked])

	# From the centre of the enlarged sitting room the full indoor boom fits.
	# The bounds also prove the interior profile was applied: the outdoor 3 m
	# boom would otherwise pass a lower-bound-only test.
	_player.global_position = Vector3(-3.50, 0.05, -5.90)
	_player.rotation.y = 0.0
	pivot.rotation.x = 0.0
	await _wait_ms(1200)
	var boom := float(_player.call("camera_boom_length"))
	_check(boom > 2.20 and boom < 2.50, "the open sitting room gets the indoor boom (%.2f m, expected 2.35)" % boom)
	_check(absf(pivot.position.y - 1.62) < 0.06, "the indoor camera pivot sits at 1.62 m (%.2f m)" % pivot.position.y)


# --- helpers ----------------------------------------------------------------

## Whether a player-sized capsule can cross the wall plane over a one-metre
## span, at `along` of the opening.  Catches furniture standing in a doorway.
func _door_lane_clear(axis: String, plane: float, along: float, base: float) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.10
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1 | 4
	query.collide_with_areas = false
	for step in [-0.60, -0.30, 0.0, 0.30, 0.60]:
		var pos := Vector3(plane + step, base + 0.90, along) if axis == "z" else Vector3(along, base + 0.90, plane + step)
		query.transform = Transform3D(Basis.IDENTITY, pos)
		if not _space.intersect_shape(query, 1).is_empty():
			return false
	return true


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
