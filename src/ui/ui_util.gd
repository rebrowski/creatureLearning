class_name UiUtil
extends RefCounted
## Kleine Helfer für die im Code gebauten Oberflächen (einheitliche Größen für Touch).

## Bezeichnung für noch nicht angeheuerte Kreaturen.
const STRANGER := "Fremdling"


static func button(text: String, action: Callable = Callable(), min_size := Vector2(0, 48)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.pressed.connect(func(): Sound.play("click"))
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
## Das Panel wird auf die Bildschirmgröße begrenzt; der Inhalt scrollt, wenn er
## nicht passt (kleine Bildschirme, große Schrift). Rückgabe: Container für den
## Inhalt (Kinder füllen die Fläche).
static func overlay(parent: Control, panel_size: Vector2) -> Container:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var panel := PanelContainer.new()
	var screen := parent.get_viewport_rect().size if parent.is_inside_tree() else Vector2(1280, 720)
	var max_size := screen - Vector2(24, 24)
	panel.custom_minimum_size = Vector2(minf(panel_size.x, max_size.x), minf(panel_size.y, max_size.y))
	panel.add_theme_stylebox_override("panel", panel_style())
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# ohne feste Höhe wächst das Panel mit dem Inhalt – aber nie über den Bildschirm
	scroll.custom_minimum_size.y = minf(panel_size.y, max_size.y) if panel_size.y > 0.0 else 0.0
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	box.child_entered_tree.connect(func(n: Node) -> void:
		if n is Control and n.get_parent() == box:
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			n.size_flags_vertical = Control.SIZE_EXPAND_FILL)
	if panel_size.y <= 0.0:
		# Höhe nach Inhalt, begrenzt auf den Bildschirm
		box.resized.connect(func() -> void:
			scroll.custom_minimum_size.y = minf(box.get_combined_minimum_size().y, max_size.y - 32.0))
	return box


static func clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()
