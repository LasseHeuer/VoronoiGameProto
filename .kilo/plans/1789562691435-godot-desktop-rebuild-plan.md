# Grundupdate: Desktop-Neuaufbau in Godot 4 (GDScript)

## Ziel

Die bestehende JS-Voronoi-Game-Prototyp (eine 1751-Zeilen-Datei `src/core.js` + `src/index.html` + `src/style.css`) wird als modulare Godot-4-Desktop-App neu aufgebaut. Alle wirksamen Features werden erhalten. Der Kern steht vor allem anderen; jede Ebene baut auf dem Kern auf.

## Nicht-Ziele (dieser Schritt)

- Keine neuen Spielinhalte (keine Siegbedingung, keine Runden, kein Gegner-KI, kein Undo, kein Replay).
- Keine Touch-/Mobile-/Web-Umsetzung. Architektur wird aber nicht dagegen verblockt.
- `legacy_WIP/` bleibt unverändert und wird ignoriert.
- `src/` bleibt als lauffähige Referenz liegen; erst nach erreichter Parität optional entfernen/archivieren.

## Entscheidungen

| Thema | Entscheidung |
|---|---|
| Engine/Sprache | Godot 4.x, reines GDScript (kein C#, kein GDExtension, kein Rust) |
| Begründung | Interpretiert, sofortiger Reload, kein Kompilieren -> kürzeste Testzyklen; Export für Windows/Linux eingebaut |
| Rust | Erst später als optionaler GDExtension-Hotspot (z. B. echter DSP). Nicht Teil dieses Plans |
| Voronoi | Eigenes GDScript-Modul (Delaunay-Port + Zellpolygone), keine Fremdabhängigkeit |
| Audio jetzt | Sample-Voices: Waveform-Loops als `AudioStreamWAV`, Frequenz über `pitch_scale`, Hüllkurve über eigenes Voice-State-Machine, Lowpass + Limiter als Audio-Busse |
| Audio später | Synth hinter schmalem Interface, damit später ein echtes DSP-Modul (`AudioStreamGenerator`) eingesetzt werden kann |
| Ort | Neues Godot-Projekt in `game/`; `src/` bleibt |
| Fenster | Festes logisches Brett (900x600), skaliert und zentriert (Letterbox), Maus wird transformiert |
| Neustart | Neustart-Knopf erzeugt frisches Spiel; Zellzahl gilt beim Neustart |
| Einstellungen | Werden in `user://` gespeichert und beim Start geladen |
| Tests | GUT-Addon für reine Logik + headless-Läufe |
| Umfang | Parität der wirksamen Features; tote Regler entfallen |
| Simulation | Fixed Timestep 60 Hz via `_physics_process`; Rendering/Audio pro Frame |

### Tote Stellen, die entfallen

- Regler `harmonyInfluenceSlider` (nicht verwendet).
- Regler `colorThresSlider` / Variable `colorThreshold` (Wert wird gelesen, aber nie benutzt).
- Funktion `getLargestNeighbor()` (ersetzt durch `getLargestNeighborByColor`).
- Neu aufbauen statt 1:1 kopieren: pro Frame wird Delaunay/Voronoi **einmal** berechnet und geteilt; die JS-Version berechnet ihn mehrfach pro Frame in verschiedenen Funktionen.

## Voraussetzungen (M0)

1. Godot 4.x installiert und startbar (Version im Projekt auf 4.x setzen).
2. GUT-Addon nach `game/addons/gut/` (Download nötig; falls kein Netzzugang, Ersatz: minimales Test-Skript via `godot --headless -s`, im Plan als Fallback dokumentiert).
3. Export-Templates für Windows und Linux installiert (nur für echte Exporte nötig, nicht für den Dev-Loop).
4. `game/project.godot` mit: Renderer, Fenstergröße/Resizable, `display/window/stretch/mode = canvas_items` (oder äquivalent), Audio-Busse.

## Zielarchitektur

```
game/
  project.godot
  addons/gut/                     # Testframework
  scenes/
    Main.tscn                     # Wurzel: verdrahtet nur Module
    BoardView.tscn                # Node2D, zeichnet das Brett (_draw)
    SettingsPanel.tscn            # Control-basiertes Panel
    ScoreHud.tscn                 # Zahlen + zwei Balken
  scripts/
    app/
      game_app.gd                 # Orchestrierung: Tick, Verdrahtung, Neustart
      config.gd                   # GameConfig (Resource): alle Parameter + Defaults
      settings_store.gd           # Save/Load nach user://settings.cfg
    core/
      geometry.gd                 # Flaeche, Schwerpunkt, Point-in-Poly, Rect-Clip, Convex-Clip, Umfang
      delaunay.gd                 # Delaunay-Triangulation (delaunator-Port)
      voronoi.gd                  # Zellpolygone aus Delaunay + Kanten/Nachbarn
      board.gd                    # BoardState: Punkte, Dummy-Punkte, Zellfarben, active_player
      rng.gd                      # Seed-basierter Zufall (Tests/Reproduzierbarkeit)
    sim/
      territories.gd              # Seeds, Farbausbreitung, Flaechen-Balancing
      relaxation.gd               # Abstandskraefte, Gewichte, Geschwindigkeiten, Clamping
      turns.gd                    # Zugwechsel / active_color
      scoring.gd                  # Flaechen-Scoring pro Spieler
    audio/
      synth.gd                    # Interface + Sample-Voice-Implementierung
      voice_pool.gd               # Pool von AudioStreamPlayern, Envelope-State-Machine
      waveform_bank.gd            # Erzeugt Loop-AudioStreamWAV je Wellenform
      audio_setup.gd              # Busse: Lowpass-Filter, Limiter, Lautstaerken
    input/
      board_input.gd              # Maus -> Drag/Klick-Intents, Koordinaten-Mapping
    view/
      board_renderer.gd           # Zeichnet Zellen, Highlights, Punkte, Drag-Linien
      board_transform.gd          # Logisches Brett -> Fenster (Letterbox) und zurueck
    ui/
      settings_panel.gd           # Baut Regler aus Config-Schema
      score_hud.gd                # Zahlen + Balken
  tests/
    unit/
      test_geometry.gd
      test_delaunay.gd
      test_voronoi.gd
      test_territories.gd
      test_scoring.gd
      test_relaxation.gd
  assets/                         # Falls noetig (Icons); Audio wird generiert
```

### Verantwortlichkeiten und Grenzen

- `core/` kennt weder Rendering, Audio, UI noch Eingabe. Nur Daten und Mathematik. Voll unit-testbar.
- `sim/` verändert `BoardState`, nutzt nur `core/`. Keine Node-/Scene-Abhängigkeit, damit testbar.
- `view/`, `audio/`, `input/`, `ui/` lesen `BoardState` und senden Intents zurück. Sie enthalten keine Spiellogik.
- `app/` ist die einzige Stelle, die alles verdrahtet. Szenen enthalten nur Node-Struktur, keine Logik.

### Datenfluss pro Tick

1. `_physics_process(1/60)`: Eingabe-Intents anwenden -> `relaxation` -> `turns` -> `territories` (Farbausbreitung) -> `scoring`.
2. `_process`: Delaunay/Voronoi einmal berechnen -> `board_renderer` zeichnet -> `synth` verarbeitet faellige Noten/Voice-Huellkurven -> `score_hud` aktualisiert.
3. Audio-Zeit kommt aus einer eigenen Clock (`Time.get_ticks_usec()`); Noten werden mit `(start_time, cell, freq, wave)` eingeplant und bei Erreichen gestartet. Highlights nutzen dieselbe Clock.

## Parameter-Parität (Defaults aus `index.html`/`core.js`)

Synth: Wave `triangle`; Attack 0.05; Decay 0.2; Sustain 0.2; Release 0.1; Cutoff 500 Hz (100-1000, global); DragToneVolume 0.2; Drag-Neighbor-Factor 0.25.

Spiel: FreqThr 0.2; SpreadTime 0.6 -> `ms = 50 * 20^t`; SpreadDepth 2 (1-6); Zellen 20 (2-100); PushFactor 0.2; PushRadius 40 (5-150); BorderMargin 25 (5-50); WeightInfluence 0.95; Wechselnde Zuege an; DummyPoints an.

Konstanten: Brett 900x600; DragRadius 10; RepelThreshold 60; SlowFactor 0.2; MoveThreshold 1 px; Punktemargin 30; SpreadFactor 0.2 (gespiegelte Punkte); DummySpacing 50, DummyMargin 30; Luminanz 20-80; Gegner-Mischfaktor 0.5; Rahmen Highlight weiss/6, sonst #999/3; Punktradius 5; Flaechen-Text `round(area/10)`; Farbausbreitung 12 Iterationen; Balancing-Toleranz 5% der Brettflaeche, maxIter 100 (init) / 50 (Neustart), Relax-Iterationen 30 (n>50) sonst 10; Notendauer 2 s; Distanzfaktor 0.003; Drag-BFS-Tiefe 2 (Start 1.0, groesster Nachbar 0.5); Voice-Attack 60 ms, Smooth 50 ms; RampDown Frequenz->20 Hz in 0.4 s, Gain->0 in 1 s; Daempfung 0.9; Frequenz `ratio = area/brettflaeche`, bei `ratio <= freqThr`: `1200 - 1150*(ratio/freqThr)`, sonst 50; Spielerfarben `#FF8BA7` (P1) und `#76FFE8` (P2).

## Umsetzungsschritte (geordnet)

### M0 Projektgeruest
1. `game/project.godot` anlegen, Godot 4.x als Feature, Fenster resizable, Audio-Busse vorbereiten.
2. `scenes/Main.tscn` + `scripts/app/game_app.gd` als minimale Wurzel.
3. `scripts/app/config.gd` (`GameConfig` Resource) mit allen Parametern und Defaults aus der Tabelle; `scripts/app/settings_store.gd` fuer `user://settings.cfg`.
4. GUT installieren; ein Smoke-Test laeuft headless.
5. Verifikation: Projekt startet, leeres Fenster; `godot --headless` fuehrt Tests aus.

### M1 Kern-Geometrie (kein Rendering)
6. `core/geometry.gd`: Flaeche (Shoelace), Schwerpunkt, Point-in-Polygon, Rect-Clip (Sutherland-Hodgman), Convex-Clip, Umfang.
7. `core/delaunay.gd`: Delaunay-Triangulation als Port des delaunator-Algorithmus (Nachbarschaftsabfrage `neighbors(i)`).
8. `core/voronoi.gd`: Zellpolygon aus Delaunay + Brett-Rechteck; sichtbare Nachbarn und gemeinsame sichtbare Kante.
9. `core/rng.gd`: Seed-basierter Zufall; `core/board.gd`: `BoardState` (Punkte, gespiegelte Generierung, Dummy-Punkte).
10. Tests: `test_geometry.gd`, `test_delaunay.gd`, `test_voronoi.gd` (u. a. Kollinearitaet, doppelte Punkte, Randzellen, 2 bis 100 Punkte).
11. Verifikation: Tests gruen; optional Debug-Szene, die Zellpolygone und Punkte zeichnet.

### M2 Brettdarstellung und Skalierung
12. `view/board_transform.gd` (Letterbox-Skalierung + inverses Maus-Mapping), `view/board_renderer.gd` (Zellfuellung nach Flaechen-Luminanz 20-80, Basisfarbe mit Graumischung, Gegner-Mischung, Rahmen, Flaechen-Text, Punkte).
13. `scenes/BoardView.tscn` anbinden; `Main.tscn` zeigt ein neutrales Brett (ohne Territorien).
14. Verifikation: Optische Paritaet des neutralen Bretts; Resize und Mausposition korrekt.

### M3 Territorien, Zugwechsel
15. `sim/territories.gd`: Seeds (zwei groesste, nicht benachbarte Zellen), Farbausbreitung ueber sichtbare Nachbarn, Balancing-Schleife mit Toleranz und Iterationsgrenzen.
16. `sim/turns.gd`: `active_player`, Wechsel nach Zug, automatischer Farbwechsel beim Ueberstreichen.
17. Tests: `test_territories.gd` (Seed-Auswahl, Ausbreitung, Flaechenbalance in Toleranz).
18. Verifikation: Startaufstellung und Farbverlauf wie in der JS-Version; Balance-Warnung nur im Ausnahmefall.

### M4 Physik und Drag-Interaktion
19. `sim/relaxation.gd`: Abstandskraft mit `push_radius`/`push_factor`, Gewichte (`computeCellWeights`-Vererbung ueber gleiche Farbe), `weight_influence`-Sonderfall, Geschwindigkeiten mit Daempfung 0.9, Clamping auf `border_margin`.
20. `input/board_input.gd`: Hit-Test (DragRadius 10), Klick in Zelle, Zug-Erlaubnis bei "wechselnde Zuege", SlowFactor bei Naehe, Block-Reversion, Drag-Linien zum groessten gleichen/gegnerischen Nachbarn.
21. Tests: `test_relaxation.gd` (Kraft, Gewicht, Clamping deterministisch mit festem Seed).
22. Verifikation: Ziehen/Bremsen/Blockieren und Zugwechsel entsprechen dem JS-Verhalten.

### M5 Audio
23. `audio/audio_setup.gd`: Bus-Layout, Lowpass-Filter (global, Cutoff 100-1000), Limiter, Lautstaerken.
24. `audio/waveform_bank.gd`: Loop-faehige `AudioStreamWAV` fuer Sine/Triangle/Square/Saw (bandbegrenzt erzeugt), Basis-Frequenz als Referenz fuer `pitch_scale`.
25. `audio/voice_pool.gd`: Pool von `AudioStreamPlayer`, Voice-State-Machine fuer Attack/Decay/Sustain/Release in dB (`linear_to_db`), Start/Stop, globale Clock.
26. `audio/synth.gd`: Interface (NoteEvents planen, Drag-Ton starten/aktualisieren/stoppen, Farbwechsel-RampDown) + Sample-Voice-Implementierung.
27. Anbindung: Klick-BFS-Ausbreitung (Tiefe `spread_depth`, Offset `(d-1)*spread_ms + dist*0.003`, nur gleiche Startfarbe, Notendauer 2 s + Release), Drag-Toene (BFS Tiefe 2, Start 1.0, groesster Nachbar 0.5), Frequenz aus Zellflaeche, Highlight ueber Audio-Clock.
28. Verifikation: Vergleich mit JS-Version bei gleichem Brett (Wellenform, Frequenz, Huellkurve, Reihenfolge der Ausbreitung); keine Klick-/Dropouts bis 100 Zellen.

### M6 UI, Neustart, Persistenz
29. `ui/settings_panel.gd`: Panel aus Config-Schema (Regler mit Min/Max/Step/Default, Wellenform-Auswahl, Checkboxen); enthaelt nur die wirksamen Parameter.
30. `ui/score_hud.gd`: Zahlen, zwei Balken (Anteilsbreite), Spielerfarben.
31. Neustart-Knopf; Zellzahl greift beim Neustart; `settings_store.gd` speichert/laedt alle Regler.
32. Verifikation: Sichtbares/versteckbares Panel, Persistenz ueber Neustart, Score-Balken korrekt.

### M7 Export und Abschluss
33. Export-Presets fuer Windows und Linux, Kurzdoku im Plan/README-Abschnitt `game/` (Start, Tests, Export).
34. Paritaetsdurchlauf: Feature-Liste gegen `src/core.js` abhaken; nicht mehr benoetigte tote Regler endgueltig entfernen.
35. Optional: `src/` als Referenz kennzeichnen (z. B. Umbenennen des Ordners) - nur nach Rueckfrage.

## Validierung

- `godot --headless` fuehrt die GUT-Suite aus; Kern- und Sim-Tests muessen gruen sein.
- Manueller Vergleich JS vs. Godot bei gleichem Seed/Brett: Territorien, Farbverlauf, Balancing, Zugwechsel, Scoring.
- Audiopruefung: gleiche Ausbreitung, Frequenzen, Huellkurven; keine Uebersteuerung bis 100 Zellen (Limiter).
- Fensterpruefung: Resize, Buchstabenbox, Maus-Mapping, HiDPI.
- Export-Smoke-Test auf Windows 10 und Linux (Start der exportierten Build).

## Risiken und Gegenmassnahmen

- Delaunay-Robustheit bei degenerierten Faellen (kollinear, Duplikate, Randpunkte): eigene Tests, Dummy-Punkte-Verhalten beibehalten.
- Aliasing bei stark verschobener Tonhoehe (Square/Saw via `pitch_scale`): bandbegrenzte Grundsamples erzeugen; falls unzureichend, DSP-Modul vorziehen (Interface ist dafuer vorbereitet).
- Fixed-60-Hz-Simulation vs. JS-`requestAnimationFrame`: kleine Verhaltensunterschiede moeglich; als bewusste Entscheidung dokumentiert, Parameter bleiben gleich.
- GUT/Export-Templates erfordern Download; Fallback fuer Tests ist ein headless-Skript.
- Godot-Version im Projekt fixieren, damit sich die API nicht unbemerkt aendert.

## Offen / spaeter

- Sieg- oder Rundenziel, Gegner-KI, Undo, Replay, Aufnahme.
- Touch-Eingabe und Mobile-/Web-Export.
- Echtes DSP-Modul (Rust/C++/GDScript-`AudioStreamGenerator`) statt Sample-Voices.
- Weitere Plattform-Exporte und Lokalisierung.

## Hinweis

Dieser Plan ist implementierungsreif. Die Umsetzung erfordert einen Implementierungs-Agenten, da hier nur Planungsdateien bearbeitet werden duerfen.
