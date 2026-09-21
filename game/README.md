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
Fenstergroesse und haelt dabei das Seitenverhaeltnis. Die Spielflaeche hat
dabei mindestens 50 px Abstand zu oben und den Seiten sowie 70 px nach
unten fuer die Ausdauerbalken (`project.godot`:
`window/stretch/mode=canvas_items`,
`window/stretch/aspect=keep`). Alle Regler werden in `user://settings.cfg`
gespeichert und beim Start geladen.

Die Zellzahl wirkt wie im Original durch die gespiegelte Punkterzeugung
doppelt: "20 Zellen" im Regler ergeben 40 Zellen auf dem Brett. Die Zellzahl
greift erst beim Neustart.

## Tests

```powershell
godot --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

Aktueller Stand: 192 Tests / 36517 Asserts, alle gruen.
Abgedeckt: Geometrie, Delaunay, Voronoi (inkl. Robustheit ueber mehrere
Bretter und Ticks), Territorien/Zugwechsel, schrittweiser Farbwechsel,
durchgehende Territoriums-Grenzen beim Drag, Zeichnen eines kompletten
Frames, Einstellungsmenue, Relaxation, Konfiguration/Einstellungen,
Notenplanung/Audio-Zeitversatz (inkl. Hover-Toene und Uebernahme-Warnung),
Zell-Abrundung, Skalierung und Farbberechnung.

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
  sim/     territories.gd, cell_geometry.gd, influence.gd, color_steps.gd,
           relaxation.gd, turns.gd
  audio/   audio_setup.gd, waveform_bank.gd, voice_pool.gd, synth.gd
  input/   board_input.gd
  view/    board_renderer.gd, board_transform.gd, halftone_overlay.gd
  ui/      settings_panel.gd, gear_button.gd
shaders/   halftone.gdshader (CMYK-Halbton)
assets/    halftone_pattern.png (Streumuster des Halbtons)
tests/unit/  GUT-Tests (test_geometry, test_delaunay, test_voronoi,
             test_territories, test_relaxation, test_settings,
             test_synth, test_view, test_board_input, test_color_steps,
              test_cell_geometry, test_halftone)
```

`core/` kennt kein Rendering, Audio, UI oder Eingabe. `sim/` veraendert nur
`BoardState`. `app/` ist die einzige Stelle, die alles verdrahtet.

## Datenfluss pro Tick

`_physics_process` (fixed 60 Hz):

1. Drag-Bewegung anwenden (mousemove-Aequivalent); der Punkt folgt dem Zeiger
   ungebremst
1b. Hover: leiser Ton, wenn der Zeiger auf eine andere Zelle wechselt
2. Voronoi **ohne** Dummy-Punkte aufbauen (Gewichte, Frequenzen, Klick)
3. Klick in Zelle -> Noten; laufender Drag -> Dauertoene
4. Abstandskraefte, Geschwindigkeiten
5. Voronoi **mit** Dummy-Punkten aufbauen (einmal, wird geteilt)
6. Rand-Clamping
7. Farbausbreitung (beim Dragging zweimal, wie im Original; Wechsel werden
   beim Verlust nacheinander angewendet)
7b. Nach dem Loslassen: Tonkaskade ab der gezogenen Zelle
8. Drag-Uebernahme-Warnung

`_process`: faellige Noten starten, Huellkurven fortschreiben, blinkende
Uebernahme-Warnung aktualisieren, Zeichnen.

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

Beim Beginn eines Drags werden die groessten gleich- und gegnerisch gefaerbten
Nachbarn bestimmt. Die Warnung blinkt schneller, je naeher der Gegner am
Uebernahme-Punkt liegt.

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
- **Zellfarben** folgen den drei Stufen aus `assets/spielerfarben.svg`: die
  groesste Zelle eines Spielers traegt Stufe 1, die groessere Haelfte der
  restlichen Zellen Stufe 2 und die kleinere Haelfte Stufe 3. Die Aufteilung
  ist relativ zu den Zellen des jeweiligen Spielers; ein Spieler mit kleineren
  Zellen und Territorium wird also genauso abgestuft wie ein grosser. Die
  Spielerfarben bleiben unveraendert; die Schwaeche einer Zelle wird nur durch
  das Blinken angezeigt. Zellen, deren Zellwert unter der Neutral-Schwelle
  (Standard 10) liegt, gelten als neutral: sie werden statt in Spielerfarbe im
  einstellbaren Neutralgrau (Regler "Neutralgrau", Standard mittleres Grau
  `#808080`) gezeichnet und zaehlen nicht zum Territorium. Sie gehoeren keinem
  Spieler mehr: sie vererben keine Werte an kleinere Nachbarn und zaehlen bei
  der Flaechenwertung nicht mit.
- **Zellraender**: zwischen zwei gleichfarbigen Zellen liegt eine duenne
  graue Linie (1.5 px) mittig auf der Kante. Zur fremden Farbe und zum
  Brettrand laeuft eine dicke Linie (5 px) in der eigenen Teamfarbe. Sie wird
  um ihre halbe Breite ins Zellinnere versetzt und liegt damit vollstaendig
  innerhalb der eigenen Form; an der gemeinsamen Front zeichnen beide Zellen
  ihre eigene Farbe auf ihrer Seite, sodass die beiden Linien direkt
  aneinander liegen, ohne sich zu ueberdecken. Die Frontlinie laeuft nur um die
  tatsaechlich in Spielerfarbe gezeichneten Zellen (Neutralzellen bilden
  Luecken). Abgerundet werden die
  konvexen Ecken aller Zellen (Radius aus dem Regler "Zell-Abrundung",
  Standard 8 px, 0 = spitz); die Aufloesung des Bogens haengt an der
  Bogenlaenge (mindestens acht Stuetzpunkte, bei grossen Radien bis 28), damit
  die Ecken auch bei grossem Radius weich aussehen. Die Linien bleiben dabei
  innerhalb der Zellfuellung, es entstehen also keine Luecken. Einspringende
  Ecken bleiben spitz. Das Original zeichnete alle Raender gleich
  (weisse Frontlinie).
- **Hover** ist neu: wechselt der Mauszeiger auf eine andere Zelle, klingt
  dort ein sehr leiser Ton (10 % Lautstaerke, Mindestabstand 90 ms, ohne
  Hervorhebung), der Punkt dieser Zelle wird weiss und die Zelle bekommt eine
  weisse Umrandung in der Dicke der normalen Zellgrenze (1.5 px). Die
  Umrandung ist an den konvexen Ecken genauso gerundet wie die Zellraender.
  Das Original hatte dafuer nur den Klick und das Ziehen.
- **Zahlen anzeigen** ist ein Schalter (Standard: aus). Er blendet den Wert
  (den Flusswert) der Zelle unter dem Zeiger und ihrer Nachbarn ein; **Zahlen
  fuer alle Zellen** zeigt den Wert jeder Zelle. Werte sind vorzeichenbehaftet:
  rote Zellen positiv, blaue Zellen negativ; Zellen ohne Zufluss zeigen 0.
- **Flow anzeigen** zeigt das Kraftfeld: an jeder Grenze ein Pfeil in der
  Spielerfarbe der groesseren Zelle, von der groesseren zur kleineren Zelle.
  Auf dem Pfeil steht die Fliessmenge dieser Kante (der Anteil, den die
  groessere Zelle an die kleinere abgibt) in weisser Schrift, mittig auf dem
  Pfeil, rot positiv und blau negativ. Kanten ohne Fluss (Fliessmenge 0)
  werden weder als Pfeil noch als Zahl gezeigt. Neutrale Zellen ohne Farbe
  bekommen einen grauen Pfeil. So entsteht ein Vektorfeld von gross nach klein.
  Grosse Fliessmengen bekommen breite, lange Pfeile, kleine Fliessmengen kurze,
  schmale Pfeile (Bezug ist der groesste Fluss des Feldes). Die maximale Breite
  und Laenge stehen als Regler "Pfeilbreite" und "Pfeillaenge", die
  Schriftgroesse als "Pfeil-Schriftgroesse" in der Rubrik Darstellung. Pfeile
  und Zahlen lassen sich gleichzeitig anzeigen.
- **Kraftverteilung** ersetzt die frueheren Flow- und Nachbarwert-Regeln: nur
  die groesste Zelle je Spieler (die Wurzel) traegt einen eigenen Groessenwert,
  rot positiv und blau negativ. Waechst im Spiel eine andere Zelle zur
  groessten ihrer Farbe heran, wandert die Wurzel mit; so traegt die groesste
  Zelle immer den Groessenwert. Der Wert ist die Tonmenge x (Regler "Tonmenge
  (x)" in der Rubrik "Gameplay Core", Standard 100) fuer die groesste Zelle des
  Bretts; eine kleinere Wurzel traegt entsprechend weniger (x mal ihre Flaeche
  geteilt durch die groesste Flaeche). So kann eine kleinere blaue Wurzel vom
  groesseren roten Zufluss ueberholt werden. Weitergegeben wird immer der
  angezeigte (Netto-)Zellwert, also Groessenwert plus der bei der Zelle
  ankommende gegnerische Fluss: zieht der Gegner etwas ab, fliesst entsprechend
  weniger weiter, und gleicht der Zufluss den Groessenwert aus, fliesst nichts
  mehr weiter. Alle anderen Zellen bekommen ausschliesslich die Summe der
  Flusswerte, die von groesseren Nachbarn ankommen; die eigene Zellgroesse
  zaehlt nicht mit. Von jeder Zelle fliesst ihr Wert an die naechstkleineren
  Nachbarn, aufgeteilt nach der gemeinsamen Kantenlaenge. Der Zellwert ist damit
  die vorzeichenbehaftete Summe der Zufluesse: zwei rote Nachbarn mit +20 und
  +30 und ein blauer mit -40 ergeben +10. Eine Zelle gehoert dem Spieler, dessen
  Zufluss an ihr ueberwiegt; Zellen ohne Zufluss behalten ihre Farbe.
- **Gespiegelter Start**: Die Punkte werden paarweise erzeugt und nach der
  Entspannung exakt gespiegelt. Die beiden Wurzelzellen sind Spiegelpartner,
  damit die Startaufstellung symmetrisch ist. Damit der Fluss diese Symmetrie
  nicht durch Rundungsrauschen verliert, vergleicht er die Zellgroessen ueber
  gerundete Groessenstufen.
- **Uebernahme-Warnung**: Nur die gezogene Zelle blinkt kurz vor einem
  Farbverlust. Je naeher der gegnerische Flaechenanteil am Kipp-Punkt liegt,
  desto schneller blinkt die Warnung. Zellen mit kleinen Werten blinken nicht
  mehr von selbst.
- **Neustart** setzt Punkte, Zellen, Farben und Zugrecht zurueck. Im Original
  gab es keinen Neustart; die Zellzahl wirkte dort sofort, hier erst beim
  Neustart.
- **Tote Stellen entfallen** (wie im Plan): `harmonyInfluenceSlider`,
  `colorThresSlider`/`colorThreshold`, `getLargestNeighbor()`,
  `generateRegularPoints()`, `generateRandomPoints()`,
  `getMaxCommonEdgeLengthForColor()`.
- **Dragtone Neighbor Factor** ist im Original wirkungslos (der Wert landet
  nur in einer nie gelesenen Variable); die zweite Stimme fuer die groesste
  Zelle der Spielerfarbe ist wie dort fest 0.5. Der Regler bleibt erhalten,
  hat aber keinen hoerbaren Effekt.
- **Audio**: der globale Cutoff ist ein Lowpass auf dem Bus "Synth" statt
  eines Filters pro Note (gleiche Wirkung, da der Wert global ist). Der
  Limiter ist ein `AudioEffectCompressor` mit den Originalwerten
  (Schwelle -8 dB, Ratio 20, Attack 3 ms, Release 200 ms); ein Knie-Parameter
  existiert in Godot nicht. Die Huellkurve bildet die Web-Audio-Ramps exakt
  nach (auch das Absinken waehrend der Haltephase).
- **Wellenformen** werden bandbegrenzt (18 Harmonische) als eine Periode
  erzeugt und ueber `pitch_scale` gestimmt; der Rest der Klangformung bleibt
  wie im Original (ADSR, Lowpass, Limiter).
- **Stimmung**: die Tonhoehe einer Zelle ist nicht mehr stufenlos, sondern
  wird auf die naechste Note einer Skala gerundet (`audio/tuning.gd`).
  Standard ist 12-stufig gleichstufig mit A4 = 432 Hz. Eine Stimmung besteht
  aus Referenzfrequenz und den Verhaeltnissen einer Oktave, sodass weitere
  Temperaturen (andere Schrittweite oder feste Intervalle) moeglich sind;
  gesetzt wird sie ueber `Synth.tuning`.
- **Doppelte Dummy-Ecken** (die Erzeugung erzeugt zwei Paare doppelt) sind
  bewusst nicht entdoppelt; sie erhalten wie bei d3 keine Zelle.
- **Drag-Bewegung** wird einmal pro Tick angewendet statt pro Mausereignis;
  Slow-Faktor, Blockierung und Zugwechsel bleiben gleich.
- **Abspielen beim Loslassen** ist neu: klingende Zellen werden entsprechend
  der Lautstaerke ihres Tons hervorgehoben. Beim Verlust einer eigenen Zelle
  faellt ihre Tonhoehe wie in der Webversion nach unten.
- **Fensterformat**: skaliert wird von der Engine
  (`window/stretch/mode=canvas_items`, `aspect=keep`): das Brett bleibt immer
  im Verhaeltnis 3:2, passt sich beim Ziehen fluessig an und die ungenutzten
  Raender bleiben leer. Bei genau 900x600 ist die eigene Brett-Transformation
  neutral, Linien und Text werden also im 1:1-Massstab gerastert. Ein
  fruehrerer Ansatz, die Fenstergroesse selbst nachzuziehen, ist entfallen.
- **Einstellungen**: ein kleines Zahnrad oben links oeffnet das Menue
  (`ui/gear_button.gd`, ohne Bilddatei gezeichnet). Das Menue ist eine schmale,
  dunkle Spalte ueber die gesamte Fensterhoehe, mit Abschnitten (Gameplay Core,
  Klang, Spiel, Darstellung, Halbton), Wertanzeige je Regler, "Neu starten" am
  unteren Rand und einem "x" zum Ausblenden. Die Wertanzeige ist ein direkt
  editierbares Zahlenfeld: ein Klick setzt den Cursor und waehlt den Wert aus,
  Enter oder Fokusverlust uebernehmen die Eingabe und begrenzen sie auf den
  erlaubten Bereich.
- **Schrittweiser Verlust**: Mehrere Farbwechsel laufen nacheinander im
  Abstand des Reglers "Verlust-Schritt (ms)" (Standard 25 ms). So ist zu
  sehen, wie die Zellen eine nach der anderen fallen.
- **Grauer Zugverlust**: Wird die gezogene Zelle grau (Zellwert unter der
  Neutral-Schwelle), droht derselbe Zugverlust wie bei einem Verlust an die
  Gegnerfarbe: Pitch-Down und Rettungszeit. Wird sie nicht rechtzeitig wieder
  stark genug, geht der Zug an den Gegner.
- **CMYK-Halbton**: Ein bildschirmweiter Effekt (`shaders/halftone.gdshader`,
  gesteuert von `view/halftone_overlay.gd`, nach dem "Canvas Item Halftone
  Shader" von OskarGosbol) zerlegt das Spiel in CMYK. Jede Druckfarbe bekommt
  ein eigenes, gedrehtes Punktraster, die Punkte liegen auf weissem Papier. Die
  Punktschwelle kommt aus einem Streumuster, das entweder beim Start im Code
  erzeugt oder als `assets/halftone_pattern.png` geladen wird; der Regler
  "Streumuster" waehlt die Quelle. Das Rechteck liegt unter dem
  Einstellungsmenue, deshalb bleiben die Einstellungen ungerastert. Alle Werte
  stehen als Regler in der Gruppe "Halbton" und wirken ohne Neustart;
  "Halbtonraster" schaltet den Effekt ganz aus.
