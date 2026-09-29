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

## M4 – Fähigkeiten, Kontext, Verhalten ✅
- Fähigkeiten als unsichtbare Gene im selben Vererbungsmechanismus, teils an sichtbare Merkmale
  gekoppelt (`derived_from`), Kontext-Modifikatoren (Terrain, Tageszeit, Wetter).
- Leerlauf-Verhalten (klettern, graben, schwimmen …) als Informationsquelle für den Spieler.
- **Diagnostische Unschärfe** (umgesetzt; nach M1 trennte fast immer ein einzelnes Merkmal
  zwei Arten zu 100 %):
  1. **Polymorphismus mit Häufigkeiten** pro Taxon, z. B.
     `"morphs": [{"p": 0.8}, {"p": 0.2, "set": {"pattern_type": "none"}}]`, pro Individuum
     reproduzierbar gewürfelt, unabhängig vom Geschlecht.
  2. **Individuelle Streuung pro Art und Gen** (Taxon-Feld für die Individuen-Varianz) und
     Standard-Streuung der Individuen näher an die der Arten, damit Schwesterarten überlappen.
  3. **Diagnose-Werkzeug**: im Vergleichsmodus pro Gen die Trennschärfe zwischen zwei Arten
     (beste Einzelregel in %), plus Tests für Designziele wie „Schwesterarten haben kein
     sichtbares Einzelmerkmal über 90 %“.

## M5 – Journal und erste Aufgabe ✅
Markieren, eigene Gruppen, Notizen; Aufgaben als JSON mit Rollen; Simulation, Abspielen,
Auswertung mit Hinweisen ohne Lösung; neue Gruppenmitglieder inklusive Doppelgänger-Arten.
**Spielstand** (siehe unten) wird hier eingeführt, weil das Journal ihn als Erstes braucht.

## Spielstand (umgesetzt in M5, siehe docs/tasks_format.md)
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

## M6 – Export und Leistung ✅ (Messung auf echten Geräten steht aus)
Presets für Web (ohne Threads, PWA), Android (arm64) und iOS (vorbereitet, Build auf dem Mac);
GitHub-Actions-Workflow: Tests, Web-Export, Android-APK, GitHub Pages; Grafikstufen,
Leistungsanzeige und Leistungstest im Spiel. Siehe docs/export.md.
Offen: Messung auf Mittelklasse-Handy (Ziel: 15–20 Kreaturen bei 60 FPS), danach LOD-Feintuning.

## M7 – Rückmeldungen aus dem ersten Handy-Test

Entscheidungen: kein Lohn, nur Anheuern mit Startguthaben; erfolgreiche Aufgaben
bringen Guthaben. Startgruppe: 3 Arten à 2 Tiere, davon zwei Doppelgänger-Arten.

- **A – Aufgabenablauf lesbar**: Schritt-Einblendung mit Rolle und Name;
  Scheitern sichtbar (Nicht-Schwimmer zögert am Ufer und weicht zurück,
  schwacher Schwimmer strampelt, treibt ab, verliert die Frucht, die davontreibt);
  ✓/✗ über den Beteiligten am Ende. Fehler behoben: Schwimmhaltung kippte
  senkrecht (Rückkopplung Paddel-Füße ↔ Körperneigung).
- **B – Kein Durchlaufen**: Kreaturen halten Abstand nach Körpergröße
  (Überlappung wird aufgelöst), weichen einander rechts aus und warten kurz.
- **C – Handy-Bedienung**: automatische Oberflächen-Skalierung nach
  Bildschirmgröße (+ Regler „Textgröße“), Namensschilder über den Kreaturen
  (abschaltbar), kleinere Startgruppe, Hinweis „Aufgabe starten?“ nach 20 s ohne Eingabe.
- **D – Guthaben und Anheuern**: Startguthaben, Belohnung pro Aufgabe (vor dem
  Start sichtbar), fremde Kreaturen am Waldrand, die man beobachten und
  anheuern kann; ersetzt das automatische Dazukommen. Werte in
  `data/game/progression.json`.

### 0.7.1 – zweite Runde Handy-Test
- Kreaturen stupsen einander beiseite: Wer läuft oder an einer Aufgabe beteiligt
  ist (`Creature.priority`), umgeht Stehende nicht, sondern schiebt sie weg.
- Beteiligte, die später dran sind, gehen schon während des aktuellen Schritts in
  dessen Nähe; Knopf „» Schneller“ (Zeitraffer ×2.5) während Aufgaben.
- Einschätzung: gewählte Stufe farbig hervorgehoben mit Text (schwach/mittel/stark);
  Debug-Werte als „wahre Werte“ gekennzeichnet.
- Kamera: Nach einer Zwei-Finger-Geste dreht der letzte Finger nicht mehr (kein
  Kippen beim Loslassen); Sprünge einzelner Touch-Ereignisse werden ignoriert,
  flachster Blickwinkel begrenzt.

### 0.7.2
- Während Aufgaben: Knopf „◎ Zur Aufgabe“ bringt die Kamera zur Kreatur, die gerade am Zug ist.
- Kreaturen-Karte: mit ‹ › durch alle Kreaturen blättern (Gruppe, dann Fremde).
