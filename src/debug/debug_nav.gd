extends CanvasLayer
## Autoload: blendet in allen Szenen außer dem Menü einen „Menü“-Knopf ein
## (oben rechts); Esc bzw. Android-Zurück führt ebenfalls zum Menü,
## Zurück im Menü beendet die App. Setzt außerdem die Oberflächen-Skalierung
## (UiSettings) für alle Szenen.

const MENU := "res://scenes/main.tscn"

var _button: Button


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
