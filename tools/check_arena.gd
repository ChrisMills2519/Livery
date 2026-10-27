extends SceneTree

## Headless verification for the competition arena and the show class.
##
##   godot --headless --path . --script res://tools/check_arena.gd
##
## Covers what a scene screenshot cannot: the venue is complete, all ten fences
## sit inside the ring and use the fancy jump types, the entry fee is taken, the
## bell start line begins the class, a clear round pays out and leaves a
## collectable rosette, leaving the ring eliminates the rider with no prize, and
## the showground door points back at the yard.

const ARENA := "res://scenes/competition_arena.tscn"
const MAIN := "res://scenes/main.tscn"
const RING_MIN := Vector2(-30.0, -15.0)
const RING_MAX := Vector2(30.0, 15.0)

var _failures: Array[String] = []


func _initialize() -> void:
	await _run()
	if _failures.is_empty():
		print("ARENA CHECK: PASS")
		quit(0)
	else:
		for failure in _failures:
			print("  FAIL: ", failure)
		print("ARENA CHECK: FAIL (%d)" % _failures.size())
		quit(1)


func _run() -> void:
	var arena := _instantiate(ARENA)
	if arena == null:
		return
	await _frames(8)

	var game := root.get_node("/root/GameState")
	game.money = 200
	game.rosettes.clear()
	game.show_entries = 0

	var venue := arena.get_node_or_null("Venue") as Node3D
	_check(venue != null, "the arena has a venue root")

	# ---------------------------------------------------------------------
	# venue
	# ---------------------------------------------------------------------
	var required := [
		"Ring", "Grandstand", "JudgesBox", "JudgeBell", "Entrance",
		"SponsorBoards", "WarmUp", "LorryPark", "TradeStands", "Scoreboard",
		"ClassBoard", "Crowd", "MountingBlock", "HitchingPost", "WaterTrough",
	]
	for part in required:
		_check(venue.get_node_or_null(part) != null, "the venue includes %s" % part)

	var crowd := venue.get_node_or_null("Crowd") as Node3D
	if crowd != null:
		_check(crowd.get_child_count() >= 20, "the grandstand crowd has a full field (got %d)" % crowd.get_child_count())

	var stand := venue.get_node_or_null("Grandstand") as Node3D
	if stand != null:
		var last_y := -99.0
		var ascending := true
		for i in range(5):
			var tier := stand.get_node_or_null("Tier%d" % i) as Node3D
			if tier == null:
				ascending = false
				break
			if tier.global_position.y <= last_y:
				ascending = false
			last_y = tier.global_position.y
		_check(ascending, "the five grandstand tiers step upwards")

	var boards := venue.get_node_or_null("SponsorBoards") as Node3D
	if boards != null:
		_check(boards.get_child_count() >= 8, "the ring is dressed with sponsor boards (got %d)" % boards.get_child_count())

	var scoreboard := venue.get_node_or_null("Scoreboard") as Node3D
	if scoreboard != null:
		var labels := 0
		for child in scoreboard.get_children():
			if child is Label3D:
				labels += 1
		_check(labels >= 3, "the scoreboard shows class, placing and entries")

	# The ring rails are solid, so a rider cannot cut across them.
	# The east rail is split either side of the gate, so the opening is the only
	# way into the ring.
	for rail in ["North", "South", "West", "EastN", "EastS"]:
		_check(
			venue.get_node_or_null("Ring/Rail%sBody" % rail) != null,
			"the %s ring rail is solid" % rail.to_lower()
		)

	# ---------------------------------------------------------------------
	# course
	# ---------------------------------------------------------------------
	var show := arena.get_node_or_null("ShowClass")
	_check(show != null, "the arena has a show class")
	if show == null:
		arena.queue_free()
		return
	show.set_physics_process(false)

	_check(int(show.call("get_jump_count")) == 10, "the show course has ten fences (got %d)" % int(show.call("get_jump_count")))

	var types: Array[int] = []
	var outside: Array[String] = []
	for jump in show.call("get_jump_list"):
		var node := jump["node"] as Node3D
		var aabb: AABB = jump["aabb"]
		types.append(int(node.get("jump_type")))
		var centre := aabb.get_center()
		if (
			centre.x < RING_MIN.x or centre.x > RING_MAX.x
			or centre.z < RING_MIN.y or centre.z > RING_MAX.y
		):
			outside.append(String(node.name))
	_check(outside.is_empty(), "every fence is inside the ring (outside: %s)" % [outside])
	for wanted in [0, 3, 4, 5, 6, 7]:
		_check(types.has(wanted), "the course includes jump type %d" % wanted)
	var seen := {}
	for jump in show.call("get_jump_list"):
		seen[String(jump["node"].call("get_type_name"))] = true
	_check(seen.size() >= 5, "the course mixes at least five fence styles (got %s)" % [seen.keys()])

	var numbers := 0
	for child in show.get_children():
		if String(child.name).begins_with("FenceNumber"):
			numbers += 1
	_check(numbers == 0, "physics fences use their own number boards, not floating labels")

	# ---------------------------------------------------------------------
	# secretary's desk
	# ---------------------------------------------------------------------
	var horse := arena.get_node_or_null("Horse") as Node3D
	var player := arena.get_node_or_null("Player") as Node3D
	_check(horse != null, "the arena has a horse")
	_check(player != null, "the arena has a player")
	if horse == null or player == null:
		arena.queue_free()
		return

	var secretary := venue.get_node_or_null("Entrance/EntriesDesk/Secretary")
	_check(secretary != null, "the secretary's desk is staffed")
	var rosette_stand := venue.get_node_or_null("JudgesBox/RosetteStand")
	_check(rosette_stand != null, "the judges' box has a rosette stand")

	var start_money: int = game.money
	game.money = 5
	var refused: Dictionary = show.call("request_entry")
	_check(not bool(refused.get("ok", true)), "the desk refuses entry without the fee")
	_check(game.money == 5, "a refused entry takes no money")
	game.money = start_money

	player.set("mounted", false)
	player.set("controls_enabled", true)
	player.global_position = Vector3(37.4, 0.0, 11.4)
	if secretary != null:
		secretary.call("_refresh")
		var offer: Dictionary = secretary.call("touch_context")
		_check(
			String(offer.get("label", "")).begins_with("ENTER CLASS"),
			"the desk offers ENTER CLASS up close (got '%s')" % String(offer.get("label", ""))
		)
		_check(bool(secretary.call("use")), "the secretary takes the entry")
	else:
		show.call("request_entry")
	_check(bool(show.get("entered")), "the desk accepts a paid entry")
	_check(game.money == start_money - int(show.get("entry_fee")), "the entry fee is taken (got £%d)" % game.money)
	_check(int(show.get("rider_number")) == 101, "the first rider is number 101 (got %d)" % int(show.get("rider_number")))
	_check(show.get("rivals").size() == 7, "seven rivals make up the field")
	_check(game.show_entries == 1, "the entry is recorded on GameState")

	# ---------------------------------------------------------------------
	# start line and clear round
	# ---------------------------------------------------------------------
	player.set("mounted", true)

	horse.global_position = Vector3(31.0, 0.0, 6.0)
	show.call("_physics_process", 0.016)
	_check(String(show.get("state")) == "idle", "the class does not start before the gate")
	horse.global_position = Vector3(29.0, 0.0, 6.0)
	show.call("_physics_process", 0.016)
	_check(String(show.get("state")) == "running", "riding through the gate starts the class")

	for i in range(10):
		show.call("_clear_jump", i)
	_check(String(show.get("state")) == "finished", "clearing ten fences finishes the class")
	var result: Dictionary = show.get("last_result")
	_check(int(result.get("placing", 0)) == 1, "a clear round wins against the field (got place %d)" % int(result.get("placing", 0)))
	_check(bool(result.get("clear_round", false)), "the result is a clear round")
	_check(int(result.get("prize", 0)) == 120, "first place pays £120 (got £%d)" % int(result.get("prize", 0)))
	_check(game.money == start_money - int(show.get("entry_fee")) + 120, "prize money is credited (got £%d)" % game.money)
	_check(String(result.get("rosette", "")) == "red", "a win earns the red rosette")
	_check(bool(show.call("can_collect_rosette")), "the rosette waits at the judges' box")

	var hud := arena.get_node_or_null("HUD")
	var card := hud.get_node_or_null("HudRoot/ResultCard") as PanelContainer if hud != null else null
	_check(card != null and card.visible, "the HUD shows the class result card")
	if card != null:
		var card_title := card.find_child("ResultTitle", true, false) as Label
		_check(
			card_title != null and card_title.text.contains("1ST PLACE"),
			"the result card celebrates the win (got '%s')" % (card_title.text if card_title != null else "")
		)

	player.set("mounted", false)
	player.global_position = Vector3(-33.0, 0.0, -16.0)
	if rosette_stand != null:
		rosette_stand.call("_refresh")
		var rosette_offer: Dictionary = rosette_stand.call("touch_context")
		_check(
			String(rosette_offer.get("label", "")).contains("ROSETTE"),
			"the judges' box offers the rosette (got '%s')" % String(rosette_offer.get("label", ""))
		)
		_check(bool(rosette_stand.call("use")), "the rosette stand hands over the rosette")
	else:
		show.call("collect_rosette")
	_check(game.rosettes.size() == 1, "the rosette is recorded on GameState")
	_check(horse.get_node_or_null("ShowRosette") != null, "the rosette is pinned to the horse")
	_check(not bool(show.call("can_collect_rosette")), "a collected rosette cannot be taken twice")

	# ---------------------------------------------------------------------
	# elimination
	# ---------------------------------------------------------------------
	var second: Dictionary = show.call("request_entry")
	_check(bool(second.get("ok", false)), "a second class can be entered")
	_check(int(show.get("rider_number")) == 102, "the rider number advances")
	player.set("mounted", true)
	horse.global_position = Vector3(31.0, 0.0, 6.0)
	show.call("_physics_process", 0.016)
	horse.global_position = Vector3(29.0, 0.0, 6.0)
	show.call("_physics_process", 0.016)
	_check(String(show.get("state")) == "running", "the second class starts at the gate")
	var before: int = game.money
	horse.global_position = Vector3(40.0, 0.0, 0.0)
	show.call("_physics_process", 0.016)
	var eliminated: Dictionary = show.get("last_result")
	_check(String(show.get("state")) == "finished", "leaving the ring ends the class")
	_check(bool(eliminated.get("eliminated", false)), "leaving the ring is an elimination")
	_check(String(eliminated.get("title", "")) == "ELIMINATED", "the elimination card reads ELIMINATED")
	_check(int(eliminated.get("prize", 0)) == 0, "an elimination pays no prize")
	_check(game.money == before, "an elimination takes no money beyond the fee")
	_check(not bool(show.call("can_collect_rosette")), "an elimination leaves no rosette")

	# ---------------------------------------------------------------------
	# door back to the yard
	# ---------------------------------------------------------------------
	var door := arena.get_node_or_null("ExitDoor")
	_check(door != null, "the arena has a door back to the yard")
	if door != null:
		_check(String(door.get("target_scene")) == MAIN, "the arena door returns to the main yard")

	arena.queue_free()
	await _frames(3)

	# ---------------------------------------------------------------------
	# the yard side of the gate
	# ---------------------------------------------------------------------
	var main := _instantiate(MAIN)
	if main == null:
		return
	await _frames(8)
	var gate := main.get_node_or_null("ShowgroundGate")
	_check(gate != null, "the yard has a showground gate")
	if gate != null:
		_check(String(gate.get("target_scene")) == ARENA, "the showground gate enters the arena")
	_check(main.get_node_or_null("ShowgroundArch") != null, "the yard shows the showground arch")
	main.queue_free()
	await _frames(2)


func _instantiate(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		_check(false, "%s loads" % path)
		return null
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	return scene


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
