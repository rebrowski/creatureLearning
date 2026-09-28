# Taxonomie-Format

Taxonomien sind JSON-Dateien unter `data/taxonomies/`. Sie können von Hand geschrieben oder vom
Generator erzeugt und exportiert werden (Debug-Viewer → „Export“ schreibt nach `user://`). Beide
Wege ergeben dasselbe Format. Vollständiges Beispiel: [`forest_demo.json`](../data/taxonomies/forest_demo.json).

**Neue Taxa brauchen keine Code-Änderung.** Beim Laden wird alles geprüft; Fehlermeldungen nennen
den genauen Pfad, z. B.
`forest_demo.json: taxa[0] (chitinopoda).children[1] (octopodida).set: unbekanntes Gen 'legcount'`.

## Aufbau

```jsonc
{
  "format": "creature_taxonomy/1",
  "name": "Waldgruppe (Demo)",
  "seed": 20260928,              // Basis aller Zufallswerte; anderer Seed = andere Abweichungen
  "notes": "Freitext",
  "similarity": { ... },         // optional, siehe unten
  "taxa": [ <Klasse>, <Klasse>, ... ]
}
```

Die Taxa sind verschachtelt: Klasse → `children` (Ordnungen) → Familien → Gattungen → Arten.
Arten haben keine Kinder. Einzelne Kreaturen stehen **nicht** in der Datei; sie werden aus
`(seed, Art-ID, Nummer)` erzeugt.

## Felder eines Taxons

| Feld | Bedeutung |
|---|---|
| `id` | **Pflicht**, eindeutig in der ganzen Datei. Bestimmt die Zufallswerte – umbenennen ändert das Aussehen! |
| `rank` | Optional (wird aus der Tiefe abgeleitet), aber wenn angegeben, muss er passen: `class`, `order`, `family`, `genus`, `species`. |
| `name` | Wissenschaftlicher Name (Anzeige). Standard: `id`. |
| `common_name` | Deutscher Name (Anzeige). |
| `set` | `{gen: wert}` – ersetzt den geerbten Wert. Auf diesem Rang kein Zufall für diese Gene; tiefere Ränge weichen wieder ab (außer mit `fixed`). Enum-Werte als Name, z. B. `"gait": "hop"`. |
| `shift` | `{gen: zahl}` – addiert eine feste Verschiebung (absolute Einheiten), danach kommt der normale Zufall. Nicht für enum-Gene. |
| `variance` | `{gen: zahl}` – eigene Streuung für diesen Rang als Bruchteil des Wertebereichs (0.1 = 10 %), statt `base_variance`. Bei enum-Genen: Wechselwahrscheinlichkeit. `0` = auf diesem Rang keine Abweichung. `"*"` gilt für alle nicht genannten Gene (z. B. `{"*": 0.01}` für Doppelgänger-Arten). |
| `individual_variance` | `{gen: zahl}` – Streuung der **Individuen** (statt `base_variance.individual`), gilt für den ganzen Teilbaum; `"*"` = alle übrigen Gene. Große Werte machen Merkmale innerhalb der Art unzuverlässig. |
| `morphs` | Polymorphismus: `[{"name", "p", "set", "shift", "scale"}]` – jedes Individuum würfelt eine Variante (Summe der `p` ≤ 1, Rest = keine Variante). Beispiel: `[{"name": "ungefleckt", "p": 0.2, "set": {"pattern_type": "none"}}]` |
| `fixed` | `["gen", ...]` – diese Gene weichen ab hier im ganzen Teilbaum (inklusive Individuen) nicht mehr zufällig ab. Ein explizites `set`/`shift` weiter unten wirkt trotzdem. Typisch für Baupläne: `"fixed": ["leg_count", "segment_count"]` auf der Klasse. |
| `dimorphism` | Geschlechts-/Altersunterschiede, siehe unten. |
| `convergence` | Oberflächliche Ähnlichkeit zu einem nicht verwandten Taxon, siehe unten. |
| `children` | Liste der Kind-Taxa. |
| `notes` | Freitext. |

Unbekannte Felder erzeugen nur eine Warnung.

### Regeln, die der Loader prüft

- Gen-IDs müssen im Schema existieren, Werte gültig sein (Werte außerhalb des Bereichs → Warnung und Begrenzung).
- `set`, `shift`, `variance` dürfen nur Gene verwenden, die auf diesem Rang noch variieren dürfen
  (`varies_until` im Schema). Beispiel: `leg_count` ist ab Familie fixiert, also nur auf Klasse
  oder Ordnung setzbar.
- IDs eindeutig, Rangfolge korrekt, Arten ohne Kinder.
- Konvergenz-Ziele existieren, sind weder Vorfahre noch Nachkomme, keine Zyklen.

## Dimorphismus

```jsonc
"dimorphism": {
  "male":     { "shift": { "horn_length": 0.3, "crest_height": 0.2 } },
  "female":   { "set":   { "horn_count": 0 } },
  "juvenile": { "scale": { "body_length": 0.55, "leg_length": 0.8 }, "shift": { "head_size": 0.08 } }
}
```

- Stufen: `male`, `female`, `juvenile`. Erwachsene bekommen die Regeln ihres Geschlechts,
  Jungtiere nur `juvenile` (kein Geschlechtsunterschied).
- Operationen, in dieser Reihenfolge: `scale` (multiplizieren), `shift` (addieren), `set` (ersetzen).
- Regeln werden vererbt: eine Art sammelt die Regeln aller Vorfahren; feinere Ränge überschreiben
  gröbere pro Gen und Operation. Typisch: `juvenile` auf der Klasse, Geschlechtsunterschiede auf
  Gattung oder Art.
- Dimorphismus darf auch fixierte Gene ändern (z. B. Larven ohne Beine: `"juvenile": {"set": {"leg_count": 0}}`).
- Regler `dimorphism_strength` blendet alles stufenlos aus (0) oder verstärkt es (bis 2).

## Konvergenz

```jsonc
"convergence": {
  "target": "stelzus_fluvialis",                       // Vorbild (beliebiges Taxon)
  "groups": ["proportion", "appendage", "color", "pattern"],  // Gen-Gruppen …
  "genes":  ["tail_length"],                           // … und/oder einzelne Gene
  "strength": 0.85                                     // 0..1, Anteil der Annäherung
}
```

Das Mittel-Genom des Taxons wird in den genannten sichtbaren Genen um `strength` Richtung
Mittel-Genom des Vorbilds gezogen – für alle Nachkommen. Gene, die auf dem Rang des Taxons
schon fixiert sind (z. B. `leg_count` bei einer Art), bleiben unverändert. Für eine überzeugende
Täuschung muss der Bauplan daher schon auf höherem Rang passen – im Demo setzt die Ordnung
*Hexasquamida* dafür sechs Beine und drei Segmente. Regler `convergence_strength` skaliert alle
Konvergenzen.

## `similarity` – globale Regler

Alle Felder optional; fehlende behalten ihren Standard.

```jsonc
"similarity": {
  "spread":        { "class": 1, "order": 1, "family": 1, "genus": 1, "species": 1, "individual": 1 },
  "base_variance": { "class": 0.2, "order": 0.12, "family": 0.08, "genus": 0.06, "species": 0.04, "individual": 0.03 },
  "dimorphism_strength": 1.0,
  "convergence_strength": 1.0,
  "enum_switch_factor": 2.0
}
```

`spread` sind die Hauptregler: `species` steuert, wie stark sich Arten einer Gattung unterscheiden,
`individual` die Streuung innerhalb einer Art. `0` schaltet die Abweichung auf dem Rang ab.

Fähigkeiten (unsichtbare Gene wie `swim`, `night_vision`) werden genauso mit `set`/`shift`
festgelegt, siehe [`abilities_format.md`](abilities_format.md).

## Neues Taxon hinzufügen – Beispiel

Eine neue Art in der Gattung *Tessella*, dunkel, mit weniger Flecken und Männchen mit Kamm:

```json
{
  "id": "tessella_nigra", "rank": "species", "name": "Tessella nigra", "common_name": "Rußweber",
  "set": { "brightness": 0.2, "pattern_density": 2 },
  "dimorphism": { "male": { "shift": { "crest_height": 0.15 } } }
}
```

In `children` von `tessella` einfügen, Viewer starten (oder Tests laufen lassen) – fertig.

## Generator-Presets

`data/generator_presets/*.json` steuern `TaxonomyGenerator` (Seed im Viewer wählbar):

| Feld | Bedeutung |
|---|---|
| `classes` | Anzahl Klassen. |
| `children_per_rank` | `{rang: [min, max]}` Kinder pro Taxon für `order`, `family`, `genus`, `species`. |
| `similarity` | wie oben, wird in die erzeugte Taxonomie übernommen. |
| `juvenile` | `chance` pro Klasse, `scale`/`shift`: `{gen: [min, max]}` Bereiche für Jungtier-Regeln. |
| `sexual` | `chance` pro Gattung, `genes_per_taxon: [min, max]`, `male`/`female` → `shift: {gen: [min, max]}`. |
| `convergence` | `pairs` (Anzahl), `strength: [min, max]`, `groups`, `require_matching_bodyplan` (bevorzugt Paare mit gleichem fixiertem Bauplan). Paare stammen immer aus verschiedenen Ordnungen, bevorzugt Klassen. |
| `names` | `syllables`, `suffix` pro Rang (String oder Liste), `epithets` für Artnamen. |

Gleicher Seed + gleiches Preset → identische Taxonomie. Ein Export der generierten Taxonomie lädt
wieder zu exakt denselben Kreaturen.
