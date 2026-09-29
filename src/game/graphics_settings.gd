class_name GraphicsSettings
extends RefCounted
## Grafikstufen für unterschiedlich starke Geräte. Gespeichert in user://settings.cfg.
##
##   high   Schatten (2 Kaskaden, 35 m), volle Auflösung, Kreaturen-LOD normal
##   medium Schatten (1 Kaskade, 22 m), 85 % Auflösung, Kreaturen-LOD etwas enger
##   low    keine Schatten, 70 % Auflösung, Kreaturen-LOD deutlich enger
## Standard: high auf dem Desktop, medium auf Handys und im Browser.

const PATH := "user://settings.cfg"
const LEVELS: PackedStringArray = ["low", "medium", "high"]
const LABELS := {"low": "niedrig", "medium": "mittel", "high": "hoch"}
const PRESETS := {
	"high": {"shadows": 2, "shadow_distance": 35.0, "scale": 1.0, "lod_factor": 1.0},
	"medium": {"shadows": 1, "shadow_distance": 22.0, "scale": 0.85, "lod_factor": 0.8},
	"low": {"shadows": 0, "shadow_distance": 0.0, "scale": 0.7, "lod_factor": 0.6},
}
const BASE_LOD := [14.0, 32.0, 70.0]


static func default_level() -> String:
	return "medium" if OS.has_feature("mobile") or OS.has_feature("web") else "high"


static func load_level() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		var level := str(cfg.get_value("graphics", "level", default_level()))
		if LEVELS.has(level):
			return level
	return default_level()


static func save_level(level: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("graphics", "level", level)
	cfg.save(PATH)


static func next_level(level: String) -> String:
	return LEVELS[(LEVELS.find(level) + 1) % LEVELS.size()]


## Wendet eine Stufe auf Sonne und Viewport an.
static func apply(level: String, sun: DirectionalLight3D, viewport: Viewport) -> void:
	var p: Dictionary = PRESETS.get(level, PRESETS.high)
	if sun != null:
		sun.shadow_enabled = p.shadows > 0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if p.shadows >= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = p.shadow_distance
	if viewport != null:
		viewport.scaling_3d_scale = p.scale
	var f: float = p.lod_factor
	CreatureLOD.thresholds = PackedFloat32Array([BASE_LOD[0] * f, BASE_LOD[1] * f, BASE_LOD[2] * f])
