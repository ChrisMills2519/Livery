extends SceneTree

## Headless check for the horse-progress owner.
##
##   godot --headless --path . --script res://tools/check_horse_state.gd
##
## The bug this pins down: the horse is a scene node, and every door in the game
## is a full scene change, so trust, training and the painted coat were reset by
## walking into the farmhouse or the showground.  Worse, the save read whichever
## horse the current scene held, so a show entry fee (money -> debounced save)
## wrote a pristine horse over the cloud save.
##
## Each case below failed before `scripts/horse_state.gd` existed.  Run the door
## trip itself rather than a snapshot round trip: `check_save` already covers the
## serialisation, and the fault was never in the serialisation.

const MAIN := "res://scenes/main.tscn"
const ARENA := "res://scenes/competition_arena.tscn"

var _failures: Array[String] = []
# Autoloads are resolved by path: in --script mode their names are not known
# identifiers at compile time (see check_character_select.gd).
var _gs
var _hs
var _save
var _world: Node = null


func _initialize() -> void:
	await process_frame
	_gs = root.get_node("GameState")
	_hs = root.get_node("HorseState")
	_save = root.get_node("SaveGame")
	await _run()
	if _failures.is_empty():
		print("HORSE STATE CHECK: PASS")
		quit(0)
		return
	for failure in _failures:
		print("  FAIL: ", failure)
	print("HORSE STATE CHECK: FAIL (%d)" % _failures.size())
	quit(1)


func _run() -> void:
	await _spawn(MAIN)
	var horse: Node = _live_horse()
	if horse == null:
		_check("the main scene holds a horse", false)
		return
	_check("a fresh stable starts untrained", is_equal_approx(float(horse.get("jumping_skill")), 1.0))

	# Earn something the way the game does: a fence clear and a groom.
	horse.call("award_training", 2.0, 1.0)
	for i in range(4):
		horse.call("mark_hoof", i)
	horse.call("apply_grooming_result", 0.9, 0.6, 4, false)
	_check("training reaches the state owner", is_equal_approx(float(_hs.jumping_skill), 3.0))
	_check("grooming reaches the state owner", float(_hs.trust) > 0.0)
	_check("the pick reaches the state owner", int(_hs.hooves_cleaned) == 4)

	# The show entry: money moves, which queues a save.  The payload used to be
	# taken from the scene, so paying the fee here would have written zeros.
	_gs.add_money(-20)
	var entry_payload: Dictionary = _save.snapshot()
	var entry_horse: Dictionary = entry_payload.get("horse", {})
	_check("paying an entry fee keeps the trained jump bonus",
		is_equal_approx(float(entry_horse.get("jumping_skill", 0.0)), 3.0))
	_check("paying an entry fee keeps the earned trust",
		float(entry_horse.get("trust", 0.0)) > 0.0)

	var earned_trust := float(_hs.trust)
	await _free_world()
	_check("no horse is left in the tree", _live_horse() == null)

	# The farmhouse case: a scene with no horse in it still saves the horse.
	var house_payload: Dictionary = _save.snapshot()
	_check("a horse-less scene still carries the horse", house_payload.has("horse"))
	_check("a horse-less scene keeps the training",
		is_equal_approx(float((house_payload.get("horse", {}) as Dictionary).get("jumping_skill", 0.0)), 3.0))

	# The door trip: come back and find the horse as it was left.
	await _spawn(MAIN)
	horse = _live_horse()
	if horse == null:
		_check("the main scene holds a horse after the round trip", false)
		return
	_check("training survives the doorway", is_equal_approx(float(horse.get("jumping_skill")), 3.0))
	_check("fitness survives the doorway", is_equal_approx(float(horse.get("fitness")), 2.0))
	_check("cleanliness survives the doorway", is_equal_approx(float(horse.get("cleanliness")), 0.9))
	_check("trust survives the doorway", is_equal_approx(float(horse.get("trust")), earned_trust))
	_check("the pick survives the doorway", int(horse.get("hooves_cleaned")) == 4)
	_check("the hoof flags survive the doorway", horse.get("groomed_hooves") == [true, true, true, true])

	# The coat: a bake produces a mask, and the next spawn is handed it before
	# its own bake, which is where `import_mask` parks it.
	var baked := await _wait_for_bake(horse)
	_check("the groom surface bakes", baked)
	if baked:
		_hs.record_from(horse)
		_check("the painted coat is recorded", not String(_hs.coat_mask).is_empty())

	# The showground: reached by a scene change, and it used to arrive with a
	# horse that had never been trained.
	await _free_world()
	await _spawn(ARENA)
	var arena_horse: Node = _live_horse()
	if arena_horse == null:
		_check("the showground holds a horse", false)
		return
	_check("the showground horse inherits the trained jump bonus",
		is_equal_approx(float(arena_horse.get("jumping_skill")), 3.0))
	_check("the showground horse inherits fitness",
		is_equal_approx(float(arena_horse.get("fitness")), 2.0))
	_check("the showground horse inherits trust",
		is_equal_approx(float(arena_horse.get("trust")), earned_trust))
	if baked:
		var surface: Node = arena_horse.get("groom_surface")
		var parked := 0
		if surface != null:
			var parked_bytes: PackedByteArray = surface.get("_imported_data")
			parked = parked_bytes.size()
		_check("the showground horse is handed the painted coat", parked == 256 * 256 * 4)

	# A rosette is won in the showground and has to still be worn afterwards.
	_gs.award_rosette("1.05 m OPEN", 1, "red")
	await _free_world()
	await _spawn(MAIN)
	horse = _live_horse()
	if horse != null:
		_check("a won rosette is worn after the door",
			horse.get_node_or_null("ShowRosette") != null)
		_check("a second rosette does not stack",
			not bool(horse.call("attach_rosette", "blue")))

	await _free_world()


## Loads a scene the way the game does, with the autoloads already up.
func _spawn(path: String) -> void:
	var packed := load(path) as PackedScene
	_world = packed.instantiate()
	root.add_child(_world)
	current_scene = _world
	# Let `_ready()` chains and the first physics frames settle.
	for i in range(4):
		await process_frame


func _free_world() -> void:
	if _world != null:
		_world.queue_free()
		_world = null
		current_scene = null
	# The freed nodes leave the scene groups at the end of the frame, and the
	# next spawn must not find the old horse through `get_first_node_in_group`.
	for i in range(3):
		await process_frame


func _live_horse() -> Node:
	# `self` is the SceneTree, so the group lookup is the tree's own.
	return get_first_node_in_group("horse")


## The groom surface bakes 0.2 s after it loads, then rasterises the mask.
func _wait_for_bake(horse: Node) -> bool:
	var surface: Node = horse.get("groom_surface")
	if surface == null:
		return false
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		if bool(surface.get("_ready_done")):
			return true
		await process_frame
	return false


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)
		print("  FAIL: ", label)
	else:
		print("  ok: ", label)
