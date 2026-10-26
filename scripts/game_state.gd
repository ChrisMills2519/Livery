extends Node

## The yard's books: money, times, entries and rosettes.
##
## These are autoload values, so they survive a scene change and a reload, and
## `SaveGame` mirrors them into a slot.  The horse's own progress lives in
## `HorseState`; this file is what the player earned, not what the horse is.

signal money_changed(money: int)
signal best_time_changed(seconds: float)
signal rosettes_changed(count: int)
## Emitted when progress without a narrower signal changes.  `SaveGame` listens
## to this as well as to the three above.
##
## `show_entries` and `show_best_time` had no signal at all, so they were saved
## only because a prize or an entry fee moved money alongside them - a contract
## nobody had written down.  It is written down now.
signal progress_changed

var money := 0
var best_round_time := 0.0

## Show-class rosettes won so far.  Each entry is {class, place, colour}.
## They are saved with the slot and re-pinned to the horse on spawn.
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


## Records one class entry.  A function rather than `+= 1` so the save hears
## about it, and returns the new count.
func add_show_entry() -> int:
	show_entries += 1
	progress_changed.emit()
	return show_entries


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
		progress_changed.emit()
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
