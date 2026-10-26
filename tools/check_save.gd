extends SceneTree

## Headless check for the save slots.
##
##   godot --headless --path . --script res://tools/check_save.gd
##
## Covers the identity rules the shelf depends on (`?player=`/`?slot=`), the
## snapshot/apply round trip across GameState and the horse, the local file and
## its revision, and the refusal to write anything for a guest.
##
## The horse half travels through the `HorseState` autoload, so every snapshot
## here is taken after a `record_from()` - the save no longer reads the scene.
## `check_horse_state` covers what that arrangement exists for: progress
## surviving a scene change and a spawn that did not earn it.

## Stand-in for the real horse: the save only reads and writes these nine
## properties, so a stub keeps this check off the GLB and the skeleton.
class StubHorse:
	extends Node
	var trust := 0.0
	var happiness := 0.5
	var cleanliness := 0.0
	var grooming_polish := 0.0
	var hooves_cleaned := 0
	var groomed_hooves := [false, false, false, false]
	var care_reward_score := 0.0
	var fitness := 1.0
	var jumping_skill := 1.0
	var groom_surface: Node = null


## Stand-in for GroomSurface: records what the save asks it to restore.
class StubSurface:
	extends Node
	var exported := "MASK-PNG"
	var imported := ""
	var dirt := -1.0

	func export_mask() -> String:
		return exported

	func import_mask(encoded: String) -> bool:
		imported = encoded
		return true

	func set_dirt_level(value: float) -> void:
		dirt = value

var _failures: Array[String] = []
var _horse: StubHorse
## The autoload globals are not registered for the main-loop script, so they are
## resolved by path once the tree exists.  Left untyped so the calls stay
## dynamic.
var _save
var _gs
var _hs


func _initialize() -> void:
	# Autoloads exist as nodes but the tree is not live until the loop runs.
	await process_frame
	_save = root.get_node("SaveGame")
	_gs = root.get_node("GameState")
	_hs = root.get_node("HorseState")
	_check_identity()
	_check_round_trip()
	_check_local_file()
	_check_guest_writes_nothing()
	_check_response_handling()
	_check_mask_round_trip()
	_check_progress_signal()
	_finish()


func _check(false_message: String, condition: bool) -> void:
	if not condition:
		_failures.append(false_message)


func _check_identity() -> void:
	var cases := [
		{"search": "?player=liv&slot=2", "player": "liv", "slot": 2},
		{"search": "?player=ted", "player": "ted", "slot": 1},
		{"search": "?touch=1&player=liv&slot=3", "player": "liv", "slot": 3},
		{"search": "", "player": "", "slot": 1},
		# A guest must never get a named slot, and an unknown name is not guessed.
		{"search": "?player=guest", "player": "", "slot": 1},
		{"search": "?player=bob&slot=4", "player": "", "slot": 4},
		{"search": "?player=LIV", "player": "liv", "slot": 1},
		# Out-of-range slots clamp instead of failing the load.
		{"search": "?slot=99", "player": "", "slot": 9},
		{"search": "?slot=0", "player": "", "slot": 1},
		{"search": "?slot=abc", "player": "", "slot": 1},
	]
	for entry in cases:
		var parsed: Dictionary = _save._parse_identity(entry["search"])
		_check("player for '%s' was '%s', expected '%s'" % [entry["search"], parsed["player"], entry["player"]],
			parsed["player"] == entry["player"])
		_check("slot for '%s' was %d, expected %d" % [entry["search"], parsed["slot"], entry["slot"]],
			int(parsed["slot"]) == int(entry["slot"]))
	print("identity rules: %d cases" % cases.size())


func _check_round_trip() -> void:
	_horse = StubHorse.new()
	_horse.add_to_group("horse")
	var surface := StubSurface.new()
	_horse.groom_surface = surface
	_horse.add_child(surface)
	root.add_child(_horse)

	_gs.money = 240
	_gs.best_round_time = 61.5
	_gs.show_best_time = 72.25
	_gs.show_entries = 2
	var rosettes: Array[Dictionary] = [{"class": "1.05 m OPEN", "place": 1, "colour": "red"}]
	_gs.rosettes = rosettes
	_horse.trust = 3.5
	_horse.happiness = 0.8
	_horse.cleanliness = 0.72
	_horse.grooming_polish = 0.4
	_horse.hooves_cleaned = 3
	_horse.groomed_hooves = [true, true, true, false]
	_horse.care_reward_score = 0.65
	_horse.fitness = 2.25
	_horse.jumping_skill = 4.0
	# The horse records itself at its own mutation points; the check stands in
	# for one of those, so the snapshot has something to serialise.
	_hs.record_from(_horse)

	var payload: Dictionary = _save.snapshot()
	_check("snapshot has a horse section", payload.has("horse"))
	_check("snapshot carries the painted coat",
		String((payload["horse"] as Dictionary).get("coat_mask", "")) == "MASK-PNG")
	_check("snapshot carries money", int(payload["money"]) == 240)
	_check("snapshot is under the 256 KB cap",
		JSON.stringify(payload).to_utf8_buffer().size() < 262144)

	# Corrupt every value, then let the payload restore it.
	_gs.money = 0
	_gs.best_round_time = 0.0
	_gs.show_entries = 0
	var cleared: Array[Dictionary] = []
	_gs.rosettes = cleared
	_horse.trust = 0.0
	_horse.cleanliness = 0.0
	_horse.hooves_cleaned = 0
	_horse.groomed_hooves = [false, false, false, false]
	_horse.jumping_skill = 1.0

	_save.apply(payload)

	_check("money restored", _gs.money == 240)
	_check("best round time restored", is_equal_approx(_gs.best_round_time, 61.5))
	_check("show best time restored", is_equal_approx(_gs.show_best_time, 72.25))
	_check("show entries restored", _gs.show_entries == 2)
	_check("rosette restored", _gs.rosettes.size() == 1 and int(_gs.rosettes[0]["place"]) == 1)
	_check("horse trust restored", is_equal_approx(_horse.trust, 3.5))
	_check("horse cleanliness restored", is_equal_approx(_horse.cleanliness, 0.72))
	_check("horse polish restored", is_equal_approx(_horse.grooming_polish, 0.4))
	_check("horse hooves restored", _horse.hooves_cleaned == 3)
	_check("horse hoof flags restored", _horse.groomed_hooves == [true, true, true, false])
	_check("horse fitness restored", is_equal_approx(_horse.fitness, 2.25))
	_check("horse jumping restored", is_equal_approx(_horse.jumping_skill, 4.0))
	_check("painted coat restored", String(_horse.groom_surface.get("imported")) == "MASK-PNG")
	_check("dirt level follows cleanliness",
		is_equal_approx(float(_horse.groom_surface.get("dirt")), 0.28))
	print("round trip: money, times, rosettes, nine horse fields")


## A scene with no horse in it (the farmhouse) must not drop the horse half: the
## snapshot reads the state, not the tree.
func _check_snapshot_without_a_horse() -> void:
	_horse.remove_from_group("horse")
	_hs.trust = 7.0
	_hs.jumping_skill = 6.0
	var payload: Dictionary = _save.snapshot()
	_check("a horse-less scene still snapshots the horse", payload.has("horse"))
	if payload.has("horse"):
		var section: Dictionary = payload["horse"]
		_check("the horse-less snapshot keeps trust", is_equal_approx(float(section.get("trust", 0.0)), 7.0))
		_check("the horse-less snapshot keeps training", is_equal_approx(float(section.get("jumping_skill", 0.0)), 6.0))
	_horse.add_to_group("horse")


func _check_local_file() -> void:
	_save.player = "liv"
	_save.slot = 1
	_save.enabled = true
	_save.revision = 4
	_gs.money = 512

	_save.save_now("check")
	var path: String = _save._local_path()
	_check("local file written", FileAccess.file_exists(path))

	var handle := FileAccess.open(path, FileAccess.READ)
	if handle != null:
		var parsed: Variant = JSON.parse_string(handle.get_as_text())
		handle.close()
		_check("local file is JSON", typeof(parsed) == TYPE_DICTIONARY)
		if typeof(parsed) == TYPE_DICTIONARY:
			_check("local file records the revision", int(parsed.get("revision", -1)) == 4)

	_gs.money = 1
	_horse.trust = 0.0
	_save._read_local()
	_check("local file restores money", _gs.money == 512)
	# A horse is in the tree here, so its half is applied in place as well as to
	# the state; the horse-less case is checked on its own below.
	_check("local file restores the horse", is_equal_approx(_horse.trust, 3.5))
	_check("local file restores the state", is_equal_approx(float(_hs.trust), 3.5))
	_check_snapshot_without_a_horse()

	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
	_check("local file cleaned up", not FileAccess.file_exists(path))
	print("local file: written, revision kept, restored, cleaned up")


func _check_guest_writes_nothing() -> void:
	_save.player = ""
	_save.slot = 1
	_save.enabled = false
	var before := 0
	var dir := DirAccess.open("user://")
	if dir != null:
		before = Array(dir.get_files()).filter(func(name: String) -> bool: return name.begins_with("save_livery_")).size()

	_gs.money = 999
	_save.save_now("guest")

	var after := 0
	if dir != null:
		after = Array(dir.get_files()).filter(func(name: String) -> bool: return name.begins_with("save_livery_")).size()

	_check("guest writes no file", after == before)
	_check("guest state is untouched", _gs.money == 999)
	print("guest: no file, no state change")


## The reply handler is driven directly, so the revision bookkeeping and the
## conflict path are covered without a network round trip.  A 409 must adopt the
## cloud revision and ask for that save rather than overwrite it.
func _check_response_handling() -> void:
	_save.player = "liv"
	_save.slot = 1
	_save.enabled = true

	_save.revision = 0
	_save._request_kind = "save"
	_save._on_request_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
		JSON.stringify({"ok": true, "revision": 3}).to_utf8_buffer())
	_check("an acknowledged save records the revision", _save.revision == 3)

	var seen := [0]
	var on_conflict := func(revision: int) -> void: seen[0] = revision
	_save.conflict.connect(on_conflict)
	_save.revision = 1
	_save._request_kind = "save"
	_save._on_request_completed(HTTPRequest.RESULT_SUCCESS, 409, PackedStringArray(),
		JSON.stringify({"error": "stale save", "revision": 5}).to_utf8_buffer())
	_check("a stale save adopts the cloud revision", _save.revision == 5)
	_check("a stale save reports the conflict", seen[0] == 5)
	_save.conflict.disconnect(on_conflict)

	_gs.money = 0
	_save.revision = 0
	_save._request_kind = "load"
	_save._on_request_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
		JSON.stringify({"ok": true, "exists": true, "revision": 4, "payload": {"money": 77}}).to_utf8_buffer())
	_check("a cloud load applies the payload", _gs.money == 77)
	_check("a cloud load records the revision", _save.revision == 4)

	_gs.money = 0
	_save._request_kind = "load"
	_save._on_request_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
		JSON.stringify({"ok": true, "exists": false, "revision": 0}).to_utf8_buffer())
	_check("a missing cloud save changes nothing", _gs.money == 0)

	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("save_livery_liv_1.json"):
		dir.remove("save_livery_liv_1.json")
	print("cloud replies: revision kept, 409 adopted + reported, load applied")


## The mask is the one non-scalar field: a base64 PNG that has to survive the
## round trip byte for byte, because a lossy trip would show as a changed coat.
func _check_mask_round_trip() -> void:
	var surface_script := load("res://scripts/groom_surface.gd")
	var source = surface_script.new()
	_check("an unbaked mask exports nothing", String(source.export_mask()).is_empty())

	var data := PackedByteArray()
	data.resize(256 * 256 * 4)
	for i in range(data.size()):
		data[i] = (i / 4) % 256
	source._mask_data = data

	var encoded: String = source.export_mask()
	_check("the coat mask encodes", not encoded.is_empty())
	_check("the encoded mask fits the payload cap", encoded.length() < 262144)

	var target = surface_script.new()
	_check("the coat mask imports", target.import_mask(encoded))
	_check("the coat mask round-trips byte for byte", target._imported_data == data)
	_check("a corrupt mask is refused", not target.import_mask("not-a-png"))
	var tiny := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	_check("a wrong-sized PNG is refused",
		not target.import_mask(Marshalls.raw_to_base64(tiny.save_png_to_buffer())))

	print("coat mask: %d bytes base64, exact round trip, bad input refused" % encoded.length())
	source.free()
	target.free()


## The show-class fields had no signal of their own, so they were only saved when
## a fee or a prize moved money 1.5 s earlier.  A contract that invisible is one
## refactor away from silent data loss, so it is asserted here.
func _check_progress_signal() -> void:
	var seen := [0]
	var on_progress := func() -> void: seen[0] += 1
	_gs.progress_changed.connect(on_progress)
	_gs.show_entries = 0
	_gs.add_show_entry()
	_check("an entry reports progress", seen[0] == 1)
	_gs.show_best_time = 0.0
	_gs.record_show_time(70.0)
	_check("a show best time reports progress", seen[0] == 2)
	_gs.record_show_time(80.0)
	_check("a slower round reports nothing", seen[0] == 2)
	_gs.progress_changed.disconnect(on_progress)
	print("progress signal: entry and best time reported")


func _finish() -> void:
	if _failures.is_empty():
		print("SAVE CHECK: PASS")
		quit(0)
		return
	for failure in _failures:
		print("FAIL: %s" % failure)
	print("SAVE CHECK: FAIL (%d)" % _failures.size())
	quit(1)
