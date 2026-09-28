# Creature Learning

Godot-4-Spiel für Android: Der Spieler lebt in einer Gruppe prozedural erzeugter Kreaturen, erschließt
deren Art und Fähigkeiten durch Beobachtung und weist ihnen in kurzen Aufgaben passende Rollen zu.

**Stand: Meilenstein 1** – Genom und Taxonomie als reine Datenlogik, Unit-Tests, Debug-Viewer.

| Meilenstein | Inhalt | Status |
|---|---|---|
| 1 | Genom, Taxonomie, Tests, Debug-Viewer | ✅ |
| 2 | Prozedurales Mesh, IK-Laufen | – |
| 3 | Welt mit Spatial Gardener, Touch-Kamera | – |
| 4 | Fähigkeiten, Kontext, sichtbares Verhalten | – |
| 5 | Journal, erste Aufgabe | – |
| 6 | Android-Export, Performance | – |

![Debug-Viewer: Konvergenzpaar Stelzus fluvialis / Mimula fallax](docs/images/taxonomy_viewer.png)

## Voraussetzungen

- Godot **4.4.x** (getestet: 4.4.1 stable)
- Test-Framework GUT 9.4.0 liegt bereits unter `addons/gut`

## Starten

Projekt im Godot-Editor öffnen und F5 drücken. Hauptszene ist vorerst der Debug-Viewer
`scenes/debug/taxonomy_viewer.tscn`:

- links: Quelle (Demo-JSON oder generiert), Seed, Regler für die Streuung pro Rang,
  Dimorphismus und Konvergenz, darunter der Taxonomie-Baum (≈ markiert konvergente Taxa)
- rechts oben: Kreaturen des gewählten Taxons (Glyphen in einheitlichem Maßstab)
- rechts unten: Vergleich – Kreaturen antippen (abwechselnd A/B) → Distanz, Aufschlüsselung
  nach Merkmalsgruppen, Gen-Tabelle
- „Export“ schreibt die aktuelle Taxonomie als JSON nach `user://`

`scenes/debug/genome_compare.tscn` ist der eigenständige Vergleichsmodus mit Schnellwahl
(gleiche Art, Gattung, Familie, andere Klasse, Konvergenzpaar, ♂/♀, Alt/Jung).

## Tests

```bash
godot --headless --import                      # einmalig bzw. nach neuen Klassen
godot --headless -s addons/gut/gut_cmdln.gd    # nutzt .gutconfig.json (tests/unit)
```

Screenshot einer Szene (z. B. im Container ohne Bildschirm):

```bash
xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
  -s tools/screenshot.gd -- res://scenes/debug/taxonomy_viewer.tscn out.png 30 select=squamopoda
```

## Inhalte ohne Code erweitern

- Gene: [`docs/genome_parameters.md`](docs/genome_parameters.md) → `data/genome_schema.json`
- Taxa, Dimorphismus, Konvergenz, Generator: [`docs/taxonomy_format.md`](docs/taxonomy_format.md) → `data/taxonomies/`, `data/generator_presets/`
- Architektur und Module: [`docs/architecture.md`](docs/architecture.md)

## Ordnerstruktur

```
addons/gut/            Test-Framework
data/                  Schema, Taxonomien, Generator-Presets (JSON)
docs/                  Dokumentation
scenes/debug/          Debug-Szenen
src/core/              Ränge, Seeds, JSON
src/genome/            Gen-Definitionen, Genom, Distanz
src/taxonomy/          Taxonomie, Loader, Generator, Individuen, Dimorphismus, Konvergenz
src/debug/             Viewer, Glyphen, Vergleich
tests/unit/            GUT-Tests
tools/                 Hilfsskripte (Screenshot)
```
