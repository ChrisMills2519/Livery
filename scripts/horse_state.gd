extends Node

## The one owner of the player's horse progress.
##
## The horse is a node inside a scene, and both the farmhouse and the showground
## are reached by a full scene change, which builds a brand new horse.  Anything
## kept only on that node is therefore reset by walking through a door: the
## trained jump bonus, the trust earned by grooming and the painted coat all
## vanished on the way to the show ring, and the care -> train -> compete loop
## never closed.
##
## This autoload is the state instead.  A horse hydrates from it in `_ready()`,
## records back to it wherever care or training changes, and `SaveGame`
## serialises this object rather than scraping whichever horse the current scene
## happens to hold.  That scrape is what used to let a show entry fee write a
## pristine horse over the cloud save, and what dropped the horse half of the
## payload entirely when the player was in the farmhouse.
##
## `record_from()` emits `changed`; `apply_to()` and `from_dict()` never do, so a
## load or a scene spawn cannot queue another save behind itself.

signal changed

## Below this the bed is not worth mucking out, and the station says so rather
## than offering the chore.  A tenth of a bed is a couple of minutes of stabling.
const MUCK_MIN := 0.10

var trust := 0.0
var happiness := 0.5
var cleanliness := 0.0
var grooming_polish := 0.0
var hooves_cleaned := 0
var groomed_hooves: Array = [false, false, false, false]
var care_reward_score := 0.0
var fitness := 1.0
var jumping_skill := 1.0
## Daily needs, 1.0 = content.  They decay slowly while the horse is in the
## world (see `horse.gd`), so they are part of the state rather than the scene:
## a horse that walked into the stable hungry comes back out hungry.
var hunger := 1.0
var energy := 1.0
var health := 1.0
## How soiled the stable bed is: 0.0 a fresh bed, 1.0 a full muck-out.  It lives
## with the rest of the care progress because the stable is reached through a
## scene change like everywhere else, and because `SaveGame` serialises this
## object rather than whichever horse the current scene happens to hold.
var stall_muck := 0.0
## Base64 PNG of the painted coat.  Empty until a mask has been exported.
var coat_mask := ""


## Writes the state onto a live horse.  The coat mask is handed to the groom
## surface even before it has baked: `import_mask()` parks the bytes and
## `_setup()` copies them over the visible mask between the rasterise and the
## material build, because that bake is also what builds the zone map and the
## paint-gating triangle table the brush needs.
func apply_to(horse: Node) -> void:
	if horse == null:
		return
	horse.set("trust", trust)
	horse.set("happiness", happiness)
	horse.set("cleanliness", cleanliness)
	horse.set("grooming_polish", grooming_polish)
	horse.set("hooves_cleaned", hooves_cleaned)
	horse.set("groomed_hooves", groomed_hooves.duplicate())
	horse.set("care_reward_score", care_reward_score)
	horse.set("fitness", fitness)
	horse.set("jumping_skill", jumping_skill)
	horse.set("hunger", hunger)
	horse.set("energy", energy)
	horse.set("health", health)
	horse.set("stall_muck", stall_muck)
	# The shader mixes a global dirt level with the local mask, so both halves
	# have to be restored: the mask alone leaves the whole coat dark, the level
	# alone erases the painted clean patches.
	var surface: Node = horse.get("groom_surface")
	if surface == null:
		return
	var dirt := 0.0 if cleanliness >= 1.0 else 1.0 - cleanliness
	if surface.has_method("set_dirt_level"):
		surface.call("set_dirt_level", dirt)
	if not coat_mask.is_empty() and surface.has_method("import_mask"):
		surface.call("import_mask", coat_mask)


## Reads a live horse back into the state.  Called from the horse's own mutation
## points (awarded training, a finished hoof, a grooming result, leaving the
## bay) rather than from a timer, so the values here are the values the player
## earned.  An unmasked surface exports "", which must not wipe a restored coat,
## hence the empty check.
func record_from(horse: Node) -> void:
	if horse == null:
		return
	trust = maxf(0.0, float(horse.get("trust")))
	happiness = clampf(float(horse.get("happiness")), 0.0, 1.0)
	cleanliness = clampf(float(horse.get("cleanliness")), 0.0, 1.0)
	grooming_polish = clampf(float(horse.get("grooming_polish")), 0.0, 1.0)
	hooves_cleaned = clampi(int(horse.get("hooves_cleaned")), 0, 4)
	var hooves: Variant = horse.get("groomed_hooves")
	if hooves is Array and (hooves as Array).size() == 4:
		groomed_hooves = (hooves as Array).duplicate()
	care_reward_score = maxf(0.0, float(horse.get("care_reward_score")))
	fitness = maxf(1.0, float(horse.get("fitness")))
	jumping_skill = maxf(1.0, float(horse.get("jumping_skill")))
	hunger = clampf(float(horse.get("hunger")), 0.0, 1.0)
	energy = clampf(float(horse.get("energy")), 0.0, 1.0)
	health = clampf(float(horse.get("health")), 0.0, 1.0)
	stall_muck = clampf(float(horse.get("stall_muck")), 0.0, 1.0)
	var surface: Node = horse.get("groom_surface")
	if surface != null and surface.has_method("export_mask"):
		var exported := str(surface.call("export_mask"))
		if not exported.is_empty():
			coat_mask = exported
	changed.emit()


## The needs tick every second from the horse, which is far too often to go
## through `changed` (that queues a save) and too fine for anything to listen
## to.  It is a plain write; the save points pick the values up.
func set_needs(new_hunger: float, new_energy: float, new_health: float) -> void:
	hunger = clampf(new_hunger, 0.0, 1.0)
	energy = clampf(new_energy, 0.0, 1.0)
	health = clampf(new_health, 0.0, 1.0)


## The bed soils on the horse's own clock and is cleaned by the muck session,
## both far too often for `changed` (which queues a save).  A plain write, like
## `set_needs()`.
func set_stall_muck(value: float) -> void:
	stall_muck = clampf(value, 0.0, 1.0)


## True when the bed is dirty enough to be worth mucking out.  The station, the
## session and the check all ask this one rule rather than repeating the
## threshold.
func needs_mucking() -> bool:
	return stall_muck >= MUCK_MIN


func to_dict() -> Dictionary:
	return {
		"trust": trust,
		"happiness": happiness,
		"cleanliness": cleanliness,
		"grooming_polish": grooming_polish,
		"hooves_cleaned": hooves_cleaned,
		"groomed_hooves": groomed_hooves.duplicate(),
		"care_reward_score": care_reward_score,
		"fitness": fitness,
		"jumping_skill": jumping_skill,
		"hunger": hunger,
		"energy": energy,
		"health": health,
		"stall_muck": stall_muck,
		"coat_mask": coat_mask,
	}


## Clamps everything on the way in, because a save written by an older build (or
## edited by hand) must not be able to push a horse out of range.
func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	trust = maxf(0.0, float(data.get("trust", trust)))
	happiness = clampf(float(data.get("happiness", happiness)), 0.0, 1.0)
	cleanliness = clampf(float(data.get("cleanliness", cleanliness)), 0.0, 1.0)
	grooming_polish = clampf(float(data.get("grooming_polish", grooming_polish)), 0.0, 1.0)
	hooves_cleaned = clampi(int(data.get("hooves_cleaned", hooves_cleaned)), 0, 4)
	care_reward_score = maxf(0.0, float(data.get("care_reward_score", care_reward_score)))
	fitness = maxf(1.0, float(data.get("fitness", fitness)))
	jumping_skill = maxf(1.0, float(data.get("jumping_skill", jumping_skill)))
	hunger = clampf(float(data.get("hunger", hunger)), 0.0, 1.0)
	energy = clampf(float(data.get("energy", energy)), 0.0, 1.0)
	health = clampf(float(data.get("health", health)), 0.0, 1.0)
	stall_muck = clampf(float(data.get("stall_muck", stall_muck)), 0.0, 1.0)
	var hooves: Variant = data.get("groomed_hooves", [])
	if hooves is Array and (hooves as Array).size() == 4:
		groomed_hooves = (hooves as Array).duplicate()
	coat_mask = str(data.get("coat_mask", coat_mask))
