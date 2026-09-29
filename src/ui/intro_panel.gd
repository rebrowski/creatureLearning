class_name IntroPanel
extends Control
## Begrüßung beim ersten Start: worum es geht, in zwei Sätzen.

signal started
signal skipped


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func open() -> void:
	UiUtil.clear(self)
	var box := UiUtil.overlay(self, Vector2(640, 0))
	box.add_theme_constant_override("separation", 12)
	box.add_child(UiUtil.label("Creature Learning", 30))
	box.add_child(UiUtil.label("Niemand weiß, was diese Wesen können – nicht einmal, welche von ihnen zur selben Art gehören.", 18))
	box.add_child(UiUtil.label("Stell sie auf die Probe, beobachte genau und finde heraus, wer welche Aufgabe meistert.", 18, Color(0.8, 0.95, 0.6)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(UiUtil.button("Los geht’s", func(): visible = false; started.emit(), Vector2(220, 56)))
	row.add_child(UiUtil.button("Einführung überspringen", func(): visible = false; skipped.emit(), Vector2(260, 56)))
	visible = true
