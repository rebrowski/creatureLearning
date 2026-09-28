extends SceneTree
## Misst die CPU-Zeit der Kreaturen (Locomotion + Bewegung) ohne Rendering.
##
##   godot --headless -s tools/benchmark_creatures.gd -- [anzahl=20] [frames=600] [lod=full|auto]
## Taktet Verhalten + Kreaturen manuell (inkl. Raycasts) und misst die Zeit direkt.
## Ausgabe: mittlere, 95%- und Maximal-Zeit pro Frame in ms.

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var count := int(args.get("anzahl", "20"))
	var frames := int(args.get("frames", "600"))
	var lab: Node = load("res://scenes/debug/creature_lab.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	var missing: int = count - lab.creatures.size()
	if missing > 0:
		lab._spawn_more(missing)
	elif missing < 0:
		lab._remove(-missing)
	if args.get("lod", "full") == "full":
		for c in lab.creatures:
			c.auto_lod = false
			c.set_lod(CreatureLOD.FULL)
	# Automatische Verarbeitung aus, stattdessen manuell takten und direkt messen
	lab.set_physics_process(false)
	for c in lab.creatures:
		c.set_physics_process(false)
	var dt := 1.0 / 60.0
	var samples: Array[float] = []
	for n in frames + 60:
		var t0 := Time.get_ticks_usec()
		lab._physics_process(dt)
		for c in lab.creatures:
			c._physics_process(dt)
		if n >= 60:
			samples.append((Time.get_ticks_usec() - t0) / 1000.0)
		await process_frame
	samples.sort()
	var total := 0.0
	for s in samples:
		total += s
	print("Kreaturen: %d · Frames: %d · CPU pro Frame Mittel %.2f ms · 95%% %.2f ms · max %.2f ms" % [
		lab.creatures.size(), frames, total / samples.size(), samples[int(samples.size() * 0.95)], samples[-1]])
	quit()
