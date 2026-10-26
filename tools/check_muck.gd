extends SceneTree

## Headless check for the muck-out chore - the third care job the GDD asks for
## (feeding, grooming and stall cleaning).
##
##   godot --headless --path . --script res://tools/check_muck.gd
##
## Covers the bed soiling on the horse's clock and mirroring into the state
## owner, the station at the stable and its refusals, the rule that the stable
## door and the muck point never both offer (one `interact` event is claimed by
## one node), the session taking and returning the camera, the HUD and the
## player body, one scoop clearing exactly one heap, the reward being paid
## against the mess that was there, leaving early keeping the work that was
## done, and the bed surviving a doorway and a save.
##
## The station, the session and the stable door are the real nodes in
## `scenes/stable.tscn`, so this drives the shipped prompts and gates rather than
## copies of them.

const MAIN := "res://scenes/main.tscn"
const CLUMP_COUNT := 8
## Long enough for the session's own fade-and-restore timer to finish.
const EXIT_SETTLE := 0.6

var _failures: Array[String] = []
# Autoloads are resolved by path: in --script mode their names are not known
# identifiers at compile time.
var _gs
var _hs
var _save
var _world: Node = null
var _horse: Node
var _player: Node
var _station: Node
var _session: Node
var _stable: Node
var _hud: Node


func _initialize() -> void:
	await process_frame
	_gs = root.get_node("GameState")
	_hs = root.get_node("HorseState")
	_save = root.get_node("SaveGame")
	await _spawn()
	if _horse == null or _player == null or _station == null or _session == null or _stable == null:
		_check("the world exposes the horse, the player, the stable door and the muck point", false)
		_finish()
		return

	await _check_soiling()
	await _check_station()
	await _check_session()
	await _check_partial_visit()
	await _check_persistence()
	_finish()


# --- the bed ------------------------------------------------------------------

func _check_soiling() -> void:
	_horse.set("mucking", false)
	_set_bed(0.0)

	# Standing about the yard is what soils the bed.
	_horse.call("_tick_needs", 60.0)
	var standing := float(_horse.get("stall_muck"))
	_check("the bed soils while the horse stands about (%.3f)" % standing, standing > 0.0)
	_check("standing soils it at the standing rate",
		absf(standing - float(_horse.get("stall_muck_standing_per_minute"))) < 0.002)
	_check("the bed reaches the state owner",
		absf(float(_hs.stall_muck) - standing) < 0.002)

	# Riding does not soil it at the standing rate, because the horse is not in
	# the bed.  The horse's own rule is `working`, which needs a rider, so the
	# rider is set for the one synchronous call and cleared straight after - no
	# frame runs in between for the ride path to act on.
	var saved_rider = _horse.get("rider")
	_horse.set("rider", _player)
	_horse.set("_ride_speed", 4.0)
	_set_bed(0.0)
	_horse.call("_tick_needs", 60.0)
	var riding := float(_horse.get("stall_muck"))
	_horse.set("rider", saved_rider)
	_horse.set("_ride_speed", 0.0)
	_check("riding soils it more slowly than standing about (%.3f vs %.3f)" % [riding, standing],
		riding < standing - 0.001)

	# The chore itself pauses the clock: the session is removing exactly what is
	# in the bed, and a rate running underneath would fight the scoop.
	_set_bed(0.4)
	_horse.set("mucking", true)
	_horse.call("_tick_needs", 60.0)
	_check("the bed does not soil while it is being mucked",
		is_equal_approx(float(_horse.get("stall_muck")), 0.4))
	_horse.set("mucking", false)

	# One threshold, asked by the station, the session and this check.
	var muck_min := float(_constant(_hs, "MUCK_MIN", 0.1))
	_set_bed(muck_min - 0.01)
	_check("a bed under the threshold needs nothing", not bool(_hs.needs_mucking()))
	_set_bed(muck_min + 0.01)
	_check("a soiled bed needs mucking", bool(_hs.needs_mucking()))
	print("the bed: soils standing and riding, pauses in the chore, one threshold")


# --- the station --------------------------------------------------------------

func _check_station() -> void:
	_place_horse_at_yard()
	_set_bed(0.6)
	await _stand_at(_station)

	_check("the muck point offers the chore", bool(_station.call("_refresh")))
	var offer: Dictionary = _station.call("touch_context")
	_check("the muck point offers MUCK OUT on touch", String(offer.get("label", "")) == "MUCK OUT")
	_check("the prompt names the chore",
		String(_station.get("_prompt").text).contains("MUCK OUT"))
	_check("the prompt names how soiled the bed is",
		String(_station.get("_prompt").text).contains("60%"))

	# One `interact` event is claimed by one node, so only the nearer of the pair
	# may offer at all - otherwise the stable door's PUT AWAY swallows the press
	# and MUCK OUT silently does nothing.
	_stable.call("_refresh")
	_check("the stable door does not also offer here",
		_stable.call("touch_context").is_empty())
	_check("the stable door's prompt is hidden here",
		not bool(_stable.get("_prompt").visible))

	await _stand_at(_stable.get_node("UseAnchor"), _stable)
	_check("the stable door offers when it is the nearer one",
		bool(_stable.call("_refresh")))
	_station.call("_refresh")
	_check("the muck point does not also offer there",
		_station.call("touch_context").is_empty())
	_check("the muck point's prompt is hidden there",
		not bool(_station.get("_prompt").visible))

	# Refusals, each with its own copy and never an offer.
	await _stand_at(_station)
	_player.set("mounted", true)
	_check("a mounted player is told to dismount",
		not bool(_station.call("_refresh"))
		and String(_station.get("_prompt").text).contains("DISMOUNT")
		and _station.call("touch_context").is_empty())
	_player.set("mounted", false)

	_horse.global_position = _station.global_position + Vector3(40.0, 0.0, 0.0)
	await process_frame
	_check("the horse has to be at the yard",
		not bool(_station.call("_refresh"))
		and String(_station.get("_prompt").text).contains("BRING YOUR HORSE")
		and _station.call("touch_context").is_empty())

	_place_horse_at_yard()
	_set_bed(0.0)
	await _stand_at(_station)
	_check("a clean bed offers nothing",
		not bool(_station.call("_refresh"))
		and String(_station.get("_prompt").text).contains("CLEAN")
		and _station.call("touch_context").is_empty())
	print("the station: prompt, touch offer, nearest of the pair, three refusals")


# --- the session --------------------------------------------------------------

func _check_session() -> void:
	_set_bed(1.0)
	_place_horse_at_yard()
	await _stand_at(_station)
	var trust_before := float(_horse.get("trust"))
	await _interact()

	_check("the real interact press starts the chore", bool(_session.get("active")))
	if not bool(_session.get("active")):
		return
	_check("a full bed has heaps to scoop", int(_session.call("clumps_remaining")) == CLUMP_COUNT)
	_check("the session takes the camera", bool(_session.get("_camera").current))
	_check("the player cannot walk during the chore",
		not bool(_player.get("controls_enabled")))
	_check("the gameplay HUD steps aside", not bool(_hud.visible))
	_check("the player body is hidden", not bool(_player.get("model").visible))
	_check("the bed is on show", bool(_session.get("_bed").visible))
	_check("the session HUD is up", bool(_session.get("_hud").visible))
	_check("the station stops offering while the chore is up",
		not bool(_station.call("_refresh")))

	var camera: Camera3D = _session.get("_camera")
	var heaps := int(_session.call("clumps_remaining"))
	var first := int(_session.call("clumps_remaining")) - 1
	var heap_point: Vector3 = _session.call("clump_position", first)
	var heap_screen := camera.unproject_position(heap_point)
	_check("a heap can be aimed at", int(_session.call("clump_at_screen", heap_screen)) == first)
	_check("a scoop takes one heap", bool(_session.call("scoop_at_screen", heap_screen)))
	_check("exactly one heap left the bed",
		int(_session.call("clumps_remaining")) == heaps - 1)
	_check("the bed's muck fell by that heap",
		absf(float(_hs.stall_muck) - (float(heaps - 1) / float(heaps))) < 0.01)
	_check("the live horse carries the new value",
		absf(float(_horse.get("stall_muck")) - float(_hs.stall_muck)) < 0.001)

	# Aimed away from the bed: a miss must not quietly eat a heap.
	var away := camera.unproject_position(Vector3(-14.0, 0.0, -22.0))
	_check("a scoop aimed away from the bed picks nothing",
		not bool(_session.call("scoop_at_screen", away)))
	_check("a miss leaves the bed alone",
		int(_session.call("clumps_remaining")) == heaps - 1)

	# Clear what is left, one scoop at a time.
	var guard := 0
	while int(_session.call("clumps_remaining")) > 0 and guard < CLUMP_COUNT + 4:
		guard += 1
		var index := int(_session.call("clumps_remaining")) - 1
		var point: Vector3 = _session.call("clump_position", index)
		if not bool(_session.call("scoop_at_screen", camera.unproject_position(point))):
			break
	_check("the bed can be worked clean", int(_session.call("clumps_remaining")) == 0)
	_check("the chore reports itself finished", bool(_session.get("finished")))
	_check("the state owner sees a clean bed", float(_hs.stall_muck) < 0.001)
	_check("the barrow counted every heap",
		int((_session.get("_result") as Dictionary).get("scoops", 0)) == CLUMP_COUNT)

	var result: Dictionary = _session.get("_result")
	_check("the card reports a full clean", bool(result.get("complete", false)))
	_check("the mess that was there is what was cleaned",
		is_equal_approx(float(result.get("cleaned", 0.0)), 1.0))
	var trust_per_muck := float(_constant(_session, "TRUST_PER_MUCK", 0.0))
	_check("a full muck pays trust",
		is_equal_approx(float(result.get("trust_gain", 0.0)), trust_per_muck))
	_check("a full muck pays happiness",
		is_equal_approx(float(result.get("happiness_gain", 0.0)),
			float(_constant(_session, "HAPPINESS_PER_MUCK", 0.0))))
	_check("the horse is paid",
		float(_horse.get("trust")) > trust_before
		and is_equal_approx(float(_horse.get("trust")), trust_before + float(result.get("trust_gain", 0.0))))
	_check("the result card is up", bool(_session.get("_hud").get("_result_panel").visible))

	# A finished session takes no more scoops, so the same clean bed cannot be
	# worked again for another payment.
	var trust_after := float(_horse.get("trust"))
	_check("a finished chore takes no more scoops",
		not bool(_session.call("scoop_at_screen", heap_screen)))
	_check("and pays nothing more", is_equal_approx(float(_horse.get("trust")), trust_after))

	_session.call("exit_session")
	await create_timer(EXIT_SETTLE).timeout
	_check("the session lets go", not bool(_session.get("active")))
	_check("the player's own camera comes back", bool(_player.get("camera").current))
	_check("the player can walk again", bool(_player.get("controls_enabled")))
	_check("the gameplay HUD returns", bool(_hud.visible))
	_check("the player body returns", bool(_player.get("model").visible))
	_check("the session HUD goes away", not bool(_session.get("_hud").visible))
	_check("the bed is hidden again", not bool(_session.get("_bed").visible))
	_check("the muck session is not still running", not bool(_horse.get("mucking")))

	# Clean bed, so the station says so and the session refuses to open.
	await _stand_at(_station)
	_check("a mucked bed is not offered again",
		not bool(_station.call("_refresh")) and _station.call("touch_context").is_empty())
	_check("and the session refuses to open",
		not bool(_session.call("enter")))
	print("the session: camera, HUD, body, one heap per scoop, payment, clean exit")


# --- leaving early ------------------------------------------------------------

func _check_partial_visit() -> void:
	_set_bed(0.5)
	_place_horse_at_yard()
	await _stand_at(_station)
	var trust_before := float(_horse.get("trust"))
	_check("a half-soiled bed offers the chore", bool(_station.call("_refresh")))
	await _interact()
	_check("the session opens on a half-soiled bed", bool(_session.get("active")))
	if not bool(_session.get("active")):
		return
	var heaps := int(_session.call("clumps_remaining"))
	_check("a half-soiled bed has heaps for its mess", heaps > 0 and heaps < CLUMP_COUNT)
	var camera: Camera3D = _session.get("_camera")
	var point: Vector3 = _session.call("clump_position", heaps - 1)
	_check("one heap is scooped", bool(_session.call("scoop_at_screen", camera.unproject_position(point))))

	# Walking away with heaps still in the bed keeps what was done and pays only
	# for the part that was actually cleaned.
	_session.call("exit_session")
	await create_timer(EXIT_SETTLE).timeout
	var expected := 0.5 * float(heaps - 1) / float(heaps)
	_check("the part-cleaned bed is kept (%.3f, expected %.3f)" % [float(_hs.stall_muck), expected],
		absf(float(_hs.stall_muck) - expected) < 0.01)
	var paid := float(_horse.get("trust")) - trust_before
	var expected_pay := float(_constant(_session, "TRUST_PER_MUCK", 0.0)) * (0.5 - expected)
	_check("leaving early pays only for the part that was cleaned (%.3f, expected %.3f)" % [paid, expected_pay],
		absf(paid - expected_pay) < 0.005)
	_check("the work that was done is not lost", absf(float(_hs.stall_muck) - 0.5) > 0.01)
	# Heaps are still in the bed, so the chore is still on offer.
	_check("a part-mucked bed is offered again", bool(_hs.needs_mucking()))
	await _stand_at(_station)
	_check("and the station offers it", bool(_station.call("_refresh")))
	print("leaving early: the work stays, the payment is only for what was cleaned")


# --- persistence --------------------------------------------------------------

func _check_persistence() -> void:
	_set_bed(0.63)
	var payload: Dictionary = _save.snapshot()
	var horse_part: Dictionary = payload.get("horse", {})
	_check("the snapshot carries the bed",
		absf(float(horse_part.get("stall_muck", -1.0)) - 0.63) < 0.001)

	_set_bed(0.0)
	_save.apply(payload)
	_check("a load restores the bed", absf(float(_hs.stall_muck) - 0.63) < 0.001)
	_check("a load restores the live horse",
		absf(float(_horse.get("stall_muck")) - 0.63) < 0.001)

	# The doorway: the stable is reached through a full scene change, like every
	# other building, so the bed has to travel in the state owner.
	await _free_world()
	await _spawn()
	_check("the bed survives the doorway",
		absf(float(_horse.get("stall_muck")) - 0.63) < 0.01)

	# The HUD is the only place the player can see it.
	var fill := (_hud as Node).find_child("StableFill", true, false) as ColorRect
	_check("the gameplay HUD has a bed bar", fill != null)
	if fill != null:
		_horse.set("stall_muck", 1.0)
		_hud.call("_refresh_needs")
		var soiled_width := fill.size.x
		_horse.set("stall_muck", 0.0)
		_hud.call("_refresh_needs")
		_check("the bar reads clean when the bed is clean",
			fill.size.x > soiled_width + 1.0)
		_horse.set("stall_muck", 1.0)
		_check("and empty when the bed is full", soiled_width < 1.0)
	print("persistence: snapshot, load, doorway, HUD bar")


# --- world plumbing -----------------------------------------------------------

func _spawn() -> void:
	var packed := load(MAIN) as PackedScene
	_world = packed.instantiate()
	root.add_child(_world)
	current_scene = _world
	for i in range(6):
		await process_frame
	_horse = get_first_node_in_group("horse")
	_player = get_first_node_in_group("player")
	_station = _world.find_child("MuckStation", true, false)
	_stable = _world.find_child("Stable", true, false)
	_hud = get_first_node_in_group("gameplay_hud")
	if _station != null:
		_session = _station.get_node_or_null("Session")
	# The session's station is the one that owns the chore; both must be the
	# shipped nodes rather than anything this check builds.
	if _session != null and _session.get_script() == null:
		_session = null


## The horse standing in the yard, the same rule the station asks about.  It is
## parked behind the session's camera, where the yard's own start puts it, so it
## cannot stand between the camera and the bed.
func _place_horse_at_yard() -> void:
	if _horse == null or _station == null:
		return
	_horse.set("boarded", false)
	_horse.global_position = _station.global_position + Vector3(2.0, 0.0, 2.5)


## A script constant, which is not on the object's property list.
func _constant(node: Node, name: String, fallback: float) -> float:
	var script: Script = node.get_script()
	if script == null:
		return fallback
	return float(script.get_script_constant_map().get(name, fallback))


func _free_world() -> void:
	if _world != null:
		_world.queue_free()
		_world = null
		current_scene = null
	for i in range(3):
		await process_frame


## Stands the player at `anchor` and refreshes the station that owns the offer
## there.  The two differ for the stable door, whose anchor is a marker on the
## root that carries the script.
func _stand_at(anchor: Node3D, refresher: Node = null) -> void:
	_player.global_position = anchor.global_position + Vector3(0.0, 0.0, 1.4)
	_player.set("velocity", Vector3.ZERO)
	await process_frame
	await physics_frame
	_player.global_position = anchor.global_position + Vector3(0.0, 0.0, 1.4)
	var target: Node = refresher if refresher != null else anchor
	target.call("_refresh")


## The bed is written in two places - the horse, which the HUD and the state
## mirror read, and the state owner, which the station and the session read - and
## the horse mirrors its own value into the owner once a second.  Setting one of
## them alone is a check that measures whichever write landed last.
func _set_bed(muck: float) -> void:
	_hs.set_stall_muck(muck)
	if _horse != null:
		_horse.set("stall_muck", muck)


## Goes through the real input pipeline, so the station's own `_input` runs and
## `set_input_as_handled()` is legal.
func _interact() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)
		print("  FAIL: ", label)
	else:
		print("  ok: ", label)


func _finish() -> void:
	if _failures.is_empty():
		print("MUCK CHECK: PASS")
		quit(0)
		return
	print("MUCK CHECK: FAIL (%d)" % _failures.size())
	quit(1)
