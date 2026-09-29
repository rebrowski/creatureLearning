class_name ResultPanel
extends Control
## Auswertung einer Aufgabe: Erfolg/Misserfolg, welche Rolle schwach besetzt
## war (ohne die Lösung zu verraten), verdientes Guthaben, neue Fremde.

signal closed


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


## outcome: GameState.record_task() → {"earned", "new_offers"}
func show_result(task: TaskDef, result: Dictionary, names: Dictionary, outcome: Dictionary) -> void:
	UiUtil.clear(self)
	var panel := UiUtil.overlay(self, Vector2(700, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UiUtil.label(task.name, 20, Color(1, 1, 1, 0.7)))
	box.add_child(UiUtil.label("Geschafft!" if result.success else "Nicht geschafft", 30,
			Color(0.6, 1.0, 0.5) if result.success else Color(1.0, 0.6, 0.45)))
	for r in task.roles:
		var e: Dictionary = result.roles.get(r.id, {})
		var verdict := "nicht dran gekommen" if e.get("skipped", false) else (
				("gut besetzt" if not e.get("close", false) else "knapp geschafft") if e.get("success", false)
				else ("knapp gescheitert" if e.get("close", false) else "schwach besetzt"))
		box.add_child(UiUtil.label("%s (%s): %s" % [r.name, names.get(r.id, "?"), verdict], 17))
	for h in result.hints:
		box.add_child(UiUtil.label("• " + h, 15, Color(0.85, 0.9, 1.0)))
	var cur := GameState.currency()
	if outcome.get("earned", 0) > 0:
		box.add_child(UiUtil.label("+%d %s" % [outcome.earned, cur], 26, Color(0.95, 0.85, 0.4)))
	var n: int = outcome.get("new_offers", []).size()
	if n > 0:
		box.add_child(UiUtil.label(("Am Waldrand wartet eine neue fremde Kreatur" if n == 1 else "Am Waldrand warten %d neue fremde Kreaturen" % n) + " – unter „Anheuern“.", 16, Color(0.95, 0.85, 0.4)))
	box.add_child(UiUtil.button("Weiter", func(): visible = false; closed.emit(), Vector2(200, 52)))
	visible = true
