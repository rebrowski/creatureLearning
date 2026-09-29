extends Node
## Autoload „Sfx“: kurze Geräusche und Vibration. Klänge liegen als kleine
## WAV-Dateien in assets/sounds (erzeugt, keine Fremdrechte). Abschaltbar über
## Optionen → Ton (UiSettings "sound").
##
##   Sound.play("splash", position)   räumlich in der Welt
##   Sound.play("success")            ohne Position (Oberfläche)
##   Sound.vibrate(40)                kurze Vibration (Handy, falls unterstützt)

const SOUNDS := ["splash", "dig", "call", "climb", "success", "fail", "click", "coin", "bait"]
const VOLUME_DB := {"click": -14.0, "climb": -6.0, "dig": -4.0}

var enabled := true
var _streams: Dictionary = {}
var _last_played: Dictionary = {}  # Name -> Zeit (ms), gegen Klangteppiche


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = UiSettings.sound_on()
	for n in SOUNDS:
		var s = load("res://assets/sounds/%s.wav" % n)
		if s != null:
			_streams[n] = s


func play(sound: String, at: Variant = null) -> void:
	if not enabled or not _streams.has(sound):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound, -1000)) < 90:
		return
	_last_played[sound] = now
	var scene := get_tree().current_scene
	var p: Node
	if at is Vector3 and scene is Node3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 6.0
		p3.max_distance = 45.0
		scene.add_child(p3)
		p3.global_position = at
		p = p3
	else:
		p = AudioStreamPlayer.new()
		add_child(p)
	p.stream = _streams[sound]
	p.volume_db = VOLUME_DB.get(sound, 0.0)
	p.finished.connect(p.queue_free)
	p.play()


func vibrate(ms := 40) -> void:
	if enabled and (OS.has_feature("mobile") or OS.has_feature("web")):
		Input.vibrate_handheld(ms)


func set_enabled(on: bool) -> void:
	enabled = on
	UiSettings.set_value("sound", on)
