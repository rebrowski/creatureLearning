class_name DigBehavior
extends CreatureBehavior
## Graben: Vorderbeine scharren, Erde spritzt, ein Loch entsteht. Gute Gräber
## werfen viel Erde und hinterlassen große Löcher (auf weichem Ufer besser).

const DURATION := 6.0
const SOFT_ZONES := ["forest", "clearing", "bank"]

var _skill := 0.5
var _burst := 0.0
var _front := Vector3.ZERO


func _init() -> void:
	id = "dig"
	label = "gräbt"
	ability = "dig"


func utility(s: Dictionary) -> float:
	if not SOFT_ZONES.has(s.get("zone", "")):
		return 0.0
	return brain.weight(id) * (0.1 + skill(s))


func start() -> void:
	_skill = skill()
	outcome = "success" if _skill >= 0.4 else "fail"
	brain.mover.stop()
	creature.velocity = Vector3.ZERO
	var plan := creature.plan
	_front = creature.global_transform * Vector3(0.0, 0.0, -(plan.body_length * 0.5 + plan.head_radius))
	var y := creature.ground_height_at(_front)
	if not is_nan(y):
		_front.y = y
	BehaviorEffects.hole(world_parent(), _front, 0.1 + 0.4 * _skill, DURATION)
	creature.locomotion.pose_pitch = -0.35
	creature.locomotion.pose_height = -plan.hip_height * 0.25
	creature.locomotion.head_pitch = -0.35
	if plan.leg_count > 0:
		creature.locomotion.foot_override = _scratch


func update(delta: float) -> bool:
	creature.desired_velocity = Vector3.ZERO
	_burst -= delta
	if _burst <= 0.0:
		_burst = 0.35
		BehaviorEffects.dirt_burst(world_parent(), _front, _skill)
	return elapsed < DURATION


## Vorderbeine scharren vor und zurück, die übrigen stehen normal.
func _scratch(leg: int, _hip: Vector3) -> Variant:
	var plan := creature.plan
	if plan.pair_of(leg) != 0:
		return null
	var base := creature.global_transform * (plan.foot_homes[leg] + Vector3(0.0, 0.0, -plan.body_length * 0.15))
	var phi := elapsed * 14.0 + plan.side_of(leg) * PI
	return base + forward() * sin(phi) * 0.15 * plan.leg_reach() + Vector3.UP * maxf(0.0, cos(phi)) * 0.1
