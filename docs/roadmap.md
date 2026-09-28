# Roadmap

Arbeitsweise: Meilensteine nacheinander, jeweils mit Tests, Doku und Screenshot-Prüfung.

## M1 – Genom und Taxonomie ✅
Reine Datenlogik (Schema, Taxonomie, Vererbung, Dimorphismus, Konvergenz, Generator),
GUT-Tests, Debug-Viewer mit 2D-Glyphen und Vergleichsmodus.

## M2 – Prozedurales Mesh und IK-Laufen ✅
- `CreatureMeshBuilder`: ein Mesh pro Kreatur aus dem Genom (Segmente, Kopf, Beine, Hörner,
  Schwanz, Kamm, Fühler), gebunden an ein erzeugtes `Skeleton3D` → ein Draw-Call pro Kreatur.
- Ein gemeinsamer Shader; Farbe und Muster (Streifen/Flecken/Band) als Parameter.
- Analytische 2-Knochen-IK pro Bein, Fuß-Raycasts, Schrittplaner mit Gangart-Tabellen
  (2/4/6/8 Beine; walk/trot/hop/scuttle/slither), Körperhöhe und -neigung aus den Füßen,
  Schwanken, Schwanz- und Rumpfwelle.
- LOD nach Kameradistanz (volle IK / reduzierte IK ohne Raycasts / eingefroren + Low-Poly / aus).
- Testszene `creature_lab.tscn` mit unebenem Boden, allen Bauplänen der Demo und FPS-Anzeige.

## M3 – Welt ✅
Waldszene (Terrain, Bach, Lichtung, Felsen, Bäume mit Früchten), Spatial Gardener 1.4.1 mit
Low-Poly-Platzhaltern (`docs/spatial_gardener.md`), Tag/Nacht, Regen, Terrain-Zonen,
Touch-Kamera, Kreaturen wandern per Navigation.

## M4 – Fähigkeiten, Kontext, Verhalten
- Fähigkeiten als unsichtbare Gene im selben Vererbungsmechanismus, teils an sichtbare Merkmale
  gekoppelt (`derived_from`), Kontext-Modifikatoren (Terrain, Tageszeit, Wetter).
- Leerlauf-Verhalten (klettern, graben, schwimmen …) als Informationsquelle für den Spieler.
- **Diagnostische Unschärfe** (vorgemerkt nach M1-Messung: aktuell trennt fast immer ein
  einzelnes Merkmal zwei Arten zu 100 %):
  1. **Polymorphismus mit Häufigkeiten** pro Taxon, z. B.
     `"morphs": [{"p": 0.8}, {"p": 0.2, "set": {"pattern_type": "none"}}]`, pro Individuum
     reproduzierbar gewürfelt, unabhängig vom Geschlecht.
  2. **Individuelle Streuung pro Art und Gen** (Taxon-Feld für die Individuen-Varianz) und
     Standard-Streuung der Individuen näher an die der Arten, damit Schwesterarten überlappen.
  3. **Diagnose-Werkzeug**: im Vergleichsmodus pro Gen die Trennschärfe zwischen zwei Arten
     (beste Einzelregel in %), plus Tests für Designziele wie „Schwesterarten haben kein
     sichtbares Einzelmerkmal über 90 %“.

## M5 – Journal und erste Aufgabe
Markieren, eigene Gruppen, Notizen; Aufgaben als JSON mit Rollen; Simulation, Abspielen,
Auswertung mit Hinweisen ohne Lösung; neue Gruppenmitglieder inklusive Doppelgänger-Arten.
**Spielstand** (siehe unten) wird hier eingeführt, weil das Journal ihn als Erstes braucht.

## Spielstand (Designregeln, gelten ab sofort)
- Speicherort: lokal, eine versionierte JSON-Datei unter `user://save/` (auf Android im
  privaten App-Speicher, übersteht Neustarts). Kein Server nötig; Cloud-Sync (z. B. Google Play
  Saved Games) ließe sich später auf dieselbe Datei aufsetzen.
- Gespeichert wird automatisch beim Pausieren der App (`NOTIFICATION_APPLICATION_PAUSED`),
  beim Beenden und nach jeder Aufgabe – Android beendet Hintergrund-Apps ohne Vorwarnung.
- **Der Spielstand speichert Daten, nicht nur Seeds:** die verwendete Taxonomie als
  exportiertes JSON und die Genome der Gruppenmitglieder. Grund: Ändert sich später der
  Generator- oder Vererbungscode, würde derselbe Seed andere Kreaturen erzeugen – die
  Kreaturen des Spielers dürfen sich aber nie verändern.
- IDs sind stabil: Taxon-IDs und Kreatur-IDs (`art#nummer`) werden nie umbenannt; sie verbinden
  Journal-Notizen und Kreaturen.
- Inhalt (Skizze): Formatversion, Taxonomie, Gruppe (ID, Genom, Geschlecht, Alter, Position),
  Journal (Markierungen, eigene Gruppen, Notizen), erledigte Aufgaben, freigeschaltete
  Kreaturen, Tageszeit/Wetter, Einstellungen.

## M6 – Android
Export-Preset, Profiling auf dem Gerät (Ziel: 15–20 Kreaturen bei 60 FPS), LOD-Feintuning.
