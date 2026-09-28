# Fähigkeiten und Verhalten

## Grundidee

Fähigkeiten sind **unsichtbare Gene** im selben Schema wie das Aussehen (`data/genome_schema.json`,
Gruppe `ability`, `visible: false`). Sie werden deshalb genauso über die Taxonomie vererbt,
streuen genauso und lassen sich pro Taxon mit `set`/`shift`/`variance` festlegen. Der Spieler
sieht sie nie direkt – nur das **Verhalten**, das aus ihnen folgt.

Ein Teil jeder Fähigkeit ist an sichtbare Merkmale gekoppelt (lange Beine → gut im Wasser),
ein Teil nicht (Nachtsicht ist gar nicht gekoppelt).

## `data/abilities/abilities.json`

```jsonc
{ "id": "swim", "name": "Schwimmen",
  "derived_from": [ { "gene": "leg_length", "weight": 0.25 }, { "gene": "tail_length", "weight": 0.1 } ],
  "context": { "night": 0.85 } }
```

| Feld | Bedeutung |
|---|---|
| `id` | muss einem unsichtbaren Gen im Schema entsprechen |
| `name`, `description` | Anzeige |
| `derived_from` | Kopplung: `wert += weight × (normierter Genwert − 0.5) × 2`, also höchstens ±weight |
| `context.zones` | Faktor je Zone (`water`, `bank`, `rock`, `tree`, `clearing`, `forest`), `default` für alle übrigen |
| `context.night` / `day` | Faktor nachts / tagsüber |
| `context.rain` | Faktor bei vollem Regen (dazwischen interpoliert) |
| `context.wetness` | `× (1 + wetness × Nässe)`, negativ = Nässe schadet |
| `darkness_only` | zählt nur bei Dunkelheit (bei Tageslicht Wert 1) |

**Wert im Einsatz** = clamp(Gen + Kopplung, 0, 1) × Kontextfaktor. Den Kontext liefert
`WorldContext.sample(pos)`. Neue Fähigkeit: Gen im Schema anlegen (`group: "ability"`,
`visible: false`) und Eintrag hier ergänzen; ein sichtbares Verhalten braucht dann noch eine
Verhaltensklasse (Code).

Aktuell: climb, swim, dig, carry, noise, night_vision, scent, scare.

## Verhalten (`src/behaviors/`)

Das `BehaviorBrain` jeder Kreatur wählt laufend ein Verhalten nach Nutzen:
`utility(Kontext) × Zufall(0.6..1.4) × Abkühlung`. Tiere zeigen vor allem, was sie gut können,
probieren aber auch Schwaches und **scheitern dann sichtbar** – das ist die Information für den
Spieler.

| Verhalten | Fähigkeit | Gut | Schlecht |
|---|---|---|---|
| Felsen klettern | climb | erreicht die Spitze, sitzt dort | rutscht auf halber Höhe ab (glatte Felsen schwerer) |
| Baum klettern | climb | klettert am Stamm bis zu den Früchten | fällt nach kurzer Strecke herunter |
| Bach durchqueren | swim | schwimmt zügig hinüber | liegt tief im Wasser, kehrt um; langbeinige Tiere **waten** unabhängig vom Schwimmen |
| Graben | dig | viel Erde, großes Loch (Ufer besser, Fels unmöglich) | wenig Erde, kleines Loch |
| Stein tragen | carry | trägt schwere Steine (große auf dem Rücken) | zerrt vergeblich, gibt auf |
| Rufen | noise | große Schallwellen (Regen dämpft) | kleine Wellen |
| Wittern | scent | findet danach zielstrebig einen Fruchtbaum | gibt die Suche auf |
| Ruhen | night_vision | nachts aktiv, **Augen leuchten** im Dunkeln | schläft nachts |
| Drohen | scare | richtet sich auf, plustert sich stark auf | kaum Wirkung |
| Umherstreifen | – | Standard | |

Jedes Verhalten schreibt sein Ergebnis (`success`/`fail`) in `BehaviorBrain.history` – die
Grundlage für Beobachtung und Journal (M5).

### `data/abilities/behaviors.json` – Tuning ohne Code

| Feld | Bedeutung |
|---|---|
| `weight` | Grundgewicht im Nutzenvergleich |
| `cooldown` | Sekunden, in denen das Verhalten danach nur mit 25 % Nutzen gewählt wird |
| `max_time` | Abbruch nach Sekunden |

## Diagnostische Unschärfe

Damit Aussehen allein nicht reicht (siehe Messung nach M1):

- **Polymorphismus** (`morphs` im Taxon): Varianten mit Häufigkeit, z. B. 20 % ungefleckte
  Fleckenweber.
- **Individuen-Streuung pro Taxon** (`individual_variance`, auch `"*"` für alle Gene) und
  Platzhalter-Varianz (`variance: {"*": …}`) für Doppelgänger-Arten.
- **Trennschärfe** (`SpeciesDiagnostics`, im Vergleichsmodus angezeigt): beste Einzelregel pro
  Gen in %. Designziele als Tests: Bach- und Nacht-Stelzer < 80 % (aktuell 64 %); der Nachahmer
  *Mimula fallax* ist am Aussehen < 95 %, an der Bewegung > 90 % erkennbar.

## Performance (Stand M4)

16 Kreaturen mit Verhaltensgehirn, alle auf voller LOD-Stufe, 30 s direkt getaktet
(Xeon 2.8 GHz): 0.9 ms pro Frame im Mittel, 95 % unter 2.0 ms; einzelne Spitzen bis ~6 ms
beim Planen neuer Wege. Messung auf dem Gerät folgt in M6.
