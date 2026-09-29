class_name SpeciesQuestionPanel
extends Control
## Artfrage nach einer Aufgabe: „Gehören A und B zur selben Art?“ Richtig
## beantwortet gibt es Beeren, und die Art kommt ins Bestimmungsbuch.

signal closed

var game: GameState
var _a: GroupMember
var _b: GroupMember


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func open(p_game: GameState, a: GroupMember, b: GroupMember) -> void:
	game = p_game
	_a = a
	_b = b
	UiUtil.clear(self)
	var box := UiUtil.overlay(self, Vector2(640, 0))
	box.add_child(UiUtil.label("Artfrage", 18, Color(1, 1, 1, 0.7)))
	box.add_child(UiUtil.label("Gehören %s und %s zur selben Art?" % [a.name, b.name], 24))
	var pics := HBoxContainer.new()
	pics.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(pics)
	for m in [a, b]:
		var col := VBoxContainer.new()
		var g := CreatureGlyph.new()
		g.genome = m.genome
		g.custom_minimum_size = Vector2(200, 120)
		col.add_child(g)
		var l := UiUtil.label(m.name, 16)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		pics.add_child(col)
	box.add_child(UiUtil.label("Richtig: +%d %s und ein Eintrag im Bestimmungsbuch." % [int(GameState.progression().get("species_reward", 10)), GameState.currency()], 15, Color(0.95, 0.85, 0.4)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(UiUtil.button("Ja, dieselbe Art", _answer.bind(true), Vector2(200, 52)))
	row.add_child(UiUtil.button("Nein, verschieden", _answer.bind(false), Vector2(200, 52)))
	row.add_child(UiUtil.button("Weiß nicht", func(): visible = false; closed.emit(), Vector2(140, 52)))
	visible = true


func _answer(same: bool) -> void:
	var r := game.answer_species_question(_a, _b, same)
	UiUtil.clear(self)
	var box := UiUtil.overlay(self, Vector2(600, 0))
	box.add_child(UiUtil.label("Richtig!" if r.correct else "Leider falsch", 28,
			Color(0.6, 1.0, 0.5) if r.correct else Color(1.0, 0.6, 0.45)))
	box.add_child(UiUtil.label("%s und %s gehören %s." % [_a.name, _b.name, "zur selben Art" if r.same else "zu verschiedenen Arten"], 18))
	if r.reward > 0:
		box.add_child(UiUtil.label("+%d %s" % [r.reward, GameState.currency()], 22, Color(0.95, 0.85, 0.4)))
	for n in r.discovered:
		box.add_child(UiUtil.label("Neu im Bestimmungsbuch: %s" % n, 17, Color(0.8, 0.95, 0.6)))
	box.add_child(UiUtil.button("Weiter", func(): visible = false; closed.emit(), Vector2(200, 52)))
	Sound.play("success" if r.correct else "fail")
