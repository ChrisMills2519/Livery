extends SceneTree

## Renders the stable handover: horse at the door, boarded, and brought back.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_stable.gd

const MAIN := "res://scenes/main.tscn"

var _frame := 0
var _shot := 0
var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _stable: Node3D
var _camera: Camera3D


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	_camera = Camera3D.new()
	_camera.name = "StableReviewCamera"
	_camera.fov = 48.0
	_camera.far = 400.0
	root.add_child(_camera)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 4:
		_player = _world.get_node("Player") as CharacterBody3D
		_horse = _world.get_node("Horse") as CharacterBody3D
		_stable = _world.get_node("Stable") as Node3D
		for n in _world.find_children("*", "CanvasLayer", true, false):
			(n as CanvasLayer).visible = false
		for m in _horse.find_children("*", "Label3D", true, false):
			(m as Label3D).visible = false
		_stage()
	elif _frame == 10 and _shot == 0:
		_capture("stable_boarding")
		_send_interact()
	elif _frame == 20 and _shot == 1:
		_capture("stable_boarded")
		_send_interact()
	elif _frame == 45 and _shot == 2:
		_capture("stable_released")
		quit(0)
		return true
	return false


func _stage() -> void:
	var stall := _stable.get_node("HorseStall") as Marker3D
	var use := _stable.get_node("UseAnchor") as Marker3D
	_horse.global_position = stall.global_position
	_horse.rotation.y = 0.0
	_horse.velocity = Vector3.ZERO
	_player.global_position = use.global_position
	_player.rotation.y = PI
	_player.velocity = Vector3.ZERO
	_stable.call("_refresh")
	_camera.global_position = Vector3(-1.6, 3.2, -13.5)
	_camera.look_at(Vector3(-7.0, 1.5, -24.0), Vector3.UP)
	_camera.current = true


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


func _send_interact() -> void:
	_stable.call("_refresh")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = true
	_stable.call("_input", event)
