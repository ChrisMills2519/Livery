extends Node3D

## Adjusts the stirrup leathers and irons for the current rider.  The saddle is
## authored for an adult leg; a child sits at the same seat but her boots stop
## well above the standard tread height, so the treads have to come up.
##
## The leather is shortened about its top attachment (the D-ring) and the iron
## and tread are raised by the same amount, so the whole stirrup stays one
## piece instead of leaving the leather hanging above the iron.

var _leather: Array[MeshInstance3D] = []
var _iron: Array[Node3D] = []
var _tread: Array[Node3D] = []
var _base_leather: Array[Transform3D] = []
var _base_iron: Array[Vector3] = []
var _base_tread: Array[Vector3] = []
var _lengths: Array[float] = []
var _lift := 0.0
var _cached := false


func _ready() -> void:
	for side in ["L", "R"]:
		var leather := get_node_or_null("Saddle_StirrupLeather_" + side) as MeshInstance3D
		var iron := get_node_or_null("Saddle_Iron_" + side) as Node3D
		var tread := get_node_or_null("Saddle_Tread_" + side) as Node3D
		if leather == null or iron == null or tread == null or leather.mesh == null:
			continue
		_leather.append(leather)
		_iron.append(iron)
		_tread.append(tread)
		_base_leather.append(leather.transform)
		_base_iron.append(iron.position)
		_base_tread.append(tread.position)
		_lengths.append(leather.mesh.get_aabb().size.y * absf(leather.transform.basis.get_scale().y))
	_cached = true


## Positive values raise the treads and shorten the leathers.  Safe to call
## every frame; it only rebuilds when the requested lift changes.
func set_stirrup_lift(lift: float) -> void:
	if not _cached:
		return
	lift = maxf(lift, 0.0)
	if is_equal_approx(lift, _lift):
		return
	_lift = lift
	for i in range(_leather.size()):
		var leather := _leather[i]
		leather.transform = _base_leather[i]
		_iron[i].position = _base_iron[i]
		_tread[i].position = _base_tread[i]
		if lift <= 0.0001:
			continue
		var length := _lengths[i]
		if length <= 0.01:
			continue
		var shorten := minf(lift, length * 0.8)
		var plus := _base_leather[i] * Vector3(0.0, length * 0.5, 0.0)
		var minus := _base_leather[i] * Vector3(0.0, -length * 0.5, 0.0)
		var sign := 1.0 if plus.y > minus.y else -1.0
		var up := _base_leather[i].basis.y.normalized() * sign
		leather.position = _base_leather[i].origin + up * shorten * 0.5
		var base_scale := _base_leather[i].basis.get_scale()
		leather.scale = Vector3(
			base_scale.x,
			base_scale.y * (length - shorten) / length,
			base_scale.z
		)
		_iron[i].position = _base_iron[i] + Vector3(0.0, shorten, 0.0)
		_tread[i].position = _base_tread[i] + Vector3(0.0, shorten, 0.0)
