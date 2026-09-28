class_name BehaviorBrain
extends RefCounted
## Wählt für eine Kreatur laufend ein sichtbares Verhalten aus.
##
## Nutzen = Verhalten.utility(Kontext) × Zufall (0.6..1.4) × Abkühlung
## (kürzlich ausgeführte Verhalten × 0.25). Tiere zeigen so vor allem, was sie
## gut können, probieren aber auch Schwaches – und scheitern sichtbar.
## Tuning: data/abilities/behaviors.json.

const PARAMS_PATH := "res://data/abilities/behaviors.json"
const HISTORY_SIZE := 30

static var _params: Dictionary = {}

var creature: Creature
var navigation: ForestNavigation
var context: WorldContext
var mover: NavMover
var home := Vector3.ZERO
var roam_radius := 16.0
var rng := RandomNumberGenerator.new()
var behaviors: Array[CreatureBehavior] = []
var current: CreatureBehavior
## Letzte Verhalten: [{id, outcome, time}] – Grundlage für Beobachtung (Journal, M5).
var history: Array[Dictionary] = []
## Pausiert (Aufgaben): kein eigenes neues Verhalten, nur erzwungene.
var paused := false

var _cooldowns: Dictionary = {}
var _glow_timer := 0.0
var _time := 0.0


func _init(p_creature: Creature, p_navigation: ForestNavigation, p_context: WorldContext, p_home: Vector3, seed_value: int) -> void:
	creature = p_creature
	navigation = p_navigation
	context = p_context
	home = p_home
	rng.seed = seed_value
	mover = NavMover.new(creature, navigation)
	for b in [WanderBehavior.new(), ClimbRockBehavior.new(), ClimbTreeBehavior.new(), SwimBehavior.new(),
			DigBehavior.new(), CarryBehavior.new(), CallBehavior.new(), SniffBehavior.new(),
			RestBehavior.new(), DisplayBehavior.new()]:
		b.setup(self)
		behaviors.append(b)


static func params() -> Dictionary:
	if _params.is_empty():
		var res := JsonLoader.read(PARAMS_PATH)
		_params = res.data.get("behaviors", {}) if res.error == "" else {}
	return _params


func weight(id: String) -> float:
	return float(params().get(id, {}).get("weight", 0.3))


func max_time(id: String) -> float:
	return float(params().get(id, {}).get("max_time", 30.0))


func layout() -> ForestLayout:
	return context.layout()


func sample_here() -> Dictionary:
	return context.sample(creature.global_position)


func neighbor_within(radius: float) -> Creature:
	for o in mover.others:
		if o != creature and is_instance_valid(o) and o.global_position.distance_to(creature.global_position) < radius:
			return o
	return null


func update(delta: float) -> void:
	_time += delta
	for k in _cooldowns.keys():
		_cooldowns[k] -= delta
		if _cooldowns[k] <= 0.0:
			_cooldowns.erase(k)
	_glow_timer -= delta
	if _glow_timer <= 0.0 and creature.abilities != null:
		_glow_timer = 0.5
		var darkness := 1.0 - float(sample_here().get("light", 1.0))
		creature.set_eye_glow(creature.abilities.value("night_vision") * darkness * darkness)
	if not mover.ready():
		creature.desired_velocity = Vector3.ZERO
		return
	if current != null:
		current.elapsed += delta
		if current.update(delta) and current.elapsed < max_time(current.id):
			return
		_end_current()
	if paused:
		creature.desired_velocity = Vector3.ZERO
		return
	_choose()


## Startet ein bestimmtes Verhalten (Aufgaben, Debug, Tests). false = unbekannt.
func force(id: String, p_params := {}) -> bool:
	for b in behaviors:
		if b.id == id:
			if current != null:
				_end_current()
			_start(b, p_params)
			return true
	return false


## Bricht das laufende Verhalten ab.
func stop_current() -> void:
	if current != null:
		_end_current()


func _choose() -> void:
	var sample := sample_here()
	var best: CreatureBehavior = null
	var best_u := 0.0
	for b in behaviors:
		var u := b.utility(sample)
		if u <= 0.0:
			continue
		u *= rng.randf_range(0.6, 1.4)
		if _cooldowns.has(b.id):
			u *= 0.25
		if u > best_u:
			best_u = u
			best = b
	if best != null:
		_start(best)


func _start(b: CreatureBehavior, p_params := {}) -> void:
	current = b
	b.params = p_params
	b.elapsed = 0.0
	b.outcome = ""
	b.timed_out = false
	creature.behavior_label = b.label
	b.start()


func _end_current() -> void:
	var b := current
	current = null
	b.finish()
	creature.clear_behavior_pose()
	creature.behavior_label = ""
	_cooldowns[b.id] = float(params().get(b.id, {}).get("cooldown", 20.0))
	history.append({"id": b.id, "outcome": b.outcome, "time": _time})
	if history.size() > HISTORY_SIZE:
		history.pop_front()
