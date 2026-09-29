class_name GeneDef
extends RefCounted
## Definition eines einzelnen Gens: Typ, Wertebereich, Vererbungsregeln.
##
## Werte werden im Genom so gespeichert:
##   FLOAT -> float, INT -> int, ENUM -> int (Index in `options`).
## In JSON dürfen ENUM-Werte als Name ("scuttle") oder Index angegeben werden.

enum Type { FLOAT, INT, ENUM }
const TYPE_NAMES: PackedStringArray = ["float", "int", "enum"]

var id: String = ""
var type: int = Type.FLOAT
## Merkmalsgruppe, z. B. "bodyplan", "color". Distanz wird auch pro Gruppe ausgewiesen.
var group: String = "misc"
var min_value: float = 0.0
var max_value: float = 1.0
## Nur INT: Werte werden auf Vielfache von `step` (ab `min_value`) gerundet.
var step: float = 1.0
## Nur ENUM: erlaubte Namen.
var options: PackedStringArray = []
var default_value: Variant = 0.0
## Nur FLOAT: Wert läuft im Kreis (z. B. Farbton). Distanz wird kreisförmig gemessen.
var wrap: bool = false
## Feinster Rang, der dieses Gen noch verändern darf (Ranks.CLASS .. Ranks.INDIVIDUAL).
## Beispiel: leg_count = ORDER -> ab Familie abwärts ist die Beinzahl fixiert.
var varies_until: int = Ranks.INDIVIDUAL
## Multiplikator auf alle zufälligen Abweichungen dieses Gens.
var variance_scale: float = 1.0
## Gewicht in der Distanzfunktion.
var distance_weight: float = 1.0
## Sichtbar = Teil des Aussehens. Unsichtbare Gene (z. B. Fähigkeiten ab M4)
## zählen nicht zur visuellen Distanz.
var visible: bool = true
## Wenn gesetzt: hat das Gen `depends_on` den Wert 0, ist dieses Gen bedeutungslos
## (z. B. horn_length ohne Hörner) und zählt in der Distanz als `min_value`.
var depends_on: String = ""
var description: String = ""


func range_size() -> float:
	if type == Type.ENUM:
		return maxf(1.0, options.size() - 1)
	return maxf(max_value - min_value, 0.000001)


## Bringt einen Wert in den gültigen Bereich und auf den richtigen Typ.
func sanitize(value: Variant) -> Variant:
	match type:
		Type.ENUM:
			return clampi(int(round(float(value))), 0, options.size() - 1)
		Type.INT:
			var steps := roundf((float(value) - min_value) / step)
			return int(clampf(min_value + steps * step, min_value, max_value))
		_:
			var v := float(value)
			if wrap:
				return min_value + fposmod(v - min_value, max_value - min_value)
			return clampf(v, min_value, max_value)


## Zufällige Abweichung. `sigma` ist ein Bruchteil des Wertebereichs (0.1 = 10 %).
## ENUM-Gene wechseln stattdessen mit Wahrscheinlichkeit `switch_probability`
## auf eine andere Option.
func mutate(value: Variant, sigma: float, switch_probability: float, rng: RandomNumberGenerator) -> Variant:
	if type == Type.ENUM:
		if options.size() > 1 and rng.randf() < switch_probability:
			var other := rng.randi_range(0, options.size() - 2)
			if other >= int(value):
				other += 1
			return other
		return value
	if sigma <= 0.0:
		return value
	return sanitize(float(value) + rng.randfn(0.0, sigma * variance_scale * range_size()))


## Interpoliert Richtung `target`. ENUM springt ab t >= 0.5.
func lerp_toward(value: Variant, target: Variant, t: float) -> Variant:
	if type == Type.ENUM:
		return target if t >= 0.5 else value
	if wrap:
		var span := max_value - min_value
		var delta := fposmod(float(target) - float(value) + span * 0.5, span) - span * 0.5
		return sanitize(float(value) + delta * t)
	return sanitize(lerpf(float(value), float(target), t))


## Normierter Unterschied zweier Werte in [0, 1].
func diff(a: Variant, b: Variant) -> float:
	if type == Type.ENUM:
		return 0.0 if int(a) == int(b) else 1.0
	var d := absf(float(a) - float(b)) / range_size()
	if wrap:
		d = minf(d, 1.0 - d) * 2.0
	return clampf(d, 0.0, 1.0)


## Wandelt einen JSON-Wert um. Liefert null bei ungültigem Wert.
func parse_value(raw: Variant) -> Variant:
	if type == Type.ENUM:
		if raw is String:
			var idx := options.find(raw)
			return idx if idx >= 0 else null
		if raw is float or raw is int:
			var i := int(raw)
			return i if i >= 0 and i < options.size() else null
		return null
	if raw is float or raw is int:
		return sanitize(raw)
	return null


## Wert für JSON-Export / Anzeige (ENUM als Name).
func to_json_value(value: Variant) -> Variant:
	if type == Type.ENUM:
		return options[int(value)]
	if type == Type.INT:
		return int(value)
	return snappedf(float(value), 0.0001)


func format_value(value: Variant) -> String:
	match type:
		Type.ENUM:
			return options[int(value)]
		Type.INT:
			return str(int(value))
		_:
			return "%.2f" % float(value)


## Erzeugt ein GeneDef aus einem JSON-Objekt. Fehler landen in `errors`.
static func from_dict(d: Dictionary, errors: PackedStringArray, ctx: String) -> GeneDef:
	var g := GeneDef.new()
	g.id = str(d.get("id", ""))
	if g.id.is_empty():
		errors.append("%s: 'id' fehlt" % ctx)
		return null
	ctx = "%s (%s)" % [ctx, g.id]
	var type_idx := TYPE_NAMES.find(str(d.get("type", "float")))
	if type_idx < 0:
		errors.append("%s: unbekannter type '%s' (erlaubt: %s)" % [ctx, d.get("type"), ", ".join(TYPE_NAMES)])
		return null
	g.type = type_idx
	g.group = str(d.get("group", "misc"))
	g.description = str(d.get("description", ""))
	g.wrap = bool(d.get("wrap", false))
	g.visible = bool(d.get("visible", true))
	g.distance_weight = float(d.get("weight", 1.0))
	g.variance_scale = float(d.get("variance_scale", 1.0))
	g.depends_on = str(d.get("depends_on", ""))
	var rank_name := str(d.get("varies_until", "individual"))
	g.varies_until = Ranks.from_name(rank_name)
	if g.varies_until < 0:
		errors.append("%s: unbekannter Rang in varies_until: '%s'" % [ctx, rank_name])
		return null
	if g.type == Type.ENUM:
		var opts = d.get("options", [])
		if not opts is Array or opts.size() < 1:
			errors.append("%s: enum braucht eine nicht-leere 'options'-Liste" % ctx)
			return null
		for o in opts:
			g.options.append(str(o))
		g.min_value = 0
		g.max_value = g.options.size() - 1
	else:
		if not d.has("min") or not d.has("max"):
			errors.append("%s: 'min' und 'max' sind Pflicht" % ctx)
			return null
		g.min_value = float(d["min"])
		g.max_value = float(d["max"])
		if g.max_value <= g.min_value:
			errors.append("%s: max muss größer als min sein" % ctx)
			return null
		g.step = float(d.get("step", 1.0))
		if g.type == Type.INT and g.step <= 0.0:
			errors.append("%s: step muss > 0 sein" % ctx)
			return null
	var parsed = g.parse_value(d.get("default", g.min_value if g.type != Type.ENUM else 0))
	if parsed == null:
		errors.append("%s: ungültiger default-Wert '%s'" % [ctx, d.get("default")])
		return null
	g.default_value = parsed
	return g
