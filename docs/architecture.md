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
tasks / journal / progression         (M5)  Spiellogik
abilities + behaviors  <- world_context (M4/M3) Fähigkeiten, Kontext (Zeit, Wetter, Terrain)
creature - mesh - locomotion - camera (M2)  Darstellung; kennt nur Genome
taxonomy - individual_factory         (M1)  Taxa, Vererbung, Dimorphismus, Konvergenz
genome - genome_schema - distance     (M1)  Gen-Definitionen, Werte, Distanz
core                                  (M1)  Ränge, Seeds, JSON
```

## Module (Stand M2)

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
| `src/creature/creature.gd`, `creature_lod.gd` | Node3D einer Kreatur: Bewegung, Bodenhaftung, LOD. |
| `src/creature/wander_brain.gd` | Platzhalter-Verhalten (zufällige Ziele) bis M4. |
| `src/camera/orbit_camera.gd` | Orbit-Kamera mit Maus und Touch. |
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

## Ausblick: Spatial Gardener (M3)

Geprüft am 28.09.2026: Releases v1.4.1 (Godot 4.4) und v1.4.0 (Godot 4.3, Breaking Changes
gegenüber 1.3.x, neues LOD-System). Einrichtung: Ordner `addons/dreadpon.spatial_gardener/` aus
dem Release nach `res://addons/` kopieren und unter Projekt → Projekteinstellungen → Plugins
aktivieren. Mobile-Eignung ist nicht dokumentiert – wird in M3 mit Low-Poly-Platzhaltern und
Distanz-Culling gemessen. Details folgen in `docs/spatial_gardener.md`.
