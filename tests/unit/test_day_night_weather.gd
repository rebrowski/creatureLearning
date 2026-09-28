extends GutTest
## Tageszeit und Wetter (ohne Szene).


func test_phases() -> void:
	assert_eq(DayNightCycle.phase_for(2.0), "night")
	assert_eq(DayNightCycle.phase_for(6.0), "dawn")
	assert_eq(DayNightCycle.phase_for(12.0), "day")
	assert_eq(DayNightCycle.phase_for(19.0), "dusk")
	assert_eq(DayNightCycle.phase_for(22.0), "night")


func test_light_level() -> void:
	assert_gt(DayNightCycle.light_level_for(12.0, 0.0), 0.9)
	assert_lt(DayNightCycle.light_level_for(0.0, 0.0), 0.15)
	assert_lt(DayNightCycle.light_level_for(12.0, 1.0), DayNightCycle.light_level_for(12.0, 0.0), "Wolken dämpfen")
	assert_gt(DayNightCycle.sun_direction(12.0).y, 0.9)
	assert_lt(DayNightCycle.sun_direction(0.0).y, 0.0)


func test_time_advances_and_wraps() -> void:
	var dn := DayNightCycle.new()
	add_child_autofree(dn)
	dn.day_length_seconds = 24.0  # 1 s = 1 h
	dn.hour = 23.5
	var phases := []
	dn.phase_changed.connect(func(p): phases.append(p))
	dn.advance(1.0)
	assert_almost_eq(dn.hour, 0.5, 0.001)
	dn.advance(6.0)
	assert_almost_eq(dn.hour, 6.5, 0.001)
	assert_true(phases.has("dawn"))
	dn.time_scale = 0.0
	dn.advance(10.0)
	assert_almost_eq(dn.hour, 6.5, 0.001, "angehalten")


func test_weather_is_reproducible_and_smooth() -> void:
	var runs := []
	for n in 2:
		var w := Weather.new()
		w.seed_value = 5
		w.durations = Vector2(1.0, 2.0)
		add_child_autofree(w)
		var states := []
		w.weather_changed.connect(func(s): states.append(s))
		for i in 600:
			w.step(0.05)
			assert_between(w.rain, 0.0, 1.0)
			assert_between(w.wetness, 0.0, 1.0)
		runs.append(states)
	assert_eq(runs[0], runs[1], "gleicher Seed -> gleicher Wetterverlauf")
	assert_gt(runs[0].size(), 3)


func test_rain_makes_wet_and_cloudy() -> void:
	var dn := DayNightCycle.new()
	add_child_autofree(dn)
	var w := Weather.new()
	w.auto_change = false
	w.day_night = dn
	add_child_autofree(w)
	w.set_state("rain")
	for i in 400:
		w.step(0.1)
	assert_gt(w.rain, 0.9)
	assert_gt(w.wetness, 0.5)
	assert_gt(dn.cloudiness, 0.8)
	w.set_state("clear")
	for i in 400:
		w.step(0.1)
	assert_lt(w.rain, 0.1)
	assert_lt(w.wetness, 0.9, "trocknet ab")
