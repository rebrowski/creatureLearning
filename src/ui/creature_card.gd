class_name CreatureCard
extends PanelContainer
## Leiste am unteren Bildschirmrand zur ausgewählten Kreatur – verdeckt die
## Kreatur nicht (die Kamera rückt sie ins obere Bilddrittel, siehe
## OrbitCamera.view_shift). Eingeklappt: Name, ‹ ›, vermutete Art, Kurzfassung
## der Einschätzung. Ausgeklappt (▲): Einschätzung aller Fähigkeiten in zwei
## Spalten und die letzten Beobachtungen.
##
## Drei Arten von Inhalt:
##   show_member()   Gruppenmitglied (Einschätzung, vermutete Art)
##   show_stranger() Fremder (Preis, Anheuern)
##   show_rival()    Kreatur einer Rivalen-Gruppe (nur ansehen)
## Rollen wählt man in der Galerie (GalleryBar), nicht hier.
## Die Art wird im Spiel nicht angezeigt (nur im Debug-Modus).

signal closed
signal hire_requested(offer: GroupMember)
## -1 = vorherige, +1 = nächste Kreatur zeigen
signal cycle_requested(direction: int)
## Höhe geändert (eingeklappt/ausgeklappt) – die Welt passt die Kamera an.
signal layout_changed(expanded: bool)

const RATING_COLORS := {0: Color(1.0, 0.55, 0.45), 1: Color(1.0, 0.85, 0.4), 2: Color(0.55, 1.0, 0.45)}
## Höhe als Anteil der Bildschirmhöhe
const COMPACT := 0.3
const EXPANDED := 0.52

var journal: Journal
var catalog: AbilityCatalog
var member: GroupMember
var debug_text := ""
var expanded := false
## "member" | "stranger" | "rival"
var mode := "member"

## Fähigkeit der gerade gezeigten Probe: eingeklappt erscheinen Ergebnis und
## Einschätzungs-Knöpfe direkt (ohne Aufklappen).
var quick_ability := ""

var _box: VBoxContainer
var _stranger: GroupMember
var _problem := ""


func _init() -> void:
	add_theme_stylebox_override("panel", UiUtil.panel_style())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)


func _ready() -> void:
	_apply_height()
	get_viewport().size_changed.connect(_apply_height)


## Am unteren Rand andocken; Höhe je nach Zustand.
func _apply_height() -> void:
	if not is_inside_tree():
		return
	var h := get_viewport_rect().size.y * height_fraction()
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 10
	offset_right = -10
	offset_bottom = -10
	offset_top = -h


## Anteil der Bildschirmhöhe, den die Leiste gerade einnimmt.
func height_fraction() -> float:
	return EXPANDED if expanded else COMPACT


func set_expanded(on: bool) -> void:
	expanded = on
	_rebuild()


func show_member(p_member: GroupMember, p_journal: Journal, p_catalog: AbilityCatalog, p_debug := "") -> void:
	if p_member != member:
		quick_ability = ""
	mode = "member"
	member = p_member
	journal = p_journal
	catalog = p_catalog
	debug_text = p_debug
	visible = true
	refresh()


## Fremde Kreatur am Waldrand; problem = GameState.hire_problem().
func show_stranger(offer: GroupMember, _title: String, p_journal: Journal, problem: String, p_debug := "") -> void:
	mode = "stranger"
	member = null
	_stranger = offer
	_problem = problem
	journal = p_journal
	debug_text = p_debug
	visible = true
	refresh()


## Kreatur einer Rivalen-Gruppe (nur ansehen).
func show_rival(m: GroupMember, group_name: String, p_journal: Journal, p_debug := "") -> void:
	mode = "rival"
	member = null
	_stranger = m
	_problem = group_name
	journal = p_journal
	debug_text = p_debug
	visible = true
	refresh()


## Nach einer Probe: Ergebnis und Einschätzung dieser Fähigkeit eingeklappt zeigen.
func show_quick(ability: String) -> void:
	quick_ability = ability
	expanded = false
	refresh()


func refresh() -> void:
	_rebuild()


func _rebuild() -> void:
	UiUtil.clear(_box)
	_apply_height()
	layout_changed.emit(expanded)
	match mode:
		"stranger":
			_build_stranger()
		"rival":
			_head(_stranger.name, _info(_stranger) + " · gehört zu den " + _problem)
			if debug_text != "":
				_box.add_child(UiUtil.label(debug_text, 13, Color(1, 0.8, 0.4)))
			_box.add_child(UiUtil.label("Rivalen sammeln um dieselben Vorräte. Schau zu, was sie können – vielleicht verrät es etwas über deine eigenen Tiere.", 14, Color(1, 1, 1, 0.7)))
			if expanded:
				_observations(_box, _stranger.id)
		_:
			if member != null:
				_build_member()


# --- Kopfzeile ------------------------------------------------------------------

func _head(title: String, subtitle: String, close_text := "✕") -> HBoxContainer:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	_box.add_child(head)
	var t := UiUtil.caption(title, 0, 22)
	head.add_child(t)
	var sub := UiUtil.caption(subtitle, 0, 15, Color(1, 1, 1, 0.7))
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sub)
	head.add_child(UiUtil.button("‹", func(): cycle_requested.emit(-1), Vector2(52, 44)))
	head.add_child(UiUtil.button("›", func(): cycle_requested.emit(1), Vector2(52, 44)))
	head.add_child(UiUtil.button("▼" if expanded else "▲", func(): set_expanded(not expanded), Vector2(52, 44)))
	head.add_child(UiUtil.button(close_text, func(): visible = false; closed.emit(), Vector2(52 if close_text == "✕" else 130, 44)))
	return head


static func _info(m: GroupMember) -> String:
	return "%s%s%s" % ["♂" if m.sex == "male" else "♀", " · Jungtier" if m.age == "juvenile" else "",
			" · erschöpft" if m.exhausted else ""]


# --- Gruppenmitglied ------------------------------------------------------------

func _build_member() -> void:
	_head(member.name, _info(member))
	if debug_text != "":
		_box.add_child(UiUtil.label(debug_text, 13, Color(1, 0.8, 0.4)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	row.add_child(UiUtil.caption("Vermutete Art", 0, 15))
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(180, 44)
	opt.add_item("– unbekannt –", 0)
	for i in journal.groups.size():
		opt.add_item(journal.groups[i].name, i + 1)
	opt.add_item("+ neue Art", journal.groups.size() + 1)
	opt.select(journal.group_of(member.id) + 1)
	opt.item_selected.connect(_on_group_selected)
	row.add_child(opt)
	if not expanded:
		var summary := UiUtil.label(_rating_summary(), 15, Color(0.8, 0.95, 0.6))
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(summary)
		var probes := _probe_summary()
		if quick_ability != "":
			var quick := GridContainer.new()
			quick.columns = 6
			_box.add_child(quick)
			_rating_row(quick, quick_ability)
			quick.add_child(UiUtil.caption("← deine Einschätzung", 0, 13, Color(1, 1, 1, 0.6)))
		elif probes != "":
			_box.add_child(UiUtil.label(probes, 14, Color(0.75, 0.9, 1.0)))
		return
	# ausgeklappt: Einschätzung in zwei Spalten, daneben Beobachtungen
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	_box.add_child(body)
	var grid := GridContainer.new()
	grid.columns = 10
	body.add_child(grid)
	for id in catalog.order:
		_rating_row(grid, id)
	var obs := VBoxContainer.new()
	obs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(obs)
	_observations(obs, member.id)


func _rating_summary() -> String:
	var parts := []
	for id in catalog.order:
		var r := journal.rating(member.id, id)
		if r >= 0:
			parts.append("%s %s" % [catalog.name_of(id), ["–", "o", "+"][r]])
	return "Einschätzung: " + (", ".join(parts) if not parts.is_empty() else "noch keine – ▲ öffnen")


## "Proben: Klettern ●●○ · Graben ○○○" oder "".
func _probe_summary() -> String:
	var parts := []
	for id in catalog.order:
		var g := journal.probe(member.id, id)
		if g >= 0:
			parts.append("%s %s" % [catalog.name_of(id), Journal.grade_dots(g)])
	return "Proben: " + " · ".join(parts) if not parts.is_empty() else ""


func _rating_row(grid: GridContainer, id: String) -> void:
	var g := journal.probe(member.id, id)
	grid.add_child(UiUtil.caption(catalog.name_of(id) + ("  " + Journal.grade_dots(g) if g >= 0 else ""), 140, 14))
	var r := journal.rating(member.id, id)
	for v in [0, 1, 2]:
		var b := UiUtil.button(["–", "o", "+"][v], _set_rating.bind(id, v if r != v else -1), Vector2(40, 38))
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
	grid.add_child(UiUtil.caption(Journal.RATING_LABELS[r] if r >= 0 else "", 60, 13,
			RATING_COLORS[r] if r >= 0 else Color(1, 1, 1, 0.5)))


func _observations(parent: Control, id: String) -> void:
	parent.add_child(UiUtil.label("Zuletzt beobachtet", 15, Color(0.8, 0.95, 0.6)))
	var entries := journal.entries_for(id, 4)
	if entries.is_empty():
		parent.add_child(UiUtil.label("noch nichts – eine Weile zuschauen oder eine Probe machen", 13, Color(1, 1, 1, 0.6)))
	for e in entries:
		parent.add_child(UiUtil.label("%s  %s" % [e.time, e.text], 13))


# --- Fremder ----------------------------------------------------------------------

func _build_stranger() -> void:
	var o := _stranger
	_head(o.name, _info(o) + " · gehört noch nicht zur Gruppe")
	if debug_text != "":
		_box.add_child(UiUtil.label(debug_text, 13, Color(1, 0.8, 0.4)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_box.add_child(row)
	row.add_child(UiUtil.caption("Preis: %d %s" % [o.price, GameState.currency()], 0, 19, Color(0.95, 0.85, 0.4)))
	var hire := UiUtil.button("Anheuern", func(): hire_requested.emit(o), Vector2(160, 48))
	hire.disabled = _problem != ""
	row.add_child(hire)
	if _problem != "":
		row.add_child(UiUtil.caption(_problem, 0, 13, Color(1, 0.7, 0.5)))
	if expanded:
		_observations(_box, o.id)


func _set_rating(ability: String, value: int) -> void:
	journal.set_rating(member.id, ability, value)
	refresh()


func _on_group_selected(index: int) -> void:
	if index == journal.groups.size() + 1:
		var gi := journal.add_group("Art %s" % char(65 + journal.groups.size() % 26))
		journal.assign_group(member.id, gi)
	else:
		journal.assign_group(member.id, index - 1)
	refresh()
