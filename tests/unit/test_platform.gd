extends GutTest
## Grafikstufen, Leistungsmessung, Export-Voraussetzungen.


func after_all() -> void:
	GraphicsSettings.apply("high", null, null)


func test_graphics_presets() -> void:
	var sun := DirectionalLight3D.new()
	add_child_autofree(sun)
	GraphicsSettings.apply("low", sun, null)
	assert_false(sun.shadow_enabled)
	assert_lt(CreatureLOD.thresholds[0], 14.0)
	GraphicsSettings.apply("high", sun, null)
	assert_true(sun.shadow_enabled)
	assert_eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	assert_almost_eq(CreatureLOD.thresholds[0], 14.0, 0.001)
	assert_eq(GraphicsSettings.next_level("high"), "low")


func test_perf_monitor() -> void:
	var p := PerfMonitor.new()
	for i in 5:
		p.tick()
	var st := p.stats()
	assert_true(st.has("avg") and st.has("p95") and st.has("max"))
	assert_gte(st.max, st.p95)


func test_export_presets_exist() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	var names := []
	for s in cfg.get_sections():
		if cfg.has_section_key(s, "name"):
			names.append(cfg.get_value(s, "name"))
	for n in ["Web", "Android", "iOS"]:
		assert_true(names.has(n), n)
	assert_false(cfg.get_value("preset.0.options", "variant/thread_support"), "Web ohne Threads (einfaches Hosting)")


func test_data_files_are_exported() -> void:
	# JSON-Daten sind keine Godot-Ressourcen und müssen per include_filter mit exportiert werden
	var cfg := ConfigFile.new()
	cfg.load("res://export_presets.cfg")
	for s in ["preset.0", "preset.1", "preset.2"]:
		assert_string_contains(cfg.get_value(s, "include_filter"), "data/")
