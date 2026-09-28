class_name TaskPanel
extends Control
## Aufgabenwahl: Aufgabe aussuchen, pro Rolle ein Gruppenmitglied zuweisen, starten.

signal start_requested(task: TaskDef, assignments: Dictionary)
signal closed

var game: GameState
var catalog: TaskCatalog
var _selected: TaskDef
var _choice: Dictionary = {}  # role_id -> member_id


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func open(p_game: GameState, p_catalog: TaskCatalog) -> void:
	game = p_game
	catalog = p_catalog
	if _selected == null and not catalog.tasks.is_empty():
		_selected = catalog.tasks[0]
	_build()
	visible = true


func _build() -> void:
	UiUtil.clear(self)
	var panel := UiUtil.overlay(self, Vector2(980, 600))
	var root := HBoxContainer.new()
	panel.add_child(root)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	root.add_child(left)
	left.add_child(UiUtil.label("Aufgaben", 26))
	for t in catalog.tasks:
		var st: Dictionary = game.tasks.get(t.id, {})
		var mark := " ✓" if st.get("successes", 0) > 0 else ("  (%d×)" % st.attempts if st.get("attempts", 0) > 0 else "")
		var b := UiUtil.button(t.name + mark, func(): _selected = t; _choice.clear(); _build(), Vector2(280, 52))
		b.toggle_mode = true
		b.button_pressed = t == _selected
		left.add_child(b)
	left.add_child(Control.new())
	left.get_child(left.get_child_count() - 1).size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(UiUtil.button("Schließen", func(): visible = false; closed.emit(), Vector2(280, 48)))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	if _selected == null:
		return
	right.add_child(UiUtil.label(_selected.name, 24))
	right.add_child(UiUtil.label(_selected.description, 16))
	var ctx := []
	if _selected.context.has("hour"):
		ctx.append("%02d:00 Uhr" % int(_selected.context.hour))
	if _selected.context.has("weather"):
		ctx.append({"clear": "klar", "cloudy": "bewölkt", "rain": "Regen"}.get(_selected.context.weather, ""))
	right.add_child(UiUtil.label(" · ".join(ctx), 15, Color(1, 1, 1, 0.7)))
	right.add_child(UiUtil.label("Rollen", 20, Color(0.8, 0.95, 0.6)))
	for r in _selected.roles:
		var row := HBoxContainer.new()
		right.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiUtil.caption(r.name, 0, 18))
		info.add_child(UiUtil.label(r.description, 14, Color(1, 1, 1, 0.75)))
		row.add_child(info)
		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(220, 48)
		opt.add_item("– wählen –")
		for m in game.members:
			opt.add_item(m.name)
		var cur: String = _choice.get(r.id, "")
		for i in game.members.size():
			if game.members[i].id == cur:
				opt.select(i + 1)
		opt.item_selected.connect(func(i):
			if i == 0:
				_choice.erase(r.id)
			else:
				_choice[r.id] = game.members[i - 1].id
			_build())
		row.add_child(opt)
	var problem := _problem()
	var start := UiUtil.button("Aufgabe starten", _start, Vector2(260, 56))
	start.disabled = problem != ""
	right.add_child(Control.new())
	right.get_child(right.get_child_count() - 1).size_flags_vertical = Control.SIZE_EXPAND_FILL
	if problem != "":
		right.add_child(UiUtil.label(problem, 14, Color(1, 0.7, 0.5)))
	right.add_child(start)


func _problem() -> String:
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
