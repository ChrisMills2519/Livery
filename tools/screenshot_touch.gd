extends SceneTree

## Renders the touch UI for review: the ride view with the stick held and the
## CONTEXT cluster showing, the grooming view, and the character-select screen.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_touch.gd
##
## Output: artifacts/touch_ride.png, touch_groom.png, touch_select.png

const MAIN := "res://scenes/main.tscn"
const SELECT := "res://scenes/character_select.tscn"

var _touch
var _scene: Node
var _frame := 0
var _step := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	_touch = root.get_node_or_null("TouchControls")
	var device := root.get_node_or_null("Device")
	if _touch == null or device == null:
		push_error("touch autoloads are missing")
		quit(1)
		return
	device.set_touch_mode(1)
	_load(MAIN)


func _process(_delta: float) -> bool:
	_frame += 1
	match _step:
		0:
			# Ride: hold the stick forward and let the CONTEXT label settle.
			if _frame < 60:
				return false
			_touch.feed_touch(0, Vector2(220, 520), true)
			_touch.feed_drag(0, Vector2(220, 430), Vector2(0, -90))
			if _frame < 90:
				return false
			_save("touch_ride")
			_touch.feed_touch(0, Vector2(220, 430), false)
			_begin_groom()
			return false
		1:
			# Grooming: wait for the coat bake, then capture the session.
			if _frame < 150:
				return false
			_save("touch_groom")
			_load_select()
			return false
		2:
			if _frame < 60:
				return false
			_save("touch_select")
			quit(0)
			return true
	return false


func _load(path: String) -> void:
	if _scene != null:
		root.remove_child(_scene)
		_scene.free()
	_scene = (load(path) as PackedScene).instantiate()
	root.add_child(_scene)
	current_scene = _scene
	_frame = 0


func _begin_groom() -> void:
	var bay := _scene.get_node_or_null("GroomingBay")
	var horse := _scene.get_node_or_null("Horse") as Node3D
	var player := _scene.get_node_or_null("Player") as Node3D
	if bay == null or horse == null or player == null:
		push_error("grooming scene nodes are missing")
		quit(1)
		return
	player.global_position = (bay.get_node("GroomerAnchor") as Marker3D).global_position
	horse.global_position = (bay.get_node("HorseAnchor") as Marker3D).global_position
	bay.call("_process", 0.2)
	var event := InputEventAction.new()
	event.action = "groom"
	event.pressed = true
	event.strength = 1.0
	bay.call("_unhandled_input", event)
	_step = 1
	_frame = 0


func _load_select() -> void:
	_load(SELECT)
	_step = 2
	_frame = 0


func _save(label: String) -> void:
	var image := root.get_texture().get_image()
	var target := "res://artifacts/%s.png" % label
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
		quit(1)
		return
	print("saved %s (%dx%d)" % [target, image.get_width(), image.get_height()])
