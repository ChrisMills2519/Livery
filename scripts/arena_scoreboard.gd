extends Node3D

## Live scoreboard for the showground.
##
## The board owns its Label3D children, so the scene generator only has to place
## the node on the board face and point it at the ring.  It reads the show class
## through its group, so it needs no wiring in the scene file.

@export var title := "CLASS 1 · 1.05 m OPEN"
@export var width := 3.4

var _title_label: Label3D
var _main_label: Label3D
var _lines_label: Label3D
var _course: Node
var _tick := 0.0


func _ready() -> void:
	_title_label = _make_label(Vector3(0.0, 0.82, 0.09), 40, title, Color(0.95, 0.92, 0.76))
	_main_label = _make_label(Vector3(0.0, 0.22, 0.09), 88, "—", Color(0.97, 0.95, 0.85))
	_lines_label = _make_label(Vector3(0.0, -0.58, 0.09), 34, "Entries open at the desk", Color(0.86, 0.90, 0.80))
	_lines_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	call_deferred("_bind")


func _make_label(pos: Vector3, size: int, text: String, colour: Color) -> Label3D:
	var label := Label3D.new()
	label.position = pos
	label.text = text
	label.font_size = size
	label.pixel_size = 0.0045
	label.outline_size = 10
	label.outline_modulate = Color(0.03, 0.04, 0.03, 1.0)
	label.modulate = colour
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = false
	add_child(label)
	return label


func _bind() -> void:
	_course = get_tree().get_first_node_in_group("show_class")


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.15:
		return
	_tick = 0.0
	if _course == null or not is_instance_valid(_course):
		_bind()
		return
	_refresh()


func _refresh() -> void:
	var state := String(_course.get("state"))
	if state == "running":
		_main_label.text = "%.1f" % float(_course.call("get_elapsed"))
		_lines_label.text = "No. %d\n%s" % [
			int(_course.get("rider_number")),
			String(_course.call("get_status_line")),
		]
		_main_label.modulate = Color(0.97, 0.95, 0.85)
		return
	if not bool(_course.get("entered")):
		var result: Dictionary = _course.get("last_result")
		if not result.is_empty():
			_main_label.text = String(result.get("title", "RESULT"))
			_main_label.modulate = Color(0.75, 1.0, 0.65)
			var lines: Array[String] = []
			var standings: Array = _course.call("get_standings")
			for i in range(mini(3, standings.size())):
				var row: Dictionary = standings[i]
				lines.append("%d. %s  %dF  %.1fs" % [i + 1, String(row["name"]), int(row["faults"]), float(row["time"])])
			_lines_label.text = "\n".join(lines) if not lines.is_empty() else String(result.get("notice", ""))
			return
		_main_label.text = "ENTRIES"
		_main_label.modulate = Color(0.97, 0.95, 0.85)
		_lines_label.text = "£%d per class\n10 fences · 1.05 m" % int(_course.get("entry_fee"))
		return
	_main_label.text = "No. %d" % int(_course.get("rider_number"))
	_lines_label.text = "ON COURSE\nAwaiting the bell"
