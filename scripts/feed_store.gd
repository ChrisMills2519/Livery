extends Node3D

## The feed store: where money becomes hay.
##
## Until this existed, money only ever left the wallet as a competition entry
## fee, so earning had no use.  The bin sells one bale at a time through
## `GameState.buy_hay()`, which owns the price and the refusal, and the message
## it returns is shown on this station's own prompt - a refusal needs no second
## UI path and works the same on a phone.

@export var player_range := 3.0
@export var prompt_height := 1.45

var _player: Node3D
var _prompt: Label3D
var _can_use := false
var _tick := 0.0
var _flash_until := 0
var _flash_text := ""


func touch_context() -> Dictionary:
	if not _can_use:
		return {}
	return {"action": "interact", "label": "BUY HAY", "priority": 2}


func _ready() -> void:
	add_to_group("touch_context")
	add_to_group("feed_station")
	_build_prompt()
	call_deferred("_bind")


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.name = "StorePrompt"
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


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.10:
		return
	_tick = 0.0
	_refresh()


func _refresh() -> bool:
	if _player == null:
		_bind()
	_can_use = false
	if _player == null or _prompt == null:
		return false
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var player_near := to_player.length() <= player_range
	# The trough stands inside this station's range and one interact event is
	# claimed by one node, so the nearest station wins the prompt and the press.
	if player_near and not _is_nearest_station():
		player_near = false
	_prompt.visible = player_near
	if not player_near:
		return false
	if bool(_player.get("mounted")):
		_prompt.text = Device.pick("E  ·  DISMOUNT TO SHOP", "TAP  ·  DISMOUNT TO SHOP")
		return false
	var affordable: bool = GameState.money >= GameState.HAY_PRICE
	if Time.get_ticks_msec() < _flash_until:
		_prompt.text = _flash_text
	elif not affordable:
		_prompt.text = "A BALE IS £%d  —  YOU HAVE £%d" % [GameState.HAY_PRICE, GameState.money]
	else:
		_prompt.text = Device.pick("E  ·  BUY HAY  £%d  (%d in the yard)",
			"BUY HAY  £%d  (%d in the yard)") % [GameState.HAY_PRICE, GameState.hay]
	# A flash is feedback, not permission.
	if not affordable:
		return false
	_can_use = true
	return true


func _is_nearest_station() -> bool:
	if _player == null:
		return true
	var mine := _player.global_position.distance_to(global_position)
	for other in get_tree().get_nodes_in_group("feed_station"):
		if other == self or not (other as Node3D).is_inside_tree():
			continue
		if _player.global_position.distance_to((other as Node3D).global_position) < mine - 0.05:
			return false
	return true


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if not event.is_action_pressed("interact"):
		return
	if not _refresh():
		return
	get_viewport().set_input_as_handled()
	var result: Dictionary = GameState.buy_hay()
	_flash(String(result.get("message", "")))
	_refresh()


func _flash(text: String) -> void:
	if text.is_empty():
		return
	_flash_text = text
	_flash_until = Time.get_ticks_msec() + 2500
	if _prompt != null:
		_prompt.text = text
		_prompt.visible = true
