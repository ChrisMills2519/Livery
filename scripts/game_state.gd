extends Node

## Session-level state for the first gameplay loop.
##
## Money and the best schooling-round time survive a scene reload so the
## reward loop keeps meaning while the player rides again.  This is deliberately
## small: save/load and the rest of the stable economy come later.

signal money_changed(money: int)
signal best_time_changed(seconds: float)
signal rosettes_changed(count: int)

var money := 0
var best_round_time := 0.0

## Show-class rosettes won this session.  Each entry is
## {class, place, colour}.  They are not saved to disk yet.
var rosettes: Array[Dictionary] = []
var show_best_time := 0.0
var show_entries := 0

## Character-select handoff.  The selected profile survives the scene change
## into main.tscn; auto_mount asks the player to start in the saddle instead
## of walking up to the horse.
var selected_character: PlayerModelProfile = null
var auto_mount_on_start := false

## Door handoff.  A scene door asks for a world position before the scene
## change; the player in the new scene reads and clears it once.
var _pending_spawn_position := Vector3.ZERO
var _pending_spawn_yaw := 0.0
var _has_pending_spawn := false


func choose_character(profile: PlayerModelProfile, start_mounted := true) -> void:
	selected_character = profile
	auto_mount_on_start = start_mounted


## Reads and clears the one-shot start-mounted request, so a later scene
## reload starts on foot unless the player asks for the character screen again.
func consume_auto_mount() -> bool:
	var requested := auto_mount_on_start
	auto_mount_on_start = false
	return requested


## Places the player at `position` and `yaw_degrees` in the next scene to load.
func request_player_spawn(position: Vector3, yaw_degrees: float) -> void:
	_pending_spawn_position = position
	_pending_spawn_yaw = yaw_degrees
	_has_pending_spawn = true


## Reads and clears the one-shot door spawn.  Empty when no door was used.
func consume_player_spawn() -> Dictionary:
	if not _has_pending_spawn:
		return {}
	_has_pending_spawn = false
	return {
		"position": _pending_spawn_position,
		"yaw_degrees": _pending_spawn_yaw,
	}


func add_money(amount: int) -> void:
	if amount == 0:
		return
	money += amount
	money_changed.emit(money)


## Adds a show-class rosette and returns the new total.
func award_rosette(class_label: String, place: int, colour: String) -> int:
	rosettes.append({"class": class_label, "place": place, "colour": colour})
	rosettes_changed.emit(rosettes.size())
	return rosettes.size()


## Records a clear show-class time and returns true when it is a new best.
func record_show_time(seconds: float) -> bool:
	if seconds <= 0.0:
		return false
	if show_best_time <= 0.0 or seconds < show_best_time:
		show_best_time = seconds
		return true
	return false


## Records a completed round and returns true when it is a new best time.
func record_round_time(seconds: float) -> bool:
	if seconds <= 0.0:
		return false
	if best_round_time <= 0.0 or seconds < best_round_time:
		best_round_time = seconds
		best_time_changed.emit(best_round_time)
		return true
	return false
