extends Control
## Startmenü: wählt eine der Debug-Szenen. Neue Szenen einfach in SCENES eintragen.

const SCENES := [
	["Spielen – Waldwelt", "res://scenes/world/forest.tscn", "Beobachten, Journal, Aufgaben (Spielstand wird gespeichert)"],
	["Taxonomie-Viewer", "res://scenes/debug/taxonomy_viewer.tscn", "Baum, Glyphen, Ähnlichkeitsregler (M1)"],
	["Genom-Vergleich", "res://scenes/debug/genome_compare.tscn", "Zwei Kreaturen und ihr Abstand (M1)"],
	["Kreaturen-Labor", "res://scenes/debug/creature_lab.tscn", "3D-Meshes, IK-Laufen, LOD, FPS (M2)"],
]


func _ready() -> void:
	theme = Theme.new()
	theme.default_font_size = 22
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.13, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)
	var title := Label.new()
	title.text = "Creature Learning – Debug"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for spec in SCENES:
		var b := Button.new()
		b.text = "%s\n%s" % [spec[0], spec[2]]
		b.custom_minimum_size = Vector2(520, 66)
		b.pressed.connect(get_tree().change_scene_to_file.bind(spec[1]))
		box.add_child(b)
