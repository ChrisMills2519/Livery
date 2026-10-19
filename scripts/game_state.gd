extends Node

## Session-level state for the first gameplay loop.
##
## Money and the best schooling-round time survive a scene reload so the
## reward loop keeps meaning while the player rides again.  This is deliberately
## small: save/load and the rest of the stable economy come later.

signal money_changed(money: int)
signal best_time_changed(seconds: float)

var money := 0
var best_round_time := 0.0

## Character-select handoff.  The selected profile survives the scene change
## into main.tscn; auto_mount asks the player to start in the saddle instead
## of walking up to the horse.
var selected_character: PlayerModelProfile = null
var auto_mount_on_start := false


func choose_character(profile: PlayerModelProfile, start_mounted := true) -> void:
	selected_character = profile
	auto_mount_on_start = start_mounted


## Reads and clears the one-shot start-mounted request, so a later scene
## reload starts on foot unless the player asks for the character screen again.
func consume_auto_mount() -> bool:
	var requested := auto_mount_on_start
	auto_mount_on_start = false
	return requested


func add_money(amount: int) -> void:
	if amount == 0:
		return
	money += amount
	money_changed.emit(money)


## Records a completed round and returns true when it is a new best time.
func record_round_time(seconds: float) -> bool:
	if seconds <= 0.0:
		return false
	if best_round_time <= 0.0 or seconds < best_round_time:
		best_round_time = seconds
		best_time_changed.emit(best_round_time)
		return true
	return false
