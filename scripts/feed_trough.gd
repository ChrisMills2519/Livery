extends Node3D

## The feed trough: hay for the horse, bought at the store across the yard.
##
## A station like the stable door: the player stands at it, the horse has to be
## within reach, and one prompt serves both the E key and the touch CONTEXT
## button.  The horse eats through its own `feed()`, so the needs, the trust gain
## and the record back into `HorseState` stay in one place, and a bale is only
## taken from the yard when the horse actually ate it.

const StationProximity := preload("res://scripts/station_proximity.gd")

@export var player_range := 3.0
@export var horse_range := 3.5
@export var prompt_height := 1.15

var _player: Node3D
var _horse: Node3D
var _prompt: Label3D
var _can_use := false
var _tick := 0.0
var _flash_until := 0
var _flash_text := ""
## Whether this station is the one currently hiding the mount prompt.  Only the
## edges are written, so two stations in one scene cannot flicker the flag at
## each other every refresh.
var _suppressing := false


## CONTEXT offer while the player stands at a full trough with a horse beside
## it.  Refusals do not offer anything, so the button never implies an action
## that cannot happen.
func touch_context() -> Dictionary:
	if not _can_use:
		return {}
	return {"action": "interact", "label": "FEED", "priority": 2}


func _ready() -> void:
	add_to_group("touch_context")
	add_to_group("feed_station")
	_build_prompt()
	call_deferred("_bind")


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.name = "FeedPrompt"
	_prompt.position = Vector3(0.0, prompt_height, 0.0)
	_prompt.pixel_size = 0.006
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 44
	_prompt.outline_size = 9
	_prompt.outline_modulate = Color(0.05, 0.06, 0.04, 1.0)
	_prompt.modulate = Color(1.0, 0.96, 0.82, 1.0)
	_prompt.visible = false
	add_child(_prompt)


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_horse = get_tree().get_first_node_in_group("horse") as Node3D


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.10:
		return
	_tick = 0.0
	_refresh()
	_apply_suppression(_can_use)


## Recomputes the prompt and the interaction gate; also called from `_input`, so
## a press on the frame the player arrives still lands.
func _refresh() -> bool:
	if _player == null or _horse == null:
		_bind()
	_can_use = false
	if _player == null or _horse == null or _prompt == null:
		return false
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var player_near := to_player.length() <= player_range
	# The store is the other feed station and a single interact event is claimed
	# by one node, so the nearest station wins the prompt and the press.  The two
	# stand apart now; the rule stays because it is what stopped the store
	# swallowing FEED when their ranges overlapped.
	if player_near and not _is_nearest_station():
		player_near = false
	var horse_near := _horse.global_position.distance_to(global_position) <= horse_range
	var mounted := bool(_player.get("mounted"))
	var boarded := bool(_horse.get("boarded"))

	_prompt.visible = player_near
	if not player_near:
		return false
	if mounted:
		_prompt.text = Device.pick("E  ·  DISMOUNT TO FEED", "TAP  ·  DISMOUNT TO FEED")
		return false
	if boarded:
		_prompt.text = "BRING YOUR HORSE OUT OF THE STABLE"
		return false
	if not horse_near:
		_prompt.text = "BRING YOUR HORSE TO THE TROUGH"
		return false

	var has_hay: bool = GameState.hay > 0
	if Time.get_ticks_msec() < _flash_until:
		_prompt.text = _flash_text
	elif not has_hay:
		_prompt.text = "NO HAY  ·  BUY A BALE AT THE STORE"
	else:
		_prompt.text = Device.pick("E  ·  FEED HAY  (%d in the yard)", "FEED  ·  %d in the yard") % GameState.hay

	# A flash is feedback, not permission: out of hay there is nothing to offer,
	# even while the last message is still on screen.
	if not has_hay:
		return false
	_can_use = true
	return true


## The trough owns E while it is usable, so the mount prompt underneath steps
## aside.  Only the edges are written: two stations sharing this flag would
## otherwise flip it at each other every refresh.
func _apply_suppression(on: bool) -> void:
	if on == _suppressing or _horse == null:
		return
	_horse.set("mount_prompt_suppressed", on)
	_suppressing = on


func _is_nearest_station() -> bool:
	return StationProximity.is_nearest(_player, self, "feed_station")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if not event.is_action_pressed("interact"):
		return
	if not _refresh():
		return
	get_viewport().set_input_as_handled()
	_use()


## The horse eats first and the bale is taken afterwards, so a refusal never
## costs hay.  `_refresh()` has already gated on a bale being in the yard, so the
## take cannot fail in the same frame.
func _use() -> void:
	var result: Dictionary = _horse.call("feed")
	if not bool(result.get("ok", false)):
		_flash(String(result.get("message", "Your horse is not hungry.")))
		return
	GameState.use_hay()
	_flash(String(result.get("message", "Your horse eats the hay.")))
	_refresh()


func _flash(text: String) -> void:
	_flash_text = text
	_flash_until = Time.get_ticks_msec() + 2500
	if _prompt != null:
		_prompt.text = text
		_prompt.visible = true
