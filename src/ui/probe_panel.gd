class_name ProbePanel
extends Control
## Proben-Auswahl: acht Proben, je eine Fähigkeit. Nach der Wahl öffnet die Welt
## die Galerie, um die Kreatur zu bestimmen. Pro Tag sind nur wenige Proben
## möglich (ForestWorld.PROBES_PER_DAY).

signal probe_chosen(probe: Dictionary)
signal closed


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func open(probes: ProbeCatalog, abilities: AbilityCatalog, left: int) -> void:
	UiUtil.clear(self)
	var box := UiUtil.overlay(self, Vector2(760, 0))
	var head := HBoxContainer.new()
	box.add_child(head)
	var t := UiUtil.caption("Probe auf der Lichtung", 0, 24)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UiUtil.button("✕", func(): visible = false; closed.emit(), Vector2(52, 44)))
	var info := "Heute noch %d %s. Eine Probe zeigt genau eine Fähigkeit in vier Stufen (○○○ bis ●●●)." % [
			left, "Probe" if left == 1 else "Proben"]
	if left <= 0:
		info = "Für heute sind alle Proben verbraucht – morgen früh geht es weiter."
	box.add_child(UiUtil.label(info, 15, Color(1, 1, 1, 0.75)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for p in probes.probes:
		var b := UiUtil.button("%s – %s\n%s" % [p.name, abilities.name_of(str(p.ability)), p.hint],
				func(): visible = false; probe_chosen.emit(p), Vector2(340, 72))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = left <= 0
		grid.add_child(b)
	visible = true
