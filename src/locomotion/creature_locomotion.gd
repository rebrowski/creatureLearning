class_name CreatureLocomotion
extends RefCounted
## Prozedurales Laufen: Schrittplaner, Bein-IK, Körperhaltung, Rumpf-/Schwanzwelle.
##
## Ein globaler Gangzyklus (phase 0..1) läuft mit einer Frequenz, die aus Tempo
## und Schrittlänge folgt. Jedes Bein hat einen Phasenversatz (GaitTable);
## während seiner Schwungphase fliegt der Fuß auf einem Bogen zum nächsten
## Aufsetzpunkt (Ruhepunkt + Vorhalt in Laufrichtung, Bodenhöhe per
## `ground_query`), in der Standphase bleibt er fest in der Welt stehen.
## Steht die Kreatur, setzen nur Beine um, die zu weit vom Ruhepunkt entfernt sind.
##
## `ground_query(world_pos: Vector3) -> float` liefert die Bodenhöhe oder NAN.
## Dadurch ist die Klasse ohne Physik testbar.

const IDLE_STEP_FREQUENCY := 1.4
const TURN_BLEND := 6.0

var plan: BodyPlan
var rig: CreatureRig
var skeleton: Skeleton3D
var ground_query: Callable
## Optional: func(leg: int, hip_world: Vector3) -> Variant. Liefert eine Vector3-
## Fußposition (Welt) oder null für normales Laufen (z. B. Paddeln, Scharren, Klettern).
var foot_override: Callable

## Posen-Ziele für Verhalten (werden weich angesteuert):
## Höhe (m), Nicken/Rollen (rad, + = Nase hoch / rechts hoch), Größe, Kopfneigung (rad).
var pose_height := 0.0
var pose_pitch := 0.0
var pose_roll := 0.0
var pose_scale := 1.0
var head_pitch := 0.0

## Gangzyklus 0..1
var phase := 0.0
var time := 0.0
## Pro Bein: Fußposition in Weltkoordinaten
var feet: PackedVector3Array = []
## Pro Bein: schwingt gerade?
var swinging: PackedByteArray = []

var _offsets: PackedFloat32Array
var _duty := 0.6
var _swing_from: PackedVector3Array = []
var _target_cache: PackedVector3Array = []  # zuletzt abgefragter Aufsetzpunkt
var _skip_cycle: PackedByteArray = []       # Bein setzt in diesem Zyklus nicht um
var _body_y := 0.0
var _pitch := 0.0
var _roll := 0.0
var _speed_factor := 0.0
var _pose := Vector4.ZERO  # aktuelle Höhe, Nicken, Rollen, Kopf
var _scale := 1.0


func _init(p_plan: BodyPlan, p_rig: CreatureRig, p_skeleton: Skeleton3D, p_ground_query: Callable) -> void:
	plan = p_plan
	rig = p_rig
	skeleton = p_skeleton
	ground_query = p_ground_query
	_offsets = GaitTable.offsets(plan.leg_count, plan.gait)
	_duty = GaitTable.duty(plan.gait)
	feet.resize(plan.leg_count)
	swinging.resize(plan.leg_count)
	_swing_from.resize(plan.leg_count)
	_target_cache.resize(plan.leg_count)
	_skip_cycle.resize(plan.leg_count)


## Stellt alle Füße auf ihre Ruhepunkte (z. B. nach dem Spawnen).
func reset(xform: Transform3D) -> void:
	for leg in plan.leg_count:
		feet[leg] = _ground(xform * plan.foot_homes[leg], xform.origin.y, true)
		_target_cache[leg] = feet[leg]
		swinging[leg] = 0
		_skip_cycle[leg] = 0
	_body_y = 0.0
	_pitch = 0.0
	_roll = 0.0


## Ein Simulationsschritt. `velocity` in Weltkoordinaten, `use_raycasts` false =
## Boden wird als Ebene auf Höhe der Kreatur angenommen (LOD).
func update(delta: float, xform: Transform3D, velocity: Vector3, use_raycasts := true) -> void:
	time += delta
	var speed := velocity.length()
	_speed_factor = clampf(speed / maxf(plan.move_speed, 0.05), 0.0, 1.5)
	var swing_frac := 1.0 - _duty
	var stance_time := 1.0

	var kp := 1.0 - exp(-5.0 * delta)
	_pose = _pose.lerp(Vector4(pose_height, pose_pitch, pose_roll, head_pitch), kp)
	_scale = lerpf(_scale, pose_scale, kp)

	if plan.leg_count > 0 and foot_override.is_valid():
		phase = fposmod(phase + delta * 1.2, 1.0)
		for leg in plan.leg_count:
			var hip_world := xform * (body_transform() * rig.local_rest[rig.upper[leg]])
			var r = foot_override.call(leg, hip_world)
			if r is Vector3:
				feet[leg] = r
				swinging[leg] = 0
			else:
				_update_leg(leg, xform, velocity, speed, swing_frac, 1.0, use_raycasts)
	elif plan.leg_count > 0:
		var freq := speed * _duty / plan.stride_length
		if freq < IDLE_STEP_FREQUENCY * 0.5 and _needs_correction(xform):
			freq = IDLE_STEP_FREQUENCY
		phase = fposmod(phase + freq * delta, 1.0)
		stance_time = _duty / maxf(freq, 0.001)
		for leg in plan.leg_count:
			_update_leg(leg, xform, velocity, speed, swing_frac, minf(stance_time, 1.0), use_raycasts)
	else:
		phase = fposmod(phase + delta * (0.4 + speed * 1.5 / plan.stride_length), 1.0)

	_update_body(delta, xform)
	if skeleton != null:
		_apply_pose(xform)


func _update_leg(leg: int, xform: Transform3D, velocity: Vector3, speed: float, swing_frac: float, stance_time: float, use_raycasts: bool) -> void:
	var p := fposmod(phase + _offsets[leg], 1.0)
	var in_swing := p < swing_frac
	if in_swing and swinging[leg] == 0 and _skip_cycle[leg] == 0:
		# Beginn der Schwungphase: umsetzen nur, wenn nötig
		var home := xform * plan.foot_homes[leg]
		var error := Vector2(feet[leg].x - home.x, feet[leg].z - home.z).length()
		if speed < 0.05 and error < plan.stride_length * 0.2:
			_skip_cycle[leg] = 1
		else:
			swinging[leg] = 1
			_swing_from[leg] = feet[leg]
	if not in_swing:
		_skip_cycle[leg] = 0
		if swinging[leg] == 1:
			swinging[leg] = 0
			feet[leg] = _target(leg, xform, velocity, stance_time, use_raycasts)
		return
	if swinging[leg] == 0:
		return
	var t := clampf(p / swing_frac, 0.0, 1.0)
	var target := _target(leg, xform, velocity, stance_time, use_raycasts)
	var s := t * t * (3.0 - 2.0 * t)
	var pos := _swing_from[leg].lerp(target, s)
	pos.y += sin(PI * t) * GaitTable.lift(plan.gait) * plan.leg_reach()
	feet[leg] = pos


## Nächster Aufsetzpunkt: Ruhepunkt plus halber Standweg in Laufrichtung.
func _target(leg: int, xform: Transform3D, velocity: Vector3, stance_time: float, use_raycasts: bool) -> Vector3:
	var p := xform * plan.foot_homes[leg] + velocity * stance_time * 0.5
	var cached := _target_cache[leg]
	if use_raycasts and Vector2(p.x - cached.x, p.z - cached.z).length() < 0.05:
		return Vector3(p.x, cached.y, p.z)
	var grounded := _ground(p, xform.origin.y, use_raycasts)
	_target_cache[leg] = grounded
	return grounded


func _ground(p: Vector3, fallback_y: float, use_raycasts: bool) -> Vector3:
	var y := fallback_y
	if use_raycasts and ground_query.is_valid():
		var hit: float = ground_query.call(p)
		if not is_nan(hit):
			y = hit
	return Vector3(p.x, y, p.z)


func _needs_correction(xform: Transform3D) -> bool:
	for leg in plan.leg_count:
		var home := xform * plan.foot_homes[leg]
		if Vector2(feet[leg].x - home.x, feet[leg].z - home.z).length() > plan.stride_length * 0.2:
			return true
	return false


# --- Körper -------------------------------------------------------------------

func _update_body(delta: float, xform: Transform3D) -> void:
	var target_y := 0.0
	var target_pitch := 0.0
	var target_roll := 0.0
	if plan.leg_count > 0:
		var inv := xform.affine_inverse()
		var front := 0.0
		var back := 0.0
		var left := 0.0
		var right := 0.0
		var sum := 0.0
		var pairs := plan.leg_count / 2
		for leg in plan.leg_count:
			var local := inv * feet[leg]
			# schwingende Füße tragen nicht zur Körperhöhe bei
			var h := local.y if swinging[leg] == 0 else local.y - sin(PI * _swing_t(leg)) * GaitTable.lift(plan.gait) * plan.leg_reach()
			sum += h
			if plan.side_of(leg) == 0:
				left += h
			else:
				right += h
			if pairs > 1:
				if plan.pair_of(leg) < pairs / 2.0:
					front += h
				else:
					back += h
		target_y = sum / plan.leg_count
		left /= pairs
		right /= pairs
		target_roll = atan2(right - left, plan.half_width * 2.0 + 0.3) * 0.7
		if pairs > 1:
			var per_half := float(plan.leg_count) / 2.0
			target_pitch = atan2(front / per_half - back / per_half, plan.body_length * 0.8) * 0.8
	var k := 1.0 - exp(-TURN_BLEND * delta)
	_body_y = lerpf(_body_y, target_y, k)
	_pitch = lerpf(_pitch, target_pitch, k)
	_roll = lerpf(_roll, target_roll, k)


func _swing_t(leg: int) -> float:
	return clampf(fposmod(phase + _offsets[leg], 1.0) / (1.0 - _duty), 0.0, 1.0)


## Körpermitte in Kreatur-Koordinaten (für Tests und Debug).
func body_transform() -> Transform3D:
	var s := _speed_factor
	var bob := 0.0
	var sway_yaw := 0.0
	var sway_roll := 0.0
	var reach := plan.leg_reach()
	match plan.gait:
		"hop":
			bob = absf(sin(PI * phase)) * reach * 0.25 * minf(s, 1.0)
		"slither":
			sway_yaw = sin(TAU * phase) * 0.12 * (0.3 + s)
		"trot", "scuttle":
			bob = cos(TAU * 2.0 * phase) * reach * 0.025 * s
		_:
			bob = cos(TAU * 2.0 * phase) * reach * 0.035 * s
			if plan.leg_count == 2:
				sway_roll = sin(TAU * phase) * 0.08 * s
	var basis := Basis.from_euler(Vector3(_pitch + _pose.y, sway_yaw, _roll + sway_roll + _pose.z)).scaled(Vector3.ONE * _scale)
	return Transform3D(basis, Vector3(0.0, plan.body_center_y + _body_y + bob + _pose.x, 0.0))


func _apply_pose(xform: Transform3D) -> void:
	var root_pose := body_transform()
	_set_local(rig.root, root_pose)

	# Rumpfwelle: stark beim Schlängeln, sonst kaum sichtbar
	var wave_amp := (0.18 if plan.gait == "slither" or plan.leg_count == 0 else 0.03) * (0.3 + _speed_factor)
	for i in rig.segments.size():
		var ph := TAU * (phase * 1.0 - float(i) / maxf(1.0, rig.segments.size()))
		var yaw := sin(ph) * wave_amp
		var offset := Vector3(sin(ph) * wave_amp * plan.half_width, 0.0, 0.0)
		_set_local(rig.segments[i], Transform3D(Basis(Vector3.UP, yaw), rig.local_rest[rig.segments[i]] + offset))

	_set_local(rig.head, Transform3D(Basis(Vector3.RIGHT, _pose.w), rig.local_rest[rig.head]))

	# Schwanz: hängt, beim Hüpfen erhoben, wedelt mit dem Gang
	var droop := -0.25 if plan.gait == "hop" else 0.2
	for i in rig.tail.size():
		var wag := sin(TAU * phase + i * 0.8) * (0.08 + 0.12 * _speed_factor)
		_set_local(rig.tail[i], Transform3D(Basis.from_euler(Vector3(droop / rig.tail.size(), wag, 0.0)), rig.local_rest[rig.tail[i]]))

	if plan.leg_count == 0:
		return
	var inv := xform.affine_inverse()
	for leg in plan.leg_count:
		var hip: Vector3 = root_pose * rig.local_rest[rig.upper[leg]]
		var pole: Vector3 = root_pose.basis * plan.knee_poles[leg]
		var ik := LegIK.solve(hip, inv * feet[leg], plan.upper_leg, plan.lower_leg, pole)
		var upper_global := Transform3D(LegIK.bone_basis(hip, ik.knee), hip)
		var lower_global := Transform3D(LegIK.bone_basis(ik.knee, ik.foot), ik.knee)
		# gegen den (evtl. aufgeplusterten) Rumpf gerechnet: Beine behalten ihre Länge
		_set_local(rig.upper[leg], root_pose.affine_inverse() * upper_global)
		_set_local(rig.lower[leg], upper_global.affine_inverse() * lower_global)


func _set_local(bone: int, t: Transform3D) -> void:
	skeleton.set_bone_pose_position(bone, t.origin)
	skeleton.set_bone_pose_rotation(bone, t.basis.get_rotation_quaternion())
	skeleton.set_bone_pose_scale(bone, t.basis.get_scale())
