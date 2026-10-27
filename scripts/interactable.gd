extends Node3D

## A thing the player can use by looking at it and pressing E (or CONTEXT on touch).
##
## The player controller's aim ray finds the nearest node in the "interactable"
## group.  The node provides a label and runs `action` when used.  The prompt
## text goes through Device.pick, so touch players see the touch wording.

signal used

## Text shown on the prompt and the CONTEXT button.
@export var prompt_label := "USE"
## Reach measured from the player's body, in metres.  Zero means the target
## is only reached by the camera ray.  Low targets such as a bowl set this.
@export var body_reach := 0.0
## Name of the method called on `target` when used, if set.
@export var action_method := ""
## Node the action is called on.  Defaults to this node.
@export var action_target: Node

var _prompt: Label3D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("touch_context")
	_prompt = Label3D.new()
	_prompt.name = "InteractPrompt"
	_prompt.pixel_size = 0.005
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 36
	_prompt.outline_size = 9
	_prompt.outline_modulate = Color(0.04, 0.03, 0.02, 1.0)
	_prompt.modulate = Color(1.0, 0.94, 0.82, 1.0)
	_prompt.position = Vector3(0.0, 0.6, 0.0)
	_prompt.visible = false
	add_child(_prompt)


## Shown by the player controller while this is the aimed-at target.
func show_prompt(show: bool) -> void:
	if _prompt == null:
		return
	_prompt.visible = show
	if show:
		_prompt.text = Device.pick("E  ·  " + prompt_label, "TAP  ·  " + prompt_label)


## CONTEXT offer for touch players while the target is aimed at.
func touch_context() -> Dictionary:
	if _prompt != null and _prompt.visible:
		return {"action": "interact", "label": prompt_label, "priority": 3}
	return {}


## Runs the action.  Returns true when something was used.
func use() -> bool:
	used.emit()
	var receiver: Node = action_target if action_target != null else self
	if action_method.is_empty() or not receiver.has_method(action_method):
		return true
	receiver.call(action_method)
	return true
