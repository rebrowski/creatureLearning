class_name GenomeComparePanel
extends PanelContainer
## Zeigt zwei Kreaturen nebeneinander mit Gesamtdistanz, Distanz pro
## Merkmalsgruppe und einer Gen-Tabelle.
##
## Hält nur Schlüssel (Art, Nummer, Geschlecht, Alter) und baut die Genome bei
## refresh() neu – so wirken geänderte Regler sofort.

const GROUP_LABELS := {
	"bodyplan": "Bauplan", "movement": "Bewegung", "proportion": "Proportionen",
	"appendage": "Anhänge", "color": "Farbe", "pattern": "Muster", "misc": "Sonstiges",
}

var factory: IndividualFactory

## Je Slot: {"species_id", "index", "sex", "age"} oder leer.
var _slots: Array[Dictionary] = [{}, {}]
var _next_slot := 0

var _glyphs: Array[CreatureGlyph] = []
var _names: Array[Label] = []
var _distance_label: Label
var _relation_label: Label
var _groups_box: VBoxContainer
var _table: GridContainer
var _table_scroll: ScrollContainer


func _init() -> void:
	var root := VBoxContainer.new()
	add_child(root)
	var hint := Label.new()
	hint.text = "Vergleich – tippe Kreaturen an (abwechselnd A / B)"
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	root.add_child(hint)

	var top := HBoxContainer.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(top)
	for slot in 2:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var glyph := CreatureGlyph.new()
		glyph.custom_minimum_size = Vector2(200, 140)
		glyph.size_flags_vertical = Control.SIZE_EXPAND_FILL
		glyph.pressed.connect(func(): _next_slot = slot)
		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(glyph)
		col.add_child(name_label)
		_glyphs.append(glyph)
		_names.append(name_label)
		if slot == 0:
			top.add_child(col)
			top.add_child(_build_center())
		else:
			top.add_child(col)

	_table_scroll = ScrollContainer.new()
	_table_scroll.custom_minimum_size = Vector2(0, 160)
	_table_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_table_scroll)
	_table = GridContainer.new()
	_table.columns = 4
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_scroll.add_child(_table)


func _build_center() -> Control:
	var center := VBoxContainer.new()
	center.custom_minimum_size = Vector2(230, 0)
	_distance_label = Label.new()
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_distance_label.add_theme_font_size_override("font_size", 30)
	_relation_label = Label.new()
	_relation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_relation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_groups_box = VBoxContainer.new()
	center.add_child(_distance_label)
	center.add_child(_relation_label)
	center.add_child(_groups_box)
	return center


func set_factory(p_factory: IndividualFactory) -> void:
	factory = p_factory
	_slots = [{}, {}]
	_next_slot = 0
	refresh()


## Legt eine Kreatur in den nächsten Slot (A, B, A, ...).
func assign_next(ind: Individual) -> void:
	set_slot(_next_slot, ind)
	_next_slot = 1 - _next_slot


func set_slot(slot: int, ind: Individual) -> void:
	_slots[slot] = {"species_id": ind.species_id, "index": ind.index, "sex": ind.sex, "age": ind.age}
	refresh()


func set_pair(a: Individual, b: Individual) -> void:
	_slots[0] = {}
	_slots[1] = {}
	set_slot(0, a)
	set_slot(1, b)
	_next_slot = 0


func refresh() -> void:
	var inds: Array[Individual] = [null, null]
	for slot in 2:
		var key := _slots[slot]
		if factory != null and not key.is_empty() and factory.taxonomy.has_taxon(key.species_id):
			inds[slot] = factory.create_individual(key.species_id, key.index, key.sex, key.age)
		_glyphs[slot].genome = inds[slot].genome if inds[slot] else null
		_names[slot].text = _describe(inds[slot], "AB"[slot])
	for child in _groups_box.get_children():
		child.queue_free()
	for child in _table.get_children():
		child.queue_free()
	if inds[0] == null or inds[1] == null:
		_distance_label.text = "–"
		_relation_label.text = ""
		return

	var a := inds[0].genome
	var b := inds[1].genome
	var br := GenomeDistance.breakdown(a, b)
	_distance_label.text = "d = %.3f" % br.total
	_relation_label.text = _relation_text(inds[0].species_id, inds[1].species_id)
	for group in a.schema.groups:
		if br.has(group):
			_groups_box.add_child(_bar_row(GROUP_LABELS.get(group, group), br[group]))

	for header in ["Gen", "A", "B", "Δ"]:
		var h := Label.new()
		h.text = header
		h.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		_table.add_child(h)
	for row in GenomeDistance.gene_diffs(a, b):
		var gene := a.schema.get_gene(row.id)
		var cells := [row.id, gene.format_value(row.a), gene.format_value(row.b), "%.2f" % row.diff]
		for n in cells.size():
			var l := Label.new()
			l.text = cells[n]
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if n == 3:
				l.add_theme_color_override("font_color", Color(1, 1, 1).lerp(Color(1, 0.35, 0.3), row.diff))
			if not gene.visible:
				l.modulate = Color(1, 1, 1, 0.5)
			_table.add_child(l)


func _describe(ind: Individual, slot_name: String) -> String:
	if ind == null:
		return "%s: –" % slot_name
	var sp := factory.taxonomy.get_taxon(ind.species_id)
	return "%s: %s %s" % [slot_name, sp.display_name(), ind.short_label()]


func _relation_text(a_id: String, b_id: String) -> String:
	if a_id == b_id:
		return "gleiche Art"
	var rank := factory.taxonomy.shared_rank(a_id, b_id)
	if rank < 0:
		return "verschiedene Klassen"
	return "gleiche %s, verschiedene %s" % [Ranks.label_of(rank), Ranks.label_of(rank + 1)]


func _bar_row(label_text: String, value: float) -> Control:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(110, 0)
	var bar := _Bar.new()
	bar.value = value
	bar.custom_minimum_size = Vector2(80, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := Label.new()
	v.text = "%.2f" % value
	row.add_child(l)
	row.add_child(bar)
	row.add_child(v)
	return row


## Schlichter Balken 0..1 mit Hintergrund.
class _Bar extends Control:
	var value := 0.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(value, 0.0, 1.0), size.y)), Color(1, 1, 1).lerp(Color(1, 0.4, 0.3), value))
