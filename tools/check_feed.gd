extends SceneTree

## Headless check for feeding the dog from the bowl in the farmhouse.
##
##   godot --headless --path . --script res://tools/check_feed.gd
##
## Aims the player at the bowl, confirms the feed target is the aimed
## interactable, uses it, and confirms the dog enters the EAT state.

const SCENE := "res://scenes/farmhouse.tscn"

var _failures: Array[String] = []
var _world: Node3D
var _player: CharacterBody3D
var _dog: CharacterBody3D
var _stage := 0
var _wait := 0


func _initialize() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		_check(false, "farmhouse scene loads")
		_finish()
		return
	_world = packed.instantiate() as Node3D
	root.add_child(_world)
	_player = _world.get_node_or_null("Player") as CharacterBody3D
	_dog = _world.get_node_or_null("Dog/Body") as CharacterBody3D
	_check(_player != null, "farmhouse has a player")
	_check(_dog != null, "farmhouse has a dog body")


func _physics_process(_delta: float) -> bool:
	if _player == null or _dog == null:
		_finish()
		return true
	_wait += 1
	if _wait < 4:
		return false
	_wait = 0
	match _stage:
		0:
			_aim_at_bowl()
			_stage = 1
		1:
			var target := _player.call("aim_target") as Node
			_check(target != null and target.name == "FeedTarget", "the bowl is the aimed interactable")
			if target != null:
				target.call("use")
			_stage = 2
		2:
			_check(_dog.call("get_state_name") == "eat", "using the bowl sends the dog to eat (got %s)" % _dog.call("get_state_name"))
			_finish()
			return true
	return false


## Stands the player a short way from the bowl, facing it.
func _aim_at_bowl() -> void:
	var bowl := _world.get_node_or_null("Dog/BowlSpot") as Node3D
	if bowl == null:
		_check(false, "bowl spot exists")
		return
	var bowl_pos := bowl.global_position
	# Stand 0.9 m south of the bowl, facing it.  Reach is measured from the body,
	# so the bowl counts without the camera having to pitch down at it.
	_player.global_position = bowl_pos + Vector3(0.0, 0.05, 0.9)
	_player.rotation.y = 0.0
	_player.set("controls_enabled", true)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS: %s" % label)
	else:
		print("  FAIL: %s" % label)
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("FEED CHECK: PASS")
		quit(0)
	else:
		print("FEED CHECK: FAIL (%d)" % _failures.size())
		quit(1)
