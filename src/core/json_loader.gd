class_name JsonLoader
extends RefCounted
## Liest und schreibt JSON-Dateien mit verständlichen Fehlermeldungen.


## Liefert {"data": Variant, "error": String}. `error` ist leer bei Erfolg.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"data": null, "error": "Datei nicht gefunden: %s" % path}
	var text := FileAccess.get_file_as_string(path)
	return parse(text, path)


## Wie `read`, aber aus einem String. `source` erscheint in Fehlermeldungen.
static func parse(text: String, source := "<string>") -> Dictionary:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return {
			"data": null,
			"error": "%s: JSON-Fehler in Zeile %d: %s" % [source, json.get_error_line(), json.get_error_message()],
		}
	return {"data": json.data, "error": ""}


static func write(path: String, data: Variant) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "  ", false, true))
	return OK
