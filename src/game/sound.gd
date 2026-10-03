class_name Sound
extends RefCounted
## Zugriff auf den Autoload „Sfx“ (src/game/sfx.gd) – funktioniert auch, wenn er
## fehlt (Werkzeuge, eigene Hauptschleifen); dann bleibt es still.


static func _node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Sfx") if tree != null else null


## source: Kreatur, die das Geräusch macht (nur hörbar, wenn sie im Fokus ist).
static func play(sound: String, at: Variant = null, source: Node = null) -> void:
	var n := _node()
	if n != null:
		n.play(sound, at, source)


static func vibrate(ms := 40) -> void:
	var n := _node()
	if n != null:
		n.vibrate(ms)


static func is_enabled() -> bool:
	var n := _node()
	return n.enabled if n != null else false


static func set_enabled(on: bool) -> void:
	var n := _node()
	if n != null:
		n.set_enabled(on)
