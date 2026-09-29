# Export: Web, Android, iOS

Presets stehen in `export_presets.cfg`. Tests, Werkzeuge und Doku werden nicht exportiert;
die JSON-Daten (`data/`) werden per `include_filter` mitgenommen.

## Automatisch: GitHub Actions (`.github/workflows/build.yml`)

Bei jedem Push (und für Pull Requests):
1. lädt Godot 4.4.1 und die benötigten Export-Vorlagen (zwischengespeichert),
2. führt alle Unit-Tests aus,
3. exportiert die **Web-Version** und eine **Android-Debug-APK** (das Android SDK ist auf den
   GitHub-Runnern vorinstalliert; ein Debug-Schlüssel wird pro Lauf erzeugt),
4. legt beides als Download an der Workflow-Ausführung ab (*Actions* → Lauf → *Artifacts*),
5. veröffentlicht die Web-Version auf **GitHub Pages** – nur vom Standard-Branch.

**Einmalige Einrichtung für Pages:** Repository → *Settings* → *Pages* → *Source*:
„GitHub Actions“. Danach nach jedem Push auf den Standard-Branch unter
`https://<nutzer>.github.io/<repo>/` spielbar. Soll auch ein anderer Branch veröffentlicht
werden, muss er unter *Settings* → *Environments* → *github-pages* erlaubt und die Bedingung
im Job `pages` angepasst werden.

APK installieren: Datei aufs Handy laden, Installation aus unbekannten Quellen erlauben.
Die Debug-APK ist nur zum Testen gedacht (für den Play Store braucht es einen eigenen
Release-Schlüssel und ein AAB).

## Web (HTML5)

- Läuft zwingend mit dem **Compatibility-Renderer** (WebGL 2), auch auf dem iPhone (Safari ab iOS 15).
- **Ohne Threads** exportiert (`variant/thread_support=false`): keine besonderen Server-Header
  nötig, läuft auf jedem statischen Webspace (GitHub Pages, itch.io).
  Angepasst dafür: Navmesh wird synchron gebacken (~0.3 s beim Start),
  Spatial Gardener rechnet LODs im Web ohne Threads (`plugin/is_threaded_LOD_update.web=false`).
- **PWA**: im Handy-Browser „Zum Home-Bildschirm“ → startet wie eine App im Vollbild.
- Spielstand liegt im Browser-Speicher (IndexedDB) – bleibt erhalten, außer Browserdaten werden gelöscht.
- Größe: ~44 MB (WASM der Engine), komprimiert übertragen ~10 MB.
- Lokal testen: `godot --headless --export-release "Web" build/web/index.html`, dann
  `python3 -m http.server -d build/web 8000` und `http://localhost:8000` öffnen
  (direkt als Datei geht nicht).
- Schrift: `assets/fonts/DejaVuSans.ttf` (freie Lizenz, siehe `DejaVu-LICENSE.txt`) als
  Projektschrift – im Browser gibt es keine System-Schriften, sonst fehlen Zeichen wie ♂/♀.

## Android

- Mobile-Renderer (Vulkan, auf älteren Geräten automatisch OpenGL-Fallback), arm64, Querformat.
- Lokal bauen: Android SDK (Build-Tools, Platform 34) und JDK 17 in den Editor-Einstellungen
  eintragen (*Editor* → *Editoreinstellungen* → *Export* → *Android*), dann
  `godot --headless --export-debug "Android" build/android/creature-learning.apk`.
- Im Cloud-Container dieses Projekts ist `dl.google.com` gesperrt – deshalb baut die APK die CI.

## iOS

Vorbereitet (Preset „iOS“), aber nur auf einem **Mac mit Xcode** zu bauen:
1. Apple-Developer-Account (für Geräte/TestFlight; 99 USD/Jahr), Team-ID in
   `application/app_store_team_id` eintragen, ggf. Bundle-ID anpassen
   (`com.rebrowski.creaturelearning`).
2. Godot-Export-Vorlagen inkl. `ios.zip` installieren.
3. *Projekt* → *Exportieren* → iOS → Xcode-Projekt erzeugen, in Xcode signieren und aufs Gerät
   bringen.
Kurzfristig spielt man auf dem iPhone am einfachsten die Web-Version (PWA).

## Leistung messen

Im Spiel **Debug** einschalten:
- Anzeige: FPS, Frame-Zeit (Mittel / 95 % / Maximum der letzten 3 s), Draw-Calls,
  Kreaturen je LOD-Stufe.
- **Grafik: hoch / mittel / niedrig** – Schatten, Auflösungsskalierung (100/85/70 %),
  LOD-Distanzen (100/80/60 %). Standard: hoch am Desktop, mittel auf Handy und im Browser.
  Wird in `user://settings.cfg` gespeichert.
- **+5 Test** fügt vorübergehend 5 Kreaturen hinzu (nicht im Spielstand), um die Grenze des
  Geräts zu finden. Ziel: 15–20 Kreaturen bei 60 FPS (nativ) bzw. 30 FPS (Browser).

Messwerte im Container (keine echte GPU) sagen über Handys wenig; CPU-Seite siehe
`docs/creature_rendering.md` und `docs/abilities_format.md`.
