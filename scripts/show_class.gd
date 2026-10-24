extends SchoolingCourse

## A full show class layered on the schooling round.
##
## The rider pays an entry fee at the secretary's desk, rides through the gate
## when the bell rings, and is placed against a deterministic field of rivals by
## faults and then time.  A top-three finish pays prize money and leaves a
## rosette to collect at the judges' box.
##
## The schooling arena keeps its own behaviour: this script is only used by
## scenes/competition_arena.tscn, which is reached through the showground gate.

signal class_entered(rider_number: int)
signal class_finished(result: Dictionary)
signal rosette_available(info: Dictionary)

const CLASS_LABEL := "CLASS 1 · 1.05 m OPEN"
const DEFAULT_ENTRY_FEE := 20
const PRIZE_MONEY := {1: 120, 2: 70, 3: 45, 4: 25}
const ROSETTE_COLOURS := {1: "red", 2: "blue", 3: "yellow"}
const RIVAL_NAMES := [
	"J. Hartley on Copperfield",
	"M. Ellery on Bracken",
	"S. Okafor on Thistle",
	"R. Vance on Juniper",
	"A. Whitlock on Marigold",
	"T. Byrne on Storm",
	"D. Prowse on Clover",
]

## Ring used for elimination and for the start line.
const RING_MIN := Vector2(-30.0, -15.0)
const RING_MAX := Vector2(30.0, 15.0)
## The gate the bell starts the class from, and the horse crosses westwards.
const START_LINE_X := 30.0

@export var class_label := CLASS_LABEL
@export var entry_fee := DEFAULT_ENTRY_FEE
@export var par_time := 78.0
@export var rival_count := 7

var entered := false
var rider_number := 0
var rivals: Array[Dictionary] = []
var last_result: Dictionary = {}
var pending_rosette: Dictionary = {}

var _prev_horse_x := 0.0
var _started_from_line := false
var _left_ring := false
var _entry_counter := 0
var _bell: AudioStreamPlayer


func _ready() -> void:
	super._ready()
	add_to_group("show_class")
	reset_delay = 8.0
	if horse != null:
		_prev_horse_x = horse.global_position.x
	_bell = get_node_or_null("BellAudio") as AudioStreamPlayer
	if _bell == null:
		_bell = AudioStreamPlayer.new()
		_bell.name = "BellAudio"
		add_child(_bell)
	if _bell.stream == null and ResourceLoader.exists("res://assets/sounds/ui/arena_bell.wav"):
		_bell.stream = load("res://assets/sounds/ui/arena_bell.wav")
	_bell.volume_db = -2.0


# ---------------------------------------------------------------------------
# entry
# ---------------------------------------------------------------------------

## Called by the secretary's desk.  Returns {ok, message}.
func request_entry() -> Dictionary:
	if entered:
		return {"ok": false, "message": "You are already entered — ride through the gate when the bell rings."}
	if state == "running":
		return {"ok": false, "message": "Your round is already under way."}
	if GameState.money < entry_fee:
		return {"ok": false, "message": "The entry fee is £%d — you only have £%d." % [entry_fee, GameState.money]}
	GameState.add_money(-entry_fee)
	GameState.show_entries += 1
	_entry_counter += 1
	rider_number = 100 + _entry_counter
	entered = true
	_started_from_line = false
	_left_ring = false
	last_result = {}
	_build_field()
	reset_round()
	class_entered.emit(rider_number)
	notice.emit("Entered %s as number %d — the bell rings at the gate." % [class_label, rider_number])
	return {"ok": true, "message": "Entered as number %d" % rider_number}


func _build_field() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3100 + GameState.show_entries
	rivals.clear()
	for i in range(rival_count):
		var faults := 0
		var time := par_time + rng.randf_range(-3.5, 6.5)
		if i == 2:
			faults = 4
		if i == 5:
			time += 3.5
		rivals.append({
			"name": RIVAL_NAMES[i % RIVAL_NAMES.size()],
			"time": time,
			"faults": faults,
		})


# ---------------------------------------------------------------------------
# start / finish
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if horse != null:
		var x := horse.global_position.x
		if state == "idle" and entered and not _started_from_line:
			var mounted: bool = player != null and bool(player.get("mounted"))
			if mounted and _prev_horse_x > START_LINE_X and x <= START_LINE_X:
				_begin_class()
		_prev_horse_x = x
	super._physics_process(delta)


func _begin_class() -> void:
	_started_from_line = true
	_left_ring = false
	if _bell != null and _bell.stream != null:
		_bell.play()
	notice.emit("The bell rings — %d fences to clear." % get_jump_count())
	start_round()


## The schooling course starts on a cleared fence; a class starts at the bell.
func _start_if_idle() -> void:
	if state == "idle" and entered and _started_from_line:
		start_round()


func is_inside_ring(point: Vector3) -> bool:
	return (
		point.x >= RING_MIN.x and point.x <= RING_MAX.x
		and point.z >= RING_MIN.y and point.z <= RING_MAX.y
	)


func _check_left_training_area() -> void:
	if is_inside_ring(horse.global_position):
		return
	_left_ring = true
	_finish(true)


func _finish(timed_out: bool) -> void:
	if state != "running":
		return
	state = "finished"
	_reset_left = reset_delay
	entered = false
	var result := _score_class(timed_out)
	last_result = result
	round_finished.emit(result)
	class_finished.emit(result)
	var line := String(result.get("notice", ""))
	if not line.is_empty():
		notice.emit(line)


func _score_class(timed_out: bool) -> Dictionary:
	var total := get_jump_count()
	var clear_round := (cleared_count >= total and faults == 0 and not timed_out and not _left_ring)
	var place := 0
	var prize := 0
	var rosette := ""
	var new_best := false
	var eliminated := _left_ring or timed_out

	if clear_round:
		new_best = GameState.record_show_time(elapsed)
		place = 1
		for rival in rivals:
			var rival_faults: int = rival["faults"]
			var rival_time: float = rival["time"]
			if rival_faults < faults or (rival_faults == faults and rival_time < elapsed):
				place += 1
		prize = int(PRIZE_MONEY.get(place, 0))
		if prize > 0:
			GameState.add_money(prize)
		if place <= 3:
			rosette = ROSETTE_COLOURS[place]
			pending_rosette = {
				"place": place,
				"colour": rosette,
				"class": class_label,
				"collected": false,
			}
			rosette_available.emit(pending_rosette)
		if horse.has_method("award_training"):
			horse.award_training(4.0, 2.0)
	elif horse.has_method("award_training") and cleared_count > 0:
		horse.award_training(cleared_count * 0.4, 0.5)

	var title := _result_title(place, clear_round, eliminated)
	var notice_text := ""
	if eliminated and _left_ring:
		notice_text = "Eliminated — you left the ring."
	elif timed_out:
		notice_text = "Time up — the class is over."
	elif place == 1:
		notice_text = "★ 1st place! +£%d — collect your rosette at the judges' box." % prize
	elif place > 1:
		notice_text = "%s place, +£%d — collect your rosette at the judges' box." % [_ordinal(place), prize]

	return {
		"show_class": true,
		"class_label": class_label,
		"title": title,
		"clears": cleared_count,
		"total": total,
		"faults": faults,
		"seconds": elapsed,
		"reward": prize,
		"prize": prize,
		"placing": place,
		"field": rivals.size() + 1,
		"rosette": rosette,
		"new_best": new_best,
		"timed_out": timed_out,
		"clear_round": clear_round,
		"eliminated": eliminated,
		"left_ring": _left_ring,
		"rider_number": rider_number,
		"entry_fee": entry_fee,
		"notice": notice_text,
		"hint": "Enter again at the desk for another class",
	}


func _result_title(place: int, clear_round: bool, eliminated: bool) -> String:
	if eliminated:
		return "ELIMINATED"
	if not clear_round:
		return "CLASS COMPLETE"
	match place:
		1:
			return "★ 1ST PLACE ★"
		2:
			return "2ND PLACE"
		3:
			return "3RD PLACE"
		_:
			return "CLEAR ROUND"


func _ordinal(value: int) -> String:
	match value:
		1:
			return "1st"
		2:
			return "2nd"
		3:
			return "3rd"
		_:
			return "%dth" % value


# ---------------------------------------------------------------------------
# rosette
# ---------------------------------------------------------------------------

func can_collect_rosette() -> bool:
	return not pending_rosette.is_empty() and not bool(pending_rosette.get("collected", false))


func collect_rosette() -> Dictionary:
	if not can_collect_rosette():
		return {"ok": false, "message": "There is no rosette waiting for you."}
	pending_rosette["collected"] = true
	var total := GameState.award_rosette(class_label, int(pending_rosette["place"]), String(pending_rosette["colour"]))
	_attach_rosette_to_horse(String(pending_rosette["colour"]))
	notice.emit("Rosette collected — %s place. %d rosette(s) this season." % [_ordinal(int(pending_rosette["place"])), total])
	return {"ok": true, "message": "Rosette collected"}


func _attach_rosette_to_horse(colour: String) -> void:
	if horse == null or horse.get_node_or_null("ShowRosette") != null:
		return
	var colours := {
		"red": Color(0.55, 0.09, 0.07),
		"blue": Color(0.09, 0.18, 0.50),
		"yellow": Color(0.80, 0.58, 0.09),
	}
	var body := StandardMaterial3D.new()
	body.albedo_color = colours.get(colour, Color(0.8, 0.8, 0.8))
	body.roughness = 0.6
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.72, 0.55, 0.18)
	gold.metallic = 0.7
	gold.roughness = 0.35

	var rosette := Node3D.new()
	rosette.name = "ShowRosette"
	rosette.position = Vector3(0.16, 1.66, 0.14)
	rosette.rotation = Vector3(0.0, -0.6, 0.25)
	horse.add_child(rosette)

	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.055
	disc_mesh.bottom_radius = 0.055
	disc_mesh.height = 0.012
	disc_mesh.radial_segments = 16
	disc.mesh = disc_mesh
	disc.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	disc.material_override = body
	rosette.add_child(disc)

	var centre := MeshInstance3D.new()
	var centre_mesh := SphereMesh.new()
	centre_mesh.radius = 0.018
	centre_mesh.height = 0.036
	centre.mesh = centre_mesh
	centre.position = Vector3(0.0, 0.0, 0.01)
	centre.material_override = gold
	rosette.add_child(centre)

	for side in [-1.0, 1.0]:
		var tail := MeshInstance3D.new()
		var tail_mesh := BoxMesh.new()
		tail_mesh.size = Vector3(0.030, 0.10, 0.008)
		tail.mesh = tail_mesh
		tail.position = Vector3(side * 0.018, -0.085, 0.0)
		tail.rotation = Vector3(0.0, 0.0, side * 0.22)
		tail.material_override = body
		rosette.add_child(tail)


# ---------------------------------------------------------------------------
# board / HUD text
# ---------------------------------------------------------------------------

func get_objective_text() -> String:
	match state:
		"running":
			return "%s · clear all %d fences" % [class_label, get_jump_count()]
		"finished":
			return "Class complete — results on the board"
	if entered:
		return "Number %d — ride through the gate when the bell rings" % rider_number
	return "Enter %s at the secretary's desk  ·  £%d" % [class_label, entry_fee]


func get_standings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for rival in rivals:
		rows.append({
			"name": rival["name"],
			"time": rival["time"],
			"faults": rival["faults"],
			"player": false,
		})
	if not last_result.is_empty() and int(last_result.get("placing", 0)) > 0:
		rows.append({
			"name": "YOU (No. %d)" % int(last_result.get("rider_number", rider_number)),
			"time": last_result.get("seconds", 0.0),
			"faults": last_result.get("faults", 0),
			"player": true,
		})
	rows.sort_custom(func(a, b):
		if int(a["faults"]) != int(b["faults"]):
			return int(a["faults"]) < int(b["faults"])
		return float(a["time"]) < float(b["time"]))
	return rows


func get_status_line() -> String:
	if state == "running":
		return "Fences %d/%d   ·   Faults %d" % [cleared_count, get_jump_count(), faults]
	if not last_result.is_empty():
		return "Last class: %s" % String(last_result.get("title", ""))
	if entered:
		return "ON COURSE · No. %d" % rider_number
	return "Entries open at the desk"
