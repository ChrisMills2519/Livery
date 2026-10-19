extends SceneTree

## Renders the character-select screen for review.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x720 --script res://tools/screenshot_character_select.gd
##
## Output: artifacts/character_select_chris.png, character_select_liv.png,
##         character_select_handoff.png

const SELECT := "res://scenes/character_select.tscn"

var _scene: Node3D
var _frame := 0
var _shot := 0
var _handoff_started_ms := 0


func _initialize() -> void:
	_scene = (load(SELECT) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))


func _process(_delta: float) -> bool:
	_frame += 1
	if _shot == 0:
		if _frame < 40:
			return false
		_save("chris")
		_scene._select(1)
		_shot = 1
		_frame = 0
		return false
	if _shot == 1:
		if _frame < 30:
			return false
		_save("liv")
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.physical_keycode = KEY_ENTER
		enter.pressed = true
		Input.parse_input_event(enter)
		_handoff_started_ms = Time.get_ticks_msec()
		_shot = 2
		_frame = 0
		return false
	if Time.get_ticks_msec() - _handoff_started_ms > 20000:
		push_error("handoff screenshot timed out")
		quit(1)
		return true
	var scene := current_scene
	if scene == null or scene.name != "Main":
		return false
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	if player == null or not player.mounted:
		return false
	var fade := root.get_node_or_null("SceneFade")
	if fade != null and fade.has_method("is_transitioning") and fade.is_transitioning():
		return false
	if _frame < 10:
		return false
	_save("handoff")
	quit(0)
	return true


func _save(label: String) -> void:
	var image := root.get_texture().get_image()
	var target := "res://artifacts/character_select_%s.png" % label
	var err := image.save_png(ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("failed to save " + target)
		quit(1)
		return
	var who := label
	if label != "handoff":
		who = _scene._previews[_scene._selected]["profile"].display_name
	print("saved %s (%dx%d) selected=%s" % [
		target, image.get_width(), image.get_height(), who
	])
