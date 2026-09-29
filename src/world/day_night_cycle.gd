class_name DayNightCycle
extends Node
## Tageszeit: steuert Sonne, Mond, Umgebungslicht und Himmel.
##
## Stunde 0..24. Ein Tag dauert `day_length_seconds` Echtzeit (Standard 8 min,
## damit eine Aufgabe von 2–5 min Tageszeitwechsel erleben kann).
## Phasen: "night" (< 5), "dawn" (5–7), "day" (7–18), "dusk" (18–20), "night".
## Die Bewölkung aus Weather dämpft das Licht (cloudiness 0..1).

signal hour_changed(hour: int)
signal phase_changed(phase: String)

@export_range(0.0, 24.0) var hour := 9.0
@export var day_length_seconds := 480.0
## Multiplikator für die Zeit (Debug: schneller vorspulen). 0 = angehalten.
@export var time_scale := 1.0
@export var sun: DirectionalLight3D
@export var moon: DirectionalLight3D
@export var environment: WorldEnvironment

var cloudiness := 0.0
var _last_hour := -1
var _last_phase := ""


func _process(delta: float) -> void:
	advance(delta)


## Zeit weiterstellen und Licht anpassen (auch aus Tests aufrufbar).
func advance(delta: float) -> void:
	if day_length_seconds > 0.0:
		hour = fposmod(hour + delta * time_scale * 24.0 / day_length_seconds, 24.0)
	apply_lighting()
	var h := int(hour)
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)
	var p := phase()
	if p != _last_phase:
		_last_phase = p
		phase_changed.emit(p)


static func phase_for(h: float) -> String:
	if h < 5.0 or h >= 20.0:
		return "night"
	if h < 7.0:
		return "dawn"
	if h < 18.0:
		return "day"
	return "dusk"


func phase() -> String:
	return phase_for(hour)


func is_night() -> bool:
	return phase() == "night"


## Sonnenhöhe als Sinus: 1 = Zenit (12 Uhr), 0 = Horizont (6/18 Uhr), negativ = unter dem Horizont.
static func sun_elevation(h: float) -> float:
	return sin((h - 6.0) / 24.0 * TAU)


## Richtung zur Sonne (Einheitsvektor).
static func sun_direction(h: float) -> Vector3:
	var a := (h - 6.0) / 24.0 * TAU
	return Vector3(cos(a), sin(a), 0.35).normalized()


## Helligkeit 0..1 für Spiellogik (Sicht, Aktivität), inkl. Bewölkung.
static func light_level_for(h: float, clouds: float) -> float:
	var day := clampf(sun_elevation(h) * 2.5 + 0.35, 0.0, 1.0)
	var night_floor := 0.08
	return lerpf(night_floor, 1.0, day) * (1.0 - clouds * 0.45)


func light_level() -> float:
	return light_level_for(hour, cloudiness)


func apply_lighting() -> void:
	var elev := sun_elevation(hour)
	var day := clampf(elev * 2.5 + 0.35, 0.0, 1.0)
	var warm := 1.0 - clampf(elev * 3.0, 0.0, 1.0)  # tiefe Sonne -> warmes Licht
	if sun != null:
		# Sonne zieht von Osten (+X) über Süden (+Z) nach Westen; Licht fällt entlang -Z des Nodes
		sun.basis = Basis.looking_at(-sun_direction(hour), Vector3.UP)
		sun.light_energy = day * 1.05 * (1.0 - cloudiness * 0.6)
		sun.light_color = Color(1.0, 0.95, 0.88).lerp(Color(1.0, 0.6, 0.35), warm * day)
		sun.visible = day > 0.01
	if moon != null:
		moon.light_energy = (1.0 - day) * 0.25 * (1.0 - cloudiness * 0.7)
		moon.visible = day < 0.99
	if environment != null and environment.environment != null:
		var env := environment.environment
		var sky_day := Color(0.32, 0.5, 0.78).lerp(Color(0.5, 0.53, 0.57), cloudiness)
		var sky_dusk := Color(0.75, 0.45, 0.35)
		var sky_night := Color(0.03, 0.04, 0.09)
		var sky := sky_night.lerp(sky_dusk.lerp(sky_day, clampf(elev * 3.0, 0.0, 1.0)), day)
		env.background_color = sky
		env.ambient_light_color = sky.lerp(Color(0.45, 0.47, 0.5), 0.5)
		env.ambient_light_energy = lerpf(0.12, 0.32, day)
		env.fog_light_color = sky
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sm: ProceduralSkyMaterial = env.sky.sky_material
			sm.sky_top_color = sky
			sm.sky_horizon_color = sky.lerp(Color(0.8, 0.8, 0.8), 0.3 * day)
			sm.ground_horizon_color = sm.sky_horizon_color
			sm.ground_bottom_color = sky.darkened(0.5)
