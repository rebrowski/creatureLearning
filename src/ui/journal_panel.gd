class_name JournalPanel
extends Control
## Beobachtungs-Journal (Vollbild): Kreaturen, eigene Gruppen, Protokoll.

signal member_chosen(member_id: String)
signal closed

var game: GameState
var _tabs: TabContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func open(p_game: GameState) -> void:
	game = p_game
	UiUtil.clear(self)
	var panel := UiUtil.overlay(self, Vector2(900, 600))
	var root := VBoxContainer.new()
	panel.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := UiUtil.caption("Journal", 0, 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiUtil.button("Schließen", _close, Vector2(140, 48)))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_tabs.add_child(_creatures_tab())
	_tabs.add_child(_groups_tab())
	_tabs.add_child(_log_tab())
	visible = true


func _close() -> void:
	visible = false
	closed.emit()


func _scroll(tab_name: String) -> Array:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return [scroll, box]


func _creatures_tab() -> Control:
	var sb := _scroll("Kreaturen")
	var j := game.journal
	for m in game.members:
		var row := HBoxContainer.new()
		sb[1].add_child(row)
		var mark := UiUtil.caption("●" if j.marks.has(m.id) else "·", 30, 22)
		if j.marks.has(m.id):
			mark.add_theme_color_override("font_color", Journal.MARK_COLORS[j.marks[m.id]])
		mark.custom_minimum_size = Vector2(30, 0)
		row.add_child(mark)
		var b := UiUtil.button(m.name, func(): visible = false; member_chosen.emit(m.id), Vector2(150, 44))
		row.add_child(b)
		var gi := j.group_of(m.id)
		var rated := []
		for a in j.ratings.get(m.id, {}):
			rated.append("%s %s" % [game_catalog_name(a), ["–", "o", "+"][j.ratings[m.id][a]]])
		var txt := "%s%s%s" % [("Gruppe: %s · " % j.groups[gi].name) if gi >= 0 else "",
				", ".join(rated), (" · Notiz" if j.notes.has(m.id) else "")]
		var l := UiUtil.label(txt, 14, Color(1, 1, 1, 0.75))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
	return sb[0]


func game_catalog_name(ability: String) -> String:
	return {"climb": "Klettern", "swim": "Schwimmen", "dig": "Graben", "carry": "Tragen", "noise": "Lärm",
			"night_vision": "Nachtsicht", "scent": "Wittern", "scare": "Verscheuchen"}.get(ability, ability)


func _groups_tab() -> Control:
	var sb := _scroll("Gruppen")
	var j := game.journal
	sb[1].add_child(UiUtil.label("Eigene Gruppen – z. B. Kreaturen, die du für dieselbe Art hältst. Das Spiel sagt dir nicht, ob sie stimmen.", 14, Color(1, 1, 1, 0.7)))
	for i in j.groups.size():
		var row := HBoxContainer.new()
		sb[1].add_child(row)
		var edit := LineEdit.new()
		edit.text = j.groups[i].name
		edit.custom_minimum_size = Vector2(200, 44)
		edit.text_submitted.connect(func(t): j.rename_group(i, t))
		edit.focus_exited.connect(func(): j.rename_group(i, edit.text))
		row.add_child(edit)
		var names := []
		for id in j.groups[i].members:
			var m := game.member(id)
			if m != null:
				names.append(m.name)
		var l := UiUtil.label(", ".join(names) if not names.is_empty() else "(leer)", 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UiUtil.button("Löschen", func(): j.remove_group(i); open(game), Vector2(110, 44)))
	sb[1].add_child(UiUtil.button("+ Neue Gruppe", func(): j.add_group("Gruppe %d" % (j.groups.size() + 1)); open(game); _tabs.current_tab = 1, Vector2(200, 48)))
	return sb[0]


func _log_tab() -> Control:
	var sb := _scroll("Protokoll")
	var entries := game.journal.entries
	if entries.is_empty():
		sb[1].add_child(UiUtil.label("Noch keine Beobachtungen. Schau den Kreaturen eine Weile zu.", 15))
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		var m := game.member(e.member)
		sb[1].add_child(UiUtil.label("%s  %s: %s" % [e.time, m.name if m else e.member, e.text], 15))
	return sb[0]
