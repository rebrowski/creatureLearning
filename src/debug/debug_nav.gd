extends CanvasLayer
## Autoload: blendet in allen Szenen außer dem Menü einen „Menü“-Knopf ein
## (oben rechts); Esc bzw. Android-Zurück führt ebenfalls zum Menü,
## Zurück im Menü beendet die App. Setzt außerdem die Oberflächen-Skalierung
## (UiSettings) für alle Szenen.
##
## Web-App (PWA): Der Service Worker speichert das Spiel offline und liefert
## sonst bis zum Schließen aller Fenster die alte Version aus. Liegt eine neue
## Version bereit, wird sie im Menü sofort geladen, im Spiel per Knopf
## („Neue Version laden“, speichert vorher).

const MENU := "res://scenes/main.tscn"

var _button: Button
var _update_button: Button


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_button = Button.new()
	_button.text = "Menü"
	_button.custom_minimum_size = Vector2(90, 44)
	_button.add_theme_font_size_override("font_size", 18)
	_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_button.position += Vector2(-100, 8)
	_button.pressed.connect(_to_menu)
	add_child(_button)
	UiSettings.apply(get_tree().root)
	get_tree().root.size_changed.connect(func(): UiSettings.apply(get_tree().root))
	_update_button = Button.new()
	_update_button.text = "Neue Version laden"
	_update_button.custom_minimum_size = Vector2(200, 44)
	_update_button.add_theme_font_size_override("font_size", 18)
	_update_button.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	_update_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_update_button.position += Vector2(-310, 8)
	_update_button.visible = false
	_update_button.pressed.connect(_apply_update)
	add_child(_update_button)
	if OS.has_feature("web"):
		JavaScriptBridge.pwa_update_available.connect(_on_update_available)
		if JavaScriptBridge.pwa_needs_update():
			_on_update_available.call_deferred()


func _on_update_available() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path == MENU:
		_apply_update()
	else:
		_update_button.visible = true


func _apply_update() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("save_game"):
		scene.save_game()
	JavaScriptBridge.pwa_update()


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	_button.visible = scene != null and scene.scene_file_path != MENU


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _button.visible:
		_to_menu()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or _button == null:
		return
	if _button.visible:
		_to_menu()
	else:
		get_tree().quit()  # Zurück im Menü beendet die App


func _to_menu() -> void:
	get_tree().change_scene_to_file(MENU)
