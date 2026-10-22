extends SceneTree

## Renders the footprint trail for review: the horse ridden at walk and the
## character walking on foot, then a wide shot and a ground-level close-up.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --fixed-fps 30 --resolution 960x540 \
##     --script res://tools/screenshot_footprints.gd
##
## --fixed-fps keeps the simulation at 60 Hz under software rendering.  Without
## it llvmpipe renders at a few frames a second, the walk clips are sampled too
## coarsely to find their foot contacts, and almost no prints are laid.
##
## This is also the render pass for the footprint shader: headless runs never
## compile it, so a shader error or an unsupported render mode only shows up
## here.

const MAIN := "res://scenes/main.tscn"

var _world: Node3D
var _player: CharacterBody3D
var _horse: CharacterBody3D
var _trail: Node3D
var _camera: Camera3D

var _frame := 0


func _initialize() -> void:
	_world = (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	_camera = Camera3D.new()
	_camera.name = "FootprintReviewCamera"
	_camera.fov = 52.0
	_camera.near = 0.05
	_camera.far = 400.0
	root.add_child(_camera)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame % 25 == 0:
		print("  frame %d, %d prints" % [_frame, int(_trail.call("stamped_count")) if _trail != null else 0])
	if _frame == 5:
		_stage()
	elif _frame == 8:
		_player.call("try_mount")
		if not bool(_player.get("mounted")):
			push_error("footprint render: could not mount for the ride pass")
			quit(1)
			return true
	elif _frame == 12:
		Input.action_press("move_forward")
	elif _frame == 57:
		Input.action_release("move_forward")
		_player.call("dismount")
	elif _frame == 60:
		_horse.velocity = Vector3.ZERO
		_player.global_position = Vector3(4.2, 0.05, -8.0)
		_player.rotation.y = 0.0
		_player.velocity = Vector3.ZERO
		Input.action_press("move_forward")
	elif _frame == 135:
		Input.action_release("move_forward")
	elif _frame == 140:
		# Wide shot down both trails.
		_camera.global_position = Vector3(8.6, 2.7, -5.6)
		_camera.look_at(Vector3(4.8, 0.0, -12.6), Vector3.UP)
		_camera.current = true
	elif _frame == 143:
		_report_camera()
		_capture("footprints_yard")
	elif _frame == 146:
		# Ground-level close-up between the two trails.
		_camera.global_position = Vector3(5.1, 0.62, -8.6)
		_camera.look_at(Vector3(5.2, 0.0, -11.0), Vector3.UP)
	elif _frame == 149:
		_capture("footprints_closeup")
	elif _frame == 152:
		# Straight down over both trails: the clearest read of the shapes.
		_camera.global_position = Vector3(5.1, 8.0, -10.8)
		_camera.look_at(Vector3(5.1, 0.0, -10.79), Vector3(0.0, 0.0, -1.0))
	elif _frame == 155:
		_capture("footprints_top")
		var count := int(_trail.call("stamped_count"))
		print("footprint renders: %d prints on the trail" % count)
		if count < 6:
			push_error("footprint render: too few prints to review (%d)" % count)
			quit(1)
			return true
		quit(0)
		return true
	return false


func _report_camera() -> void:
	var active := root.get_camera_3d()
	print(
		"  camera %s at %s (active: %s)" % [
			_camera.name, str(_camera.global_position),
			active.name if active != null else "none",
		]
	)
	var trail: Array[String] = []
	for i in range(int(_trail.call("slot_count"))):
		var slot := _trail.call("get_slot", i) as Dictionary
		if not slot.is_empty():
			trail.append("%s/%d" % [str((slot["position"] as Vector3).snapped(Vector3.ONE * 0.1)), int(slot["kind"])])
	print("  trail: ", ", ".join(trail))


func _stage() -> void:
	_player = _world.get_node("Player") as CharacterBody3D
	_horse = _world.get_node("Horse") as CharacterBody3D
	_trail = _world.get_node("Footprints") as Node3D
	for n in _world.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	for m in _horse.find_children("*", "Label3D", true, false):
		(m as Label3D).visible = false
	for m in _player.find_children("*", "Label3D", true, false):
		(m as Label3D).visible = false
	# Open grass west of the yard: the horse rides away from the camera along
	# -Z, then the character walks the same direction a couple of metres over.
	_horse.global_position = Vector3(6.0, 0.0, -10.0)
	_horse.rotation.y = 0.0
	_horse.velocity = Vector3.ZERO
	_player.global_position = Vector3(7.4, 0.05, -10.0)
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO


func _capture(name: String) -> void:
	var image := root.get_texture().get_image()
	var target := "res://artifacts/%s.png" % name
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
		quit(1)
		return
	print("saved ", target)
