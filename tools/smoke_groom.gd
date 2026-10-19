extends SceneTree


func _initialize() -> void:
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in range(10):
		await process_frame
	var horse := world.get_node_or_null("Horse")
	var bay := world.get_node_or_null("GroomingBay")
	print("horse=", horse, " bay=", bay)
	if horse != null:
		var surface = horse.get("groom_surface")
		print("surface=", surface)
		if surface != null:
			# The mask bake is deferred one short beat so it does not sit in the
			# character-select handoff.
			for i in range(90):
				if float(surface.get("last_bake_ms")) > 0.0:
					break
				await process_frame
			print("bake_ms=", surface.get("last_bake_ms"), " tris=", surface.get("picker").triangle_count if surface.get("picker") else -1)
			print("zones=", surface.call("get_zone_counts"), " groomable=", surface.call("get_groomable_count"))
			print("coverage=", surface.call("coverage"))
	if bay != null:
		var session := bay.get_node_or_null("Session")
		print("session=", session, " active=", session.get("active") if session else null)
		if session != null:
			var player := world.get_node_or_null("Player")
			var horse_anchor := bay.get_node("HorseAnchor") as Node3D
			var groomer_anchor := bay.get_node("GroomerAnchor") as Node3D
			player.global_position = groomer_anchor.global_position
			horse.global_position = horse_anchor.global_position
			await process_frame
			var entered = session.call("enter", horse_anchor.global_transform, groomer_anchor.global_transform)
			print("entered=", entered)
			for i in range(10):
				await process_frame
			print("active=", session.get("active"), " player_controls=", player.get("controls_enabled"), " horse_grooming=", horse.get("grooming"))
			var cam := session.call("get_camera") as Camera3D
			print("camera=", cam, " current=", cam.current if cam else null, " pos=", cam.global_position if cam else null)
			var surface = horse.get("groom_surface")
			var target: Vector3 = horse.global_position + Vector3(0, 1.05, 0)
			var hit = surface.call("pick_ray", cam.global_position, (target - cam.global_position).normalized())
			print("centre_hit=", hit)
			if not hit.is_empty():
				print("paint=", surface.call("paint_hit", hit, "curry"))
				print("clean=", surface.call("get_mask_value", hit["uv"], "clean"), " loosen=", surface.call("get_mask_value", hit["uv"], "loosen"))
				print("dandy=", surface.call("paint_hit", hit, "dandy"))
				print("after dandy clean=", surface.call("get_mask_value", hit["uv"], "clean"))
				print("soft=", surface.call("paint_hit", hit, "soft"))
				print("polish=", surface.call("get_mask_value", hit["uv"], "polish"), " cov=", surface.call("coverage"))
			var clumps = session.get("_hoof_clumps")
			print("clumps=", clumps.size())
			for c in clumps:
				print("  clump=", c, " pos=", c.global_position if c else null, " visible=", c.visible if c else null)
			print("mark_hoof=", session.call("mark_hoof", 0), " count=", horse.get("hooves_cleaned"), " state=", horse.get("groomed_hooves"))
	quit(0)
