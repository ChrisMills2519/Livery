extends Node3D

## A door that swaps to another scene.
##
## The door owns its proximity prompt and the E / CONTEXT offer.  On use it
## asks GameState for a player spawn in the target scene, then fades through
## SceneFade.  The player controller consumes that spawn once the new scene is
## ready, so the same door works in both directions without either scene
## knowing about the other's layout.

@export_file("*.tscn") var target_scene := ""
## Text shown on the prompt and the CONTEXT button.
@export var prompt_label := "ENTER"
## Height of the prompt above the door anchor.
@export var prompt_height := 2.60
## How close the player has to be, measured on the ground plane.
@export var reach := 2.60
## Reach used by the aim path, measured from the player's body.
@export var body_reach := 1.6
## Where the player stands in the target scene.
@export var spawn_position := Vector3.ZERO
## Facing in the target scene, in degrees.
@export var spawn_yaw_degrees := 0.0

var _player: Node3D
var _prompt: Label3D
var _can_use := false
var _entering := false
var _tick := 0.0


func _ready() -> void:
	add_to_group("touch_context")
	add_to_group("interactable")
	_build_prompt()
	call_deferred("_bind")


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.name = "DoorPrompt"
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
	_player = get_tree().get_first_node_in_group("player") as Node3D


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.10:
		return
	_tick = 0.0
	_refresh()


## CONTEXT offer at the door, for touch players.
## Aim path: the prompt is driven by the player's aim, not by proximity alone.
func show_prompt(show: bool) -> void:
	if _prompt != null and show:
		_prompt.visible = true


## Aim-path use: the player's interact on this door enters it.
func use() -> bool:
	if _entering or not _refresh():
		return false
	_enter()
	return true


func touch_context() -> Dictionary:
	if _can_use:
		return {"action": "interact", "label": prompt_label, "priority": 5}
	return {}


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if _entering:
		return
	if not _refresh():
		return
	get_viewport().set_input_as_handled()
	_enter()


## Recomputes the prompt and interaction gate.  Also called directly from
## _unhandled_input so a key press on the frame the player arrives still lands.
func _refresh() -> bool:
	if _player == null or not is_instance_valid(_player):
		_bind()
	if _player == null or not is_instance_valid(_player) or _prompt == null:
		_can_use = false
		return false
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var near := to_player.length() <= reach
	var available := (
		not bool(_player.get("mounted"))
		and not bool(_player.get("seated"))
		and bool(_player.get("controls_enabled"))
	)
	_can_use = near and available and not _entering
	_prompt.visible = _can_use
	if _prompt.visible:
		_prompt.text = Device.pick("E  ·  " + prompt_label, "TAP  ·  " + prompt_label)
	return _can_use


func _enter() -> void:
	if target_scene.is_empty():
		push_error("SceneDoor: no target scene set on %s" % name)
		return
	var fade := get_node_or_null("/root/SceneFade")
	if fade != null and fade.has_method("is_transitioning") and fade.is_transitioning():
		return
	_entering = true
	_prompt.visible = false
	if GameState.has_method("request_player_spawn"):
		GameState.request_player_spawn(spawn_position, spawn_yaw_degrees)
	if fade != null and fade.has_method("change_scene"):
		fade.change_scene(target_scene)
	else:
		var err := get_tree().change_scene_to_file(target_scene)
		if err != OK:
			push_error("SceneDoor: cannot change to %s (error %d)" % [target_scene, err])
			_entering = false
