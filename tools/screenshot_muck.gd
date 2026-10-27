extends SceneTree

## Renders the muck-out chore: the approach at the stable, the soiled bed through
## the session's own camera, the bed part-scooped, and the clean bed with the
## result card.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_muck.gd
##
## The session shots use the session's camera, not a review camera, so they show
## the view a player actually gets.

const MAIN := "res://scenes/main.tscn"

var _frame := 0
var _shot := 0
var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _station: Node3D
var _session: Node
var _camera: Camera3D


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	_camera = Camera3D.new()
	_camera.name = "MuckReviewCamera"
	_camera.fov = 48.0
	_camera.far = 400.0
	root.add_child(_camera)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 4:
		_stage()
	elif _frame == 10 and _shot == 0:
		_capture("muck_approach")
		_start_chore()
	elif _frame == 24 and _shot == 1:
		_capture("muck_dirty")
		_scoop(3)
	elif _frame == 34 and _shot == 2:
		_capture("muck_scooped")
		_scoop(99)
	elif _frame == 44 and _shot == 3:
		_capture("muck_clean")
		quit(0)
		return true
	return false


func _stage() -> void:
	_player = _world.get_node("Player") as CharacterBody3D
	_horse = _world.get_node("Horse") as CharacterBody3D
	_station = _world.find_child("MuckStation", true, false) as Node3D
	if _station != null:
		_session = _station.get_node_or_null("Session")
	# The bed is written in both places the game reads it from.
	if _session != null:
		var state := root.get_node("HorseState")
		state.call("set_stall_muck", 1.0)
	_horse.set("stall_muck", 1.0)
	# The mount prompt would hang over the yard in every frame; every other
	# Label3D on the horse is hidden for the same reason.
	for label in _horse.find_children("*", "Label3D", true, false):
		(label as Label3D).visible = false
	if _player == null or _station == null:
		push_error("the level has no player or muck point")
		quit(1)
		return
	_player.global_position = _station.global_position + Vector3(0.4, 0.0, 1.5)
	_player.set("velocity", Vector3.ZERO)
	_station.call("_refresh")
	# The approach: the yard's south-east, looking at the stable front, the muck
	# tub and the prompt over it.
	_camera.global_position = Vector3(-2.2, 2.6, -14.2)
	_camera.look_at(Vector3(-7.4, 1.2, -21.5), Vector3.UP)
	_camera.current = true


func _start_chore() -> void:
	if _station == null:
		return
	_station.call("start_session")
	if _session == null or not bool(_session.get("active")):
		push_error("the muck session did not start")
		quit(1)
		return
	# The session fades in over 0.3 s of wall clock, which a headless frame loop
	# cannot be relied on to wait out.
	var tween = _session.get("_fade_tween")
	if tween != null and tween.is_valid():
		tween.kill()
	var fade := _session.get("_fade") as ColorRect
	if fade != null:
		fade.color.a = 0.0


## Scoops from the bed through the session's own picking, so the shot shows the
## real removal path rather than a hidden flag.
func _scoop(count: int) -> void:
	if _session == null:
		return
	var camera: Camera3D = _session.get("_camera")
	var taken := 0
	while taken < count and int(_session.call("clumps_remaining")) > 0:
		var index := int(_session.call("clumps_remaining")) - 1
		var point: Vector3 = _session.call("clump_position", index)
		if not bool(_session.call("scoop_at_screen", camera.unproject_position(point))):
			break
		taken += 1


func _capture(name: String) -> void:
	var image := root.get_texture().get_image()
	var target := "res://artifacts/%s.png" % name
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
		quit(1)
		return
	print("saved ", target)
	_shot += 1
