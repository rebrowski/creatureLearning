extends Control
## Debug-Viewer: Taxonomie als Baum, Kreaturen des gewählten Taxons als Glyphen,
## Regler für die Ähnlichkeit und ein Vergleichs-Panel.
##
## Quelle ist entweder die handgeschriebene Demo-Taxonomie (JSON) oder eine
## zufällig generierte. Der Seed gilt für beide: bei der Demo ändert er die
## Zufallsabweichungen, beim Generator zusätzlich die Struktur.

const DEMO_PATH := "res://data/taxonomies/forest_demo.json"
const MAX_CARDS := 40
const SLIDERS := [
	# [Beschriftung, Rang oder Schlüssel, max]
	["Klassen", Ranks.CLASS, 3.0],
	["Ordnungen", Ranks.ORDER, 3.0],
	["Familien", Ranks.FAMILY, 3.0],
	["Gattungen", Ranks.GENUS, 3.0],
	["Arten", Ranks.SPECIES, 4.0],
	["Individuen", Ranks.INDIVIDUAL, 5.0],
	["Dimorphismus", "dimorphism_strength", 2.0],
	["Konvergenz", "convergence_strength", 1.0],
]

var schema: GenomeSchema
var preset: Dictionary
var taxonomy: Taxonomy
var factory: IndividualFactory
var selected_id := ""

var _source: OptionButton
var _seed: SpinBox
var _per_species: SpinBox
var _juveniles: CheckBox
var _sliders: Array[HSlider] = []
var _slider_values: Array[Label] = []
var _tree: Tree
var _info: RichTextLabel
var _cards: VBoxContainer
var _compare: GenomeComparePanel
var _status: Label
var _selected_glyph: CreatureGlyph


func _ready() -> void:
	theme = Theme.new()
	theme.default_font_size = 17
	_build_ui()
	schema = GenomeSchema.load_file()
	if not schema.is_valid():
		_show_status("Schema-Fehler:\n" + "\n".join(schema.errors), true)
		return
	preset = TaxonomyGenerator.load_preset()
	_on_source_changed(0)


# --- Aufbau -------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.13, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var split := HSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.split_offset = 380
	add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(340, 0)
	split.add_child(left)

	var row := HBoxContainer.new()
	left.add_child(row)
	_source = OptionButton.new()
	_source.add_item("Demo (JSON)")
	_source.add_item("Generiert")
	_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source.item_selected.connect(_on_source_changed)
	row.add_child(_source)
	var export_btn := Button.new()
	export_btn.text = "Export"
	export_btn.tooltip_text = "Aktuelle Taxonomie als JSON nach user:// schreiben"
	export_btn.pressed.connect(_on_export)
	row.add_child(export_btn)

	row = HBoxContainer.new()
	left.add_child(row)
	row.add_child(_label("Seed"))
	_seed = SpinBox.new()
	_seed.min_value = 0
	_seed.max_value = 2147483647
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.value_changed.connect(func(_v): _rebuild())
	row.add_child(_seed)
	var dice := Button.new()
	dice.text = "Würfeln"
	dice.pressed.connect(func(): _seed.value = randi() % 1000000)
	row.add_child(dice)

	var grid := GridContainer.new()
	grid.columns = 3
	left.add_child(grid)
	for spec in SLIDERS:
		grid.add_child(_label(spec[0]))
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = spec[2]
		s.step = 0.05
		s.custom_minimum_size = Vector2(150, 28)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value_label := _label("")
		s.value_changed.connect(func(v):
			value_label.text = "%.2f" % v
			_on_slider_changed())
		grid.add_child(s)
		grid.add_child(value_label)
		_sliders.append(s)
		_slider_values.append(value_label)

	row = HBoxContainer.new()
	left.add_child(row)
	row.add_child(_label("Pro Art"))
	_per_species = SpinBox.new()
	_per_species.min_value = 1
	_per_species.max_value = 16
	_per_species.value = 6
	_per_species.value_changed.connect(func(_v): _refresh_cards())
	row.add_child(_per_species)
	_juveniles = CheckBox.new()
	_juveniles.text = "Jungtiere"
	_juveniles.button_pressed = true
	_juveniles.toggled.connect(func(_on): _refresh_cards())
	row.add_child(_juveniles)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.item_selected.connect(_on_tree_selected)
	left.add_child(_tree)

	_status = _label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status)

	var right := VSplitContainer.new()
	right.split_offset = 390
	split.add_child(right)

	var upper := VBoxContainer.new()
	upper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(upper)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.scroll_active = false
	_info.add_theme_font_size_override("normal_font_size", 14)
	_info.add_theme_font_size_override("bold_font_size", 16)
	upper.add_child(_info)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	upper.add_child(scroll)
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cards)

	_compare = GenomeComparePanel.new()
	right.add_child(_compare)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


# --- Daten --------------------------------------------------------------------

func _on_source_changed(index: int) -> void:
	_source.select(index)
	var start_seed := 1
	if index == 0:
		var res := JsonLoader.read(DEMO_PATH)
		if res.error == "" and res.data is Dictionary:
			start_seed = int(res.data.get("seed", 1))
	_seed.set_value_no_signal(start_seed)
	_rebuild(true)


## Baut die Taxonomie neu. `reset_sliders`: Regler aus der Quelle übernehmen.
func _rebuild(reset_sliders := false) -> void:
	var old_settings: SimilaritySettings = null if reset_sliders or taxonomy == null else taxonomy.settings
	if _source.selected == 0:
		var loader := TaxonomyLoader.new()
		taxonomy = loader.load_file(DEMO_PATH, schema)
		if taxonomy == null:
			_show_status("Fehler in %s:\n%s" % [DEMO_PATH, "\n".join(loader.errors)], true)
			return
		taxonomy.base_seed = int(_seed.value)
		_show_status("\n".join(loader.warnings), false)
	else:
		var gen := TaxonomyGenerator.new()
		taxonomy = gen.generate(schema, preset, int(_seed.value))
		_show_status("\n".join(gen.errors), not gen.errors.is_empty())
	if old_settings != null:
		taxonomy.settings = old_settings
	_sync_sliders_from_settings()
	factory = IndividualFactory.new(taxonomy)
	_compare.set_factory(factory)
	_fill_tree()


func _sync_sliders_from_settings() -> void:
	for n in SLIDERS.size():
		var key = SLIDERS[n][1]
		var v: float = taxonomy.settings.get_spread(key) if key is int else taxonomy.settings.get(key)
		_sliders[n].set_value_no_signal(v)
		_slider_values[n].text = "%.2f" % v


func _on_slider_changed() -> void:
	if taxonomy == null or factory == null:
		return
	for n in SLIDERS.size():
		var key = SLIDERS[n][1]
		if key is int:
			taxonomy.settings.set_spread(key, _sliders[n].value)
		else:
			taxonomy.settings.set(key, _sliders[n].value)
	factory.clear_cache()
	_refresh_cards()
	_compare.refresh()


func _on_export() -> void:
	if taxonomy == null:
		return
	var path := "user://taxonomy_%s_%d.json" % ["demo" if _source.selected == 0 else "gen", taxonomy.base_seed]
	var err := JsonLoader.write(path, taxonomy.to_dict())
	if err == OK:
		_show_status("Exportiert: %s" % ProjectSettings.globalize_path(path), false)
	else:
		_show_status("Export fehlgeschlagen (%s)" % error_string(err), true)


func _show_status(text: String, is_error: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(1, 0.45, 0.4) if is_error else Color(1, 1, 1, 0.6))


# --- Baum ---------------------------------------------------------------------

func _fill_tree() -> void:
	var keep := selected_id
	_tree.clear()
	var root := _tree.create_item()
	var first: TreeItem = null
	var reselect: TreeItem = null
	for t in taxonomy.roots():
		var item := _add_tree_item(root, t)
		if first == null:
			first = item
		var found := _find_item(item, keep)
		if found:
			reselect = found
	var target := reselect if reselect else first
	if target:
		_tree.set_block_signals(true)
		target.select(0)
		_tree.set_block_signals(false)
		_tree.scroll_to_item(target)
	_on_tree_selected()


func _add_tree_item(parent: TreeItem, t: Taxon) -> TreeItem:
	var item := _tree.create_item(parent)
	var text := "%s: %s" % [Ranks.label_of(t.rank), t.display_name()]
	if not t.convergence.is_empty():
		text += "  ≈"
	item.set_text(0, text)
	item.set_metadata(0, t.id)
	for child in taxonomy.children_of(t.id):
		_add_tree_item(item, child)
	if t.rank >= Ranks.FAMILY:
		item.collapsed = t.rank >= Ranks.GENUS and t.children.size() > 3
	return item


func _find_item(item: TreeItem, id: String) -> TreeItem:
	if id == "":
		return null
	if item.get_metadata(0) == id:
		return item
	for child in item.get_children():
		var found := _find_item(child, id)
		if found:
			return found
	return null


func _on_tree_selected() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	selected_id = item.get_metadata(0)
	_refresh_info()
	_refresh_cards()


# --- Anzeige ------------------------------------------------------------------

func _refresh_info() -> void:
	var t := taxonomy.get_taxon(selected_id) if taxonomy else null
	if t == null:
		_info.text = ""
		return
	var path := []
	for a in taxonomy.lineage(selected_id):
		path.append(a.name)
	var lines := ["[b]%s[/b]  [color=#aaa]%s · %s · id=%s[/color]" % [t.display_name(), Ranks.label_of(t.rank), " › ".join(path), t.id]]
	var extras := []
	if not t.set_values.is_empty():
		extras.append("set: " + ", ".join(t.set_values.keys()))
	if not t.fixed.is_empty():
		extras.append("fixed: " + ", ".join(t.fixed))
	if not t.dimorphism.is_empty():
		extras.append("Dimorphismus: " + ", ".join(t.dimorphism.keys()))
	if not t.convergence.is_empty():
		var target := taxonomy.get_taxon(t.convergence.target)
		extras.append("konvergent zu [i]%s[/i] (Stärke %.2f)" % [target.name, t.convergence.strength])
	if not extras.is_empty():
		lines.append("[color=#ccc]%s[/color]" % " · ".join(extras))
	if t.notes != "":
		lines.append("[color=#9c9]%s[/color]" % t.notes)
	var species := taxonomy.species(t.id)
	lines.append("[color=#aaa]%d Art(en) · Anzeige: bis zu %d Kreaturen[/color]" % [species.size(), MAX_CARDS])
	_info.text = "\n".join(lines)


func _refresh_cards() -> void:
	for child in _cards.get_children():
		child.queue_free()
	_selected_glyph = null
	if taxonomy == null or not taxonomy.has_taxon(selected_id):
		return
	var species := taxonomy.species(selected_id)
	if species.is_empty():
		return
	var per := mini(int(_per_species.value), maxi(1, MAX_CARDS / species.size()))
	var juvenile_chance := 0.25 if _juveniles.button_pressed else 0.0
	for sp in species.slice(0, MAX_CARDS):
		var header := Label.new()
		header.text = sp.display_name() + ("   ≈ " + taxonomy.get_taxon(sp.convergence.target).name if not sp.convergence.is_empty() else "")
		header.add_theme_color_override("font_color", Color(0.75, 0.9, 0.6))
		_cards.add_child(header)
		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cards.add_child(flow)
		for ind in factory.create_group(sp.id, per, 0, juvenile_chance):
			flow.add_child(_make_card(ind))


func _make_card(ind: Individual) -> Control:
	var card := PanelContainer.new()
	var box := VBoxContainer.new()
	card.add_child(box)
	var glyph := CreatureGlyph.new()
	glyph.genome = ind.genome
	glyph.pressed.connect(func():
		if _selected_glyph and is_instance_valid(_selected_glyph):
			_selected_glyph.selected = false
		glyph.selected = true
		_selected_glyph = glyph
		_compare.assign_next(ind))
	box.add_child(glyph)
	var l := Label.new()
	l.text = ind.short_label()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	box.add_child(l)
	return card
