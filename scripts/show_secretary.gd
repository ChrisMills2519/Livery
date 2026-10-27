extends Node3D

## Entry desk and rosette stand for the showground.
##
## `mode = "entry"` takes the class fee and enters the rider; `mode = "rosette"`
## hands over a rosette earned by a top-three finish.  Both follow the project's
## proximity + aim interaction pattern so keyboard and touch players see the
## same prompt through Device.pick.

@export_enum("entry", "rosette") var mode := "entry"
@export var prompt_label := "ENTER CLASS"
@export var prompt_height := 1.55
@export var reach := 2.6
@export var body_reach := 1.6

var _course: Node
var _player: Node3D
var _prompt: Label3D
var _tick := 0.0
var _can_use := false


func _ready() -> void:
	add_to_group("touch_context")
	add_to_group("interactable")
	_build_prompt()
	call_deferred("_bind")


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.name = "ArenaPrompt"
	_prompt.position = Vector3(0.0, prompt_height, 0.0)
	_prompt.pixel_size = 0.005
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 36
	_prompt.outline_size = 9
	_prompt.outline_modulate = Color(0.04, 0.03, 0.02, 1.0)
	_prompt.modulate = Color(1.0, 0.94, 0.82, 1.0)
	_prompt.visible = false
	add_child(_prompt)


func _bind() -> void:
	_course = get_tree().get_first_node_in_group("show_class")
	_player = get_tree().get_first_node_in_group("player") as Node3D


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.10:
		return
	_tick = 0.0
	_refresh()


func show_prompt(show: bool) -> void:
	if _prompt != null and show:
		_prompt.visible = true


func use() -> bool:
	if not _refresh():
		return false
	if mode == "entry":
		_course.call("request_entry")
	else:
		_course.call("collect_rosette")
	_refresh()
	return true


func touch_context() -> Dictionary:
	if _can_use:
		return {"action": "interact", "label": _button_label(), "priority": 5}
	return {}


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if not _refresh():
		return
	get_viewport().set_input_as_handled()
	use()


func _button_label() -> String:
	if _course == null:
		return prompt_label
	if mode == "rosette":
		return "COLLECT ROSETTE"
	if bool(_course.get("entered")):
		return "ENTERED"
	return "%s · £%d" % [prompt_label, int(_course.get("entry_fee"))]


func _refresh() -> bool:
	if _course == null or not is_instance_valid(_course):
		_bind()
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _course == null or _player == null:
		_can_use = false
		_prompt.visible = false
		return false
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var near := to_player.length() <= reach
	var available := (
		not bool(_player.get("mounted"))
		and not bool(_player.get("seated"))
		and bool(_player.get("controls_enabled"))
	)
	_can_use = near and available and _offer_available()
	_prompt.visible = _can_use
	if _prompt.visible:
		_prompt.text = Device.pick("E  ·  " + _button_label(), "TAP  ·  " + _button_label())
	return _can_use


func _offer_available() -> bool:
	if mode == "entry":
		return not bool(_course.get("entered")) and String(_course.get("state")) != "running"
	if _course.has_method("can_collect_rosette"):
		return bool(_course.call("can_collect_rosette"))
	return false
