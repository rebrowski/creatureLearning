class_name RoundPanel
extends Control
## Übersicht zwischen den Phasen einer Runde: nach dem Zug der Rivalen und am
## Abend (Ergebnisse der Runde, Punktestand, Erholung). Ein Hauptknopf führt zur
## nächsten Phase, ein zweiter (optional) schließt nur, um sich im Lager umzusehen.

signal primary
signal secondary

const GOOD := Color(0.6, 1.0, 0.55)
const BAD := Color(1.0, 0.65, 0.5)
const NOTE := Color(1, 1, 1, 0.7)


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


## lines: [[Text, Farbe]]; secondary_text leer = kein zweiter Knopf.
func open(title: String, subtitle: String, lines: Array, primary_text: String, secondary_text := "") -> void:
	UiUtil.clear(self)
	var box := UiUtil.overlay(self, Vector2(680, 0))
	box.add_child(UiUtil.label(subtitle, 16, NOTE))
	box.add_child(UiUtil.label(title, 26))
	for line in lines:
		box.add_child(UiUtil.label(str(line[0]), 17, line[1]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(UiUtil.button(primary_text, func(): visible = false; primary.emit(), Vector2(300, 56)))
	if secondary_text != "":
		row.add_child(UiUtil.button(secondary_text, func(): visible = false; secondary.emit(), Vector2(200, 56)))
	visible = true
