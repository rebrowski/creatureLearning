# Aufgaben, Journal, Spielstand, Fortschritt

## Aufgaben (`data/tasks/*.json`)

Jede Datei ist eine Aufgabe; **neue Aufgaben brauchen keinen Code**, solange sie mit den
vorhandenen Schritttypen auskommen. Beispiel: [`fruit_over_stream.json`](../data/tasks/fruit_over_stream.json).

| Feld | Bedeutung |
|---|---|
| `id`, `name`, `description` | Kennung und Anzeige |
| `order` | Reihenfolge in der Aufgabenliste |
| `context` | `{"hour": 23.0, "weather": "clear"}` – wird beim Start gesetzt und für die Bewertung verwendet |
| `places` | Ortsnamen → Ortsangabe (siehe unten) |
| `roles` | 2–4 Rollen (siehe unten) |
| `steps` | Ablauf der Wiedergabe (siehe unten) |

### Rollen

| Feld | Bedeutung |
|---|---|
| `id`, `name`, `description` | Kennung und Anzeige |
| `requirements` | `[{ability, weight, zone?, wading?, dark?}]` – gewichtete Fähigkeiten. `zone` bewertet im Kontext dieser Zone (z. B. `tree`, `water`), `dark` bei Dunkelheit, `wading: true` lässt Tiere, die den Bach durchwaten können, als gute Schwimmer zählen (0.85) |
| `threshold` | nötiger Wert (0..1) |
| `requires` | Rollen, die vorher gelingen müssen (sonst „nicht dran gekommen“) |
| `hint_fail`, `hint_close`, `hint_skipped` | Hinweise für die Auswertung – beschreiben, **was** schiefging, nie **wer** es besser könnte |

**Bewertung** (`TaskSimulator`): Rollenwert = gewichteter Mittelwert der Fähigkeiten im Kontext
+ Zufall (σ 0.04, pro Versuch reproduzierbar). Die Aufgabe gelingt, wenn alle Rollen gelingen.
„Knapp“ heißt: weniger als 0.06 von der Schwelle entfernt.

### Orte

| Angabe | Bedeutung |
|---|---|
| `fruit_tree:N` | N-ter Fruchtbaum aus `forest.json` |
| `rock:largest` | größter Felsen |
| `stream_near:<ort>` | Bachpunkt, der dem genannten Ort am nächsten liegt |
| `point:x,z` | feste Koordinate |
| `spawn` | Startbereich der Gruppe |

### Schritte

Jeder Schritt einer Rolle läuft mit deren (vorher berechnetem) Ergebnis als vorgegebenem Ausgang –
die Kreaturen zeigen also sichtbar, woran es lag.

| `type` | Felder | Wirkung |
|---|---|---|
| `climb_tree` | `role`, `place`, `on_success: "drop_fruit"` | klettert; bei Erfolg fällt eine Frucht (`task_fruit`) herunter |
| `pick_up` | `role`, `item` | läuft zum Gegenstand und nimmt ihn auf |
| `cross_stream` | `role`, `place` | durchquert den Bach (schwimmt/watet; Misserfolg: kehrt um) |
| `drop` | `role` | legt den getragenen Gegenstand ab |
| `walk_to` | `role`, `place` | läuft hin (Misserfolg: irrt umher) |
| `behavior` | `role`, `behavior` | zeigt ein Verhalten: `sniff`, `call`, `display`, `dig`, `climb_rock`, `rest` |
| `follow` | `role`, `leader` | alle Beteiligten laufen zur Rolle `leader` (nur bei Erfolg) |
| `wait` | `seconds` | Pause |

Vor dem ersten Schritt versammeln sich die Beteiligten in der Nähe des ersten Ortes.

## Journal

Tippe eine Kreatur an: Karte mit **Markierung** (6 Farben), **eigener Gruppe** („gleiche Art?“),
**Einschätzung** jeder Fähigkeit (– / o / +), **Notiz** und den letzten Beobachtungen. Das Journal
(Knopf oben) listet Kreaturen, Gruppen und das **Protokoll**: Verhaltensweisen, die im Blickfeld
(≤ 28 m von der Kamera) stattfanden, z. B. „Tamo kletterte auf einen Felsen – hat geklappt“.
Das Spiel bewertet das Journal nicht; Rückmeldung gibt es nur über den Erfolg von Aufgaben.
Im Spiel sieht man Namen, nie Artnamen (nur im Debug-Modus).

## Spielstand

`user://save/savegame.json` (Android: privater App-Speicher). Enthält Taxonomie, Gruppe mit
**Genomen**, Journal, Aufgabenfortschritt, Tageszeit und Wetter. Gespeichert wird beim Pausieren
oder Verlassen der App, nach jeder Aufgabe, nach Journal-Änderungen (gebündelt) und alle 60 s.
„Neues Spiel“ im Debug-Modus löscht den Stand.

## Fortschritt (`data/game/progression.json`)

Nach jeder gelösten Aufgabe kommt `recruits_per_success` neue Kreatur(en) dazu (bis
`max_group_size`). Mit `lookalike_chance` wird eine Art gewählt, die einem vorhandenen Mitglied
möglichst ähnlich sieht (Doppelgänger, Nachahmer); oft vertretene Arten werden seltener gewählt.
Namen kommen aus `data/game/names.json`, die Startgruppe aus `data/world/start_group.json`.
