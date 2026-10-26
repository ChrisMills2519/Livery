extends SceneTree

## Headless check for the daily-needs loop.
##
##   godot --headless --path . --script res://tools/check_care.gd
##
## Covers what the GDD's MVP called "feeding ... and purchasing supplies": hunger
## and energy decay gently, health drifts toward what the care adds up to, the
## feed store turns money into hay, the trough spends a bale and the horse eats
## it, a refusal never costs hay, and all of it survives a doorway and a save.
##
## The two stations are real nodes in `scenes/stable.tscn`, so this drives the
## actual prompts, gates and CONTEXT offers rather than a copy of them.

const MAIN := "res://scenes/main.tscn"

var _failures: Array[String] = []
# Autoloads are resolved by path: in --script mode their names are not known
# identifiers at compile time (see check_character_select.gd).
var _gs
var _hs
var _save
var _world: Node = null
var _horse: Node
var _player: Node
var _trough: Node
var _store: Node


func _initialize() -> void:
	await process_frame
	_gs = root.get_node("GameState")
	_hs = root.get_node("HorseState")
	_save = root.get_node("SaveGame")
	await _spawn()
	if _horse == null or _player == null or _trough == null or _store == null:
		_check("the world exposes the horse, the player and both feed stations", false)
		_finish()
		return

	await _check_needs()
	await _check_store()
	await _check_trough()
	await _check_persistence()
	# _check_persistence leaves hunger at 0.62 and three bales in the yard.
	await _free_world()
	await _spawn()
	_check("needs survive the doorway", absf(float(_horse.get("hunger")) - 0.62) < 0.01)
	_check("hay survives the doorway", _gs.hay == 3)
	await _free_world()
	_finish()


# --- needs ------------------------------------------------------------------

func _check_needs() -> void:
	_horse.set("hunger", 1.0)
	_horse.set("energy", 1.0)
	_horse.set("health", 1.0)
	_check("a fresh horse starts fed", is_equal_approx(float(_horse.get("hunger")), 1.0))

	# One real minute of play, applied in one step so the check stays fast.
	var rate: float = _horse.get("hunger_per_minute")
	_horse.call("_tick_needs", 60.0)
	# A tolerance, not is_equal_approx: the horse keeps ticking in real physics
	# frames between the call and the assertion.
	_check("hunger falls over a minute", absf(float(_horse.get("hunger")) - (1.0 - rate)) < 0.002)

	_horse.set("energy", 0.5)
	_horse.call("_tick_needs", 60.0)
	_check("a resting horse recovers energy", float(_horse.get("energy")) > 0.5)

	# Health follows the care: clean, trusted and fed pulls it up, slowly.
	_horse.set("cleanliness", 1.0)
	_horse.set("trust", 1.0)
	_horse.set("hunger", 1.0)
	_horse.set("health", 0.5)
	_horse.call("_tick_needs", 600.0)
	_check("health drifts toward full care", float(_horse.get("health")) > 0.65)

	# The second-by-second mirror into the state owner, which is what a doorway
	# and a save travel through.
	_horse.call("_tick_needs", 60.0)
	_check("needs reach the state owner",
		is_equal_approx(float(_hs.hunger), float(_horse.get("hunger"))))

	# The HUD is the only place the player can see any of this.
	var hud := get_first_node_in_group("gameplay_hud")
	var panel: Node = null
	if hud != null:
		panel = (hud as Node).find_child("NeedsPanel", true, false)
	_check("the HUD has a needs panel", panel != null)
	if panel != null:
		_check("the panel shows hay and three bars", panel.get_child_count() == 4)
	print("needs: decay, rest, health drift, state mirror, HUD panel")


# --- store ------------------------------------------------------------------

func _check_store() -> void:
	_gs.money = 100
	_gs.hay = 0

	await _stand_at(_store)
	_check("the store offers a buy", bool(_store.call("_refresh")))
	var offer: Dictionary = _store.call("touch_context")
	_check("the store offers BUY HAY on touch", String(offer.get("label", "")) == "BUY HAY")

	await _interact()
	_check("a bale costs its price", _gs.money == 100 - int(_gs.HAY_PRICE))
	_check("the bale lands in the yard", _gs.hay == 1)

	_gs.money = 0
	await _interact()
	_check("a broke player buys nothing", _gs.hay == 1)
	_check("a broke player is told why",
		String(_store.get("_flash_text")).to_lower().contains("bale"))

	# One more, so the trough has something to refuse later.
	_gs.money = 50
	await _interact()
	_check("a second bale can be bought", _gs.hay == 2)
	print("store: price, stock, refusal when broke, touch offer")


# --- trough -----------------------------------------------------------------

func _check_trough() -> void:
	_gs.hay = 2
	_horse.set("hunger", 0.4)
	_horse.set("boarded", false)
	await _stand_at(_trough)
	await _place_horse_at(_trough)

	_check("the trough offers a feed", bool(_trough.call("_refresh")))
	var offer: Dictionary = _trough.call("touch_context")
	_check("the trough offers FEED on touch", String(offer.get("label", "")) == "FEED")

	# Only one feed station may offer at a time, or a phone thumb would see two
	# buttons for one spot - and the far one used to swallow the press.  Both are
	# refreshed so the assertion is about the rule, not about poll timing.
	_store.call("_refresh")
	_check("the nearer station is the only one offering",
		_trough.call("touch_context").get("label", "") == "FEED"
		and _store.call("touch_context").is_empty())

	await _interact()
	_check("feeding spends one bale", _gs.hay == 1)
	_check("feeding fills the bowl", float(_horse.get("hunger")) > 0.85)
	_check("feeding is remembered by the owner",
		is_equal_approx(float(_hs.hunger), float(_horse.get("hunger"))))

	# A full horse refuses, and the refusal must not cost the bale that is left.
	var hay_before: int = int(_gs.hay)
	_horse.set("hunger", 1.0)
	await _interact()
	_check("a full horse refuses another bale", _gs.hay == hay_before)
	_check("the refusal says the horse is not hungry",
		String(_trough.get("_flash_text")).to_lower().contains("not hungry"))

	# No hay at all: no offer, and nothing to press.
	_gs.hay = 0
	_horse.set("hunger", 0.4)
	_trough.call("_refresh")
	_check("an empty yard offers no feed", _trough.call("touch_context").is_empty())
	await _interact()
	_check("an empty yard spends nothing", _gs.hay == 0)

	# The horse has to be at the trough: walking away withdraws the offer.
	_gs.hay = 1
	_horse.global_position = _trough.global_position + Vector3(12.0, 0.0, 0.0)
	await process_frame
	_trough.call("_refresh")
	_check("the offer needs the horse at the trough", _trough.call("touch_context").is_empty())
	print("trough: spend, fill, refusal costs nothing, empty yard, horse must be near")


# --- persistence ------------------------------------------------------------

func _check_persistence() -> void:
	_gs.hay = 3
	_hs.hunger = 0.62
	_hs.energy = 0.41
	_hs.health = 0.88
	_gs.money = 240

	var payload: Dictionary = _save.snapshot()
	var horse_part: Dictionary = payload.get("horse", {})
	_check("the snapshot carries hunger", is_equal_approx(float(horse_part.get("hunger", -1.0)), 0.62))
	_check("the snapshot carries energy", is_equal_approx(float(horse_part.get("energy", -1.0)), 0.41))
	_check("the snapshot carries health", is_equal_approx(float(horse_part.get("health", -1.0)), 0.88))
	_check("the snapshot carries the hay", int(payload.get("hay", -1)) == 3)

	_gs.hay = 0
	_hs.hunger = 1.0
	_hs.energy = 1.0
	_hs.health = 1.0
	_save.apply(payload)
	_check("a load restores hunger", is_equal_approx(_hs.hunger, 0.62))
	_check("a load restores energy", is_equal_approx(_hs.energy, 0.41))
	_check("a load restores health", is_equal_approx(_hs.health, 0.88))
	_check("a load restores the hay", _gs.hay == 3)
	_check("a load restores the live horse",
		is_equal_approx(float(_horse.get("hunger")), 0.62))
	print("persistence: needs and hay in the snapshot, applied to the live horse")


# --- world plumbing ---------------------------------------------------------

func _spawn() -> void:
	var packed := load(MAIN) as PackedScene
	_world = packed.instantiate()
	root.add_child(_world)
	current_scene = _world
	for i in range(6):
		await process_frame
	_horse = get_first_node_in_group("horse")
	_player = get_first_node_in_group("player")
	_trough = _world.find_child("FeedTrough", true, false)
	_store = _world.find_child("FeedStore", true, false)


func _free_world() -> void:
	if _world != null:
		_world.queue_free()
		_world = null
		current_scene = null
	for i in range(3):
		await process_frame


func _stand_at(station: Node3D) -> void:
	_player.global_position = station.global_position + Vector3(0.0, 0.0, 1.4)
	_player.set("velocity", Vector3.ZERO)
	await process_frame
	await physics_frame
	_player.global_position = station.global_position + Vector3(0.0, 0.0, 1.4)
	station.call("_refresh")


func _place_horse_at(station: Node3D) -> void:
	_horse.global_position = station.global_position + Vector3(0.0, 0.0, 1.1)
	await process_frame
	await physics_frame
	station.call("_refresh")


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
		print("CARE CHECK: PASS")
		quit(0)
		return
	print("CARE CHECK: FAIL (%d)" % _failures.size())
	quit(1)
