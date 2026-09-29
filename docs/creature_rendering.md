# Kreaturen: Mesh, Skelett, Laufen, LOD

Alles wird zur Laufzeit aus dem Genom gebaut – keine Modelle, keine Animationsdateien.
Neue Baupläne entstehen allein über Gene bzw. Taxa (siehe [`taxonomy_format.md`](taxonomy_format.md));
Testdaten für seltene Baupläne liegen in [`bodyplan_gallery.json`](../data/taxonomies/bodyplan_gallery.json).

## Ablauf

```
Genome ─► BodyPlan ─► CreatureRig ─► Skeleton3D
                  └─► CreatureMeshBuilder ─► ArrayMesh (hoch + niedrig) ─► MeshInstance3D (1 Draw-Call)
                  └─► CreatureLocomotion (Schrittplaner, IK, Körperhaltung) ─► Knochen-Posen
Creature (Node3D): Bewegung Richtung desired_velocity, Bodenhaftung, LOD
```

## Wie Gene das Aussehen bestimmen

| Gen | Wirkung |
|---|---|
| `segment_count` | Anzahl Rumpf-Ellipsoide, je ein Knochen (Rumpfwelle). |
| `body_length`, `body_width`, `body_shape` | Rumpfmaße; `body_shape` streckt den Querschnitt: round 1.0 × 1.0, elongated 0.85 × 0.65, flat 1.25 × 0.42 (seitlich × vertikal). |
| `head_size` | Kopfdurchmesser; Augen skalieren mit. |
| `leg_count`, `leg_length`, `leg_thickness` | Beinpaare gleichmäßig entlang des Rumpfs; Ober- und Unterschenkel je 0.55 × `leg_length`. |
| `posture` | Hüfthöhe: normal 0.45–0.9 × Beinlänge, gespreizte Baupläne (scuttle oder ≥ 6 Beine) 0.3–0.65 × mit weit abgespreizten Füßen und hochstehenden Knien. |
| `horn_count`, `horn_length` | Kegel auf dem Kopf, knochenfarben. |
| `tail_length` | Röhre aus 3 Knochen; hängt, beim Hüpfen erhoben, wedelt im Gang. |
| `crest_height` | Zacken entlang des Rückens (nur hohe Detailstufe). |
| `antenna_length` | Zwei gebogene Fühler. |
| `hue`, `saturation`, `brightness` | Körperfarbe (Shader-Parameter). |
| `pattern_type`, `pattern_density`, `pattern_contrast` | Muster im Shader: Querstreifen, Flecken, Längsband; Dichte = Anzahl pro Segment. |
| `gait` | Schrittmuster (siehe unten), Hüpf-/Schlängelbewegung des Körpers. |
| `speed` | Grundtempo; zusammen mit der Größe: `move_speed = speed × clamp(Beinlänge + 0.3 × Rumpflänge, 0.3, 2) × 0.9` m/s. |

## Skelett

`root` (Körpermitte) → `seg_i`, `head`, `tail_0..2`, pro Bein `leg_i_upper` → `leg_i_lower`.
Jeder Vertex hängt mit Gewicht 1 an genau einem Knochen (starres Skinning). Beinknochen zeigen
in Ruhe nach unten; die IK setzt ihre Posen jedes Frame.

## Laufen

- **Gangzyklus:** Phase 0..1, Frequenz = Tempo × Standanteil / Schrittlänge. Jedes Bein hat einen
  Phasenversatz; während seiner Schwungphase fliegt der Fuß auf einem Bogen zum nächsten
  Aufsetzpunkt (Ruhepunkt + halber Standweg in Laufrichtung, Bodenhöhe per Raycast), in der
  Standphase bleibt er fest in der Welt. Steht die Kreatur, setzen nur Beine um, die weiter als
  20 % der Schrittlänge vom Ruhepunkt entfernt sind.
- **Schrittmuster** (`GaitTable`), Beine nummeriert Paar × 2 + Seite, Paar 0 = vorne:

  | Beine | walk | trot | hop | scuttle / sonst |
  |---|---|---|---|---|
  | 2 | abwechselnd | abwechselnd | gleichzeitig | abwechselnd |
  | 4 | Kreuzgang (4 Phasen) | diagonale Paare | vorne, dann hinten | diagonal |
  | 6 | Dreifuß | Dreifuß | vordere/hintere Hälfte | Dreifuß |
  | 8 | Wellengang | alternierend | Hälften | alternierend |

  Standanteil: walk 0.65, trot 0.5, hop 0.35, scuttle 0.55, slither 0.7.
- **IK:** analytische 2-Knochen-Lösung; Kniebeuge nach vorne (Vorderbeine), nach hinten
  (Hinterbeine) bzw. nach oben/außen (gespreizte Baupläne). Ziele außer Reichweite werden
  auf gestrecktes Bein begrenzt.
- **Körper:** Höhe folgt dem Mittel der Füße, Neigung (Nicken/Rollen) folgt Höhenunterschieden
  vorne/hinten bzw. links/rechts – Kreaturen legen sich auf Rampen schräg. Dazu Wippen im Gang,
  Hüpfbogen, seitliches Schaukeln bei Zweibeinern, Rumpfwelle (stark bei beinlosen
  Schlänglern) und Schwanzwedeln.

## LOD (`CreatureLOD`)

| Stufe | Distanz zur Kamera | Verhalten |
|---|---|---|
| full | < 14 m | volle IK, Fuß-Raycasts, jedes Physik-Frame |
| reduced | < 32 m | IK jedes 2. Frame, Boden als Ebene (keine Raycasts) |
| frozen | < 70 m | Low-Poly-Mesh, Beine eingefroren, nur Fortbewegung |
| hidden | darüber | unsichtbar, nur Fortbewegung |

Grenzen in `CreatureLOD.thresholds`, 1.5 m Hysterese gegen Flackern.

## Performance (Stand M2)

`godot --headless -s tools/benchmark_creatures.gd -- anzahl=20` (Xeon 2.8 GHz, alle Kreaturen
auf voller Stufe, inkl. Raycasts und Verhalten):

| Kreaturen | CPU pro Frame (Mittel / 95 %) |
|---|---|
| 20 | 1.6 ms / 2.4 ms |
| 40 | 2.7 ms / 4.1 ms |

Locomotion allein ≈ 56 µs pro Kreatur, davon ≈ 2/3 für das Setzen der Knochen-Posen.
Rendering: ein Draw-Call pro Kreatur plus Schatten (Labor: 2 Schattenkaskaden).
Messung auf echtem Gerät folgt in M6.

## Testszene

`scenes/debug/creature_lab.tscn`: alle Arten der Demo plus Bauplan-Galerie auf unebenem Boden
(Rampen, Stufen, Felsen). Antippen wählt eine Kreatur (Kamera folgt), „+5/−5“ ändert die Anzahl,
„LOD“ erzwingt eine Stufe, „Aufstellen“ stellt alle still in Reihen zum Vergleichen.
