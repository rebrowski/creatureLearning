# Spatial Gardener

Plugin für Vegetation: <https://github.com/dreadpon/godot_spatial_gardener> (MIT-Lizenz, liegt
unter `addons/dreadpon.spatial_gardener/`).

## Kompatibilität (geprüft 28.09.2026)

| Plugin | Godot | Bemerkung |
|---|---|---|
| **1.4.1 (verwendet)** | 4.4 | Kompatibilitäts-Update, keine großen Änderungen |
| 1.4.0 | 4.3 | Breaking Changes (Transform-/LOD-Überarbeitung) gegenüber 1.3.x |
| 1.3.3 | 4.2.2 | 1.3.2 hatte einen Datenverlust-Fehler – nicht verwenden |

Mit Godot 4.4.1 lädt das Plugin ohne Fehler oder Warnungen (Editor und Laufzeit, headless und
mit Compatibility-Renderer getestet). Vor einem Godot-Upgrade (4.5+) zuerst prüfen, ob eine
passende Plugin-Version existiert.

## Einrichtung

1. Ordner `addons/dreadpon.spatial_gardener/` aus dem Release nach `res://addons/` kopieren
   (hier bereits erledigt).
2. Projekt → Projekteinstellungen → Plugins → „Spatial Gardener“ aktivieren (bereits aktiv).
3. Ein `Gardener`-Knoten braucht ein Arbeitsverzeichnis (`garden_work_directory`) für
   `greenhouse.tres` (Pflanzendefinitionen) und `toolshed.tres` (Pinsel). Hier:
   `res://scenes/world/forest_garden/`. Die Platzierungen (Octree) speichert der Gardener in
   der Szene selbst.

## Wie die Vegetation entsteht

`tools/build_forest.gd` erzeugt die Vegetation reproduzierbar aus den Regeln in
`data/world/forest.json`:

1. Low-Poly-Meshes (`VegetationMeshes`) werden nach `assets/vegetation/*.tres` gespeichert.
2. `VegetationScatter` verteilt Pflanzen nach Zonen, Dichte und Abständen.
3. Pro Pflanze wird im Gardener eine Pflanzendefinition angelegt (LOD-Distanzen aus
   `PLANT_LOD`) und die Transformationen werden in seinen Octree geladen.

```bash
godot --headless -s tools/build_forest.gd              # Szene erzeugen, falls nicht vorhanden
godot --headless -s tools/build_forest.gd -- --regrow  # nur Vegetation neu verteilen
godot --headless -s tools/build_forest.gd -- --force   # ganze Szene neu erzeugen
```

Danach kann man im Editor mit den Gardener-Pinseln weiter malen oder radieren (Szene öffnen,
Knoten *Gardener* wählen, Pflanze in der Seitenleiste aktivieren, auf dem Gelände malen).
Achtung: `--regrow` ersetzt handgemalte Vegetation.

### Stolperfallen, die das Build-Tool umgeht

- Ohne Editor fehlt das Undo/Redo-System: `Arborist.batch_add_instances()` wirft Fehler im
  abschließenden Undo-Schritt. Das Tool fügt Instanzen deshalb direkt über den Stroke-Handler
  hinzu (`_batch_add`).
- `Gardener.save_greenhouse()` speichert nicht, wenn die Ressource schon geladen ist (verlässt
  sich auf Strg+S im Editor) – das Tool speichert `greenhouse.tres` direkt.
- Die Debug-Zeichnung des Stroke-Handlers braucht den Editor und wird im Tool per
  Projekteinstellung abgeschaltet.
- `add_plant_from_dict()` erwartet ein vollständiges Dictionary – das Tool startet mit
  `Greenhouse_PlantState.new().ifr_to_dict(true)` und überschreibt nur einzelne Werte.

## Mobile-Einstellungen

- Platzhalter-Meshes haben 20–700 Vertices, ein gemeinsames Material mit Vertexfarben.
- Gras, Farn, Schilf und Steine werfen keine Schatten; Ausblenddistanzen: Gras 26 m, Farn 35 m,
  Büsche 50 m, Bäume 90 m.
- Aktuell ~2 900 Pflanzen auf 64 × 64 m. Draw-Calls der Szene im Container: ~130 bei Tag
  (inkl. Schatten), ~80 nachts. Feintuning (Octree-Kapazität, Distanzen) folgt in M6 auf dem Gerät.
