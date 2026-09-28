class_name CreatureGlyph
extends Control
## 2D-Seitenansicht einer Kreatur, direkt aus dem Genom gezeichnet.
##
## Nur für Debug-Ansichten gedacht, bis M2 echte 3D-Meshes liefert. Alle
## Glyphen nutzen denselben Maßstab (METERS_ACROSS), damit Größen vergleichbar
## bleiben; nur zu große Kreaturen werden verkleinert, um nicht abgeschnitten
## zu werden.

signal pressed

## So viele Meter passen standardmäßig in die Breite des Controls.
const METERS_ACROSS := 3.2
const SHAPE_HEIGHT := {"round": 1.0, "elongated": 0.65, "flat": 0.42}
const HORN_COLOR := Color(0.93, 0.88, 0.74)
const EYE_COLOR := Color(0.08, 0.08, 0.08)

var genome: Genome:
	set(value):
		genome = value
		queue_redraw()
var selected := false:
	set(value):
		selected = value
		queue_redraw()

var _scale := 1.0
var _origin := Vector2.ZERO


func _init() -> void:
	custom_minimum_size = Vector2(170, 120)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed.emit()
		accept_event()


func _draw() -> void:
	if selected:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.85, 0.3, 0.9), false, 3.0)
	if genome == null:
		return
	var m := _measure()
	_fit(m)
	draw_line(_p(Vector2(m.xmin, 0)), _p(Vector2(m.xmax, 0)), Color(1, 1, 1, 0.15), 1.0)

	var body := Color.from_hsv(genome.f("hue"), genome.f("saturation"), genome.f("brightness"))
	var pattern := _pattern_color(body)
	var outline := body.darkened(0.45)

	_draw_tail(m, body, outline)
	_draw_legs(m, body.darkened(0.35), true)
	_draw_body(m, body, outline, pattern)
	_draw_crest(m, pattern)
	_draw_legs(m, body.darkened(0.1), false)
	_draw_head(m, body, outline)


# --- Maße ---------------------------------------------------------------------

func _measure() -> Dictionary:
	var m := {}
	m.L = genome.f("body_length")
	m.H = genome.f("body_width") * SHAPE_HEIGHT.get(genome.option("body_shape"), 1.0)
	m.segments = genome.i("segment_count")
	m.legs = genome.i("leg_count")
	m.leg_len = float(genome.effective("leg_length"))
	m.leg_w = float(genome.effective("leg_thickness"))
	m.hip_h = m.leg_len * (0.45 + 0.45 * genome.f("posture")) if m.legs > 0 else 0.0
	m.cy = m.hip_h + m.H * 0.5
	m.head_r = genome.f("head_size") * 0.5
	m.head_c = Vector2(m.L * 0.5 + m.head_r * 0.7, m.cy + m.H * 0.15 + m.head_r * 0.2)
	m.tail = genome.f("tail_length")
	m.horns = genome.i("horn_count")
	m.horn_len = float(genome.effective("horn_length"))
	m.crest = genome.f("crest_height")
	m.antenna = genome.f("antenna_length")
	m.gait = genome.option("gait")
	var splay: float = m.leg_len * (0.8 if m.gait == "scuttle" else 0.3)
	m.xmin = minf(-m.L * 0.5 - m.tail * 0.95, -m.L * 0.5 - splay) - 0.05
	m.xmax = maxf(m.head_c.x + m.head_r + m.antenna * 0.7, m.L * 0.5 + splay) + 0.05
	m.ytop = maxf(m.cy + m.H * 0.5 + m.crest, m.head_c.y + m.head_r + maxf(m.horn_len, m.antenna * 0.8)) + 0.05
	return m


func _fit(m: Dictionary) -> void:
	var pad := 6.0
	var avail := size - Vector2(pad * 2, pad * 2)
	_scale = avail.x / METERS_ACROSS
	var w: float = m.xmax - m.xmin
	var h: float = m.ytop
	_scale = minf(_scale, minf(avail.x / w, avail.y / h))
	var center_x: float = (m.xmin + m.xmax) * 0.5
	_origin = Vector2(size.x * 0.5 - center_x * _scale, size.y - pad)


## Kreatur-Koordinaten (Meter, y nach oben) -> Pixel.
func _p(v: Vector2) -> Vector2:
	return _origin + Vector2(v.x, -v.y) * _scale


func _pattern_color(body: Color) -> Color:
	var contrast := float(genome.effective("pattern_contrast"))
	if body.v > 0.4:
		return body.darkened(contrast * 0.75)
	return body.lightened(contrast * 0.6)


# --- Körperteile --------------------------------------------------------------

func _segment_ellipses(m: Dictionary) -> Array:
	var out := []
	var n: int = maxi(1, m.segments)
	var seg_len: float = m.L / n
	for i in n:
		var cx: float = -m.L * 0.5 + (i + 0.5) * seg_len
		var a: float = m.L * 0.5 if n == 1 else seg_len * 0.62
		var b: float = m.H * 0.5 * (0.82 + 0.18 * sin(PI * (i + 0.5) / n))
		out.append([Vector2(cx, m.cy), a, b])
	return out


func _ellipse_points(c: Vector2, a: float, b: float, count := 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in count:
		var t := TAU * k / count
		pts.append(_p(c + Vector2(cos(t) * a, sin(t) * b)))
	return pts


func _draw_body(m: Dictionary, body: Color, outline: Color, pattern: Color) -> void:
	var ellipses := _segment_ellipses(m)
	for e in ellipses:
		var pts := _ellipse_points(e[0], e[1], e[2])
		draw_colored_polygon(pts, body)
		pts.append(pts[0])
		draw_polyline(pts, outline, 1.5, true)
	var ptype := genome.option("pattern_type")
	if ptype == "none":
		return
	var density := int(round(float(genome.effective("pattern_density"))))
	for i in ellipses.size():
		var c: Vector2 = ellipses[i][0]
		var a: float = ellipses[i][1]
		var b: float = ellipses[i][2]
		match ptype:
			"stripes":
				for k in density:
					var dx := a * lerpf(-0.75, 0.75, (k + 0.5) / density)
					var dy := b * sqrt(maxf(0.0, 1.0 - pow(dx / a, 2))) * 0.9
					draw_line(_p(c + Vector2(dx, dy)), _p(c + Vector2(dx, -dy)), pattern, maxf(1.5, a * 0.12 * _scale))
			"spots":
				for k in density + 1:
					var u := _hash01(i * 31 + k * 7) * 1.4 - 0.7
					var v := _hash01(i * 17 + k * 13 + 5) * 1.2 - 0.6
					var r := b * 0.16
					var pos := c + Vector2(u * a, v * b * sqrt(maxf(0.0, 1.0 - u * u)))
					draw_circle(_p(pos), maxf(1.5, r * _scale), pattern)
			"bands":
				draw_colored_polygon(_ellipse_points(c + Vector2(0, b * 0.1), a * 0.92, b * 0.28), pattern)


func _draw_legs(m: Dictionary, color: Color, far_side: bool) -> void:
	var pairs: int = m.legs / 2
	if pairs == 0:
		return
	var width := maxf(1.5, m.leg_w * _scale)
	var seg: float = m.leg_len * 0.55
	var offset := Vector2(m.L * 0.05, 0.02) if far_side else Vector2.ZERO
	for k in pairs:
		var t := 0.0 if pairs == 1 else lerpf(-0.7, 0.7, float(k) / (pairs - 1))
		var hip := Vector2(t * m.L * 0.5, m.hip_h + m.H * 0.2) + offset
		var splay: float = t * m.leg_len * (0.8 if m.gait == "scuttle" else 0.3)
		var foot := Vector2(hip.x + splay, 0.0)
		var knee := _knee(hip, foot, seg, m.gait == "scuttle")
		draw_polyline(PackedVector2Array([_p(hip), _p(knee), _p(foot)]), color, width, true)


## Einfache 2-Knochen-IK: Knie liegt auf dem Kreis um Hüfte und Fuß.
func _knee(hip: Vector2, foot: Vector2, seg: float, knee_up: bool) -> Vector2:
	var d := hip.distance_to(foot)
	var mid := (hip + foot) * 0.5
	if d >= seg * 2.0:
		return mid
	var dir := (foot - hip) / d
	var perp := Vector2(-dir.y, dir.x)
	var h := sqrt(seg * seg - d * d * 0.25)
	var c1 := mid + perp * h
	var c2 := mid - perp * h
	if knee_up:
		return c1 if c1.y > c2.y else c2
	return c1 if c1.x > c2.x else c2


func _draw_tail(m: Dictionary, body: Color, outline: Color) -> void:
	if m.tail < 0.02:
		return
	var raise := 0.15 if m.gait == "hop" else -0.35
	var steps := 10
	var prev := Vector2(-m.L * 0.45, m.cy)
	for s in range(1, steps + 1):
		var t := float(s) / steps
		var pt := Vector2(-m.L * 0.45 - t * m.tail, m.cy + t * t * m.tail * raise)
		var w := lerpf(m.H * 0.35, m.H * 0.05, t) * _scale
		draw_line(_p(prev), _p(pt), outline, maxf(1.5, w + 2.0))
		draw_line(_p(prev), _p(pt), body, maxf(1.0, w))
		prev = pt


func _draw_crest(m: Dictionary, color: Color) -> void:
	if m.crest < 0.02:
		return
	var teeth := 7
	var half: float = m.L * 0.5
	for k in teeth:
		var x0 := lerpf(-half * 0.8, half * 0.6, float(k) / teeth)
		var x1 := lerpf(-half * 0.8, half * 0.6, float(k + 1) / teeth)
		var y0 := _body_top(m, x0)
		var y1 := _body_top(m, x1)
		var tip := Vector2((x0 + x1) * 0.5, maxf(y0, y1) + m.crest)
		draw_colored_polygon(PackedVector2Array([_p(Vector2(x0, y0 - 0.01)), _p(tip), _p(Vector2(x1, y1 - 0.01))]), color)


func _body_top(m: Dictionary, x: float) -> float:
	var u := clampf(x / (m.L * 0.52), -1.0, 1.0)
	return m.cy + m.H * 0.5 * 0.9 * sqrt(1.0 - u * u)


func _draw_head(m: Dictionary, body: Color, outline: Color) -> void:
	var c: Vector2 = m.head_c
	var r: float = m.head_r
	# Fühler hinter dem Kopf
	if m.antenna > 0.02:
		for k in 2:
			var ang := deg_to_rad(55.0 + k * 20.0)
			var base := c + Vector2(cos(ang), sin(ang)) * r * 0.9
			var ctrl: Vector2 = base + Vector2(0.15 + k * 0.1, 0.75) * m.antenna
			var tip: Vector2 = base + Vector2(0.55 + k * 0.15, 0.5) * m.antenna
			var pts := PackedVector2Array()
			for s in 9:
				var t := s / 8.0
				pts.append(_p(base.lerp(ctrl, t).lerp(ctrl.lerp(tip, t), t)))
			draw_polyline(pts, outline, 1.5, true)
	var head_pts := _ellipse_points(c, r, r * 0.9)
	draw_colored_polygon(head_pts, body)
	head_pts.append(head_pts[0])
	draw_polyline(head_pts, outline, 1.5, true)
	# Hörner
	if m.horns > 0 and m.horn_len > 0.01:
		for k in m.horns:
			var ang := deg_to_rad(lerpf(110.0, 55.0, 0.5 if m.horns == 1 else float(k) / (m.horns - 1)))
			var dir := Vector2(cos(ang), sin(ang))
			var base := c + dir * r * 0.85
			var side := Vector2(-dir.y, dir.x) * r * 0.2
			var tip: Vector2 = base + dir.rotated(-0.35) * m.horn_len
			draw_colored_polygon(PackedVector2Array([_p(base + side), _p(tip), _p(base - side)]), HORN_COLOR)
	draw_circle(_p(c + Vector2(r * 0.45, r * 0.2)), maxf(1.5, r * 0.18 * _scale), EYE_COLOR)


## Deterministische Pseudo-Zufallszahl in [0, 1) für Musterpositionen.
func _hash01(n: int) -> float:
	return float(hash(n) % 10007) / 10007.0
