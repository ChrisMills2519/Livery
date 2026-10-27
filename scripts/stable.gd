extends Node3D

## The stable's boarding point.
##
## The horse no longer trails the player around the yard, so this is how it is
## put away and brought back out.  The player stands at the use anchor outside
## the stall door; the horse must be led here (ridden back) before it can be
## stabled.  Bringing it out always works and places it at the stall marker.

## The muck-out point is the other station at this end of the yard.  See
## `station_proximity.gd` for why an overlapping pair needs one rule.
const STATION_GROUP := "stable_station"
const StationProximity := preload("res://scripts/station_proximity.gd")

@export var player_range := 3.4
@export var horse_range := 12.0
@export var prompt_height := 2.35

@onready var stall: Marker3D = $HorseStall
@onready var use_anchor: Marker3D = $UseAnchor

var _player: Node3D
var _horse: Node3D
var _prompt: Label3D
var _can_use := false
var _tick := 0.0


## CONTEXT offer at the stable door: bring the horse out or put it away.  It
## outranks the horse's own MOUNT offer while the stable prompt is showing.
func touch_context() -> Dictionary:
	if not _can_use:
		return {}
	if bool(_horse.get("boarded")):
		return {"action": "interact", "label": "HORSE OUT", "priority": 3}
	return {"action": "interact", "label": "PUT AWAY", "priority": 3}


func _ready() -> void:
	add_to_group("touch_context")
	# Joined, not merely declared: a station that is not in the group cannot be
	# compared against, and the nearer-offer rule then never fires for the pair.
	add_to_group(STATION_GROUP)
	_build_prompt()
	call_deferred("_bind")


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.name = "StablePrompt"
	_prompt.position = use_anchor.position + Vector3(0.0, prompt_height, 0.0)
	_prompt.pixel_size = 0.006
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 48
	_prompt.outline_size = 9
	_prompt.outline_modulate = Color(0.05, 0.06, 0.04, 1.0)
	_prompt.modulate = Color(1.0, 0.96, 0.82, 1.0)
	_prompt.visible = false
	add_child(_prompt)


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_horse = get_tree().get_first_node_in_group("horse") as Node3D


## This station offers from the stall door, and the node itself is the middle of
## the building 4.7 m away.  See `station_proximity.gd`.
func claim_point() -> Vector3:
	return use_anchor.global_position


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.10:
		return
	_tick = 0.0
	_refresh()


## Recomputes the prompt and interaction gate.  Also called directly from
## _input so a key press on the frame the player arrives still lands.
func _refresh() -> bool:
	if _player == null or _horse == null:
		_bind()
	if _player == null or _horse == null or _prompt == null:
		_can_use = false
		return false
	var to_player := _player.global_position - use_anchor.global_position
	to_player.y = 0.0
	var player_near := to_player.length() <= player_range
	var mounted := bool(_player.get("mounted"))
	var boarded := bool(_horse.get("boarded"))
	var horse_near := _horse.global_position.distance_to(stall.global_position) <= horse_range

	# Only the nearest of the pair claims the spot, so the two prompts never
	# stand over one patch of yard and one `interact` press is never swallowed.
	# The claim is what the prompt and the press follow.
	var here: bool = player_near and StationProximity.is_nearest(_player, self, STATION_GROUP)
	_prompt.visible = here
	_can_use = here and not mounted and (boarded or horse_near)
	# The stable owns E here; hide the overlapping mount prompt under it.  Keyed
	# on this station's own distance rather than on the claim, so the two nodes
	# never write the flag against each other on every refresh.
	_horse.set("mount_prompt_suppressed", player_near and not mounted and (boarded or horse_near))

	if not player_near:
		return false
	if mounted:
		_prompt.text = Device.pick("E  ·  DISMOUNT TO USE THE STABLE", "TAP  ·  DISMOUNT TO USE THE STABLE")
	elif boarded:
		_prompt.text = Device.pick("E  ·  BRING HORSE OUT", "TAP  ·  BRING HORSE OUT")
	elif not horse_near:
		_prompt.text = "BRING YOUR HORSE TO THE STABLE"
	else:
		_prompt.text = Device.pick("E  ·  PUT HORSE AWAY", "TAP  ·  PUT HORSE AWAY")
	return _can_use


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if not event.is_action_pressed("interact"):
		return
	if not _refresh():
		return
	get_viewport().set_input_as_handled()
	if bool(_horse.get("boarded")):
		_horse.call("release_from_stable", stall.global_transform)
	else:
		_horse.call("board")
	_refresh()
