class_name RivalAI
extends RefCounted
## Entscheidungen einer Rivalen-Gruppe – fair: Sie wählt Besetzungen nach
## ihren eigenen Schätzungen (RivalState.beliefs), das Ergebnis rechnet aber
## derselbe TaskSimulator mit den wahren Fähigkeiten aus. Aus Erfolg und
## Misserfolg (und aus Beobachten) lernt sie mit der Lernrate der
## Schwierigkeitsstufe.
##
## take_turn() ist der Zug einer Runde (actions_per_round Aktionen); act() führt
## genau eine Aktion aus und liefert ein Ereignis:
##   {"type": "task", "task": TaskDef, "result": Dictionary, "assignments": {role: GroupMember},
##    "earned": int, "cost": int, "text": String}
##   {"type": "hire", "member": GroupMember, "price": int, "text": String}
##   {"type": "observe", "member": GroupMember, "text": ""}
##   {"type": "rest", "text": ""}


## Zug einer Runde: alle Aktionen nacheinander. Rückgabe: Ereignisse (ohne „rest“).
static func take_turn(gs: GameState, rival: RivalState, task_catalog: TaskCatalog, catalog: AbilityCatalog,
		rng: RandomNumberGenerator) -> Array:
	var out := []
	for i in int(RivalState.difficulty(gs.difficulty).get("actions_per_round", 7)):
		var ev := act(gs, rival, task_catalog, catalog, rng)
		if ev.type != "rest":
			out.append(ev)
	return out


static func act(gs: GameState, rival: RivalState, task_catalog: TaskCatalog, catalog: AbilityCatalog,
		rng: RandomNumberGenerator) -> Dictionary:
	var diff := RivalState.difficulty(gs.difficulty)
	if rival.today.size() < int(diff.get("tasks_per_round", 2)):
		var plan := best_plan(gs, rival, task_catalog, catalog, float(diff.get("risk", 0.05)))
		if not plan.is_empty():
			return _attempt(gs, rival, plan, catalog)
	var focus := _focus(gs, rival, task_catalog)
	if focus.is_empty() and rng.randf() < float(diff.get("hire_chance", 0.4)):
		var ev := _hire(gs, rival, catalog, rng)
		if not ev.is_empty():
			return ev
	return _observe(rival, catalog, rng, diff, focus)


## Fähigkeiten, die für die nächste erreichbare Aufgabe zählen (darauf richtet
## sich das Beobachten). Leer = die Gruppe kann schon alles Erreichbare – dann anheuern.
static func _focus(gs: GameState, rival: RivalState, task_catalog: TaskCatalog) -> Array:
	var out := []
	for t in task_catalog.tasks:
		if not rival.task_unlocked(t) or gs.site_stock(t) == 0:
			continue
		if int(rival.tasks.get(t.id, {}).get("successes", 0)) > 0:
			continue
		for r in t.roles:
			for req in r.requirements:
				if not out.has(req.ability):
					out.append(req.ability)
		if not out.is_empty():
			return out
	return out


## Geschätzter Rollenwert eines Mitglieds (gewichtete Schätzungen).
static func estimate(rival: RivalState, m: GroupMember, role: Dictionary) -> float:
	var total := 0.0
	var wsum := 0.0
	for req in role.requirements:
		total += rival.belief(m.id, req.ability) * req.weight
		wsum += req.weight
	return total / maxf(wsum, 0.001)


## Beste Aufgabe mit Besetzung nach eigener Schätzung, oder {} (nichts lohnt sich).
## {"task": TaskDef, "assignments": {role_id: GroupMember}, "margin": float}
static func best_plan(gs: GameState, rival: RivalState, task_catalog: TaskCatalog, catalog: AbilityCatalog, risk: float) -> Dictionary:
	var best := {}
	var best_score := -INF
	for t in task_catalog.tasks:
		if gs.site_stock(t) == 0 or rival.today.has(t.id) or not rival.task_unlocked(t):
			continue
		var used := {}
		var assignments := {}
		var margin := INF
		for r in t.roles:
			var pick: GroupMember = null
			var pick_v := -INF
			for m in rival.members:
				if m.exhausted or used.has(m.id):
					continue
				var v := estimate(rival, m, r)
				if v > pick_v:
					pick_v = v
					pick = m
			if pick == null:
				margin = -INF
				break
			used[pick.id] = true
			assignments[r.id] = pick
			margin = minf(margin, pick_v - r.threshold)
		if margin < -risk:
			continue
		# lohnende Aufgaben zuerst: Belohnung × Zuversicht
		var reward := reward_for(gs, rival, t)
		var score := reward * clampf(0.5 + margin * 2.0, 0.1, 1.0)
		if score > best_score:
			best_score = score
			best = {"task": t, "assignments": assignments, "margin": margin}
	return best


## Dieselben Belohnungsregeln wie für den Spieler, mit den Versuchen der Rivalen.
static func reward_for(gs: GameState, rival: RivalState, task: TaskDef) -> int:
	var cfg := GameState.progression()
	var st: Dictionary = rival.tasks.get(task.id, {})
	if st.get("successes", 0) > 0:
		return int(roundf(task.reward * float(cfg.get("repeat_reward_factor", 0.5))))
	var factors: Array = cfg.get("first_try_factors", [1.0])
	return int(roundf(task.reward * float(factors[mini(int(st.get("attempts", 0)), factors.size() - 1)])))


static func _attempt(gs: GameState, rival: RivalState, plan: Dictionary, catalog: AbilityCatalog) -> Dictionary:
	var t: TaskDef = plan.task
	var st: Dictionary = rival.tasks.get(t.id, {"attempts": 0, "successes": 0})
	var result := TaskSimulator.simulate(t, plan.assignments, catalog, int(st.attempts) + 7919 * (rival.points + 1))
	var cfg := GameState.progression()
	var cost := mini(int(cfg.get("attempt_cost", 0)), rival.credits)
	var earned := reward_for(gs, rival, t) if result.success else 0
	if result.success and not gs.consume_site(t.site):
		earned = 0
	rival.today[t.id] = true
	st.attempts = int(st.attempts) + 1
	if result.success:
		st.successes = int(st.successes) + 1
	rival.tasks[t.id] = st
	rival.credits += earned - cost
	rival.points += earned
	var learn := float(RivalState.difficulty(gs.difficulty).get("learn", 0.6))
	for r in t.roles:
		var m: GroupMember = plan.assignments.get(r.id)
		var e: Dictionary = result.roles.get(r.id, {})
		if m == null or e.get("skipped", false):
			continue
		var ok: bool = e.get("success", false)
		if not ok:
			m.exhausted = true
		# Erfolg: mindestens knapp über der Schwelle; Misserfolg: darunter
		for req in r.requirements:
			var cur := rival.belief(m.id, req.ability)
			var target: float = maxf(cur, r.threshold + 0.12) if ok else minf(cur, r.threshold - 0.12)
			rival.set_belief(m.id, req.ability, lerpf(cur, target, learn))
	var text := "%s %s „%s“ (%s)" % [rival.name, "schafften" if result.success else "scheiterten an", t.name,
			("+%d" % earned) if result.success else ("−%d" % cost)]
	return {"type": "task", "task": t, "result": result, "assignments": plan.assignments, "earned": earned, "cost": cost, "text": text}


## Einen Fremden anheuern (wählt nach Aussehen, nicht nach den wahren Werten).
static func _hire(gs: GameState, rival: RivalState, catalog: AbilityCatalog, rng: RandomNumberGenerator) -> Dictionary:
	var have := {}
	for m in rival.members:
		have[m.species_id] = true
	var choice: GroupMember = null
	for o in gs.offers:
		if o.price + int(GameState.progression().get("attempt_cost", 10)) * 2 > rival.credits:
			continue  # Reserve für Versuche behalten
		if choice == null or (not have.has(o.species_id) and have.has(choice.species_id)) or rng.randf() < 0.3:
			choice = o
	if choice == null:
		return {}
	gs.offers.erase(choice)
	rival.credits -= choice.price
	var price := choice.price
	choice.price = 0
	choice.name = rival.next_name()
	rival.add_member(choice, catalog)
	return {"type": "hire", "member": choice, "price": price, "text": "%s heuerten %s an" % [rival.name, choice.name]}


## Ein Mitglied beobachten: Schätzung rückt (verrauscht) in Richtung wahrer Wert.
static func _observe(rival: RivalState, catalog: AbilityCatalog, rng: RandomNumberGenerator, diff: Dictionary, focus: Array = []) -> Dictionary:
	if rival.members.is_empty() or catalog.order.is_empty():
		return {"type": "rest", "text": ""}
	var m: GroupMember = rival.members[rng.randi() % rival.members.size()]
	var a: String = focus[rng.randi() % focus.size()] if not focus.is_empty() and rng.randf() < 0.8 \
			else catalog.order[rng.randi() % catalog.order.size()]
	var truth := catalog.base_value(a, m.genome)
	var cur := rival.belief(m.id, a)
	var learn := float(diff.get("learn", 0.6))
	var noise := rng.randfn(0.0, float(diff.get("noise", 0.12)))
	rival.set_belief(m.id, a, cur + learn * 0.5 * (truth - cur) + noise)
	return {"type": "observe", "member": m, "ability": a, "text": ""}
