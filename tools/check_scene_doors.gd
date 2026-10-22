extends SceneTree

## Headless verification for the farmhouse <-> yard door handoff.
##
##   godot --headless --path . --script res://tools/check_scene_doors.gd
##
## Covers the parts a unit test of either scene cannot: both scene links point
## at each other, the fantasy house has a solid collision shell, the prompt
## appears at the yard door, and a GameState spawn request moves the player in
## the scene that is loaded next.

const MAIN := "res://scenes/main.tscn"
const FARMHOUSE := "res://scenes/farmhouse.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	await _run()
	if _failures.is_empty():
		print("SCENE DOOR CHECK: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("  FAIL: ", failure)
		print("SCENE DOOR CHECK: FAIL (%d)" % _failures.size())
		quit(1)


func _run() -> void:
	var main := _instantiate(MAIN)
	if main == null:
		return
	await _frames(10)
	_check(main.get_node_or_null("HouseCollision") != null, "main has the fantasy-house collision shell")
	var door := main.get_node_or_null("FrontDoor")
	_check(door != null, "main has the front door link")
	if door != null:
		_check(String(door.get("target_scene")) == FARMHOUSE, "the yard door enters the farmhouse")
		_check(
			(door.get("spawn_position") as Vector3).distance_to(Vector3(4.6, 0.05, 1.55)) < 0.01,
			"the yard door lands in the farmhouse hall"
		)
		var player := main.get_node_or_null("Player") as Node3D
		_check(player != null, "main has a player")
		if player != null:
			player.global_position = door.global_position + Vector3(0.0, 0.05, 1.4)
			await _frames(2)
			door.call("_refresh")
			var offer: Dictionary = door.call("touch_context")
			_check(String(offer.get("label", "")) == "ENTER", "the yard door offers ENTER on CONTEXT")
	main.queue_free()
	await _frames(3)

	var game_state := root.get_node("/root/GameState")
	game_state.request_player_spawn(Vector3(1.0, 0.05, 2.0), 45.0)
	var farmhouse := _instantiate(FARMHOUSE)
	if farmhouse == null:
		return
	await _frames(10)
	var exit_door := farmhouse.get_node_or_null("FrontDoorExit")
	_check(exit_door != null, "the farmhouse has a front door link")
	if exit_door != null:
		_check(String(exit_door.get("target_scene")) == MAIN, "the farmhouse door returns to the yard")
		_check(
			(exit_door.get("spawn_position") as Vector3).distance_to(Vector3(36.978477, 0.05, -30.9)) < 0.01,
			"the farmhouse door lands outside the fantasy house"
		)
	_check(farmhouse.get_node_or_null("FrontDoorCollision") != null, "the farmhouse front door leaf is solid")
	var player := farmhouse.get_node_or_null("Player") as Node3D
	_check(player != null, "the farmhouse has a player")
	if player != null:
		_check(
			Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(1.0, 2.0)) < 0.05,
			"the pending spawn moves the player into the new scene (got %s)" % player.global_position
		)
		_check(absf(player.rotation.y - deg_to_rad(45.0)) < 0.01, "the pending spawn applies its yaw")
	_check(game_state.consume_player_spawn().is_empty(), "the pending spawn is cleared after use")
	farmhouse.queue_free()
	await _frames(2)


func _instantiate(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		_check(false, "%s loads" % path)
		return null
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	return scene


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
