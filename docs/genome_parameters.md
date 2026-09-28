# Genom-Parameter

Alle Gene stehen in [`data/genome_schema.json`](../data/genome_schema.json). Diese Seite erklärt die
Felder und listet den aktuellen Stand. **Neue Gene brauchen keine Code-Änderung**: Eintrag in der
JSON-Datei ergänzen, fertig. Bestehende Kreaturen behalten dabei exakt ihre Werte, weil jedes Gen
seinen eigenen Zufalls-Seed hat (`Welt-Seed | Taxon-ID | Gen-ID`). Die Reihenfolge in der Datei
beeinflusst nur die Anzeige.

> Hinweis: Neue Gene wirken erst sichtbar, wenn ein System sie liest (Glyph/Mesh-Builder ab M2,
> Fähigkeiten ab M4). Für Taxonomie, Distanz und Vererbung gelten sie sofort.

## Felder einer Gen-Definition

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `id` | ja | Eindeutiger Name, wird in Taxonomien verwendet. |
| `type` | nein (`float`) | `float`, `int` oder `enum`. |
| `min`, `max` | bei float/int | Wertebereich. Werte werden darauf begrenzt. |
| `step` | nein (1) | Nur `int`: Raster ab `min` (z. B. Beinzahl in Zweierschritten). |
| `options` | bei enum | Liste der erlaubten Namen. In JSON als Name oder Index angebbar. |
| `default` | nein (`min` bzw. erste Option) | Startwert, bevor die Klasse etwas verändert. |
| `group` | nein (`misc`) | Merkmalsgruppe. Die Distanz wird zusätzlich pro Gruppe ausgewiesen, Konvergenz kann ganze Gruppen betreffen. |
| `varies_until` | nein (`individual`) | Feinster Rang, der das Gen noch verändern darf: `class`, `order`, `family`, `genus`, `species`, `individual`. Gröbere Merkmale (Bauplan) werden früh fixiert. Ein `set` auf einem feineren Rang ist ein Ladefehler. |
| `variance_scale` | nein (1.0) | Multiplikator auf alle zufälligen Abweichungen dieses Gens. |
| `weight` | nein (1.0) | Gewicht in der Distanzfunktion. |
| `wrap` | nein (false) | Nur `float`: Wert läuft im Kreis (Farbton). Distanz und Interpolation nehmen den kürzeren Weg. |
| `depends_on` | nein | Ist das genannte Gen 0, ist dieses Gen bedeutungslos (Hornlänge ohne Hörner) und zählt in der Distanz nicht. |
| `visible` | nein (true) | `false` = gehört nicht zum Aussehen (z. B. Fähigkeiten ab M4) und zählt nicht zur visuellen Distanz. |
| `description` | nein | Freitext für Menschen. |

## Aktuelle Gene

| Gen | Gruppe | Typ | Bereich | Default | varies_until | Gewicht | hängt ab von | Bedeutung |
|---|---|---|---|---|---|---|---|---|
| `segment_count` | bodyplan | int | 1 – 4 | 2 | order | 3.0 |  | Anzahl der Körpersegmente (1 = kompakt, 4 = wurmartig lang). |
| `leg_count` | bodyplan | int | 0 – 8 (Schritt 2) | 4 | order | 4.0 |  | Anzahl der Beine, immer paarig (0, 2, 4, 6, 8). |
| `body_shape` | bodyplan | enum | round / elongated / flat | round | family | 2.0 |  | Querschnitt des Körpers: rund, gestreckt oder flach. |
| `gait` | movement | enum | walk / trot / hop / scuttle / slither | walk | family | 1.5 |  | Gangart für die prozedurale Animation (ab M2). |
| `speed` | movement | float | 0.3 – 3.0 | 1.0 | individual | 0.5 |  | Grundtempo (Schritte pro Sekunde relativ). |
| `posture` | movement | float | 0.0 – 1.0 | 0.5 | individual | 0.8 |  | Haltung: 0 = geduckt/breitbeinig, 1 = hoch aufgerichtet. |
| `body_length` | proportion | float | 0.4 – 2.0 | 1.0 | individual | 1.5 |  | Länge des Rumpfs in Metern (ohne Kopf und Schwanz). |
| `body_width` | proportion | float | 0.2 – 1.2 | 0.5 | individual | 1.0 |  | Dicke des Rumpfs in Metern. |
| `head_size` | proportion | float | 0.1 – 0.7 | 0.3 | individual | 1.0 |  | Kopfdurchmesser in Metern. |
| `leg_length` | proportion | float | 0.1 – 1.6 | 0.6 | individual | 1.5 | `leg_count` | Beinlänge in Metern (Ober- plus Unterschenkel). |
| `leg_thickness` | proportion | float | 0.02 – 0.2 | 0.06 | individual | 0.5 | `leg_count` | Beindicke in Metern. |
| `horn_count` | appendage | int | 0 – 4 | 0 | species | 1.5 |  | Anzahl Hörner auf dem Kopf. |
| `horn_length` | appendage | float | 0.0 – 0.8 | 0.2 | individual | 1.0 | `horn_count` | Hornlänge in Metern. |
| `tail_length` | appendage | float | 0.0 – 1.5 | 0.3 | individual | 1.0 |  | Schwanzlänge in Metern (0 = kein Schwanz). |
| `crest_height` | appendage | float | 0.0 – 0.5 | 0.0 | individual | 0.8 |  | Höhe des Rückenkamms in Metern (0 = kein Kamm). |
| `antenna_length` | appendage | float | 0.0 – 1.0 | 0.0 | individual | 0.8 |  | Fühlerlänge in Metern (0 = keine Fühler). |
| `hue` | color | float | 0.0 – 1.0 (kreisförmig) | 0.3 | individual | 1.5 |  | Farbton der Grundfarbe (0 = rot, 0.33 = grün, 0.66 = blau), kreisförmig. |
| `saturation` | color | float | 0.0 – 1.0 | 0.5 | individual | 0.8 |  | Farbsättigung der Grundfarbe. |
| `brightness` | color | float | 0.15 – 1.0 | 0.6 | individual | 0.8 |  | Helligkeit der Grundfarbe. |
| `pattern_type` | pattern | enum | none / stripes / spots / bands | none | species | 1.2 |  | Musterart: keins, Querstreifen, Flecken, Längsband. |
| `pattern_density` | pattern | float | 1.0 – 8.0 | 3.0 | individual | 0.5 | `pattern_type` | Wie viele Streifen/Flecken pro Segment. |
| `pattern_contrast` | pattern | float | 0.0 – 1.0 | 0.5 | individual | 0.5 | `pattern_type` | Kontrast des Musters zur Grundfarbe. |

Längenangaben sind in Metern gedacht; der 3D-Builder (M2) übernimmt sie direkt.

## Wie Zufall und Vererbung zusammenspielen

Für jedes Gen und jeden Rang `r` (Klasse → Art, dann Individuum):

```
wenn Taxon.set[gen]            -> wert = set[gen]                 (kein Zufall auf diesem Rang)
sonst wenn gen in fixed (auch geerbt) -> wert bleibt (+ shift)
sonst                          -> wert = wert + shift[gen] + N(0, sigma) × Wertebereich
sigma = (Taxon.variance[gen] oder base_variance[r]) × spread[r] × gen.variance_scale
```

- `base_variance` (Standard: Klasse 0.2, Ordnung 0.12, Familie 0.08, Gattung 0.06, Art 0.04,
  Individuum 0.02) sorgt dafür, dass höhere Ränge grobe, tiefere Ränge feine Unterschiede erzeugen.
- `spread` sind die globalen Regler (Debug-Viewer: „Arten“, „Individuen“ usw.).
- `enum`-Gene wechseln statt Gauß-Rauschen mit Wahrscheinlichkeit `sigma × enum_switch_factor`
  (Standard 2.0) auf eine andere Option.
- Werte werden danach auf den Bereich begrenzt (bzw. gewickelt bei `wrap`).

## Distanzfunktion

`GenomeDistance.distance(a, b)` = gewichteter Mittelwert der normierten Unterschiede aller
sichtbaren Gene, Ergebnis in [0, 1]:

- `float`/`int`: |a − b| / (max − min)
- `wrap`: kürzerer Kreisabstand, auf [0, 1] skaliert (gegenüberliegende Farbtöne = 1)
- `enum`: 0 bei gleicher, 1 bei anderer Option
- bedeutungslose Gene (`depends_on` = 0) zählen als Minimalwert

`GenomeDistance.breakdown(a, b)` liefert zusätzlich den Wert pro Gruppe.
Orientierung mit Standardreglern (generierte Taxonomie, erwachsene Weibchen):

| gemeinsamer Rang | mittlere Distanz |
|---|---|
| gleiche Art | ≈ 0.01 |
| gleiche Gattung | ≈ 0.06 |
| gleiche Familie | ≈ 0.09 |
| gleiche Ordnung | ≈ 0.11 |
| gleiche Klasse | ≈ 0.27 |
| verschiedene Klassen | ≈ 0.36 |
