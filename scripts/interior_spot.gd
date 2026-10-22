extends Node3D

## A place to sit down or lie back in the farmhouse.
##
## The spot owns the prompt, the E / CONTEXT offer and the camera settle; the
## player controller owns the camera itself through sit_at() / stand_up().  A
## "bed" spot also runs the rest fade: the screen dims, holds a beat, comes
## back warm and shows a short notice.
##
## Touch-first rule: the prompt text goes through Device.pick, and touch_context()
## offers the same action to the CONTEXT button.

@export_enum("seat", "bed") var kind := "seat"
## Height of the eye above the spot when seated.
@export var eye_height := 1.12
## Pitch applied to the camera when seated, in degrees.
@export var look_pitch := 0.0
## Where the player is put back on the floor when standing up.
@export var stand_offset := Vector3(0.0, 0.0, 0.9)
## Text shown on the prompt and the CONTEXT button.
@export var prompt_label := "SIT"
## How close the player has to be to use the spot.
@export var reach := 1.6
## Seconds of dimming for a bed rest before it comes back.
@export var rest_hold := 1.6

var _player: Node3D
var _prompt: Label3D
var _toast: Label3D
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _seated := false
var _resting := false


func _ready() -> void:
	add_to_group("touch_context")
	add_to_group("interior_spot")
	_prompt = _make_label(eye_height + 0.50, Device.pick("E  ·  " + prompt_label, "TAP  ·  " + prompt_label))
	_toast = _make_label(eye_height + 0.85, "")
	_toast.visible = false
	if kind == "bed":
		_build_fade()
	call_deferred("_bind")


func _bind() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_bind()
		return
	_prompt.visible = not _seated and _can_use()


## CONTEXT offer: sit down, or stand back up while seated.
func touch_context() -> Dictionary:
	if _seated:
		return {"action": "interact", "label": "STAND", "priority": 6}
	if _can_use():
		return {"action": "interact", "label": prompt_label, "priority": 4}
	return {}


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if _seated:
		_stand()
		get_viewport().set_input_as_handled()
	elif _can_use():
		_sit()
		get_viewport().set_input_as_handled()


func is_seated() -> bool:
	return _seated


func _can_use() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if bool(_player.get("seated")) or bool(_player.get("mounted")):
		return false
	if not bool(_player.get("controls_enabled")):
		return false
	return _player.global_position.distance_to(global_position) <= reach


func _sit() -> void:
	_seated = true
	_prompt.visible = false
	_player.call("sit_at", global_transform, eye_height, look_pitch)
	if kind == "bed" and not _resting:
		_rest()


func _stand() -> void:
	_seated = false
	_resting = false
	_toast.visible = false
	var target := to_global(Vector3(stand_offset.x, 0.0, stand_offset.z))
	target.y = global_position.y
	_player.call("stand_up", target, global_rotation.y)


## The bed's whole reason to exist: a short fade and back, rested.
func _rest() -> void:
	_resting = true
	await get_tree().create_timer(0.7).timeout
	if not _seated:
		return
	await _fade_to(0.55, 1.0)
	await get_tree().create_timer(rest_hold).timeout
	if not _seated:
		await _fade_to(0.55, 0.0)
		return
	await _fade_to(0.75, 0.0)
	_resting = false
	_show_toast("RESTED")


func _fade_to(duration: float, target: float) -> void:
	if _fade == null:
		return
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", target, duration)
	await tween.finished


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	var tween := create_tween()
	tween.tween_interval(1.4)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.6)
	await tween.finished
	_toast.visible = false
	_toast.modulate.a = 1.0


func _make_label(height: float, text: String) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 40
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 9
	label.outline_modulate = Color(0.04, 0.03, 0.02, 1.0)
	label.modulate = Color(1.0, 0.94, 0.82, 1.0)
	label.position = Vector3(0.0, height, 0.0)
	label.visible = false
	add_child(label)
	return label


func _build_fade() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 900
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.03, 0.02, 0.015, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_fade_layer.add_child(_fade)
