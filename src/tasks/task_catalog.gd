class_name TaskCatalog
extends RefCounted
## Alle Aufgaben aus data/tasks/ (jede *.json-Datei eine Aufgabe), sortiert nach "order".

const DIR := "res://data/tasks"

var tasks: Array[TaskDef] = []
var errors: PackedStringArray = []


static func load_dir(catalog: AbilityCatalog, dir: String = DIR) -> TaskCatalog:
	var c := TaskCatalog.new()
	var files := DirAccess.get_files_at(dir)
	for f in files:
		if not f.ends_with(".json"):
			continue
		var path := dir.path_join(f)
		var res := JsonLoader.read(path)
		if res.error != "":
			c.errors.append(res.error)
			continue
		var t := TaskDef.from_dict(res.data, catalog, path)
		if t.is_valid():
			c.tasks.append(t)
		else:
			c.errors.append_array(t.errors)
	c.tasks.sort_custom(func(a, b): return a.order < b.order)
	return c


func get_task(id: String) -> TaskDef:
	for t in tasks:
		if t.id == id:
			return t
	return null
