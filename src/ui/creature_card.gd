class_name CreatureCard
extends PanelContainer
## Karte der ausgewählten Kreatur: Name, Markierung, eigene Gruppe,
## Einschätzung der Fähigkeiten, Notiz, letzte Beobachtungen.
## Die Art wird im Spiel nicht angezeigt (nur im Debug-Modus).
## Für Fremde (show_stranger): Preis, „Anheuern“ und bisherige Beobachtungen.

signal closed
signal hire_requested(offer: GroupMember)
## -1 = vorherige, +1 = nächste Kreatur zeigen
signal cycle_requested(direction: int)

const RATING_COLORS := {0: Color(1.0, 0.55, 0.45), 1: Color(1.0, 0.85, 0.4), 2: Color(0.55, 1.0, 0.45)}

var journal: Journal
var catalog: AbilityCatalog
var member: GroupMember
var debug_text := ""

var _box: VBoxContainer


func _init() -> void:
	custom_minimum_size = Vector2(380, 0)
	add_theme_stylebox_override("panel", UiUtil.panel_style())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)


func show_member(p_member: GroupMember, p_journal: Journal, p_catalog: AbilityCatalog, p_debug := "") -> void:
	member = p_member
	journal = p_journal
	catalog = p_catalog
	debug_text = p_debug
	visible = true
	refresh()


## Fremde Kreatur am Waldrand: title z. B. "Fremdling 2", problem = GameState.hire_problem().
func show_stranger(offer: GroupMember, title: String, p_journal: Journal, problem: String, p_debug := "") -> void:
	member = null
	journal = p_journal
	debug_text = p_debug
	visible = true
	UiUtil.clear(_box)
	var head := HBoxContainer.new()
	_box.add_child(head)
	var t := UiUtil.caption(title, 0, 24)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_nav_buttons(head)
	head.add_child(UiUtil.button("✕", func(): visible = false; closed.emit(), Vector2(48, 48)))
	_box.add_child(UiUtil.label("%s%s · gehört noch nicht zur Gruppe" % ["♂" if offer.sex == "male" else "♀", " · Jungtier" if offer.age == "juvenile" else ""], 15, Color(1, 1, 1, 0.7)))
	if debug_text != "":
		_box.add_child(UiUtil.label(debug_text, 14, Color(1, 0.8, 0.4)))
	_box.add_child(UiUtil.label("Preis: %d %s" % [offer.price, GameState.currency()], 20, Color(0.95, 0.85, 0.4)))
	var hire := UiUtil.button("Anheuern", func(): hire_requested.emit(offer), Vector2(0, 52))
	hire.disabled = problem != ""
	_box.add_child(hire)
	if problem != "":
		_box.add_child(UiUtil.label(problem, 14, Color(1, 0.7, 0.5)))
	_box.add_child(UiUtil.label("Zuletzt beobachtet", 17, Color(0.8, 0.95, 0.6)))
	var entries := journal.entries_for(offer.id, 5)
	if entries.is_empty():
		_box.add_child(UiUtil.label("noch nichts – eine Weile zuschauen", 14, Color(1, 1, 1, 0.6)))
	for e in entries:
		_box.add_child(UiUtil.label("%s  %s" % [e.time, e.text], 14))


## ‹ › zum Durchblättern aller Kreaturen.
func _nav_buttons(head: HBoxContainer) -> void:
	head.add_child(UiUtil.button("‹", func(): cycle_requested.emit(-1), Vector2(48, 48)))
	head.add_child(UiUtil.button("›", func(): cycle_requested.emit(1), Vector2(48, 48)))


func refresh() -> void:
	UiUtil.clear(_box)
	if member == null:
		return
	var head := HBoxContainer.new()
	_box.add_child(head)
	var title := UiUtil.caption(member.name, 0, 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_nav_buttons(head)
	head.add_child(UiUtil.button("✕", func(): visible = false; closed.emit(), Vector2(48, 48)))
	var info := "%s%s" % ["♂" if member.sex == "male" else "♀", " · Jungtier" if member.age == "juvenile" else ""]
	_box.add_child(UiUtil.label(info, 15, Color(1, 1, 1, 0.7)))
	if debug_text != "":
		_box.add_child(UiUtil.label(debug_text, 14, Color(1, 0.8, 0.4)))

	# Markierung
	var marks := HBoxContainer.new()
	_box.add_child(marks)
	marks.add_child(UiUtil.caption("Markierung", 85, 15))
	var current: int = journal.marks.get(member.id, -1)
	for i in Journal.MARK_COLORS.size():
		var b := UiUtil.button("●" if current == i else "○", _set_mark.bind(i), Vector2(32, 40))
		b.add_theme_color_override("font_color", Journal.MARK_COLORS[i])
		b.add_theme_color_override("font_hover_color", Journal.MARK_COLORS[i])
		marks.add_child(b)
	marks.add_child(UiUtil.button("–", _set_mark.bind(-1), Vector2(32, 40)))

	# Eigene Gruppe („gleiche Art?“)
	var grow := HBoxContainer.new()
	_box.add_child(grow)
	grow.add_child(UiUtil.caption("Gruppe", 85, 15))
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(200, 44)
	opt.add_item("– keine –", 0)
	for i in journal.groups.size():
		opt.add_item(journal.groups[i].name, i + 1)
	opt.add_item("+ neue Gruppe", journal.groups.size() + 1)
	opt.select(journal.group_of(member.id) + 1)
	opt.item_selected.connect(_on_group_selected)
	grow.add_child(opt)

	# Fähigkeiten einschätzen (nur die eigene Meinung – das Spiel verrät keine Werte)
	_box.add_child(UiUtil.label("Meine Einschätzung", 17, Color(0.8, 0.95, 0.6)))
	var grid := GridContainer.new()
	grid.columns = 5
	_box.add_child(grid)
	for id in catalog.order:
		grid.add_child(UiUtil.caption(catalog.name_of(id), 110, 15))
		var r := journal.rating(member.id, id)
		for v in [0, 1, 2]:
			var b := UiUtil.button(["–", "o", "+"][v], _set_rating.bind(id, v if r != v else -1), Vector2(44, 40))
			b.tooltip_text = Journal.RATING_LABELS[v]
			if r == v:
				var sb := StyleBoxFlat.new()
				sb.bg_color = RATING_COLORS[v].darkened(0.35)
				sb.set_corner_radius_all(6)
				for state in ["normal", "hover", "pressed", "focus"]:
					b.add_theme_stylebox_override(state, sb)
				b.add_theme_color_override("font_color", Color.WHITE)
				b.add_theme_color_override("font_hover_color", Color.WHITE)
			grid.add_child(b)
		grid.add_child(UiUtil.caption(Journal.RATING_LABELS[r] if r >= 0 else "", 70, 14,
				RATING_COLORS[r] if r >= 0 else Color(1, 1, 1, 0.5)))

	# Notiz
	_box.add_child(UiUtil.label("Notiz", 17, Color(0.8, 0.95, 0.6)))
	var note := TextEdit.new()
	note.custom_minimum_size = Vector2(0, 70)
	note.text = journal.notes.get(member.id, "")
	note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	note.focus_exited.connect(func(): journal.set_note(member.id, note.text))
	note.text_changed.connect(func(): journal.set_note(member.id, note.text))
	_box.add_child(note)

	# Beobachtungen
	_box.add_child(UiUtil.label("Zuletzt beobachtet", 17, Color(0.8, 0.95, 0.6)))
	var entries := journal.entries_for(member.id, 5)
	if entries.is_empty():
		_box.add_child(UiUtil.label("noch nichts – eine Weile zuschauen", 14, Color(1, 1, 1, 0.6)))
	for e in entries:
		_box.add_child(UiUtil.label("%s  %s" % [e.time, e.text], 14))


func _set_mark(i: int) -> void:
	journal.set_mark(member.id, i)
	refresh()


func _set_rating(ability: String, value: int) -> void:
	journal.set_rating(member.id, ability, value)
	refresh()


func _on_group_selected(index: int) -> void:
	if index == journal.groups.size() + 1:
		var gi := journal.add_group("Gruppe %d" % (journal.groups.size() + 1))
		journal.assign_group(member.id, gi)
	else:
		journal.assign_group(member.id, index - 1)
	refresh()
