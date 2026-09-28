extends SceneTree
## Lädt eine Szene, wartet einige Frames und speichert einen Screenshot.
##
## Aufruf (braucht ein Display, z. B. xvfb-run, und den Compatibility-Renderer):
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##       -s tools/screenshot.gd -- res://scenes/debug/taxonomy_viewer.tscn out.png [frames] [aktion]
## Optionale Aktionen, um Zustände zu zeigen:
##   source=<0|1>        Viewer-Quelle: 0 = Demo-JSON, 1 = generiert
##   seed=<zahl>         Seed setzen
##   select=<taxon_id>   Taxon im Viewer auswählen
##   compare=<a>,<b>     zwei Kreaturen (Art#Nummer) in den Vergleich legen
##   call=<methode>      Methode ohne Argumente am Szenen-Root aufrufen (z. B. call=lineup)
##   follow=<n>,<abstand> Labor: Kamera folgt Kreatur Nummer n
##   wait=<frames>       zusätzlich warten

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Aufruf: -- <szene.tscn> <ausgabe.png> [frames] [aktion ...]")
		quit(1)
		return
	var scene: PackedScene = load(args[0])
	var node := scene.instantiate()
	root.add_child(node)
	var frames := int(args[2]) if args.size() > 2 else 20
	for n in frames:
		await process_frame
	for action in args.slice(3):
		var wait := 10
		if action.begins_with("wait="):
			wait = int(action.substr(5))
		else:
			_apply(node, action)
		for n in wait:
			await process_frame
	var img := root.get_texture().get_image()
	img.save_png(args[1])
	print("Screenshot gespeichert: ", args[1])
	quit(0)


func _apply(node: Node, action: String) -> void:
	var parts := action.split("=", true, 1)
	match parts[0]:
		"source":
			node._on_source_changed(int(parts[1]))
		"seed":
			node._seed.value = int(parts[1])
		"select":
			node.selected_id = parts[1]
			node._fill_tree()
		"call":
			node.call(parts[1])
		"follow":
			var f := parts[1].split(",")
			node._select(node.creatures[int(f[0])])
			node.camera.distance = float(f[1])
		"compare":
			var ids := parts[1].split(",")
			var inds := []
			for id in ids:
				var p := id.split("#")
				inds.append(node.factory.create_individual(p[0], int(p[1]), "", "adult"))
			node._compare.set_pair(inds[0], inds[1])
