class_name TaskPrompt
extends Control
## Kleiner Hinweis „Eine Aufgabe wartet – starten?“, den die Welt nach einer
## Weile ohne Eingabe zeigt (abschaltbar über „Nicht mehr fragen“).

signal accepted(task: TaskDef)
signal later
signal never

var task: TaskDef


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func open(p_task: TaskDef, reward: int) -> void:
	task = p_task
	UiUtil.clear(self)
	var box := UiUtil.overlay(self, Vector2(620, 0))
	box.add_child(UiUtil.label("Eine Aufgabe wartet", 18, Color(1, 1, 1, 0.7)))
	box.add_child(UiUtil.label(task.name, 26))
	box.add_child(UiUtil.label(task.description, 16))
	if reward > 0:
		box.add_child(UiUtil.label("Belohnung bei Erfolg: %d %s" % [reward, GameState.currency()], 18, Color(0.95, 0.85, 0.4)))
	box.add_child(UiUtil.label("Unter „Aufgaben“ wählst du, wer welche Rolle übernimmt.", 15, Color(1, 1, 1, 0.7)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(UiUtil.button("Ja, Rollen wählen", func(): visible = false; accepted.emit(task), Vector2(220, 52)))
	row.add_child(UiUtil.button("Später", func(): visible = false; later.emit(), Vector2(130, 52)))
	row.add_child(UiUtil.button("Nicht mehr fragen", func(): visible = false; never.emit(), Vector2(190, 52)))
	visible = true
