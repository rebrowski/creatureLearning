# Aufgaben, Journal, Spielstand, Guthaben und Anheuern

## Aufgaben (`data/tasks/*.json`)

Jede Datei ist eine Aufgabe; **neue Aufgaben brauchen keinen Code**, solange sie mit den
vorhandenen Schritttypen auskommen. Beispiel: [`fruit_over_stream.json`](../data/tasks/fruit_over_stream.json).

| Feld | Bedeutung |
|---|---|
| `id`, `name`, `description` | Kennung und Anzeige |
| `order` | Reihenfolge in der Aufgabenliste (der Hinweis „Aufgabe starten?“ schlägt die erste ungelöste vor) |
| `reward` | Grundbelohnung in Beeren; vor dem ersten Erfolg × `first_try_factors[bisherige Versuche]` (1. Versuch ×2), danach × `repeat_reward_factor` |
| `unlock_after` | ID einer Aufgabe, die vorher gelungen sein muss (fehlt = von Anfang an frei). So entsteht die Aufgabenkette |
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
| `hint_fail`, `hint_fail_far`, `hint_close`, `hint_skipped` | Hinweise (`hint_fail_far`: statt `hint_fail`, wenn der Wert mehr als 0.2 unter der Schwelle liegt) für die Auswertung – beschreiben, **was** schiefging, nie **wer** es besser könnte |

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

Während ein Schritt läuft, gehen die Beteiligten, die später noch dran sind, schon in
seine Nähe (etwa 2.6 m). Beteiligte haben Vorrang und stupsen andere Kreaturen
beiseite. Der Knopf „» Tempo“ schaltet das Tempo (1×–4×, Pause) auch während Aufgaben, „◎ Zur Aufgabe“
bringt die Kamera zurück zur Kreatur, die gerade am Zug ist.


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

Tippe eine Kreatur an (mit ‹ › blätterst du durch alle Kreaturen): Karte mit **vermuteter Art**
und **Einschätzung** jeder Fähigkeit (– / o / +, farbig mit Text) und den letzten Beobachtungen.
(Markierung und Notiz sind seit 0.8 gestrichen; alte Daten bleiben im Spielstand.) Das Journal
(Knopf oben) listet Kreaturen, Gruppen und das **Protokoll**: Verhaltensweisen, die im Blickfeld
(≤ 28 m von der Kamera) stattfanden, z. B. „Tamo kletterte auf einen Felsen – hat geklappt“ –
auch bei Fremden („Fremdling 3 …“; die Einträge bleiben nach dem Anheuern erhalten).
Das Spiel bewertet das Journal nicht; Rückmeldung gibt es nur über den Erfolg von Aufgaben.
Im Spiel sieht man Namen, nie Artnamen (nur im Debug-Modus).

## Spielstand

`user://save/savegame.json` (Android: privater App-Speicher). Enthält Taxonomie, Gruppe mit
**Genomen**, Journal, Aufgabenfortschritt, Guthaben (`credits`), die Fremden am Waldrand
(`offers`, ebenfalls mit Genom und Preis), Tageszeit und Wetter. Ältere Stände ohne
`credits`/`offers` bekommen beim Laden das Startguthaben und neue Fremde. Gespeichert wird beim Pausieren
oder Verlassen der App, nach jeder Aufgabe, nach Journal-Änderungen (gebündelt) und alle 60 s.
„Neues Spiel“ im Debug-Modus löscht den Stand.

## Aufgabenkette

| # | Aufgabe | Rollen (Hauptfähigkeit) | frei nach |
|---|---|---|---|
| 1 | Frucht vom Baum | Kletterer (Klettern) | – |
| 2 | Frucht über den Bach | Kletterer, Träger (Schwimmen/Waten) | 1 |
| 3 | Trüffelsuche | Spürnase (Wittern), Gräber (Graben) | 2 |
| 4 | Nachts zum großen Felsen | Späher (Nachtsicht), Rufer (Lärm) | 3 |
| 5 | Schwerer Stein | Schlepper (Tragen) | 2 |
| 6 | Lager bewachen | Wächter (Verscheuchen) | 4 |
| 7 | Bach bei Regen | Bote (Schwimmen bei Regen) | 5 |
| 8 | Nachternte | Späher (Nachtsicht), Kletterer | 6 |
| 9 | Große Expedition | Kletterer, Träger, Rufer | 8 |

Fehlt der Gruppe für eine freigeschaltete Aufgabe eine Fähigkeit ganz, sorgt das Spiel dafür,
dass unter den Fremden eine passende Art wartet (`GameState.needed_species`) – keine Sackgassen.

## Einsatz und Erschöpfung

Jeder Versuch kostet `attempt_cost` Beeren Proviant (nie mehr als das Guthaben). Wer in seiner
Rolle scheitert, ist bis zum nächsten Morgen (`morning_hour`) erschöpft und nicht einsetzbar;
über Nacht wachsen auch die Früchte nach. „Optionen → Warten …“ spult zum nächsten Abend bzw.
Morgen vor. Damit lohnt sich Beobachten mehr als Durchprobieren.

## Köder

„Köder“ (1 Beere, `bait_cost`) und dann antippen: an einen **Baumstamm** (wer klettert hinauf?),
in den **Bach** (wer kommt hin – watend, schwimmend, zögernd?) oder auf den **Boden** (nachts:
wer findet die Beere im Dunkeln?). Bis zu drei Kreaturen in der Nähe (14 m) probieren es,
auch Fremde; die Versuche landen im Protokoll.

## Artfragen und Bestimmungsbuch

Nach jeder Aufgabe fragt das Spiel: „Gehören A und B zur selben Art?“ – zuerst die
ähnlichsten Paare (Doppelgänger). Richtig: `species_reward` Beeren, und beide Arten gelten als
**bestimmt**: Das Bestimmungsbuch im Journal zeigt dann ihren wissenschaftlichen Namen und wer
dazugehört. Die Auswertung einer Aufgabe vergleicht außerdem das Ergebnis jeder Rolle mit der
eigenen Einschätzung („passt / passt nicht zu deiner Einschätzung“).

## Fundstellen (`data/world/sites.json`)

Aufgaben mit `site` verbrauchen bei Erfolg eine Einheit ihrer Fundstelle (Früchte am Baum,
Trüffel, Steine) – egal ob du oder die Rivalen sie lösen. Ist nichts mehr da, lässt sich die Aufgabe
erst am nächsten Morgen wieder starten; jeden Morgen wachsen `regrow` Einheiten nach.

## Rivalen und Saisons (`data/game/rivals.json`)

Die Moosläufer leben mit eigenen Arten im Lager am anderen Ufer und spielen nach denselben Regeln
(Einsatz, Belohnung, Erschöpfung, Freischaltungs-Kette, knappe Fundstellen). Sie kennen die wahren
Fähigkeiten nicht: Sie starten mit vorsichtigen Schätzungen (`start_belief`), beobachten gezielt die
Fähigkeiten der nächsten Aufgabe und lernen aus jedem Versuch (`learn`). Ihre Versuche sieht man in
der Welt (die entscheidende Rolle zeigt ihr Verhalten), oben rechts erscheinen Punktestand und
Meldungen. Sie heuern auch Fremde an; eine Art, die du für eine Rolle brauchst, kommt immer nach.

Eine **Saison** dauert `season_days` Spieltage. Punkte = verdiente Belohnungen + Artfragen. Danach
folgt die Schlusswertung; liegt jemand um `adaptive_margin` vorn, schlägt das Spiel eine stärkere
bzw. ruhigere Stufe vor. In der neuen Saison bleiben Gruppe, Journal, Guthaben und freigeschaltete
Aufgaben; die Rivalen beginnen neu, alle Vorräte sind voll, der Erstversuch-Bonus gilt wieder.

| Stufe | Aktion alle | Aufgaben/Tag | Lernrate |
|---|---|---|---|
| gemütlich | 2.5 Spielstunden | 1 | 0.5 |
| normal | 2 Spielstunden | 2 | 0.7 |
| ehrgeizig | 1.2 Spielstunden | 2 | 0.85 |

## Guthaben und Anheuern (`data/game/progression.json`)

Neue Kreaturen kommen nur über **Anheuern** in die Gruppe:

- Ein neues Spiel beginnt mit `start_credits` Beeren und einer kleinen Startgruppe
  (`data/world/start_group.json`: 3 Arten à 2 Tiere, zwei davon Doppelgänger).
- Am Waldrand (etwa 13 m vom Lagerplatz) streifen `offers` **Fremde** umher. Sie verhalten sich
  wie alle anderen – man kann sie beobachten, bevor man zahlt. Ihr Schild zeigt „Fremdling N ·
  Preis“; die Art wird nie angezeigt.
- Preis = `price_base` + `price_per_member` × Gruppengröße ± `price_jitter`, Jungtiere ×
  `juvenile_factor`, gerundet auf 5. Anheuern geht über die Karte des Fremden oder den Knopf
  „Anheuern“; danach bekommt er einen Namen aus `data/game/names.json`.
- Erfolgreiche Aufgaben bringen ihre Belohnung (siehe oben), Misserfolge nichts; jeder
  Versuch kostet den Einsatz. Nach **jeder** Aufgabe wird auf `offers` Fremde aufgefüllt (bis
  `max_group_size` einschließlich der Fremden).
- Mit `lookalike_chance` gehört ein neuer Fremder einer Art an, die einem Mitglied oder
  Fremden möglichst ähnlich sieht (Doppelgänger, Nachahmer); oft vertretene Arten werden
  seltener gewählt. Die Auswahl ist reproduzierbar (Seed der Taxonomie + Zähler).

## Bedienung (`user://settings.cfg`, Abschnitt `ui`)

| Schlüssel | Bedeutung |
|---|---|
| `scale` | `"auto"` oder Faktor 1.0–2.0 für Schrift und Knöpfe („Optionen → Text“). Auto: 656 / kürzere Bildschirmseite in dp (Handy ≈ 1.6, Laptop 1.0) |
| `show_names` | Namensschilder über den Kreaturen („Optionen → Namen“), Standard an |
| `task_prompt` | Hinweis „Eine Aufgabe wartet“ nach 20 s ohne Eingabe (danach alle 90 s), abschaltbar mit „Nicht mehr fragen“ |
| `sound` | Geräusche und Vibration („Optionen → Ton“), Standard an |
