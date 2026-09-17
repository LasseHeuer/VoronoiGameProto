# Voronoi Game (Godot 4 Desktop)

Desktop-Neuaufbau der JS-Voronoi-Game-Prototyp aus `../src/`.
Die JS-Dateien bleiben als lauffaehige Referenz liegen.

Der Aufbau folgt dem Plan `.kilo/plans/1789562691435-godot-desktop-rebuild-plan.md`.

## Voraussetzungen

- Godot **4.6.1** (Standard-Build, GDScript; getestet mit 4.6.1.stable)
- GUT ist enthalten (`addons/gut`, v9.6.1) - fuer die Tests, kein Download noetig
- Export-Templates nur fuer echte Exporte (`Editor > Editor-Einstellungen > Export-Templates`)

## Starten

Am einfachsten mit der beigelegten `../Voronoi Game starten.exe` (im
Hauptordner des Projekts): Doppelklick startet das Spiel direkt, ohne Editor.
Die EXE sucht Godot 4 selbst (u. a. `C:\Program Files\Godot\`) und oeffnet das
Projekt aus dem Unterordner `game`.

```powershell
# Projekt im Editor oeffnen
godot --path game --editor

# direkt starten
godot --path game
```

Kein Fensterzustand wird gespeichert. Das Brett (900x600 logisch) ist die
Basisgroesse des Fensters; die Engine skaliert es fliessend auf die
Fenstergroesse und haelt dabei das Seitenverhaeltnis (ungenutzte Raender
bleiben leer, `project.godot`: `window/stretch/mode=canvas_items`,
`window/stretch/aspect=keep`). Alle Regler werden in `user://settings.cfg`
gespeichert und beim Start geladen.

Die Zellzahl wirkt wie im Original durch die gespiegelte Punkterzeugung
doppelt: "20 Zellen" im Regler ergeben 40 Zellen auf dem Brett. Die Zellzahl
greift erst beim Neustart.

## Tests

```powershell
godot --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

Aktueller Stand: 152 Tests / 35877 Asserts, alle gruen.
Abgedeckt: Geometrie, Delaunay, Voronoi (inkl. Robustheit ueber mehrere
Bretter und Ticks), Territorien/Zugwechsel, schrittweiser Farbwechsel,
Bewegungs-Territorium und weiche Bremse beim Drag, Zeichnen eines kompletten
Frames, Einstellungsmenue, Relaxation, Konfiguration/Einstellungen,
Notenplanung/Audio-Zeitversatz (inkl. Hover-Toene und gelber Ueberlagerung),
Front-Abrundung, Skalierung und Farbberechnung.

Zusaetzlich als Startlauf ohne Fenster (darf keine `ERROR`-Zeile ausgeben):

```powershell
godot --headless --path game --quit-after 200
```

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
scenes/    Main (verdrahtet), BoardView, SettingsPanel
scripts/
  app/     game_app.gd (Takt + Verdrahtung), config.gd, settings_store.gd
  core/    geometry.gd, delaunay.gd, voronoi.gd, board.gd, rng.gd
  sim/     territories.gd, cell_geometry.gd, drag_limit.gd, color_steps.gd,
           relaxation.gd, turns.gd
  audio/   audio_setup.gd, waveform_bank.gd, voice_pool.gd, synth.gd
  input/   board_input.gd
  view/    board_renderer.gd, board_transform.gd
  ui/      settings_panel.gd, gear_button.gd
tests/unit/  GUT-Tests (test_geometry, test_delaunay, test_voronoi,
             test_territories, test_relaxation, test_settings,
             test_synth, test_view, test_board_input, test_color_steps,
             test_cell_geometry, test_drag_limit)
```

`core/` kennt kein Rendering, Audio, UI oder Eingabe. `sim/` veraendert nur
`BoardState`. `app/` ist die einzige Stelle, die alles verdrahtet.

## Datenfluss pro Tick

`_physics_process` (fixed 60 Hz):

1. Drag-Bewegung anwenden (mousemove-Aequivalent); vor der Grenze des
   Territoriums wird sie weich abgebremst
1b. Hover: leiser Ton, wenn der Zeiger auf eine andere Zelle wechselt
2. Voronoi **ohne** Dummy-Punkte aufbauen (Gewichte, Frequenzen, Klick)
3. Klick in Zelle -> Noten; laufender Drag -> Dauertoene
4. Abstandskraefte, Geschwindigkeiten
5. Voronoi **mit** Dummy-Punkten aufbauen (einmal, wird geteilt)
6. Rand-Clamping
6b. Verlust-Schutz: kostet die Position Zellen, geht sie zurueck
7. Farbausbreitung (beim Dragging zweimal, wie im Original; ohne
   Verlust-Schutz stattdessen ein Wechsel pro "Verlust-Schritt")
7b. Nach dem Loslassen: Tonkaskade ab der gezogenen Zelle
8. Drag-Linien-Daten und Bewegungs-Territorium (beim ersten Tick nach dem
   Druecken einmal komplett, danach unveraendert)

`_process`: faellige Noten starten, Huellkurven fortschreiben, gelbe
Ueberlagerung klingender Zellen aktualisieren (Deckkraft folgt der
Lautstaerke des Tons), Zeichnen.

Ruhe-Erkennung: haben sich Punkte und Farben im letzten Tick exakt nicht
geaendert und laeuft kein Drag, werden Schritte 2-8 uebersprungen (das
Ergebnis ist deterministisch identisch). Hover-Toene laufen trotzdem, weil
sie die unveraenderte Geometrie des letzten Ticks nutzen.

## Messwerte

Tick-Kosten (Simulation, ohne Rendering/Audio, aktiv):

| Zellen | Punkte | ms/Tick | Anmerkung |
|---|---|---|---|
| 20 (Default) | 40 | 7.2 | deutlich unter 16.7 ms |
| 50 | 100 | 17.2 | |
| 100 | 200 | 36.9 | Maximum des Reglers |

Im Ruhezustand (Brett beruhigt) bricht der Tick sofort ab und kostet nur noch
einen Bruchteil davon. Audio haengt nicht am Frame-Takt (Noten laufen ueber
eine eigene Uhr), daher gibt es auch bei 100 Zellen keine Aussetzer.

Beim Beginn eines Drags wird das Bewegungs-Territorium einmal berechnet: rund
105 ms bei 20 Zellen (Default). Danach kostet der Tick nur noch die Bremse
(wenige Strahlschnitte gegen die Kontur, deutlich unter 0.1 ms) und die
Pruefung des Verlust-Schutzes.

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
- **Kein Scoring** und keine Punktestand-Anzeige. Das zeitbasierte
  Flaechen-Scoring (`updateScores` und die Balken) aus dem Original ist
  ersatzlos entfernt.
- **Zellfarben** werden ueber die Helligkeit abgestuft: die kleinste Zelle
  ist am dunkelsten (20 % der Grundhelligkeit), die groesste am hellsten
  (80 %). Farbton und Saettigung der Grundfarbe bleiben. Das Original hat das
  umgekehrt (grosse Zellen dunkel).
- **Zellraender**: zwischen zwei gleichfarbigen Zellen liegt eine duenne
  graue Linie (1.5 px), zwischen zwei verschiedenen Farben eine dicke weisse
  Frontlinie (5 px). An der Frontlinie werden die Zellen abgerundet: jede nach
  aussen zeigende Ecke, an der zwei Frontkanten zusammentreffen, wird durch
  einen Bogen ersetzt (Radius aus dem Regler "Front-Abrundung", Standard 8 px,
  0 = spitz). Die dabei abgeschnittene Flaeche wird mit den Farben der beiden
  angrenzenden Zellen gefuellt, damit weder Luecke noch Spitze entsteht.
  Einspringende Ecken bleiben spitz. Das Original zeichnete alle Raender
  gleich.
- **Hover** ist neu: wechselt der Mauszeiger auf eine andere Zelle, klingt
  dort ein sehr leiser Ton (10 % Lautstaerke, Mindestabstand 90 ms, ohne
  Hervorhebung), der Punkt dieser Zelle wird weiss und die Zelle bekommt eine
  weisse Umrandung in der Dicke der normalen Zellgrenze (1.5 px). Das Original
  hatte dafuer nur den Klick und das Ziehen.
- **Zahlen anzeigen** ist ein neuer Schalter (Standard: aus). Er blendet die
  Flaechenzahlen in den Zellen ein; das Original zeigte sie immer.
- **Neustart** setzt Punkte, Zellen, Farben und Zugrecht zurueck. Im Original
  gab es keinen Neustart; die Zellzahl wirkte dort sofort, hier erst beim
  Neustart.
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
- **Verlust-Schutz** ist neu (Schalter "Verhindere Verlust", Standard: an).
  Ist er an, laesst sich ein Punkt nur so weit ziehen, dass keine Zelle des
  eigenen Gebiets ihre Farbe verliert. Eigene Nachbarzellen der gezogenen
  Zelle zaehlen dabei nicht mit: zwischen eigenen Punkten kommt die Zelle
  durch, ohne ihre Farbe zu verlieren. Das Original kannte keine solche
  Bremse.
- **Weiche Bremse** vor der Grenze: der Punkt folgt dem Zeiger auf dem Strahl
  vom Startpunkt aus und wird in Richtung der Grenze zunehmend abgebremst
  (unsichtbare Wand). Bis kurz vor die Grenze folgt er genau, danach naehert
  er sich ihr nur noch an, ohne sie zu erreichen. Die Bremsung ist stetig und
  monoton, es gibt also kein Ruckeln und kein Zurueckspringen. Gemessen wird
  gegen den Strahl durch die gelbe Kontur, damit Anzeige und Bremse
  zusammenpassen; die letzten 12 px vor der Kontur bleiben frei. Wird eine
  Richtung trotzdem einmal blockiert (die Kontur ist eine Naeherung), merkt
  sich die Bremse diese Richtung und stoppt dort kuenftig frueher. Das
  Blockieren des Verlust-Schutzes bleibt als letzte Sicherung erhalten.
- **Bewegungs-Territorium** ist neu: waehrend des Ziehens zeigt eine gelbe,
  gestrichelte Kontur mit schwach gefuellter Flaeche das Gebiet, in dem sich
  Zellen der aktiven Farbe aufhalten duerfen. Es besteht aus der kompletten
  eigenen Farbflaeche und dem Bereich, der ins Gegnergebiet hinein noch
  gefahrlos erreichbar ist; gezeichnet wird eine zusammenhaengende Kontur.
  Die Kontur gehoert zur Farbe, nicht zur gedrueckten Zelle: Grundflaeche ist
  die groesste zusammenhaengende Flaeche der Farbe, und gemessen wird mit der
  eigenen Zelle, auf deren Rand der jeweilige Punkt der eigenen Flaeche liegt.
  Sie wird einmal berechnet, sobald die Geometrie nach dem Druecken vorliegt,
  und waehrend des ganzen Zugs nicht mehr veraendert (Kosten: rund 105 ms).
  Gemessen wird lokal genaehert: fuer eine Probeposition werden alle Zellen in
  ihrem Umkreis (170 px) neu aufgebaut, mit den verschobenen Punkten und den
  dadurch entstehenden Nachbarschaften; weiter aussen liegende Zellen behalten
  ihre Werte, weil ein kompletter Voronoi-Aufbau je Probe rund 4 ms kosten
  wuerde. Zwischen den Messpunkten wird linear ergaenzt und nachgeprueft; von
  jedem Messwert wird ein Sicherheitsabstand (8 px) abgezogen. Die Kontur ist
  damit eine Naeherung: an einzelnen Stellen kann sie etwas weiter reichen als
  der Verlust-Schutz erlaubt (dort greift die Sicherung und die gemerkte
  Richtung der Bremse). Sobald die Farbe getrennte Gebiete hat, wird nur das
  groesste gezeigt.
- **Abspielen beim Loslassen** ist neu: klingende Zellen werden gelb
  ueberlegt. Die Deckkraft folgt dabei der Huellkurve des Tons (Attack, Decay
  auf Sustain, Ausblenden), und Zellen leuchten erst auf, wenn ihr Ton
  tatsaechlich beginnt - die Kaskade ist dadurch nacheinander zu sehen. Eine
  weisse Umrandung oder Funken gibt es nicht.
- **Fensterformat**: skaliert wird von der Engine
  (`window/stretch/mode=canvas_items`, `aspect=keep`): das Brett bleibt immer
  im Verhaeltnis 3:2, passt sich beim Ziehen fluessig an und die ungenutzten
  Raender bleiben leer. Bei genau 900x600 ist die eigene Brett-Transformation
  neutral, Linien und Text werden also im 1:1-Massstab gerastert. Ein
  fruehrerer Ansatz, die Fenstergroesse selbst nachzuziehen, ist entfallen.
- **Einstellungen**: ein kleines Zahnrad oben links oeffnet das Menue
  (`ui/gear_button.gd`, ohne Bilddatei gezeichnet). Das Menue ist eine schmale,
  dunkle Spalte ueber die gesamte Fensterhoehe, mit Abschnitten (Klang, Spiel,
  Darstellung), Wertanzeige je Regler, "Neu starten" am unteren Rand und
  einem "x" zum Ausblenden.
- **Schrittweiser Verlust** ist neu: mit ausgeschaltetem Verlust-Schutz kann
  ein Gebiet verloren gehen. Die einzelnen Farbwechsel laufen dann nicht alle
  im selben Tick, sondern nacheinander im Abstand des Reglers
  "Verlust-Schritt (ms)" (Standard 25 ms). Der erste Wechsel passiert sofort,
  danach ist jeder weitere erst nach dem eingestellten Abstand faellig; ein
  Zeitsprung holt nichts nach. So ist zu sehen, wie die Zellen eine nach der
  anderen fallen. Das Original faerbte sofort um.
