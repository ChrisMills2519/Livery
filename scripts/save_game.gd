extends Node

## Per-player save slots, mirrored to the shelf's `save_game` edge function.
##
## Identity comes from the shelf: `?player=liv|ted` in the web URL, remembered
## per origin and validated against the same allowlist the function uses.
## Anything else -- guest, an unknown name, a desktop shortcut -- leaves saving
## disabled rather than guessing a player, because a save filed under the wrong
## name is worse than a save that was never written.
##
## Local first: the snapshot is written to `user://` before any network call, so
## a dropped connection never costs progress.  The cloud copy is the backup that
## survives a cleared browser or a replaced tablet.
##
## Deliberately not saved: the character-select handoff and the door spawn (they
## are one-shot scene transitions, and persisting them would drop a player into
## the saddle with a stale position).
##
## The horse half of a save lives in the `HorseState` autoload, never in the
## scene: see that file for why.

signal loaded(revision: int)
signal conflict(cloud_revision: int)

const GAME_ID := "livery"
const ENDPOINT := "https://qmywqscmpduitgjqrfyb.supabase.co/functions/v1/save_game"
## Supabase's publishable anon key, the same one analytics.gd and the four shelf
## game pages carry.  It belongs in the client; it can only write through the
## function, and the table refuses an anon write.
const ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFteXdxc2NtcGR1aXRnanFyZnliIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI5Mjk3ODUsImV4cCI6MjEwODUwNTc4NX0.lUg_sLn4uWB4JXe997Xa08VYdvhjHkbda0iaFzuV0Zk"
const ALLOWED_PLAYERS := ["liv", "ted"]
const DEFAULT_SLOT := 1
const MAX_SLOT := 9
const STORAGE_KEY := "livery.player"
const SAVE_VERSION := 1
const DEBOUNCE_SECONDS := 1.5

## "" when saving is off: guest, an unknown name, or a game opened outside the
## shelf without a remembered choice.
var player := ""
var slot := DEFAULT_SLOT
## Last cloud revision this device knows about.  Sent as `base_revision`, so a
## stale device is refused instead of overwriting newer progress.
var revision := 0
var enabled := false

var _applying := false
var _in_flight := false
var _request_kind := ""
var _http: HTTPRequest = null
var _debounce: Timer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = DEBOUNCE_SECONDS
	_debounce.timeout.connect(func() -> void: save_now("auto"))
	add_child(_debounce)

	if OS.has_feature("web"):
		_http = HTTPRequest.new()
		add_child(_http)
		_http.request_completed.connect(_on_request_completed)

	_resolve_identity(_web_search())
	GameState.money_changed.connect(_on_progress)
	GameState.best_time_changed.connect(_on_progress)
	GameState.rosettes_changed.connect(_on_progress)
	GameState.progress_changed.connect(_on_progress)
	HorseState.changed.connect(_on_progress)

	# Local first, then let the cloud copy win only if it is strictly newer.
	_read_local()
	if enabled:
		_request_load()


## Focus loss is the closest thing to a clean exit on a tablet: the tab may be
## backgrounded and never return.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		save_now("focus")


# --- identity ---------------------------------------------------------------

func _web_search() -> String:
	if not OS.has_feature("web"):
		return ""
	var search: Variant = JavaScriptBridge.eval("window.location.search", true)
	return "" if search == null else str(search)


## Pure parse of a query string, so the rules can be checked headlessly.
## `player` is "" unless it is on the allowlist; `slot` falls back to 1.
func _parse_identity(search: String) -> Dictionary:
	var who := _query_value(search, "player").to_lower()
	var slot_text := _query_value(search, "slot")
	var chosen_slot := DEFAULT_SLOT
	if slot_text.is_valid_int():
		chosen_slot = clampi(int(slot_text), 1, MAX_SLOT)
	return {
		"player": who if ALLOWED_PLAYERS.has(who) else "",
		"slot": chosen_slot,
	}


func _query_value(search: String, key_name: String) -> String:
	var query := search.strip_edges()
	if query.begins_with("?"):
		query = query.substr(1)
	for pair in query.split("&", false):
		var parts := pair.split("=", true, 1)
		if parts.size() == 2 and parts[0].strip_edges() == key_name:
			return parts[1].strip_edges()
	return ""


func _resolve_identity(search: String) -> void:
	var parsed := _parse_identity(search)
	var who: String = parsed["player"]
	if who.is_empty() and OS.has_feature("web"):
		who = _remembered_player()
		if not ALLOWED_PLAYERS.has(who):
			who = ""
	player = who
	slot = int(parsed["slot"])
	enabled = not player.is_empty()
	if enabled and OS.has_feature("web"):
		_remember_player(player)


## A bookmark or home-screen icon carries no query string, so the device's last
## choice stands in.  It is a remembered claim, not an identity.
func _remembered_player() -> String:
	var stored: Variant = JavaScriptBridge.eval(
		"(function(){try{return localStorage.getItem(%s)||''}catch(e){return ''}})()" % JSON.stringify(STORAGE_KEY),
		true)
	return "" if stored == null else str(stored).to_lower()


func _remember_player(who: String) -> void:
	JavaScriptBridge.eval(
		"(function(){try{localStorage.setItem(%s,%s)}catch(e){}})()" % [JSON.stringify(STORAGE_KEY), JSON.stringify(who)],
		true)


# --- snapshot / apply -------------------------------------------------------

## Everything that should survive a visit.  Money, times and rosettes live on
## GameState; the care and training stats live on the horse.
func snapshot() -> Dictionary:
	# The horse half comes from the autoload, not from the scene.  A scene with no
	# horse (the farmhouse) used to drop it from the payload, and one holding a
	# freshly spawned horse (the showground) used to write a pristine one over
	# the save; HorseState is the copy the player actually earned.
	return {
		"version": SAVE_VERSION,
		"money": GameState.money,
		"money_floor_version": GameState.money_floor_version,
		"best_round_time": GameState.best_round_time,
		"show_best_time": GameState.show_best_time,
		"show_entries": GameState.show_entries,
		"rosettes": GameState.rosettes.duplicate(true),
		"hay": GameState.hay,
		"horse": HorseState.to_dict(),
	}


## Applies a payload to GameState and to the horse state every horse spawns
## from.  A horse already in the tree is updated in place, so the one on screen
## reflects the load without waiting for a scene change.
func apply(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	_applying = true

	GameState.money = int(payload.get("money", 0))
	# The wallet has a floor, and it is paid once.  A save written by a build with
	# an older floor is raised to the current one; a save already at this version
	# keeps exactly the money it holds, so spending down to £3 and reloading does
	# not refill the wallet.  The marker then travels with the next save.
	var floor_version := int(payload.get("money_floor_version", 0))
	if floor_version < GameState.MONEY_FLOOR_VERSION:
		GameState.adopt_starting_money()
	GameState.money_floor_version = GameState.MONEY_FLOOR_VERSION
	GameState.best_round_time = float(payload.get("best_round_time", 0.0))
	GameState.show_best_time = float(payload.get("show_best_time", 0.0))
	GameState.show_entries = int(payload.get("show_entries", 0))
	GameState.hay = int(payload.get("hay", 0))

	# GameState.rosettes is Array[Dictionary], so it has to be rebuilt rather
	# than assigned from the parsed (untyped) array.
	var list: Array[Dictionary] = []
	var raw: Variant = payload.get("rosettes", [])
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:
				list.append(entry)
	GameState.rosettes = list
	GameState.money_changed.emit(GameState.money)
	GameState.rosettes_changed.emit(GameState.rosettes.size())
	GameState.supplies_changed.emit()

	var horse_payload: Variant = payload.get("horse", {})
	if horse_payload is Dictionary and not (horse_payload as Dictionary).is_empty():
		HorseState.from_dict(horse_payload as Dictionary)
		var horse: Node = null
		var tree := get_tree()
		if tree != null:
			horse = tree.get_first_node_in_group("horse")
		if horse != null:
			HorseState.apply_to(horse)

	_applying = false


# --- saving -----------------------------------------------------------------

func _on_progress(_value = null) -> void:
	if not enabled or _applying:
		return
	_debounce.start()


## Writes the local copy first, then mirrors.  Safe to call often: the local
## write is cheap and the cloud request is dropped while one is in flight.
func save_now(_reason := "auto") -> void:
	if not enabled or _applying:
		return
	var data := snapshot()
	_write_local(data)
	_request_save(data)


func _request_save(data: Dictionary) -> void:
	if not _can_request() or _in_flight:
		return
	_send({
		"action": "save",
		"game_id": GAME_ID,
		"player": player,
		"slot": slot,
		"payload": data,
		"base_revision": revision,
	}, "save")


func _request_load() -> void:
	if not _can_request() or _in_flight:
		return
	_send({
		"action": "load",
		"game_id": GAME_ID,
		"player": player,
		"slot": slot,
	}, "load")


func _can_request() -> bool:
	return enabled and OS.has_feature("web") and _http != null


func _send(body: Dictionary, kind: String) -> void:
	_in_flight = true
	_request_kind = kind
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + ANON_KEY,
	])
	var err := _http.request(ENDPOINT, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_in_flight = false
		_request_kind = ""


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_in_flight = false
	var kind := _request_kind
	_request_kind = ""
	if result != HTTPRequest.RESULT_SUCCESS:
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed

	if kind == "save":
		if code == 200:
			revision = int(data.get("revision", revision))
			# Re-store so the local copy carries the acknowledged revision.
			_write_local(snapshot())
		elif code == 409:
			# The cloud row is newer than this device believed.  Adopt it rather
			# than overwrite it: the newer save is the one worth keeping.
			revision = int(data.get("revision", revision))
			conflict.emit(revision)
			_request_load()
	elif kind == "load" and code == 200:
		var exists := bool(data.get("exists", false))
		if not exists:
			return
		var cloud_revision := int(data.get("revision", 0))
		var payload: Variant = data.get("payload", {})
		if not payload is Dictionary:
			return
		if cloud_revision >= revision:
			revision = cloud_revision
			apply(payload)
			loaded.emit(revision)
			_write_local(snapshot())
		else:
			# This device is ahead of the cloud (played offline); push it up.
			_request_save(snapshot())


# --- local file -------------------------------------------------------------

func _local_path() -> String:
	return "user://save_%s_%s_%d.json" % [GAME_ID, player, slot]


func _write_local(data: Dictionary) -> void:
	if not enabled:
		return
	var handle := FileAccess.open(_local_path(), FileAccess.WRITE)
	if handle == null:
		return
	handle.store_string(JSON.stringify({"revision": revision, "payload": data}))
	handle.close()


func _read_local() -> void:
	if not enabled:
		return
	if not FileAccess.file_exists(_local_path()):
		return
	var handle := FileAccess.open(_local_path(), FileAccess.READ)
	if handle == null:
		return
	var text := handle.get_as_text()
	handle.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var record: Dictionary = parsed
	var payload: Variant = record.get("payload", {})
	if not payload is Dictionary:
		return
	revision = int(record.get("revision", 0))
	apply(payload)
	loaded.emit(revision)
