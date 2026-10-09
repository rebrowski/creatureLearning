class_name TaskPanel
extends Control
## Aufgabenwahl: eines der Angebote der Runde aussuchen, Rollen besetzen, starten.
##
## Tippt man auf einen Rollenplatz, schließt sich das Panel (pick_requested) und
## die Welt öffnet die Galerie; nach der Wahl öffnet sie das Panel wieder
## (assign). Neben dem Namen steht die eigene Einschätzung der wichtigsten
## Fähigkeit der Rolle. Gesperrte Aufgaben zeigen, was sie freischaltet.

signal start_requested(task: TaskDef, assignments: Dictionary)
signal pick_requested(task: TaskDef, role_id: String)
signal closed

var game: GameState
var catalog: TaskCatalog
var abilities: AbilityCatalog
var _selected: TaskDef
var _choice: Dictionary = {}  # role_id -> member_id
## Nur diese Aufgaben (IDs) anbieten; leer = alle.
var _only: Array = []


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


## task: diese Aufgabe vorauswählen (null = zuletzt gewählte bzw. erste offene).
## only: Angebote der Runde (IDs); leer = alle Aufgaben.
func open(p_game: GameState, p_catalog: TaskCatalog, task: TaskDef = null, p_abilities: AbilityCatalog = null,
		only: Array = []) -> void:
	game = p_game
	catalog = p_catalog
	if p_abilities != null:
		abilities = p_abilities
	if not only.is_empty():
		_only = only
	if task != null and task != _selected:
		_selected = task
		_choice.clear()
	if _selected != null and not _listed(_selected):
		_selected = null
		_choice.clear()
	if _selected == null:
		for t in catalog.tasks:
			if game.task_unlocked(t) and _listed(t):
				_selected = t
				break
	# Besetzungen verwerfen, die nicht mehr gültig sind (erschöpft, nicht mehr da)
	for role_id in _choice.keys():
		var m := game.member(_choice[role_id])
		if m == null or m.exhausted:
			_choice.erase(role_id)
	_build()
	visible = true


## Rolle besetzen (von der Welt nach dem Antippen aufgerufen).
func assign(role_id: String, member: GroupMember, task: TaskDef = null) -> void:
	if task != null and task != _selected:
		_selected = task
		_choice.clear()
	for r in _choice.keys():
		if _choice[r] == member.id:
			_choice.erase(r)  # wer eine andere Rolle hatte, wechselt
	_choice[role_id] = member.id


func selected_task() -> TaskDef:
	return _selected


func _listed(t: TaskDef) -> bool:
	return _only.is_empty() or _only.has(t.id)


func _build() -> void:
	UiUtil.clear(self)
	var panel := UiUtil.overlay(self, Vector2(980, 600))
	var root := HBoxContainer.new()
	panel.add_child(root)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	root.add_child(left)
	left.add_child(UiUtil.label("Angebote" if not _only.is_empty() else "Aufgaben", 26))
	for t in catalog.tasks:
		if not _listed(t):
			continue
		var st: Dictionary = game.tasks.get(t.id, {})
		var open_ := game.task_unlocked(t)
		var mark := " ✓" if st.get("successes", 0) > 0 else ("  (%d×)" % st.attempts if st.get("attempts", 0) > 0 else "")
		var b := UiUtil.button(t.name + mark if open_ else "– " + t.name, func(): _selected = t; _choice.clear(); _build(), Vector2(240, 52))
		b.toggle_mode = true
		b.button_pressed = t == _selected
		if not open_:
			b.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		left.add_child(b)
	left.add_child(Control.new())
	left.get_child(left.get_child_count() - 1).size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not _only.is_empty():
		left.add_child(UiUtil.label("Eine Aufgabe pro Runde.", 14, Color(1, 1, 1, 0.6)))
	left.add_child(UiUtil.button("Schließen", func(): visible = false; closed.emit(), Vector2(240, 48)))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	if _selected == null:
		return
	right.add_child(UiUtil.label(_selected.name, 24))
	right.add_child(UiUtil.label(_selected.description, 16))
	if not game.task_unlocked(_selected):
		var before := catalog.get_task(_selected.unlock_after)
		right.add_child(UiUtil.label("Wird frei, sobald „%s“ gelungen ist." % (before.name if before else _selected.unlock_after), 17, Color(1, 0.75, 0.5)))
		return
	var ctx := []
	if _selected.context.has("hour"):
		ctx.append("%02d:00 Uhr" % int(_selected.context.hour))
	if _selected.context.has("weather"):
		ctx.append({"clear": "klar", "cloudy": "bewölkt", "rain": "Regen"}.get(_selected.context.weather, ""))
	right.add_child(UiUtil.label(" · ".join(ctx), 15, Color(1, 1, 1, 0.7)))
	right.add_child(UiUtil.label(_economy_text(), 17, Color(0.95, 0.85, 0.4)))
	var site := game.site_text(_selected)
	if site != "":
		right.add_child(UiUtil.label(site, 16, Color(0.75, 0.9, 1.0) if game.site_stock(_selected) > 0 else Color(1, 0.7, 0.5)))
	right.add_child(UiUtil.label("Rollen – tippe auf einen Platz und wähle unten eine Kreatur", 18, Color(0.8, 0.95, 0.6)))
	for r in _selected.roles:
		right.add_child(_role_row(r))
	var problem := _problem()
	var start := UiUtil.button("Aufgabe starten", _start, Vector2(260, 56))
	start.disabled = problem != ""
	right.add_child(Control.new())
	right.get_child(right.get_child_count() - 1).size_flags_vertical = Control.SIZE_EXPAND_FILL
	if problem != "":
		right.add_child(UiUtil.label(problem, 14, Color(1, 0.7, 0.5)))
	right.add_child(start)


func _economy_text() -> String:
	var cur := GameState.currency()
	var reward := game.reward_for(_selected)
	var st: Dictionary = game.tasks.get(_selected.id, {})
	var note := ""
	if st.get("successes", 0) > 0:
		note = " (schon gelöst)"
	elif st.get("attempts", 0) == 0:
		note = " – doppelt, wenn es beim ersten Versuch klappt"
	var cost := game.attempt_cost()
	return "Belohnung: %d %s%s · Einsatz: %d %s" % [reward, cur, note, cost, cur]


func _role_row(r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UiUtil.caption(r.name, 0, 18))
	info.add_child(UiUtil.label(r.description, 14, Color(1, 1, 1, 0.75)))
	row.add_child(info)
	var m := game.member(_choice.get(r.id, ""))
	var text := "antippen …"
	if m != null:
		text = m.name
		var ability := main_ability(r)
		var rating := game.journal.rating(m.id, ability)
		if rating >= 0 and abilities != null:
			text += "\n%s: %s" % [abilities.name_of(ability), Journal.RATING_LABELS[rating]]
	var b := UiUtil.button(text, func(): visible = false; pick_requested.emit(_selected, r.id), Vector2(210, 56))
	if m == null:
		b.add_theme_color_override("font_color", Color(1, 0.92, 0.45))
	row.add_child(b)
	return row


## Fähigkeit mit dem größten Gewicht einer Rolle.
static func main_ability(r: Dictionary) -> String:
	var best := ""
	var w := -1.0
	for req in r.requirements:
		if req.weight > w:
			w = req.weight
			best = req.ability
	return best


func _problem() -> String:
	if game.site_stock(_selected) == 0:
		return "Hier gibt es gerade nichts zu holen – nächste Runde wieder."
	var used := {}
	for r in _selected.roles:
		if not _choice.has(r.id):
			return "Jede Rolle braucht ein Gruppenmitglied."
		if used.has(_choice[r.id]):
			return "Ein Gruppenmitglied kann nur eine Rolle übernehmen."
		used[_choice[r.id]] = true
	return ""


func _start() -> void:
	var assignments := {}
	for r in _selected.roles:
		assignments[r.id] = game.member(_choice[r.id])
	visible = false
	start_requested.emit(_selected, assignments)
