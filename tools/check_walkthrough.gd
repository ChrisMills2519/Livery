extends SceneTree

## Walkthrough check: walk the farmhouse on its own collision, through every
## cased opening and both stair flights, then orbit and back into walls and
## furniture while measuring the indoor camera.
##
##   godot --headless --path . --script res://tools/check_walkthrough.gd
##
## Takes about two minutes.  It is deliberately slower than check_farmhouse:
## it proves the routes in motion, which is where a camera boom or a doorway
## snag shows up.

const SCENE := "res://scenes/farmhouse.tscn"
const SPAWN := Vector3(8.35, 0.05, 2.68)

const ROUTE := [
	{"label": "hall to sitting opening", "pos": Vector3(3.2, 0.0, -1.6)},
	{"label": "sitting through opening", "pos": Vector3(1.3, 0.0, -1.6)},
	{"label": "sitting north aisle", "pos": Vector3(-3.1, 0.0, -1.2)},
	{"label": "sitting centre", "pos": Vector3(-4.8, 0.0, -2.6), "orbit": "sitting"},
	{"label": "sitting to kitchen opening", "pos": Vector3(-3.8, 0.0, -1.0)},
	{"label": "sitting to kitchen", "pos": Vector3(-3.8, 0.0, 1.2)},
	{"label": "kitchen centre", "pos": Vector3(-2.0, 0.0, 2.6), "orbit": "kitchen"},
	{"label": "kitchen to hall opening", "pos": Vector3(1.0, 0.0, 1.6)},
	{"label": "kitchen to hall", "pos": Vector3(3.6, 0.0, 1.6)},
	{"label": "hall centre", "pos": Vector3(5.5, 0.0, 0.5), "orbit": "hall"},
	{"label": "hall to study opening", "pos": Vector3(3.4, 0.0, -2.7)},
	{"label": "study through opening", "pos": Vector3(3.4, 0.0, -4.8)},
	{"label": "study centre", "pos": Vector3(5.8, 0.0, -5.8), "orbit": "study"},
	{"label": "study back to opening", "pos": Vector3(3.4, 0.0, -4.8)},
	{"label": "study back to hall", "pos": Vector3(3.4, 0.0, -2.7)},
	{"label": "hall to boot opening", "pos": Vector3(4.0, 0.0, 2.8)},
	{"label": "boot through opening", "pos": Vector3(4.0, 0.0, 4.8)},
	{"label": "boot centre", "pos": Vector3(5.8, 0.0, 5.8), "orbit": "boot"},
	{"label": "boot back to opening", "pos": Vector3(4.0, 0.0, 4.8)},
	{"label": "boot back to hall", "pos": Vector3(4.0, 0.0, 2.8)},
	{"label": "hall to stair foot", "pos": Vector3(8.78, 0.0, 1.2)},
	{"label": "lower flight", "pos": Vector3(8.78, 0.0, -3.15)},
	{"label": "upper flight", "pos": Vector3(4.20, 3.12, -3.15)},
	{"label": "gallery rail end", "pos": Vector3(4.20, 3.12, -2.0)},
	{"label": "gallery centre", "pos": Vector3(5.4, 3.12, -0.2), "orbit": "gallery"},
	{"label": "gallery to main bed", "pos": Vector3(1.2, 3.12, -1.6)},
	{"label": "main bedroom centre", "pos": Vector3(-3.5, 3.12, -3.2), "orbit": "main bedroom"},
	{"label": "main bedroom back", "pos": Vector3(1.2, 3.12, -1.6)},
	{"label": "gallery from main bed", "pos": Vector3(4.2, 3.12, -1.0)},
	{"label": "gallery to second bed", "pos": Vector3(3.2, 3.12, 1.6)},
	{"label": "second bed through opening", "pos": Vector3(1.2, 3.12, 1.6)},
	{"label": "second bedroom centre", "pos": Vector3(-3.5, 3.12, 3.0), "orbit": "second bedroom"},
	{"label": "second bedroom back", "pos": Vector3(1.2, 3.12, 1.6)},
	{"label": "gallery from second bed", "pos": Vector3(3.2, 3.12, 1.6)},
	{"label": "gallery from second bed 2", "pos": Vector3(4.2, 3.12, 1.0)},
	{"label": "gallery to bath", "pos": Vector3(4.0, 3.12, 3.0)},
	{"label": "bath through opening", "pos": Vector3(4.0, 3.12, 4.8)},
	{"label": "bath centre", "pos": Vector3(6.0, 3.12, 5.8), "orbit": "bath"},
	{"label": "bath back to gallery", "pos": Vector3(4.0, 3.12, 3.0)},
	{"label": "landing centre", "pos": Vector3(4.2, 3.12, -4.7), "orbit": "landing"},
	{"label": "landing rail end", "pos": Vector3(4.2, 3.12, -2.0)},
	{"label": "gallery from landing", "pos": Vector3(5.4, 3.12, -0.2)},
	{"label": "stair top approach", "pos": Vector3(4.2, 3.12, -2.0)},
	{"label": "stair top", "pos": Vector3(4.20, 3.12, -3.15)},
	{"label": "upper flight down", "pos": Vector3(9.15, 0.0, -3.15)},
	{"label": "lower flight down", "pos": Vector3(8.78, 0.0, 0.9)},
]

# Corners and tight furniture to back the camera into.  "face" is the yaw the
# player looks along; the camera is behind them, into the corner.
const CORNERS := [
	{"label": "sitting fireplace corner", "pos": Vector3(-8.80, 0.0, -6.90), "face": -45.0},
	{"label": "kitchen south-east corner", "pos": Vector3(1.70, 0.0, 0.55), "face": 180.0},
	{"label": "hall front-door corner", "pos": Vector3(8.70, 0.0, 3.10), "face": 135.0},
	{"label": "study east-wall corner", "pos": Vector3(8.90, 0.0, -5.20), "face": 90.0},
	{"label": "boot east-wall corner", "pos": Vector3(8.70, 0.0, 4.90), "face": 90.0},
	{"label": "bedroom window corner", "pos": Vector3(-8.80, 3.12, -6.90), "face": -45.0},
	{"label": "bedroom north-east corner", "pos": Vector3(1.70, 3.12, -0.70), "face": 0.0},
	{"label": "second bedroom south corner", "pos": Vector3(0.70, 3.12, 0.55), "face": 180.0},
	{"label": "bathroom east-wall corner", "pos": Vector3(8.70, 3.12, 4.70), "face": 90.0},
	{"label": "landing east-wall corner", "pos": Vector3(8.80, 3.12, -6.20), "face": 90.0},
	{"label": "gallery rail corner", "pos": Vector3(4.80, 3.12, -2.10), "face": 180.0},
]

const CAMERA_FAILURE_LIMIT := 8
## The old rig could fall to the 0.35 m safety clamp in any tight spot.  These
## floors are the measured answers: every open room and every backed-into
## corner must keep a third-person boom, not just stay off the clamp.  The
## doorway transit gets the same floor as a corner.  The stair is measured
## separately: it is 1.2 m wide with a wall behind the player, so its close
## camera is a genuine first-person exception rather than a doorway failure.
const ROOM_BOOM_FLOOR := 1.0
const CORNER_BOOM_FLOOR := 0.90
const ROUTE_BOOM_FLOOR := 0.90
## The stair exception still must not regress into the old head camera.
const STAIR_BOOM_FLOOR := 0.30

var _world: Node3D
var _player: CharacterBody3D
var _pivot: Node3D
var _camera: Camera3D
var _space: PhysicsDirectSpaceState3D
var _last_boom := 0.0
var _min_walk_boom := INF
var _min_walk_at := Vector3.ZERO
var _min_walk_body_visible := true
var _min_stair_boom := INF
var _min_stair_at := Vector3.ZERO
var _stair_samples := 0
var _max_boom := 0.0
var _max_inward := 0.0
var _max_outward := 0.0
var _clip_frames := 0
var _outward_pops := 0
var _sample_count := 0
var _leg_failures: Array[String] = []
var _cam_failures: Array[String] = []
var _room_booms := {}


func _initialize() -> void:
	await _run()
	print("")
	print("WALKTHROUGH SUMMARY")
	print("  legs: %d, failed legs: %d" % [ROUTE.size() + CORNERS.size(), _leg_failures.size()])
	for failure in _leg_failures:
		print("  ROUTE FAIL: " + failure)
	print("  camera samples: %d, clipped frames: %d, outward pops: %d" % [_sample_count, _clip_frames, _outward_pops])
	print("  third-person boom: %.2f .. %.2f, min at %s" % [_min_walk_boom, _max_boom, _min_walk_at])
	if _stair_samples > 0:
		print("  stair boom: %.2f (first-person exception) at %s" % [_min_stair_boom, _min_stair_at])
	print("  max inward step: %.2f, max outward step: %.2f" % [_max_inward, _max_outward])
	if _min_walk_boom < ROUTE_BOOM_FLOOR:
		_add_cam_failure("third-person boom fell to %.2f m (floor %.2f) at %s" % [_min_walk_boom, ROUTE_BOOM_FLOOR, _min_walk_at])
	if not _min_walk_body_visible:
		_add_cam_failure("body hidden at the third-person minimum (%.2f m) at %s" % [_min_walk_boom, _min_walk_at])
	if _stair_samples > 0 and _min_stair_boom < STAIR_BOOM_FLOOR:
		_add_cam_failure("stair boom fell to %.2f m (floor %.2f) at %s" % [_min_stair_boom, STAIR_BOOM_FLOOR, _min_stair_at])
	for key in _room_booms:
		print("  %s boom: %.2f" % [key, _room_booms[key]])
	for failure in _cam_failures:
		print("  CAMERA FAIL: " + failure)
	if _leg_failures.is_empty() and _cam_failures.is_empty():
		print("WALKTHROUGH CHECK: PASS")
		quit(0)
	else:
		print("WALKTHROUGH CHECK: FAIL")
		quit(1)


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	_world = packed.instantiate() as Node3D
	root.add_child(_world)
	await _frames(20)
	_space = _world.get_world_3d().direct_space_state
	_player = _world.get_node_or_null("Player") as CharacterBody3D
	_pivot = _player.get_node("CameraPivot") as Node3D
	_camera = _player.get_node("CameraPivot/Camera3D") as Camera3D
	_player.global_position = SPAWN
	_player.rotation.y = PI * 0.5
	_player.velocity = Vector3.ZERO
	_player.set("controls_enabled", true)
	_pivot.rotation.x = 0.0
	await _frames(20)
	_sample()

	for step in ROUTE:
		await _walk_to(step["pos"], String(step["label"]))
		if step.has("orbit"):
			await _orbit(String(step["orbit"]))
	for corner in CORNERS:
		await _back_into(corner["pos"], float(corner["face"]), String(corner["label"]))


func _walk_to(target: Vector3, label: String) -> void:
	var start := _player.global_position
	Input.action_press("move_forward")
	var began := Time.get_ticks_msec()
	var stalled := 0.0
	var reached := false
	while Time.get_ticks_msec() - began < 9000:
		var pos := _player.global_position
		var flat := Vector2(target.x - pos.x, target.z - pos.z)
		if flat.length() < 0.42:
			reached = true
			break
		_player.rotation.y = atan2(-flat.x, -flat.y)
		await physics_frame
		_sample()
		var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
		if speed < 0.08:
			stalled += 1.0 / 60.0
		else:
			stalled = 0.0
		if stalled > 0.55:
			break
	Input.action_release("move_forward")
	await _frames(2)
	if not reached:
		var pos := _player.global_position
		var flat := Vector2(target.x - pos.x, target.z - pos.z)
		_leg_failures.append("%s: stopped %.2f m short at %s (from %s)" % [label, flat.length(), pos, start])


func _orbit(room: String, quick := false) -> void:
	# Sweep the yaw a few degrees per physics frame, as a hand on the mouse
	# would, so an outward step is a real pop rather than a sampling artefact.
	var worst := INF
	var pitches := [0.0] if quick else [-15.0, 0.0, 10.0]
	var frames := 60 if quick else 120
	for pitch in pitches:
		_pivot.rotation.x = deg_to_rad(pitch)
		await _frames(2)
		_last_boom = float(_player.call("camera_boom_length"))
		for i in range(frames):
			_player.rotation.y += deg_to_rad(3.0)
			await physics_frame
			_sample()
			worst = minf(worst, float(_player.call("camera_boom_length")))
	_room_booms[room] = worst
	var floor := CORNER_BOOM_FLOOR if quick else ROOM_BOOM_FLOOR
	if worst < floor:
		_add_cam_failure("%s: boom fell to %.2f m (floor %.2f)" % [room, worst, floor])
	var body := _player.get_node_or_null("Model") as Node3D
	if body != null and not body.visible:
		_add_cam_failure("%s: body hidden at boom %.2f" % [room, worst])


func _back_into(pos: Vector3, face_deg: float, label: String) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.rotation.y = deg_to_rad(face_deg)
	_pivot.rotation.x = deg_to_rad(-10.0)
	# The teleport itself makes the boom snap in; let it settle before measuring.
	await _frames(20)
	Input.action_press("move_back")
	await _wait_ms(1200)
	Input.action_release("move_back")
	await _frames(10)
	await _orbit(label, true)


func _sample() -> void:
	if _pivot == null or _camera == null:
		return
	var boom := float(_player.call("camera_boom_length"))
	_sample_count += 1
	if _on_stair():
		_stair_samples += 1
		if boom < _min_stair_boom:
			_min_stair_boom = boom
			_min_stair_at = _player.global_position
	elif boom < _min_walk_boom:
		_min_walk_boom = boom
		_min_walk_at = _player.global_position
		var body := _player.get_node_or_null("Model") as Node3D
		_min_walk_body_visible = body == null or body.visible
	_max_boom = maxf(_max_boom, boom)
	if _sample_count > 2:
		var delta := boom - _last_boom
		if delta < 0.0:
			_max_inward = maxf(_max_inward, -delta)
		elif delta > 0.0:
			_max_outward = maxf(_max_outward, delta)
			# Headless frames are uneven, so a step is judged by its size, not by
			# the wall-clock rate.  The rig's own ease caps a real frame near 4 cm;
			# anything over 35 cm is a snap even on a badly hitched frame.
			if delta > 0.35:
				_outward_pops += 1
				_add_cam_failure("camera popped outward %.2f m at %s" % [delta, _player.global_position])
	_last_boom = boom
	var from := _pivot.global_position
	var to := _camera.global_position
	var distance := from.distance_to(to)
	var query := PhysicsRayQueryParameters3D.create(from, to, 5)
	query.exclude = [ _player.get_rid() ]
	query.collide_with_areas = false
	var hit := _space.intersect_ray(query)
	if not hit.is_empty() and from.distance_to(hit["position"]) < distance - 0.10:
		_clip_frames += 1
		_add_cam_failure("camera clipped at %s (boom %.2f)" % [_player.global_position, boom])
	if distance < 0.30:
		_add_cam_failure("camera too close at %s (%.2f)" % [_player.global_position, distance])


func _on_stair() -> bool:
	if _space == null:
		return false
	var from := _player.global_position + Vector3.UP * 0.10
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * 0.40, 1)
	query.exclude = [_player.get_rid()]
	var hit := _space.intersect_ray(query)
	return not hit.is_empty() and String(hit["collider"].name).begins_with("Stair")


func _add_cam_failure(message: String) -> void:
	if _cam_failures.size() < CAMERA_FAILURE_LIMIT:
		_cam_failures.append(message)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _wait_ms(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		await process_frame
