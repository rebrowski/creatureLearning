# Architektur

## Grundentscheidungen

| Thema | Entscheidung | Grund |
|---|---|---|
| Engine | **Godot 4.4.x** (getestet mit 4.4.1), GDScript | Spatial Gardener 1.4.1 zielt offiziell auf Godot 4.4 (1.4.0 auf 4.3, Minimum 4.2). Ein Upgrade auf 4.5+ erst nach eigenem Test in M3. |
| Renderer | `mobile`, ETC2/ASTC-Import | Zielplattform Android. Debug-Screenshots im Container laufen mit `--rendering-driver opengl3`. |
| Anzeige | 1280×720, `canvas_items`-Stretch, Querformat (Sensor) | Touch-Emulation per Maus ist aktiv. |
| Tests | **GUT 9.4.0** unter `addons/gut` | Reines GDScript, headless per Kommandozeile. |
| Daten | JSON (`data/`) | Von Hand editierbar, diff-freundlich; Loader validieren mit Pfadangabe. |
| Zufall | Nur `RandomNumberGenerator` mit Seeds aus `RngUtil.derive_seed([...])` | Reproduzierbar; pro Gen eigener Seed → neue Gene/Taxa verändern Bestehendes nicht. |

## Schichten

Abhängigkeiten zeigen nur nach unten. Die beiden unteren Schichten sind **node-frei**
(`RefCounted`), dadurch headless testbar und später im Aufgaben-Simulator ohne Szene nutzbar.

```
game / tasks / journal / ui           (M5)  Spielstand, Aufgaben, Journal, Oberfläche
abilities + behaviors                 (M4)  Fähigkeiten, sichtbares Verhalten, Trennschärfe
world: terrain, weather, context, nav (M3)  Waldwelt, Tageszeit, Wetter, Zonen
creature - mesh - locomotion - camera (M2)  Darstellung; kennt nur Genome
taxonomy - individual_factory         (M1)  Taxa, Vererbung, Dimorphismus, Konvergenz
genome - genome_schema - distance     (M1)  Gen-Definitionen, Werte, Distanz
core                                  (M1)  Ränge, Seeds, JSON
```

## Module (Stand M5)

| Datei | Aufgabe |
|---|---|
| `src/core/ranks.gd` | Ränge Klasse … Individuum als ints, Namen, deutsche Labels. |
| `src/core/rng_util.gd` | Seed-Ableitung, Hilfen für Bereiche/Auswahl/Mischen. |
| `src/core/json_loader.gd` | JSON lesen/schreiben mit Zeilenangabe bei Fehlern. |
| `src/genome/gene_def.gd` | Ein Gen: Typ, Bereich, `varies_until`, Mutation, Interpolation, Differenz. |
| `src/genome/genome_schema.gd` | Alle Gene aus `data/genome_schema.json`. |
| `src/genome/genome.gd` | Werte einer Kreatur bzw. eines Taxon-Mittels. |
| `src/genome/genome_distance.gd` | Distanz gesamt / pro Gruppe / pro Gen. |
| `src/taxonomy/taxon.gd`, `taxonomy.gd` | Datenstruktur Baum, Abstammung, gemeinsamer Rang, Export. |
| `src/taxonomy/taxonomy_loader.gd` | JSON → Taxonomy mit Validierung. |
| `src/taxonomy/similarity_settings.gd` | Globale Regler (`spread` pro Rang, Dimorphismus-/Konvergenzstärke). |
| `src/taxonomy/individual_factory.gd` | Mittel-Genome pro Taxon (gecacht) und Individuen. |
| `src/taxonomy/dimorphism.gd`, `convergence.gd` | Regeln für Geschlecht/Alter und Nachahmung. |
| `src/taxonomy/taxonomy_generator.gd` | Zufällige Taxonomien aus Seed + Preset. |
| `src/creature/body_plan.gd` | Aus dem Genom abgeleitete Geometrie (Hüften, Fußruhepunkte, Maße, Tempo). |
| `src/creature/creature_rig.gd` | Knochenaufbau, erzeugt das `Skeleton3D`. |
| `src/mesh/creature_mesh_builder.gd`, `creature.gdshader` | Ein Mesh pro Kreatur (zwei Detailstufen), Farbe/Muster im Shader. |
| `src/locomotion/leg_ik.gd`, `gait_table.gd`, `creature_locomotion.gd` | IK, Schrittmuster, Schrittplaner und Körperhaltung. |
| `src/creature/creature.gd`, `creature_lod.gd` | Node3D einer Kreatur: Bewegung, Bodenhaftung, LOD, Namensschild, Grundflächen-Radius. |
| `src/creature/wander_brain.gd` | Platzhalter-Verhalten (zufällige Ziele) bis M4. |
| `src/camera/orbit_camera.gd` | Touch-Kamera: drehen, zoomen, verschieben, Zwei-Finger-Drehung, Grenzen, folgt Gelände/Kreatur. |
| `src/world/forest_layout.gd` | Layout aus `forest.json`: Höhe und Zone an jeder Position (reine Logik). |
| `src/world/forest_terrain.gd` | @tool: Gelände, Wasser, Felsen, Fruchtbäume aus dem Layout. |
| `src/world/low_poly.gd`, `vegetation_meshes.gd`, `vegetation_scatter.gd` | Low-Poly-Baukasten, Platzhalter-Pflanzen, reproduzierbare Verteilung. |
| `src/world/fruit_tree.gd` | Baum mit Früchten in bestimmter Höhe (für Aufgaben). |
| `src/world/day_night_cycle.gd`, `weather.gd` | Tageszeit und Wetter. |
| `src/world/world_context.gd` | Kontextabfrage für Fähigkeiten/Verhalten. |
| `src/world/forest_navigation.gd` | Navmesh zur Laufzeit (Bach ausgespart). |
| `src/abilities/ability_catalog.gd`, `ability_profile.gd` | Fähigkeiten aus `abilities.json`: Kopplung an sichtbare Gene, Kontextfaktoren. |
| `src/behaviors/behavior_brain.gd`, `*_behavior.gd` | Nutzenbasierte Auswahl und zehn sichtbare Verhaltensweisen. |
| `src/behaviors/nav_mover.gd`, `behavior_effects.gd`, `carry_item.gd` | Wegfolgen mit Abstandhalten (nach Körpergröße, rechts ausweichen, Vortritt lassen), Effekte (Erde, Rufwellen, Löcher …), tragbare Steine. |
| `src/taxonomy/species_diagnostics.gd` | Trennschärfe einzelner Gene zwischen zwei Arten (Designwerkzeug). |
| `src/world/forest_world.gd` | Wurzel der Waldszene: Spielstand, Gruppe, Fremde, Anheuern, Überlappungen auflösen, Beobachtungsprotokoll, Aufgaben, HUD, Hinweis „Aufgabe starten?“. |
| `src/game/game_state.gd`, `group_member.gd` | Spielstand (JSON, mit Genomen), Gruppe, Guthaben, Fremde und Anheuern. |
| `src/game/ui_settings.gd` | Oberflächen-Skalierung (auto nach Bildschirmgröße), Namensschilder, Hinweis an/aus. |
| `src/journal/journal.gd` | Markierungen, eigene Gruppen, Notizen, Einschätzungen, Protokoll. |
| `src/tasks/task_def.gd`, `task_catalog.gd`, `task_simulator.gd`, `task_player.gd` | Aufgaben aus JSON, Bewertung, Wiedergabe mit den echten Kreaturen. |
| `src/ui/*` | Kreaturen-Karte, Journal, Aufgabenwahl, Auswertung, Anheuern, Aufgaben-Hinweis (im Code gebaut, touchfreundlich, passen sich der Bildschirmgröße an). |
| `tools/build_forest.gd` | Erzeugt `forest.tscn` inkl. Spatial-Gardener-Vegetation. |
| `src/debug/*` | Menü, Viewer, 2D-Glyphen, Vergleich, Kreaturen-Labor, Menü-Knopf (Autoload `DebugNav`). |
| `tools/screenshot.gd` | Szene rendern und als PNG speichern (für visuelle Prüfung). |
| `tools/benchmark_creatures.gd` | CPU-Zeit der Kreaturen messen. |

Details zu Mesh, Laufen und LOD: [`creature_rendering.md`](creature_rendering.md).

## Datenfluss einer Kreatur

```
genome_schema.json ──► GenomeSchema ──┐
taxonomy.json ──► TaxonomyLoader ──► Taxonomy ──► IndividualFactory ──► Individual(genome, sex, age)
     (oder TaxonomyGenerator)                         │
                                                      └─ mean_genome(taxon): Klasse → … → Art
```

Später liest der Mesh-Builder (M2) nur `Individual.genome`, die Fähigkeiten (M4) zusätzlich
unsichtbare Gene aus demselben Schema – vererbt über denselben Mechanismus.

## Welt

Details: [`world_format.md`](world_format.md), Vegetation: [`spatial_gardener.md`](spatial_gardener.md),
Fähigkeiten und Verhalten: [`abilities_format.md`](abilities_format.md),
Aufgaben, Journal, Spielstand: [`tasks_format.md`](tasks_format.md).
Abweichung vom ursprünglichen Plan: Zonen werden analytisch aus dem Layout berechnet statt über
Area3D-Knoten – schneller, testbar und ohne doppelte Datenhaltung.
