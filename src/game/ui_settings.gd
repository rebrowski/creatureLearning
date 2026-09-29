class_name UiSettings
extends RefCounted
## Bedienungs-Einstellungen (user://settings.cfg, Abschnitt "ui"):
##   scale        "auto" oder Faktor (1.0 … 2.0) für Schrift und Knöpfe
##   show_names   Namensschilder über den Kreaturen (Standard: an)
##   sound        Geräusche und Vibration (Standard: an)
##   task_prompt  Hinweis „Aufgabe starten?“ nach einer Weile ohne Eingabe (Standard: an)
##
## "auto" richtet sich nach der Bildschirmgröße: Die Oberfläche ist für
## 1280×720 ausgelegt; auf kleinen Bildschirmen (Handy) wäre sie ohne
## Vergrößerung physisch winzig. Maßstab ist die kürzere Bildschirmseite in
## geräteunabhängigen Pixeln (dp, CSS-Pixel): ~390 auf Handys, ≥ 700 auf
## Laptops. Faktor = AUTO_REFERENCE / kürzere Seite, begrenzt auf 1.0 … MAX_SCALE.

const PATH := GraphicsSettings.PATH
const SECTION := "ui"
const SCALES := [1.0, 1.25, 1.5, 1.75, 2.0]
const AUTO_REFERENCE := 656.0
const MAX_SCALE := 2.0

## > 0: erzwungener Faktor (Screenshots, Tests), unabhängig von der Einstellung.
static var forced := 0.0


static func get_value(key: String, default: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return default
	return cfg.get_value(SECTION, key, default)


static func set_value(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(SECTION, key, value)
	cfg.save(PATH)


static func show_names() -> bool:
	return bool(get_value("show_names", true))


static func sound_on() -> bool:
	return bool(get_value("sound", true))


static func task_prompt() -> bool:
	return bool(get_value("task_prompt", true))


## Gespeicherte Einstellung: "auto" oder Faktor als Text.
static func scale_setting() -> String:
	return str(get_value("scale", "auto"))


## Nächste Stufe beim Durchschalten: auto → 1.0 → 1.25 … → 2.0 → auto.
static func next_scale_setting(current: String) -> String:
	if current == "auto":
		return str(SCALES[0])
	var i := SCALES.find(float(current))
	return "auto" if i < 0 or i == SCALES.size() - 1 else str(SCALES[i + 1])


static func scale_label(setting: String) -> String:
	return "auto" if setting == "auto" else "%d %%" % int(round(float(setting) * 100.0))


## Kürzere Fensterseite in dp/CSS-Pixeln (Schätzung).
static func short_side_dp(window: Window) -> float:
	if OS.has_feature("web"):
		var css = JavaScriptBridge.eval("Math.min(window.innerWidth, window.innerHeight)", true)
		if css is float or css is int:
			return float(css)
	var size := window.size
	var dpi := maxf(float(DisplayServer.screen_get_dpi()), 72.0)
	return minf(size.x, size.y) * 160.0 / dpi


static func auto_scale(short_dp: float) -> float:
	if short_dp <= 0.0:
		return 1.0
	return snappedf(clampf(AUTO_REFERENCE / short_dp, 1.0, MAX_SCALE), 0.05)


static func resolve_scale(setting: String, window: Window) -> float:
	if setting == "auto":
		return auto_scale(short_side_dp(window))
	return clampf(float(setting), 0.5, 3.0)


## Wendet die gespeicherte Einstellung auf das Hauptfenster an.
static func apply(window: Window) -> void:
	var f := forced if forced > 0.0 else resolve_scale(scale_setting(), window)
	if not is_equal_approx(window.content_scale_factor, f):
		window.content_scale_factor = f
