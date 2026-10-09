class_name GalleryBar
extends PanelContainer
## Galerie am unteren Rand: Karten aller Kreaturen zum Auswählen (für Proben und
## Rollen). Jede Karte zeigt nur, was der Spieler selbst weiß: Bild (Glyphe),
## Name, eigene Einschätzung und das letzte Probenergebnis der gefragten
## Fähigkeit (●●○) bzw. eine Übersicht aller Proben – nie die wahren Werte.

signal chosen(member: GroupMember)
signal cancelled

const HEIGHT := 0.5
const CARD := Vector2(176, 210)
const SHORT := {"climb": "Kl", "swim": "Sc", "dig": "Gr", "carry": "Tr", "noise": "Lä",
		"night_vision": "Na", "scent": "Wi", "scare": "Ve"}

var journal: Journal
var abilities: AbilityCatalog
var focus_ability := ""
var filter := "group"

var _group: Array = []
var _strangers: Array = []
var _title := ""
var _allow_strangers := false
var _box: VBoxContainer
var _cards: HBoxContainer


func _init() -> void:
	add_theme_stylebox_override("panel", UiUtil.panel_style())
	visible = false
	_box = VBoxContainer.new()
	add_child(_box)


func _ready() -> void:
	_place()
	get_viewport().size_changed.connect(_place)


func _place() -> void:
	if not is_inside_tree():
		return
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 10
	offset_right = -10
	offset_bottom = -10
	offset_top = -get_viewport_rect().size.y * HEIGHT


## title: z. B. „Wähle: Kletterer“; group/strangers: GroupMember-Listen;
## ability: Fähigkeit, deren Einschätzung und Probe auf den Karten steht.
func open(title: String, group: Array, strangers: Array, p_journal: Journal, p_abilities: AbilityCatalog,
		ability := "", allow_strangers := false) -> void:
	_title = title
	_group = group
	_strangers = strangers
	journal = p_journal
	abilities = p_abilities
	focus_ability = ability
	_allow_strangers = allow_strangers
	filter = "group"
	_build()
	visible = true


func _build() -> void:
	UiUtil.clear(_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_box.add_child(head)
	var t := UiUtil.caption(_title, 0, 20)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if _allow_strangers:
		for f in [["group", "Gruppe"], ["strangers", "Fremde"]]:
			var b := UiUtil.button(f[1], func(): filter = f[0]; _build(), Vector2(110, 44))
			b.toggle_mode = true
			b.button_pressed = filter == f[0]
			head.add_child(b)
	head.add_child(UiUtil.button("Abbrechen", func(): visible = false; cancelled.emit(), Vector2(130, 44)))
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(scroll)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 10)
	scroll.add_child(_cards)
	var list: Array = _strangers if filter == "strangers" else _group
	if list.is_empty():
		_cards.add_child(UiUtil.label("Hier ist gerade niemand.", 16, Color(1, 1, 1, 0.7)))
	for m in list:
		_cards.add_child(_card(m, filter == "strangers"))


func _card(m: GroupMember, stranger: bool) -> Control:
	var b := Button.new()
	b.custom_minimum_size = CARD
	b.pressed.connect(func():
		Sound.play("click")
		visible = false
		chosen.emit(m))
	b.disabled = m.exhausted
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -6
	v.offset_top = 4
	v.offset_bottom = -4
	b.add_child(v)
	var glyph := CreatureGlyph.new()
	glyph.genome = m.genome
	glyph.custom_minimum_size = Vector2(0, 92)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(glyph)
	var name_l := UiUtil.caption(m.name, 0, 17)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	for line in card_lines(m, stranger):
		var l := UiUtil.caption(line[0], 0, 13, line[1])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	return b


## Textzeilen einer Karte: [[Text, Farbe]] (auch für Tests).
func card_lines(m: GroupMember, stranger := false) -> Array:
	var out := []
	if focus_ability != "":
		var r := journal.rating(m.id, focus_ability)
		out.append(["%s: %s" % [abilities.name_of(focus_ability), Journal.RATING_LABELS[r] if r >= 0 else "?"],
				CreatureCard.RATING_COLORS.get(r, Color(1, 1, 1, 0.6))])
		var g := journal.probe(m.id, focus_ability)
		out.append(["Probe: %s" % Journal.grade_dots(g) if g >= 0 else "noch nicht geprüft", Color(0.75, 0.9, 1.0)])
	else:
		var parts := []
		for a in abilities.order:
			var g := journal.probe(m.id, a)
			if g >= 0:
				parts.append("%s %s" % [SHORT.get(a, a), Journal.grade_dots(g)])
		out.append([" ".join(parts.slice(0, 2)) if not parts.is_empty() else "noch keine Proben", Color(0.75, 0.9, 1.0)])
	if stranger:
		out.append(["%d %s" % [m.price, GameState.currency()], Color(0.95, 0.85, 0.4)])
	elif m.exhausted:
		out.append(["erschöpft", Color(0.75, 0.75, 0.85)])
	return out
