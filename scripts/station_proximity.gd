extends RefCounted

## Which station of a cluster the player is standing at.
##
## Deliberately **not** a global `class_name`: this machine's headless editor scan
## produces no imports and no global class cache entries, so a new global class is
## invisible to every `--script` check ("Identifier not declared in the current
## scope").  Callers preload it instead: `const StationProximity :=
## preload("res://scripts/station_proximity.gd")`.
##
##
## Two stations whose ranges overlap is a real fault, not a test artifact: one
## `interact` event is claimed by one node, so without a rule the later node in
## the tree swallows the press and the nearer station's action silently does
## nothing.  The feed store did exactly that to the trough, and the muck-out
## point stands a couple of metres from the stable door.  Stations that can
## overlap join one group, and only the nearest offers - for the prompt as well
## as the press - so a thumb never sees two offers for one spot and the keyboard
## cannot press the wrong one.
##
## The 0.05 m tolerance stops a player standing exactly between two stations
## from flipping the offer on every poll.


## True when `station` is the nearest member of `group` to `player`.  A station
## on its own in the group, or a scene where the player has not spawned yet,
## answers true: the rule exists to order a cluster, not to gate a lone station.
static func is_nearest(player: Node3D, station: Node3D, group: String) -> bool:
	if player == null or station == null or station.get_tree() == null:
		return true
	var mine := player.global_position.distance_to(claim_point(station))
	for other in station.get_tree().get_nodes_in_group(group):
		if other == station or not (other is Node3D):
			continue
		var node := other as Node3D
		if not node.is_inside_tree():
			continue
		if player.global_position.distance_to(claim_point(node)) < mine - 0.05:
			return false
	return true


## The patch of ground a station offers from.  A station whose prompt stands at
## a marker rather than at its own origin (the stable door offers from
## `UseAnchor`, not from the stable root) has to say so, or the comparison
## measures the distance to a building instead of to the other prompt.
static func claim_point(station: Node3D) -> Vector3:
	if station.has_method("claim_point"):
		return station.call("claim_point")
	return station.global_position
