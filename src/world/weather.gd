class_name Weather
extends Node3D
## Einfaches Wetter: "clear", "cloudy", "rain" mit weichen Übergängen.
##
## Der Ablauf ist reproduzierbar (Seed): nach jeder Wetterphase wird die
## nächste aus `transitions` gewürfelt, Dauer aus `durations` (Sekunden).
## Regen: GPU-Partikel, die der Kamera folgen (wenige hundert, mobilgerecht).
## Nässe (wetness) steigt bei Regen und trocknet danach langsam ab.

signal weather_changed(state: String)

const STATES: PackedStringArray = ["clear", "cloudy", "rain"]
## Wahrscheinlichkeiten für den nächsten Zustand.
const TRANSITIONS := {
	"clear": {"clear": 0.5, "cloudy": 0.4, "rain": 0.1},
	"cloudy": {"clear": 0.35, "cloudy": 0.25, "rain": 0.4},
	"rain": {"clear": 0.2, "cloudy": 0.6, "rain": 0.2},
}

@export var seed_value := 1
@export var state := "clear"
## Automatisch wechseln (aus = nur per set_state).
@export var auto_change := true
## [min, max] Dauer einer Wetterphase in Sekunden.
@export var durations := Vector2(60.0, 150.0)
@export var day_night: DayNightCycle
@export var max_rain_particles := 600

## Weiche Werte 0..1
var cloudiness := 0.0
var rain := 0.0
var wetness := 0.0

var _rng := RandomNumberGenerator.new()
var _time_left := 0.0
var _particles: GPUParticles3D
var _water_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	_rng.seed = seed_value
	_time_left = _rng.randf_range(durations.x, durations.y)
	_particles = _make_rain()
	add_child(_particles)


## Wasser-Materialien, deren "rain"-Parameter mitgeführt wird.
func register_water(mat: ShaderMaterial) -> void:
	if mat != null:
		_water_materials.append(mat)


func set_state(new_state: String) -> void:
	if not STATES.has(new_state) or new_state == state:
		return
	state = new_state
	weather_changed.emit(state)


func _process(delta: float) -> void:
	step(delta)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		_particles.global_position = cam.global_position + Vector3(0, 6, 0) - cam.global_transform.basis.z * 6.0


## Ein Zeitschritt (auch aus Tests aufrufbar).
func step(delta: float) -> void:
	if auto_change:
		_time_left -= delta
		if _time_left <= 0.0:
			set_state(_pick_next())
			_time_left = _rng.randf_range(durations.x, durations.y)
	var target_clouds: float = {"clear": 0.0, "cloudy": 0.6, "rain": 0.9}[state]
	var target_rain := 1.0 if state == "rain" else 0.0
	var k := 1.0 - exp(-0.4 * delta)
	cloudiness = lerpf(cloudiness, target_clouds, k)
	rain = lerpf(rain, target_rain, k)
	wetness = clampf(wetness + (rain * 0.05 - (1.0 - rain) * 0.01) * delta, 0.0, 1.0)
	if _particles != null:
		_particles.amount_ratio = rain
		_particles.emitting = rain > 0.05
	if day_night != null:
		day_night.cloudiness = cloudiness
	for m in _water_materials:
		m.set_shader_parameter("rain", rain)


func _pick_next() -> String:
	var r := _rng.randf()
	var acc := 0.0
	for s in STATES:
		acc += TRANSITIONS[state][s]
		if r < acc:
			return s
	return state


func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Rain"
	p.amount = max_rain_particles
	p.lifetime = 1.0
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-15, -12, -15), Vector3(30, 20, 30))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 1, 14)
	pm.direction = Vector3(0.1, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 14.0
	pm.initial_velocity_max = 18.0
	pm.gravity = Vector3(0, -9.8, 0)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.3)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
