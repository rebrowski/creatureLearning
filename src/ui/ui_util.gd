class_name UiUtil
extends RefCounted
## Kleine Helfer für die im Code gebauten Oberflächen (einheitliche Größen für Touch).


static func button(text: String, action: Callable = Callable(), min_size := Vector2(0, 48)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	if action.is_valid():
		b.pressed.connect(action)
	return b


## Mehrzeiliger Text (bricht um). Für Beschriftungen in Zeilen: `caption()`.
static func label(text: String, size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


## Einzeilige Beschriftung mit fester Mindestbreite (bricht nicht um).
static func caption(text: String, width := 0.0, size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


## Deckender, abgerundeter Panel-Hintergrund.
static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.13, 0.12, 0.97)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(1)
	return sb


## Vollbild-Overlay mit dunklem Hintergrund und zentriertem Panel.
static func overlay(parent: Control, panel_size: Vector2) -> PanelContainer:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = panel_size
	panel.add_theme_stylebox_override("panel", panel_style())
	center.add_child(panel)
	return panel


static func clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()
