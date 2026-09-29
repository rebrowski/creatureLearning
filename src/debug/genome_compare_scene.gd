extends Control
## Eigenständiger Debug-Modus: zwei Kreaturen aus der Demo-Taxonomie und ihr
## Abstand. Schnellwahl-Knöpfe für typische Paare.

const DEMO_PATH := "res://data/taxonomies/forest_demo.json"

var taxonomy: Taxonomy
var factory: IndividualFactory
var _panel: GenomeComparePanel
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	theme = Theme.new()
	theme.default_font_size = 17
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.13, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bar := HBoxContainer.new()
	root.add_child(bar)
	for spec in [["Gleiche Art", "species"], ["Gleiche Gattung", "genus"], ["Gleiche Familie", "family"],
			["Andere Klasse", "class"], ["Konvergenzpaar", "convergent"], ["♂ / ♀", "sexes"], ["Alt / Jung", "ages"]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(_pick.bind(spec[1]))
		bar.add_child(b)

	_panel = GenomeComparePanel.new()
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_panel)

	var loader := TaxonomyLoader.new()
	taxonomy = loader.load_file(DEMO_PATH, GenomeSchema.load_file())
	if taxonomy == null:
		push_error("\n".join(loader.errors))
		return
	factory = IndividualFactory.new(taxonomy)
	_panel.set_factory(factory)
	_pick("convergent")


func _pick(kind: String) -> void:
	var all := taxonomy.species()
	var a: Taxon = all[_rng.randi_range(0, all.size() - 1)]
	var b: Taxon = a
	var sex_a := "female"
	var sex_b := "female"
	var age_b := "adult"
	match kind:
		"convergent":
			for sp in all:
				if not sp.convergence.is_empty():
					a = sp
					b = taxonomy.get_taxon(sp.convergence.target)
					break
		"sexes":
			sex_b = "male"
		"ages":
			age_b = "juvenile"
		"genus", "family", "class":
			var wanted: int = {"genus": Ranks.GENUS, "family": Ranks.FAMILY, "class": -1}[kind]
			var candidates := []
			for x in all:
				for y in all:
					if x != y and taxonomy.shared_rank(x.id, y.id) == wanted:
						candidates.append([x, y])
			if not candidates.is_empty():
				var pair: Array = candidates[_rng.randi_range(0, candidates.size() - 1)]
				a = pair[0]
				b = pair[1]
	var ia := _rng.randi_range(0, 20)
	var ib := ia if kind in ["sexes", "ages"] else ia + 1 + _rng.randi_range(0, 20)
	_panel.set_pair(factory.create_individual(a.id, ia, sex_a, "adult"), factory.create_individual(b.id, ib, sex_b, age_b))
