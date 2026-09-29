class_name ResultPanel
extends Control
## Auswertung einer Aufgabe: Erfolg/Misserfolg, welche Rolle schwach besetzt
## war (ohne die Lösung zu verraten), verdientes Guthaben, neue Fremde.

signal closed


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


## outcome: GameState.record_task() → {"earned", "cost", "new_offers", "exhausted"}
## assignments/journal/abilities (optional): vergleicht das Ergebnis jeder Rolle mit
## der eigenen Einschätzung der wichtigsten Fähigkeit.
func show_result(task: TaskDef, result: Dictionary, names: Dictionary, outcome: Dictionary,
		assignments: Dictionary = {}, journal: Journal = null, abilities: AbilityCatalog = null) -> void:
	UiUtil.clear(self)
	var panel := UiUtil.overlay(self, Vector2(700, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UiUtil.label(task.name, 20, Color(1, 1, 1, 0.7)))
	box.add_child(UiUtil.label("Geschafft!" if result.success else "Nicht geschafft", 30,
			Color(0.6, 1.0, 0.5) if result.success else Color(1.0, 0.6, 0.45)))
	Sound.play("success" if result.success else "fail")
	Sound.vibrate(60 if result.success else 30)
	for r in task.roles:
		var e: Dictionary = result.roles.get(r.id, {})
		var verdict := "nicht dran gekommen" if e.get("skipped", false) else (
				("gut besetzt" if not e.get("close", false) else "knapp geschafft") if e.get("success", false)
				else ("knapp gescheitert" if e.get("close", false) else "schwach besetzt"))
		box.add_child(UiUtil.label("%s (%s): %s" % [r.name, names.get(r.id, "?"), verdict], 17))
	if journal != null and abilities != null:
		for line in rating_checks(task, result, assignments, journal, abilities):
			box.add_child(UiUtil.label(line[0], 15, line[1]))
	for h in result.hints:
		box.add_child(UiUtil.label("• " + h, 15, Color(0.85, 0.9, 1.0)))
	var cur := GameState.currency()
	var money := []
	if outcome.get("earned", 0) > 0:
		money.append("+%d %s" % [outcome.earned, cur])
	if outcome.get("cost", 0) > 0:
		money.append("Proviant −%d" % outcome.cost)
	if not money.is_empty():
		box.add_child(UiUtil.label("   ".join(money), 24, Color(0.95, 0.85, 0.4)))
	var tired: Array = outcome.get("exhausted", [])
	if not tired.is_empty():
		var tired_names := []
		for m in tired:
			tired_names.append(m.name)
		box.add_child(UiUtil.label("%s %s erschöpft und %s bis morgen früh." % [" und ".join(tired_names), "ist" if tired_names.size() == 1 else "sind", "ruht" if tired_names.size() == 1 else "ruhen"], 15, Color(0.75, 0.75, 0.85)))
	var n: int = outcome.get("new_offers", []).size()
	if n > 0:
		box.add_child(UiUtil.label(("Am Waldrand wartet eine neue fremde Kreatur" if n == 1 else "Am Waldrand warten %d neue fremde Kreaturen" % n) + " – unter „Anheuern“.", 16, Color(0.95, 0.85, 0.4)))
	box.add_child(UiUtil.button("Weiter", func(): visible = false; closed.emit(), Vector2(200, 52)))
	visible = true


## [[Text, Farbe]] – passt das Ergebnis zur eigenen Einschätzung?
static func rating_checks(task: TaskDef, result: Dictionary, assignments: Dictionary, journal: Journal,
		abilities: AbilityCatalog) -> Array:
	var out := []
	var hint_given := false
	for r in task.roles:
		var m: GroupMember = assignments.get(r.id)
		var e: Dictionary = result.roles.get(r.id, {})
		if m == null or e.get("skipped", false):
			continue
		var ab := TaskPanel.main_ability(r)
		var rating := journal.rating(m.id, ab)
		var label := "„%s: %s“" % [abilities.name_of(ab), Journal.RATING_LABELS.get(rating, "?")]
		var ok: bool = e.get("success", false)
		if (rating == 2 and not ok) or (rating == 0 and ok):
			out.append(["✗ %s: deine Einschätzung %s passt nicht zum Ergebnis." % [m.name, label], Color(1.0, 0.65, 0.45)])
		elif (rating == 2 and ok) or (rating == 0 and not ok):
			out.append(["✓ %s: passt zu deiner Einschätzung %s." % [m.name, label], Color(0.6, 1.0, 0.5)])
		elif rating < 0 and not hint_given:
			hint_given = true
			out.append(["Tipp: Halte auf der Karte von %s fest, wie gut %s kann – dann prüft die Auswertung deine Einschätzung." % [m.name, abilities.name_of(ab)], Color(1, 1, 1, 0.6)])
	return out
