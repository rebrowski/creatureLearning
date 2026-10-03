class_name SeasonPanel
extends Control
## Schlusswertung einer Saison mit Vorschlag für die nächste Schwierigkeit
## (adaptiv: nach deutlichem Sieg eine Stufe schwerer, nach deutlicher
## Niederlage eine leichter – der Spieler entscheidet).

signal next_season(difficulty: String)

var _result: Dictionary = {}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func open(result: Dictionary) -> void:
	_result = result
	UiUtil.clear(self)
	var box := UiUtil.overlay(self, Vector2(640, 0))
	box.add_theme_constant_override("separation", 10)
	box.add_child(UiUtil.label("Saison %d ist vorbei" % int(result.get("number", 1)), 18, Color(1, 1, 1, 0.7)))
	var won: bool = result.get("won", false)
	box.add_child(UiUtil.label("Gewonnen!" if won else ("Unentschieden" if result.player == result.rival else "Die %s waren besser" % result.rival_name), 30,
			Color(0.6, 1.0, 0.5) if won else Color(1.0, 0.7, 0.45)))
	box.add_child(UiUtil.label("Du: %d Punkte · %s: %d Punkte" % [result.player, result.rival_name, result.rival], 20))
	box.add_child(UiUtil.label("Deine Gruppe, dein Journal und dein Guthaben bleiben. In der neuen Saison beginnen die Rivalen mit einer neuen Gruppe, und alle Vorräte sind wieder voll.", 15, Color(1, 1, 1, 0.75)))
	var cur := str(result.get("difficulty", "normal"))
	var suggest := str(result.get("suggest", ""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	if suggest != "":
		var order: Array = RivalState.config().get("order", [])
		var harder: bool = order.find(suggest) > order.find(cur)
		box.add_child(UiUtil.label(("Du hast deutlich gewonnen – wie wäre es mit stärkeren Rivalen?" if harder
				else "Die Rivalen lagen deutlich vorn – mit etwas ruhigeren Rivalen macht es vielleicht mehr Spaß."), 16, Color(0.8, 0.95, 0.6)))
		row.add_child(UiUtil.button("Neue Saison: %s" % suggest, func(): visible = false; next_season.emit(suggest), Vector2(260, 52)))
		row.add_child(UiUtil.button("Bei „%s“ bleiben" % cur, func(): visible = false; next_season.emit(cur), Vector2(240, 52)))
	else:
		row.add_child(UiUtil.button("Neue Saison", func(): visible = false; next_season.emit(cur), Vector2(240, 52)))
	Sound.play("success" if won else "fail")
	visible = true
