class_name Bait
extends Node3D
## Köder: eine Beere, die der Spieler auslegt, um Fähigkeiten zu prüfen.
## "ground" = auf dem Boden (nachts: wer findet sie?), "water" = im Bach
## (wer kommt hin?), "tree" = am Stamm eines Fruchtbaums (wer klettert hinauf?).
## Die erste Kreatur, die sie erreicht, nimmt sie (take); unberührt verschwindet
## sie nach LIFETIME Sekunden.

signal taken(by: Creature)

const LIFETIME := 45.0
const COLOR := Color(0.85, 0.15, 0.35)

var kind := "ground"
var taken_by: Creature
var _age := 0.0
var _mesh: MeshInstance3D
var _base := Vector3.ZERO


func _ready() -> void:
	_base = position
	_mesh = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.09
	s.height = 0.18
	s.radial_segments = 10
	s.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR
	mat.emission_enabled = true
	mat.emission = COLOR
	mat.emission_energy_multiplier = 0.6  # auch nachts sichtbar
	s.material = mat
	_mesh.mesh = s
	_mesh.position.y = 0.09
	add_child(_mesh)
	BehaviorEffects.ring(get_parent(), global_position + Vector3.UP * 0.03, 0.8, Color(1, 0.6, 0.7, 0.7), 0.8)
	Sound.play("bait", global_position)


func _process(delta: float) -> void:
	_age += delta
	if taken_by == null:
		if kind == "water":
			position.y = _base.y + sin(_age * 2.5) * 0.03
		_mesh.rotation.y += delta
	if _age > LIFETIME and taken_by == null:
		queue_free()


func is_free() -> bool:
	return taken_by == null and is_inside_tree()


## Kreatur nimmt die Beere (nur die erste). true = hat sie bekommen.
func take(by: Creature) -> bool:
	if not is_free():
		return false
	taken_by = by
	taken.emit(by)
	Sound.play("coin", global_position)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.35)
	tw.tween_callback(queue_free)
	return true
