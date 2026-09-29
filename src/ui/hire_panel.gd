class_name HirePanel
extends Control
## Anheuern: Liste der Fremden am Waldrand mit Preis. „Zeigen“ springt zur
## Kreatur (beobachten, bevor man zahlt), „Anheuern“ nimmt sie in die Gruppe.
## Die Art wird nicht verraten – nur Geschlecht, Alter und Preis.

signal show_requested(offer: GroupMember)
signal hire_requested(offer: GroupMember)
signal closed

var game: GameState


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func open(p_game: GameState) -> void:
	game = p_game
	UiUtil.clear(self)
	var box := UiUtil.overlay(self, Vector2(640, 0))
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := UiUtil.caption("Anheuern", 0, 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiUtil.button("Schließen", _close, Vector2(140, 48)))
	var cur := GameState.currency()
	box.add_child(UiUtil.label("Guthaben: %d %s · Gruppe: %d Tiere" % [game.credits, cur, game.members.size()], 18, Color(0.95, 0.85, 0.4)))
	box.add_child(UiUtil.label("Diese Fremden streifen am Waldrand umher. Schau ihnen eine Weile zu, bevor du dich entscheidest – nach jeder Aufgabe kommen neue dazu.", 15, Color(1, 1, 1, 0.75)))
	if game.offers.is_empty():
		box.add_child(UiUtil.label("Gerade wartet niemand.", 16))
	for i in game.offers.size():
		var o := game.offers[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var desc := "%s · %s%s" % [o.name, "♂" if o.sex == "male" else "♀", " · Jungtier" if o.age == "juvenile" else ""]
		var l := UiUtil.caption(desc, 0, 17)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UiUtil.caption("%d %s" % [o.price, cur], 110, 17, Color(0.95, 0.85, 0.4)))
		row.add_child(UiUtil.button("Zeigen", func(): visible = false; show_requested.emit(o), Vector2(110, 48)))
		var hire := UiUtil.button("Anheuern", func(): hire_requested.emit(o), Vector2(130, 48))
		var problem := game.hire_problem(o)
		hire.disabled = problem != ""
		hire.tooltip_text = problem
		row.add_child(hire)
	visible = true


func _close() -> void:
	visible = false
	closed.emit()
