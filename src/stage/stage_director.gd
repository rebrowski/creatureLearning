class_name StageDirector
extends RefCounted
## Spielt Proben und Aufgaben auf der Bühne ab. Eine Aufgabe zerfällt in
## Abschnitte – je Rolle der Beweis-Moment ihrer Fähigkeit (Klettern am Stamm,
## Bach, Erdhügel, dunkler Pfad, …) mit der Stufe aus dem Ergebnis
## (Erfolg = 3, sonst 0–2 nach Abstand zur Schwelle, ProbeCatalog.task_grade).

## Verhalten in Aufgaben-Schritten → Requisite
const BEHAVIOR_PROPS := {"sniff": "mounds", "dig": "hard_ground", "call": "posts", "display": "raider", "carry": "stone"}
const FRUIT_COLOR := Color(0.85, 0.2, 0.15)

var stage: Stage
var abilities: AbilityCatalog
var probes: ProbeCatalog
## Callable(bool): Bühne nachts (die Welt verdunkelt den Himmel)
var set_night: Callable


func _init(p_stage: Stage, p_abilities: AbilityCatalog, p_probes: ProbeCatalog, p_set_night: Callable) -> void:
	stage = p_stage
	abilities = p_abilities
	probes = p_probes
	set_night = p_set_night


## Eine Probe: Kreatur, Probe (aus probes.json), Stufe 0–3.
func run_probe(m: GroupMember, probe: Dictionary, grade: int) -> void:
	var night: bool = probe.get("night", false)
	set_night.call(night)
	await _segment(str(probe.prop), m, grade, {}, "%s – %s" % [probe.name, m.name], "%s: %s" % [m.name, probes.result_text(probe, grade)])
	set_night.call(false)


## Eine Aufgabe mit festem Ergebnis abspielen.
func run_task(task: TaskDef, result: Dictionary, assignments: Dictionary, water_depth := 0.6) -> void:
	var hour := float(task.context.get("hour", 12.0))
	set_night.call(hour >= 20.5 or hour < 5.5)
	var fruit_down := false
	for step in task.steps:
		var role_id := str(step.get("role", ""))
		var m: GroupMember = assignments.get(role_id)
		if m == null:
			continue
		var role := task.role(role_id)
		var res: Dictionary = result.roles.get(role_id, {})
		var kind := ""
		var opts := {}
		match str(step.get("type", "")):
			"climb_tree":
				kind = "trunk"
				opts.drop_fruit = step.get("on_success", "") == "drop_fruit"
			"cross_stream":
				kind = "stream"
				opts.wade = TaskSimulator.can_wade(m.genome, water_depth)
				opts.carry_fruit = fruit_down
			"walk_to":
				if TaskPanel.main_ability(role) == "night_vision":
					kind = "dark_path"
			"behavior":
				kind = BEHAVIOR_PROPS.get(str(step.get("behavior", "")), "")
		if kind == "":
			continue
		if res.get("skipped", false):
			stage.caption.emit("%s %s hatte nichts zu tun." % [role.name, m.name])
			await stage.wait(1.2)
			continue
		var g := ProbeCatalog.task_grade(res)
		var probe := _probe_for(kind)
		await _segment(kind, m, g, opts, "%s %s" % [role.name, m.name], "%s: %s" % [m.name, probes.result_text(probe, g)])
		if kind == "trunk" and g == 3 and opts.get("drop_fruit", false):
			fruit_down = true
	stage.caption.emit("Geschafft!" if result.success else "Nicht geschafft …")
	await stage.wait(1.4)
	set_night.call(false)


func _probe_for(kind: String) -> Dictionary:
	for p in probes.probes:
		if p.get("prop", "") == kind:
			return p
	return {}


func _segment(kind: String, m: GroupMember, g: int, opts: Dictionary, intro: String, outro: String) -> void:
	stage.clear()
	stage.build_prop(kind, {"correct": randi() % 4})
	var actor := stage.spawn_actor(m, Stage.start_for(kind), Vector3.RIGHT, abilities)
	if opts.get("carry_fruit", false):
		var fruit := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.26
		var mat := StandardMaterial3D.new()
		mat.albedo_color = FRUIT_COLOR
		sm.material = mat
		fruit.mesh = sm
		stage.add_child(fruit)
		opts.item = fruit
	var f: Array = Stage.focus_for(kind)
	stage.frame(f[0], f[1], f[2], true)
	stage.caption.emit(intro)
	await stage.wait(0.6)
	await stage.perform(kind, actor, g, opts)
	stage.caption.emit(outro)
	await stage.wait(1.3)
