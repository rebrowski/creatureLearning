# Welt-Format (`data/world/`)

## `forest.json` – Layout der Waldwelt

Quelle der Wahrheit für Gelände, Bach, Lichtung, Felsen, Fruchtbäume und Vegetationsregeln.
Koordinaten in Metern, `(0, 0)` = Weltmitte, `[x, z]`. Änderungen wirken beim nächsten Laden
(im Editor: Knoten *Terrain* → „Rebuild Now“). Vegetation danach neu verteilen:
`godot --headless -s tools/build_forest.gd -- --regrow`.

| Feld | Bedeutung |
|---|---|
| `seed` | Basis für Geländerauschen, Felsformen, Vegetationsverteilung. |
| `size` | `[Breite, Tiefe]` der Welt; das Gelände ist ein 1-m-Raster. |
| `terrain.noise_amplitude`, `noise_scale` | Grundwelligkeit des Bodens (Meter, Frequenz). |
| `terrain.hills[]` | `{pos, radius, height}` – weiche Hügel. |
| `stream.points` | Mittellinie des Bachs (≥ 2 Punkte, leer = kein Bach). |
| `stream.width`, `depth`, `bank` | Wasserbreite, Tiefe des Bachbetts, Breite des Uferstreifens. |
| `clearing` | `{pos, radius, flatten}` – Lichtung, `flatten` 0..1 ebnet den Boden ein. |
| `rocks[]` | `{pos, size, climbable}` – Felsen mit Kollision; `climbable` für Kletter-Verhalten (M4). |
| `fruit_trees[]` | `{pos, height, fruits, fruit_height}` – Bäume mit Früchten in `fruit_height` Metern Höhe. |
| `spawn` | `{pos, radius}` – Startbereich der Gruppe, zugleich Zentrum des Umherstreifens. |
| `vegetation[]` | Verteilungsregeln, siehe unten. |

### Zonen

`zone_at(x, z)` liefert (in dieser Priorität): `water`, `bank`, `rock`, `tree`, `clearing`,
`forest`, `outside`. Zonen steuern Bodenfarbe, Vegetation und später Fähigkeiten/Verhalten
(über `WorldContext.sample(pos)`).

### Vegetationsregeln

| Feld | Bedeutung |
|---|---|
| `plant` | Pflanze aus `VegetationMeshes.PLANTS`: tree_pine, tree_round, bush, fern, grass, reed, stone |
| `density` | Kandidaten pro m² (über die ganze Welt; nur Treffer in erlaubten Zonen bleiben) |
| `zones` | erlaubte Zonen |
| `min_spacing` | Mindestabstand innerhalb der Regel (0 = keiner) |
| `scale` | `[min, max]` Skalierung |
| `clear_radius` | freier Abstand zu Felsen, Fruchtbäumen und Wasser |

LOD- und Schatten-Einstellungen pro Pflanze stehen in `tools/build_forest.gd` (`PLANT_LOD`).

## `start_group.json` – Startgruppe

```json
{ "taxonomy": "res://data/taxonomies/forest_demo.json",
  "members": [ { "species": "stelzus_fluvialis", "index": 0 }, ... ] }
```

Jede Kreatur ist Art-ID + laufende Nummer (reproduzierbar aus der Taxonomie). Ab M5 kommt die
Gruppe aus dem Spielstand (siehe `docs/roadmap.md`, Abschnitt Spielstand).

## Laufzeit-Komponenten (`scenes/world/forest.tscn`)

| Knoten | Aufgabe |
|---|---|
| `Terrain` (`ForestTerrain`, @tool) | baut Gelände (Mesh + HeightMap-Kollision), Wasser, Felsen, Fruchtbäume aus dem Layout |
| `Gardener` | Spatial-Gardener-Vegetation (siehe `docs/spatial_gardener.md`) |
| `Navigation` (`ForestNavigation`) | backt beim Start das Navmesh (~130 ms), Bach ausgespart |
| `DayNight` (`DayNightCycle`) | Stunde 0..24, Tag = 8 min Echtzeit, Sonne/Mond/Himmel, `light_level()` |
| `Weather` (`Weather`) | clear/cloudy/rain, reproduzierbarer Verlauf, Regenpartikel, `rain`, `wetness` |
| `WorldContext` | `sample(pos)` → Zone, Höhe, Wasser, Fels/Baum in der Nähe, Stunde, Phase, Licht, Wetter, Nässe |
| `Camera` (`OrbitCamera`) | Touch-Kamera: Ziehen drehen, Pinch zoomen, zwei Finger verschieben/drehen, Tippen wählt |
| `Creatures` | Startgruppe mit `NavWanderBrain` (Platzhalter-Verhalten bis M4) |
