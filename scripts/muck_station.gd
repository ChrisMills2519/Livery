extends Node3D

## The muck-out point: the stable's bed, worked from beside the stall door.
##
## Mucking out is the third care chore the GDD asks for (feeding, grooming and
## stall cleaning).  The bed soils while the horse is stabled, and clearing it is
## what keeps the horse comfortable and its health drifting up - see
## `horse.gd` for the rates and `muck_session.gd` for the work itself.
##
## This node owns only the physical station: the proximity prompt, the refusal
## copy and the handoff into the session child.  It joins the stable door in the
## `stable_station` group, because the two stand close enough for their ranges
## to overlap and one `interact` event is claimed by one node.

const GROUP := "stable_station"
const StationProximity := preload("res://scripts/station_proximity.gd")

@export var player_range := 3.2
@export var prompt_height := 1.5
## The horse has to be at the yard, the same rule the stable door uses: the
## stall it lives in is only worth mucking while the horse is here to use it.
@export var horse_range := 14.0

@onready var session: Node = $Session

var _player: Node3D
var _horse: Node3D
var _prompt: Label3D
var _can_use := false
var _tick := 0.0
var _flash_until := 0
var _flash_text := ""


## CONTEXT offer: muck the bed out once the horse is at the yard and the bed is
## actually dirty.  Below the stable door's priority, so a phone shows one offer
## per spot even in the frame between the two stations refreshing.
func touch_context() -> Dictionary:
	if not _can_use:
		return {}
	return {"action": "interact", "label": "MUCK OUT", "priority": 2}


func _ready() -> void:
	add_to_group("touch_context")
	add_to_group(GROUP)
	_build_prompt()
	call_deferred("_bind")


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.name = "MuckPrompt"
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


## Recomputes the prompt and the interaction gate.  Also called from `_input`, so
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
	if player_near and not StationProximity.is_nearest(_player, self, GROUP):
		player_near = false
	var busy := session != null and bool(session.get("active"))
	_prompt.visible = player_near and not busy
	if not player_near or busy:
		return false
	if bool(_player.get("mounted")):
		_prompt.text = Device.pick("E  ·  DISMOUNT TO MUCK OUT", "TAP  ·  DISMOUNT TO MUCK OUT")
		return false
	if not _horse_at_the_yard():
		_prompt.text = "BRING YOUR HORSE TO THE STABLE"
		return false
	# A flash is feedback, not permission: the text and the gate are computed
	# separately, so a refusal can never leave an offer on screen.
	if Time.get_ticks_msec() < _flash_until:
		_prompt.text = _flash_text
		return false
	if not HorseState.needs_mucking():
		_prompt.text = "THE BED IS CLEAN"
		return false
	_prompt.text = Device.pick("E  ·  MUCK OUT  (%d%% SOILED)", "MUCK OUT  (%d%% SOILED)") % \
		int(round(HorseState.stall_muck * 100.0))
	_can_use = true
	return true


func _horse_at_the_yard() -> bool:
	if _horse == null:
		return false
	if bool(_horse.get("boarded")):
		return true
	return _horse.global_position.distance_to(global_position) <= horse_range


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if not event.is_action_pressed("interact"):
		return
	if not _refresh():
		return
	get_viewport().set_input_as_handled()
	start_session()


## Starts the session, and reports a refusal on this station's own prompt rather
## than leaving the press looking like it did nothing.
func start_session() -> bool:
	if session == null:
		return false
	if not bool(session.call("enter")):
		_flash("The bed cannot be mucked out just now.")
		return false
	_refresh()
	return true


func _flash(text: String) -> void:
	if text.is_empty():
		return
	_flash_text = text
	_flash_until = Time.get_ticks_msec() + 2500
	if _prompt != null:
		_prompt.text = text
		_prompt.visible = true
