# Voronoi Game (Godot 4 Desktop)

Desktop-Neuaufbau der JS-Voronoi-Game-Prototyp aus `../src/`.
Die JS-Dateien bleiben als lauffaehige Referenz liegen.

Der Aufbau folgt dem Plan `.kilo/plans/1789562691435-godot-desktop-rebuild-plan.md`.

## Voraussetzungen

- Godot **4.6.1** (Standard-Build, GDScript; getestet mit 4.6.1.stable)
- GUT ist enthalten (`addons/gut`, v9.6.1) - fuer die Tests, kein Download noetig
- Export-Templates nur fuer echte Exporte (`Editor > Editor-Einstellungen > Export-Templates`)

## Starten

```powershell
# Projekt im Editor oeffnen
godot --path game --editor

# direkt starten
godot --path game
```

Kein Fensterzustand wird gespeichert; das Brett (900x600 logisch) wird im
Fenster gleichmaessig skaliert und mittig gesetzt (Letterbox). Alle Regler
werden in `user://settings.cfg` gespeichert und beim Start geladen.

Die Zellzahl wirkt wie im Original durch die gespiegelte Punkterzeugung
doppelt: "20 Zellen" im Regler ergeben 40 Zellen auf dem Brett. Die Zellzahl
greift erst beim Neustart.

## Tests

```powershell
godot --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

Aktueller Stand: 95 Tests / 34338 Asserts, alle gruen.
Abgedeckt: Geometrie, Delaunay, Voronoi (inkl. Robustheit ueber mehrere
Bretter und Ticks), Territorien/Zugwechsel, Scoring, Relaxation,
Konfiguration/Einstellungen, Notenplanung/Audio-Zeitversatz, Skalierung und
Farbberechnung.

## Export

Presets `Windows Desktop` und `Linux` sind in `export_presets.cfg` angelegt
(Ausgabe nach `build/`). Nach Installation der Export-Templates:

```powershell
godot --headless --path game --export-release "Windows Desktop" build/windows/VoronoiGame.exe
godot --headless --path game --export-release "Linux" build/linux/VoronoiGame.x86_64
```

Die Templates sind in dieser Umgebung nicht installiert; der Export selbst
wurde daher nicht ausgefuehrt (die Presets werden von Godot korrekt geladen,
es fehlen nur die Vorlagendateien).

## Aufbau

```
scenes/    Main (verdrahtet), BoardView, SettingsPanel, ScoreHud
scripts/
  app/     game_app.gd (Takt + Verdrahtung), config.gd, settings_store.gd
  core/    geometry.gd, delaunay.gd, voronoi.gd, board.gd, rng.gd
  sim/     territories.gd, relaxation.gd, turns.gd, scoring.gd
  audio/   audio_setup.gd, waveform_bank.gd, voice_pool.gd, synth.gd
  input/   board_input.gd
  view/    board_renderer.gd, board_transform.gd
  ui/      settings_panel.gd, score_hud.gd
tests/unit/  GUT-Tests (test_geometry, test_delaunay, test_voronoi,
             test_territories, test_scoring, test_relaxation,
             test_settings, test_synth, test_view)
```

`core/` kennt kein Rendering, Audio, UI oder Eingabe. `sim/` veraendert nur
`BoardState`. `app/` ist die einzige Stelle, die alles verdrahtet.

## Datenfluss pro Tick

`_physics_process` (fixed 60 Hz):

1. Drag-Bewegung anwenden (mousemove-Aequivalent)
2. Voronoi **ohne** Dummy-Punkte aufbauen (Gewichte, Frequenzen, Klick)
3. Klick in Zelle -> Noten; laufender Drag -> Dauertoene
4. Abstandskraefte, Geschwindigkeiten
5. Voronoi **mit** Dummy-Punkten aufbauen (einmal, wird geteilt)
6. Rand-Clamping
7. Farbausbreitung (beim Dragging zweimal, wie im Original)
8. Drag-Linien-Daten
9. Scoring

`_process`: faellige Noten starten, Huellkurven fortschreiben, Highlights,
Zeichnen, Score-Anzeige.

Ruhe-Erkennung: haben sich Punkte und Farben im letzten Tick exakt nicht
geaendert und laeuft kein Drag, werden Schritte 2-8 uebersprungen (das
Ergebnis ist deterministisch identisch). Nur das Scoring laeuft weiter.

## Messwerte

Tick-Kosten (Simulation, ohne Rendering/Audio, aktiv):

| Zellen | Punkte | ms/Tick | Anmerkung |
|---|---|---|---|
| 20 (Default) | 40 | 7.2 | deutlich unter 16.7 ms |
| 50 | 100 | 17.2 | |
| 100 | 200 | 36.9 | Maximum des Reglers |

Im Ruhezustand (Brett beruhigt) faellt der Tick auf ca. 0.5 ms, weil nur noch
das Scoring laeuft. Audio haengt nicht am Frame-Takt (Noten laufen ueber eine
eigene Uhr), daher gibt es auch bei 100 Zellen keine Aussetzer.

Gemessen mit `--headless` auf einer 4-Kern-Windows-Maschine; die
Zellpolygone sind der groesste Posten (Umkreismittelpunkte + Kantenmessung),
danach folgt die Delaunay-Triangulation (Engine-Bordmittel).

## Paritaet zur JS-Referenz

Die Geometrie wurde gegen `d3-delaunay` (dieselbe Bibliothek wie im Original)
mit identischen Punkten verglichen:

- Zellflaechen: maximale Abweichung ~0.01 px2 bei ~10000 px2 Zellflaeche
  (relativ ca. 1e-6).
- Nachbarschaften und Kantenlaengen: identisch bis auf wenige Zellen in
  gespiegelten, kokreisfoermigen Sonderfaellen.

Kokreisförmige Punkte (durch die gespiegelte Punkterzeugung haeufig) haben
einen Grad-4-Knoten im Voronoi-Diagramm. An so einem Knoten liefert die
JS-Kantenmessung (Schnitt zweier Zellpolygone) rechnerisch eine Kante, obwohl
sich die Zellen nur in einem Punkt beruehren. In solchen Faellen kann sich die
Liste der sichtbaren Nachbarn in 0.5-2.5 % der Zellen um einen Nachbarn
unterscheiden. Alle uebrigen geprueften Bretter (20/50/66/100 Zellen)
stimmen vollstaendig ueberein.

### Bewusste Abweichungen

- **Delaunay** kommt aus `Geometry2D.triangulate_delaunay` (Engine, C++)
  statt aus einem delaunator-Port. Ergebnis ist dieselbe
  Delaunay-Topologie, aber robust und fuer 60 Hz schnell genug.
  Kollineare Eingaben ergeben einen leeren Graphen (im Spiel unmoeglich).
- **Simulation** laeuft fest mit 60 Hz (`_physics_process`) statt mit
  `requestAnimationFrame`.
- **Ruhe-Erkennung** (siehe oben): gleiches Ergebnis, nur ohne Neuberechnung.
- **Neustart** setzt Punkte, Zellen, Farben, Zugrecht **und Punktestand**
  zurueck. Im Original gab es keinen Neustart; die Zellzahl wirkte dort
  sofort, hier erst beim Neustart.
- **Tote Stellen entfallen** (wie im Plan): `harmonyInfluenceSlider`,
  `colorThresSlider`/`colorThreshold`, `getLargestNeighbor()`,
  `generateRegularPoints()`, `generateRandomPoints()`,
  `getMaxCommonEdgeLengthForColor()`.
- **Dragtone Neighbor Factor** ist im Original wirkungslos (der Wert landet
  nur in einer nie gelesenen Variable); die Nachbarstimme ist wie dort fest
  0.5. Der Regler bleibt erhalten, hat aber keinen hoerbaren Effekt.
- **Audio**: der globale Cutoff ist ein Lowpass auf dem Bus "Synth" statt
  eines Filters pro Note (gleiche Wirkung, da der Wert global ist). Der
  Limiter ist ein `AudioEffectCompressor` mit den Originalwerten
  (Schwelle -8 dB, Ratio 20, Attack 3 ms, Release 200 ms); ein Knie-Parameter
  existiert in Godot nicht. Die Huellkurve bildet die Web-Audio-Ramps exakt
  nach (auch das Absinken waehrend der Haltephase).
- **Wellenformen** werden bandbegrenzt (18 Harmonische) als eine Periode
  erzeugt und ueber `pitch_scale` gestimmt; der Rest der Klangformung bleibt
  wie im Original (ADSR, Lowpass, Limiter).
- **Doppelte Dummy-Ecken** (die Erzeugung erzeugt zwei Paare doppelt) sind
  bewusst nicht entdoppelt; sie erhalten wie bei d3 keine Zelle.
- **Drag-Bewegung** wird einmal pro Tick angewendet statt pro Mausereignis;
  Slow-Faktor, Blockierung und Zugwechsel bleiben gleich.
