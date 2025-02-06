// ===============================================
// 1) Grund-Setup
// ===============================================
const canvas     = document.getElementById("voronoiCanvas");
const ctx        = canvas.getContext("2d");
const width      = canvas.width;
const height     = canvas.height;
const canvasArea = width * height;

// Parameter für Drag & Drop + Abstoßung
const dragRadius     = 10;
const repelThreshold = 60;   // Für "Abstoßung" beim Drücken
const slowFactor     = 0.2;  // Bremst beim Zu-nah-Sein

// Start-Punkte (zufällig)
let points = generatePoints(20, 900, 600, 30, 0.2);

// Steuerung Drag & Drop
let isDragging   = false;
let draggedIndex = -1;
let currentDraggingCell = null;
let currentDraggingNeighborCell = null;

// Steuerung Klick in Zelle => Ton
let isMouseDownOnCell = false;
let clickedCellId     = -1;
let clickPos          = [0,0];
    
let dragStartX = null;
let dragStartY = null;

let successfulDrag = false;
let colorSwitchedAutomatically = false;

// Highlighting (Zellen, deren Ton spielt)
let highlightMap = {}; 
    
// Speichert pro Zelle: { baseColor: string, isFinal: bool, ... } 
let cellColorMap = {};    
    
// Für "dauerhaftes" Ziehen: Map aus cellIdx -> { oscillator, gainNode }
let dragToneMap = {};

// Web Audio
const audioCtx   = new (window.AudioContext || window.webkitAudioContext)();

// Globale "Limiter" (Kompressor) gegen Clipping
const limiterNode = audioCtx.createDynamicsCompressor();
limiterNode.threshold.setValueAtTime(-8, audioCtx.currentTime); 
limiterNode.knee.setValueAtTime(0, audioCtx.currentTime);
limiterNode.ratio.setValueAtTime(20, audioCtx.currentTime);
limiterNode.attack.setValueAtTime(0.003, audioCtx.currentTime);
limiterNode.release.setValueAtTime(0.2, audioCtx.currentTime);
limiterNode.connect(audioCtx.destination);

// ADSR & Filter & Slider
const waveTypeSel      = document.getElementById("waveType");
const attackSlider     = document.getElementById("attackSlider");
const decaySlider      = document.getElementById("decaySlider");
const sustainSlider    = document.getElementById("sustainSlider");
const releaseSlider    = document.getElementById("releaseSlider");
const cutoffSlider     = document.getElementById("cutoffSlider");
const dragToneVolumeSlider = document.getElementById("dragToneVolumeSlider");
const colorThresSlider = document.getElementById("colorThresSlider");
const freqThresSlider  = document.getElementById("freqThresSlider");
const spreadTimeSlider  = document.getElementById("spreadTimeSlider");
const spreadDepthSlider = document.getElementById("spreadDepthSlider");
const dragVolSlider = document.getElementById("dragVolSlider");
const cellCountSlider   = document.getElementById("cellCountSlider");
const pushFactorSlider  = document.getElementById("pushFactorSlider");
const pushRadiusSlider  = document.getElementById("pushRadiusSlider");
const boundaryRadiusSlider = document.getElementById("boundaryRadiusSlider");
const sizeInfluenceSlider = document.getElementById("sizeInfluenceSlider");
const harmonyInfluenceSlider = document.getElementById("harmonyInfluenceSlider");
const alternatingMovesCheckbox = document.getElementById("alternatingMovesCheckbox");
const freqRatiosCheckbox = document.getElementById("freqRatiosCheckbox");
const dummyPointsCheckbox = document.getElementById("dummyPointsCheckbox");
    
let activeColor = null;
    
let cachedDelaunay = null;
let cachedVoronoi = null;
    
// Erzeuge Dummy-Punkte entlang der Ränder
const dummySpacing = 50; // Abstand zwischen Dummy-Punkten
const dummyMargin = 30; // Abstand außerhalb des Canvas

dummyPointsCheckbox.addEventListener("change", () => {
  updateDelaunayAndVoronoi();
  drawVoronoi();
});

function generateDummyPoints(width, height, spacing, margin) {
  let dPoints = [];
  for (let x = -margin; x <= width + margin; x += spacing) {
    dPoints.push([x, -margin], [x, height + margin]);
  }
  for (let y = -margin; y <= height + margin; y += spacing) {
    dPoints.push([-margin, y], [width + margin, y]);
  }
  return dPoints;
}

let dummyPoints = generateDummyPoints(width, height, dummySpacing, dummyMargin);


function updateDelaunayAndVoronoi() {
  let allPoints = dummyPointsCheckbox.checked ? points.concat(dummyPoints) : points; 
  cachedDelaunay = d3.Delaunay.from(allPoints);
  cachedVoronoi = cachedDelaunay.voronoi([0, 0, width, height]);
}
    

// ===============================================
// 2) Voronoi: Zeichnen, Farb- & Frequenzlogik
// ===============================================
function drawVoronoi() {
  ctx.clearRect(0, 0, width, height);
    
  // Stelle sicher, dass der Cache existiert
  if (!cachedDelaunay || !cachedVoronoi) {
    updateDelaunayAndVoronoi();
  }

  const now      = audioCtx.currentTime;
  const delaunay = cachedDelaunay;
  const voronoi  = cachedVoronoi;
  const colorThreshold = parseFloat(colorThresSlider.value);

  for (let i = 0; i < points.length; i++) {
    const cell = voronoi.cellPolygon(i);
    if (!cell) continue;

    // Flächenberechnung
    const area = polygonArea(cell);
    let ratio  = area / canvasArea;
    if (ratio < 0) ratio = 0;
    if (ratio > 1) ratio = 1;

    let lum;
    if (ratio <= colorThreshold) {
      const t = ratio / colorThreshold; 
      lum = 100 - (100 * t); // 100..0
    } else {
      lum = 0; 
    }

    let greyColor = `hsl(0, 0%, ${lum}%)`;

    // Falls cellColorMap[i].baseColor != null => wir mischen
    let baseC = cellColorMap[i].baseColor;
    if (baseC) {
      // einfache Misch-Logik "multiply" im HSL:
      // lum => 0% = schwarz, 100% = weiß
      // wir gehen z.B. von "baseC" in HSL => multiply lum
      // => wir brauchen ne Hilfsfunktion
      let mixed = mixColorWithGrey(baseC, lum);
      ctx.fillStyle = mixed;
    } else {
      // kein baseColor => fallback grau
      ctx.fillStyle = greyColor;
    }

    // Zelle füllen
    ctx.beginPath();
    ctx.moveTo(cell[0][0], cell[0][1]);
    for (let j = 1; j < cell.length; j++) {
      ctx.lineTo(cell[j][0], cell[j][1]);
    }
    ctx.closePath();
    //ctx.fillStyle = fillColor;
    ctx.fill();

    // Highlight?
    let isHighlighted = false;
    if (highlightMap[i]) {
      const { start, end } = highlightMap[i];
      if (now > end) {
        delete highlightMap[i]; 
      }
      else if (now >= start && now <= end) {
        isHighlighted = true;
      }
    }

    // Rahmen
    if (isHighlighted) {
      ctx.strokeStyle = "white";
      ctx.lineWidth   = 6;
    } else {
      ctx.strokeStyle = "#999";
      ctx.lineWidth   = 3;
    }
    ctx.stroke();
  }

  // Punkte
  for (let i = 0; i < points.length; i++) {
      ctx.beginPath();
      ctx.arc(points[i][0], points[i][1], 5, 0, 2*Math.PI);

      if (alternatingMovesCheckbox.checked) {
        let cellColor = cellColorMap[i] ? cellColorMap[i].baseColor : null;
        if (cellColor !== activeColor) {
          ctx.fillStyle = "gray"; 
        } else {
          ctx.fillStyle = "black";
        }
      } else {
        ctx.fillStyle = "black";
      }
      ctx.fill();
    }

  // draw line to largest neighbor cell:
  if (currentDraggingCell == null || currentDraggingNeighborCell == null) {
      return;
  }
  let pointA = points[currentDraggingCell];
  let pointB = points[currentDraggingNeighborCell];
  ctx.lineWidth = 2;
  ctx.strokeStyle = "black";
  ctx.beginPath();
  ctx.moveTo(pointA[0], pointA[1]);
  ctx.lineTo(pointB[0], pointB[1]);
  ctx.stroke();
  ctx.closePath();
}

// Polygonfläche (Shoelace)
function polygonArea(poly) {
  let area = 0;
  for (let i = 0; i < poly.length; i++) {
    const j = (i + 1) % poly.length;
    area += poly[i][0] * poly[j][1] - poly[j][0] * poly[i][1];
  }
  return Math.abs(area) / 2;
}

function generatePoints(num, w, h, margin, spreadFactor) {
  //return generateRegularPoints(num, w, h, margin);
  return generateRandomButMirroredPoints(num, w, h, margin, spreadFactor);
}

// Zufällige Punkte
function generateRandomPoints(num, w, h, margin, spreadFactor) {
  const arr = [];
  for (let i = 0; i < num; i++) {
    let rx = Math.random();
    let ry = Math.random();
    rx = Math.pow(rx, 1 - spreadFactor);
    ry = Math.pow(ry, 1 - spreadFactor);
    const x = margin + rx * (w - 2*margin);
    const y = margin + ry * (h - 2*margin);
    arr.push([x, y]);
  }
  return arr;
}

function generateRandomButMirroredPoints(num, w, h, margin, spreadFactor) {
  const arr = [];
  ww = w / 2;
  for (let i = 0; i < num; i++) {
    let rx = Math.random();
    let ry = Math.random();
    rx = Math.pow(rx, 1 - spreadFactor);
    ry = Math.pow(ry, 1 - spreadFactor);
    const x = margin + rx * (ww - 2*margin);
    const y = margin + ry * (h - 2*margin);
    arr.push([x, y]);
    arr.push([w - x, y]);
  }
  return arr;
}

// Reguläre Punkte
function generateRegularPoints(num, w, h, margin) {
  const arr = [];
  const cols = Math.ceil(Math.sqrt(num * w / h));
  const rows = Math.ceil(num / cols);
  const spacing = Math.min(w / cols, h / rows);

  for (let i = 0; i < rows; i++) {
    for (let j = 0; j < cols; j++) {
      const x = margin + j * spacing + 0.5 * spacing;
      const y = margin + i * spacing + 0.5 * spacing;
      arr.push([x, y]);
    }
  }
  return arr;
}
    
// Wählt die 2 Zellen mit größter Fläche als Seeds
function initColorTerritories() {
  const delaunay = d3.Delaunay.from(points);
  const voronoi  = delaunay.voronoi([0, 0, width, height]);

  // 1) Flächen bestimmen
  let areas = [];
  for (let i = 0; i < points.length; i++) {
    const cell = voronoi.cellPolygon(i);
    if (!cell) {
      areas[i] = 0;
    } else {
      areas[i] = Math.abs(polygonArea(cell));
    }
  }

  // 2) Sortiere absteigend
  let sorted = areas.map((val, idx) => ({ val, idx }))
                    .sort((a, b) => b.val - a.val);
  if (sorted.length < 2) {
    // fallback, nicht genug Zellen
    return;
  }

  // 3) Wähle big1 = größte Zelle
  let big1 = sorted[0].idx;

  // 4) Finde big2 = NICHT benachbart zu big1
  let big2 = null;
  // Hole neighbors von big1
  let neighborsOfBig1 = new Set(delaunay.neighbors(big1));

  for (let i = 1; i < sorted.length; i++) {
    const candidate = sorted[i].idx;
    if (!neighborsOfBig1.has(candidate)) {
      big2 = candidate;
      break;
    }
  }

  if (big2 === null) {
    // Alle Kandidaten sind Nachbarn? 
    // => fallback: nimm z. B. doch den zweitgrößten, oder gib Warnung aus
    console.warn("Keine nicht-benachbarte Zelle für big2 gefunden!");
    // big2 = sorted[1].idx;  // optional fallback
    return;
  }

  // 5) Reset der cellColorMap
  cellColorMap = {};
  for (let i = 0; i < points.length; i++) {
    cellColorMap[i] = {
      baseColor: null,
      locked: false
    };
  }

  // 6) Seeds festlegen
  cellColorMap[big1].baseColor = "#FF8BA7"; 
  cellColorMap[big2].baseColor = "#76FFE8";
    
  // Setze initial activeColor, falls nicht gesetzt.
  if (!activeColor) {
    activeColor = cellColorMap[big1].baseColor;
  }
}

// Clipping eines Polygons an ein rechteckiges Gebiet (z.B. Canvas)
function clipPolygonToRect(polygon, xMin, yMin, xMax, yMax) {
  let outputList = polygon;

  // Hilfsfunktion: Schneidet einen Polygonrand entlang einer Kante
  function clipEdge(polygon, edge) {
    const inputList = polygon;
    const outputList = [];
    for (let i = 0; i < inputList.length; i++) {
      const currentPoint = inputList[i];
      const prevPoint = inputList[(i - 1 + inputList.length) % inputList.length];
      const currentInside = edge.inside(currentPoint);
      const prevInside = edge.inside(prevPoint);
      
      if (prevInside && currentInside) {
        // Beide Punkte innen: Füge aktuellen Punkt hinzu
        outputList.push(currentPoint);
      } else if (prevInside && !currentInside) {
        // Austritt: Füge Schnittpunkt hinzu
        outputList.push(edge.intersect(prevPoint, currentPoint));
      } else if (!prevInside && currentInside) {
        // Eintritt: Füge Schnittpunkt und aktuellen Punkt hinzu
        outputList.push(edge.intersect(prevPoint, currentPoint));
        outputList.push(currentPoint);
      }
      // Wenn beide außen, füge nichts hinzu.
    }
    return outputList;
  }

  // Definiere die vier Kanten des Rechtecks als Objekte mit zwei Funktionen: inside() und intersect()
  const edges = [
    { // Linke Kante: x >= xMin
      inside: p => p[0] >= xMin,
      intersect: (p1, p2) => {
        const t = (xMin - p1[0]) / (p2[0] - p1[0]);
        return [xMin, p1[1] + t * (p2[1] - p1[1])];
      }
    },
    { // Rechte Kante: x <= xMax
      inside: p => p[0] <= xMax,
      intersect: (p1, p2) => {
        const t = (xMax - p1[0]) / (p2[0] - p1[0]);
        return [xMax, p1[1] + t * (p2[1] - p1[1])];
      }
    },
    { // Obere Kante: y >= yMin
      inside: p => p[1] >= yMin,
      intersect: (p1, p2) => {
        const t = (yMin - p1[1]) / (p2[1] - p1[1]);
        return [p1[0] + t * (p2[0] - p1[0]), yMin];
      }
    },
    { // Untere Kante: y <= yMax
      inside: p => p[1] <= yMax,
      intersect: (p1, p2) => {
        const t = (yMax - p1[1]) / (p2[1] - p1[1]);
        return [p1[0] + t * (p2[0] - p1[0]), yMax];
      }
    }
  ];

  // Wende nacheinander alle Kanten an
  for (const edge of edges) {
    outputList = clipEdge(outputList, edge);
  }
  
  return outputList;
}

// Einfachere Wrapper-Funktion, um das Polygon an den Canvas (0,0,width,height) zu clippen.
function getClippedPolygon(cellPoly) {
  return clipPolygonToRect(cellPoly, 0, 0, width, height);
}

function getVisibleArea(cellIdx) {
  // Erzeuge Voronoi (oder verwende den bereits gecachten, falls möglich)
  const delaunay = d3.Delaunay.from(points);
  const voronoi  = delaunay.voronoi([0, 0, width, height]);
  
  let cellPoly = voronoi.cellPolygon(cellIdx);
  if (!cellPoly) return 0;
  
  // Clipping an den Canvas-Rand durchführen
  let visiblePoly = getClippedPolygon(cellPoly);
  
  // Fläche des sichtbaren Bereichs berechnen
  return Math.abs(polygonArea(visiblePoly));
}

function updateColorsByLargestNeighbor(iterations = 10) {
  const delaunay = d3.Delaunay.from(points);
  const voronoi  = delaunay.voronoi([0, 0, width, height]);

  let changed = true;
  let count = 0;

  while (changed && (count < iterations)) {
    changed = false;
    count++;

    let cellList = [];
    for (let i = 0; i < points.length; i++){

      let a = getVisibleArea(i);

      /* let poly = voronoi.cellPolygon(i);
      let a = poly ? Math.abs(polygonArea(poly)) : 0; */

      cellList.push({ idx: i, area: a });
    }
    cellList.sort((a, b) => b.area - a.area);

    for (let obj of cellList) {
      let i = obj.idx;
      let maxA = -1;
      let maxColor = null;
      let bestNeighbor = null;

      for (let nb of delaunay.neighbors(i)) {
        //Ignoriere Dummy Punkte
        if (nb >= points.length) continue;
        
        let aNb = getVisibleArea(nb);
        if (aNb > maxA && cellColorMap[nb].baseColor) {
          maxA = aNb;
          maxColor = cellColorMap[nb].baseColor;
          bestNeighbor = nb;
        }
      }
      if (maxColor !== null)
        cellColorMap[i].baseColor = maxColor;
    }
  }
}
    
function computeCellWeights(iterations=5) {
  const delaunay = d3.Delaunay.from(points);
  const voronoi  = delaunay.voronoi([0,0,width,height]);
  
  // 1) Grundgewicht = Zellfläche
  let weight = new Array(points.length).fill(0);
  for (let i=0; i<points.length; i++) {
    let poly = voronoi.cellPolygon(i);
    if (!poly) {
      weight[i] = 0;
      continue;
    }
    weight[i] = Math.abs(polygonArea(poly));
  }

  // 2) Vererbung an kleine Zellen, 
  //    falls harmonisch + gleiche Farbe.
  let changed = true;
  let it = 0;
  while (changed && it<iterations) {
    changed = false;
    it++;
    for (let i=0; i<points.length; i++) {
      let myColor = cellColorMap[i].baseColor;
      if (!myColor) continue;
      for (let nb of delaunay.neighbors(i)) {
        if (cellColorMap[nb].baseColor===myColor) {
          // Größeres Gewicht gewinnt
          let bigger = Math.max(weight[i], weight[nb]);
          if (weight[i]!==bigger) {
            weight[i]=bigger;
            changed=true;
          }
          if (weight[nb]!==bigger) {
            weight[nb]=bigger;
            changed=true;
          }
        }
      }
    }
  }
  return weight;
}

/**
 * Wir sammeln "Frontlinien" in einem globalen Set "frontEdges",
 * um sie später fett zu zeichnen.
 */
let frontEdges = new Set();
function markFrontLine(a, b) {
  // a<b zur Eindeutigkeit
  let mini = Math.min(a,b);
  let maxi = Math.max(a,b);
  frontEdges.add(`${mini}-${maxi}`);
}

// ===============================================
// 3) Canvas-Events: Drag & Drop vs. Klick in Zelle
// ===============================================
function getMousePos(e) {
  const rect = canvas.getBoundingClientRect();
  return [e.clientX - rect.left, e.clientY - rect.top];
}

// clamp an Canvas-Rändern: 
function clampToCanvas() {
  // Lies den Randabstand aus dem Slider statt pushRadius
  const boundary = parseFloat(boundaryRadiusSlider.value);

  for (let i = 0; i < points.length; i++) {
    if (points[i][0] < boundary) points[i][0] = boundary;
    if (points[i][0] > width - boundary) points[i][0] = width - boundary;
    if (points[i][1] < boundary) points[i][1] = boundary;
    if (points[i][1] > height - boundary) points[i][1] = height - boundary;
  }
}

canvas.addEventListener("mousedown", (e) => {
  const [mx, my] = getMousePos(e);

  // Punkt-Drag?
  let bestDist = Infinity;
  let hitIndex = -1;
  for (let i = 0; i < points.length; i++) {
    const dx   = points[i][0] - mx;
    const dy   = points[i][1] - my;
    const dist = Math.sqrt(dx*dx + dy*dy);
    if (dist < dragRadius && dist < bestDist) {
      bestDist = dist;
      hitIndex = i;
    }
  }

  if (hitIndex >= 0) {
    if (alternatingMovesCheckbox.checked) {
      let cellColor = cellColorMap[hitIndex].baseColor;
      // Nur erlauben, wenn die Farbe übereinstimmt
      if (cellColor !== activeColor) {
        return; 
      }
    }
    isDragging = true;
    draggedIndex = hitIndex;
    successfulDrag   = false;
    dragStartX = points[draggedIndex][0];
    dragStartY = points[draggedIndex][1];
    spreadDragVolume(hitIndex);
    return;
  }
    

  // Klick in Voronoi-Zelle => Ton
  const delaunay = d3.Delaunay.from(points);
  const idx      = delaunay.find(mx, my);
  if (idx == null) return;

  const voronoi  = delaunay.voronoi([0, 0, width, height]);
  const cellPoly = voronoi.cellPolygon(idx);
  if (!cellPoly) return;

  if (pointInPolygon([mx, my], cellPoly)) {
    clickedCellId     = idx;
    isMouseDownOnCell = true;
    clickPos          = [mx, my];

    // Ausbreitung starten:
    spreadNotes(idx, [mx, my]);
  }
});

canvas.addEventListener("mousemove", (e) => {
  if (!isDragging || draggedIndex < 0) return;

  const [mx, my] = getMousePos(e);

  const ox = points[draggedIndex][0];
  const oy = points[draggedIndex][1];

  // Kleines Slowdown, wenn eng an anderen Punkten
  let tooClose = false;
  for (let i = 0; i < points.length; i++) {
    if (i === draggedIndex) continue;
    const dx   = points[i][0] - mx;
    const dy   = points[i][1] - my;
    const dist = Math.sqrt(dx*dx + dy*dy);
    if (dist < repelThreshold) {
      tooClose = true;
      break;
    }
  }

  const factor = tooClose ? slowFactor : 1.0;

  // 1) Verschiebe den gezogenen Punkt
  let newX = ox + (mx - ox)*factor;
  let newY = oy + (my - oy)*factor;
  points[draggedIndex][0] = newX;
  points[draggedIndex][1] = newY;
    
  // Setze successfulDrag, wenn der Punkt signifikant bewegt wurde
  if (!successfulDrag) {
    const MOVE_THRESHOLD = 1;
    let movedDistance = Math.sqrt(
      Math.pow(points[draggedIndex][0] - dragStartX, 2) +
      Math.pow(points[draggedIndex][1] - dragStartY, 2)
    );
    if (movedDistance > MOVE_THRESHOLD) {
      successfulDrag = true;
    }
  } 

  // 2) Wechselseitiges Wegdrücken
  pushPoints();

  // 3) Rand-Kollision an Canvas
  clampToCanvas();

  // 4) Prüfen, ob sich der gezogene Punkt überhaupt bewegen konnte
  const px = points[draggedIndex][0];
  const py = points[draggedIndex][1];
  const distMoved = Math.sqrt((px - ox)**2 + (py - oy)**2);
  if (distMoved < 0.001) {
    // => Er wurde blockiert
    // => Zurücksetzen auf alte Position
    points[draggedIndex][0] = ox;
    points[draggedIndex][1] = oy;
  }

  if (isDragging && draggedIndex>=0) {
    spreadDragVolume(draggedIndex);
  }
    
  // Prüfe, ob die Farbe der gezogenen Zelle sich geändert hat
  if (alternatingMovesCheckbox.checked && draggedIndex >= 0 && successfulDrag) {
       let currentColor = cellColorMap[draggedIndex].baseColor;
       // Berechne die Distanz seit dem mousedown
       let movedDistance = Math.sqrt(
         Math.pow(points[draggedIndex][0] - dragStartX, 2) +
         Math.pow(points[draggedIndex][1] - dragStartY, 2)
       );
       const MOVE_THRESHOLD = 1; // Minimalbewegung in Pixel
       if (movedDistance > MOVE_THRESHOLD && currentColor && currentColor !== activeColor) {
        
        rampDownAndStopDragTone(draggedIndex);

        // Optional: Falls noch weitere Drag-Töne aktiv sind, stoppe diese sofort (oder ebenfalls ramp down)
        for (let cellIdxStr in dragToneMap) {
          const idx = parseInt(cellIdxStr);
          if (idx !== draggedIndex) {
            stopDragTone(idx);
          }
        }

        isDragging = false;
        draggedIndex = -1;
        activeColor = currentColor;  // Wechsel zur neuen Farbe
        colorSwitchedAutomatically = true;
       }
    }    
    
  //console.log("Set dragging cell globals:");
  let largestNeighborID = getLargestNeighbor(draggedIndex).cellID;
  //console.log(draggedIndex, largestNeighborID);
  currentDraggingCell = draggedIndex;
  currentDraggingNeighborCell = getLargestNeighbor(draggedIndex).cellID;

  updateDelaunayAndVoronoi();
    
  updateColorsByLargestNeighbor(12);    
  
  drawVoronoi();


});

canvas.addEventListener("mouseup", (e) => {
	idx = draggedIndex;
  isDragging   = false;
  draggedIndex = -1;
    
  if (alternatingMovesCheckbox.checked) {
    if (successfulDrag && !colorSwitchedAutomatically) {
      activeColor = (activeColor === "#FF8BA7") ? "#76FFE8" : "#FF8BA7";
    }
    colorSwitchedAutomatically = false;
  }

  // Töne nicht gestoppt -> BFS-Welle läuft ggf.
  if (isMouseDownOnCell) {
    isMouseDownOnCell = false;
  }
    
  // Alle Dauertöne stoppen
  for (let cellIdxStr in dragToneMap) {
      stopDragTone(parseInt(cellIdxStr));
  }
  dragToneMap = {};  
    
  successfulDrag = false;
  currentDraggingCell = null;
  currentDraggingNeighborCell = null;
    // Ausbreitung starten:
    spreadNotes(idx, getMousePos(e));
});

// Punkt-in-Polygon
function pointInPolygon(pt, polygon) {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const xi = polygon[i][0], yi = polygon[i][1];
    const xj = polygon[j][0], yj = polygon[j][1];
    const intersect = ((yi > pt[1]) !== (yj > pt[1])) &&
      (pt[0] < (xj - xi)*(pt[1] - yi)/(yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

// Stößt Punkte gegenseitig ab
function pushPoints() {
  const weight = computeCellWeights();  // s. Codeblock 2 unten
    
  // Wenn eine Zelle manuell gezogen wird, setze ihr Gewicht auf das Originalgewicht
  if (draggedIndex !== -1) {
    const delaunay = d3.Delaunay.from(points);
    const voronoi  = delaunay.voronoi([0,0,width,height]);
    const poly = voronoi.cellPolygon(draggedIndex);
    weight[draggedIndex] = poly ? Math.abs(polygonArea(poly)) : 0;
  }    
  
  const sizeInfluence = parseFloat(sizeInfluenceSlider.value);
  const pushFactor = parseFloat(pushFactorSlider.value); 
  const pushRadius = parseFloat(pushRadiusSlider.value);

  for (let i = 0; i < points.length; i++) {
    for (let j = i + 1; j < points.length; j++) {
      let dx   = points[j][0] - points[i][0];
      let dy   = points[j][1] - points[i][1];
      let dist = Math.sqrt(dx*dx + dy*dy);

      if (dist < pushRadius && dist > 0.0001) {
        let overlap = (pushRadius - dist) * pushFactor;

        // Normiere dx, dy
        dx /= dist;
        dy /= dist;

        let half = overlap * 0.5;
        
        let w_i = weight[i];
        let w_j = weight[j];

        // Falls sizeInfluence=1 & w_i != w_j => es bewegt sich NUR die leichtere Zelle
        if (Math.abs(sizeInfluence - 1) < 0.000001 && w_i !== w_j) {
          // Wer ist schwerer?
          if (w_i > w_j) {
            // i bewegt sich 0, j bewegt sich overlap
            // => dx, dy * overlap (anstatt half)
            points[j][0] += dx * overlap;
            points[j][1] += dy * overlap;
          } else {
            // j ist schwerer => i bewegt sich
            points[i][0] -= dx * overlap;
            points[i][1] -= dy * overlap;
          }
        } 
        else {
          // Interpolations-Modus (sizeInfluence < 1) oder w_i == w_j => wie bisher
          // => effectiveWeight(i) = 1 + (w_i - 1)*sizeInfluence
          // => je größer w_i, desto unbeweglicher i
          let eff_i = 1 + (w_i - 1)*sizeInfluence;
          let eff_j = 1 + (w_j - 1)*sizeInfluence;
          let total = eff_i + eff_j;

          points[i][0] -= dx * half * (eff_j / total);
          points[i][1] -= dy * half * (eff_j / total);
          points[j][0] += dx * half * (eff_i / total);
          points[j][1] += dy * half * (eff_i / total);
        }
      }
    }
  }
}

function pushPointsNoWeight() {
  const pushFactor = parseFloat(pushFactorSlider.value); 
  const pushRadius = parseFloat(pushRadiusSlider.value);

  for (let i = 0; i < points.length; i++) {
    for (let j = i + 1; j < points.length; j++) {
      let dx   = points[j][0] - points[i][0];
      let dy   = points[j][1] - points[i][1];
      let dist = Math.sqrt(dx*dx + dy*dy);

      if (dist < pushRadius && dist > 0.0001) {
        let overlap = (pushRadius - dist) * pushFactor;

        dx /= dist;
        dy /= dist;

        let half = overlap * 0.5;

        // Verschiebe beide gleich
        points[i][0] -= dx * half;
        points[i][1] -= dy * half;
        points[j][0] += dx * half;
        points[j][1] += dy * half;
      }
    }
  }
}


// ===============================================
// 4) AUSBREITUNG: BFS durch Delaunay-Nachbarn
// ===============================================
function spreadNotes(startIdx, mousePos) {
  const delaunay = d3.Delaunay.from(points);
  const maxDepth = parseInt(spreadDepthSlider.value);
  const spreadMs = getSpreadTimeMs();
  const spreadSec = spreadMs / 1000.0;

  // Speichere die Startfarbe der angeklickten Zelle
	if (!(startIdx in cellColorMap))
		// color of cell has changed during dragging
		return;
  let startingColor = cellColorMap[startIdx].baseColor;

  const queue = [];
  const visited = new Set();
  queue.push({ idx: startIdx, depth: 1 });
  visited.add(startIdx);

  const coords = points.map(p => ({x: p[0], y: p[1]}));
  const levels = [];

  while (queue.length > 0) {
    const node = queue.shift();
    const i    = node.idx;
    const d    = node.depth;
    if (d > maxDepth) continue;

    let dx = coords[i].x - mousePos[0];
    let dy = coords[i].y - mousePos[1];
    let dist = Math.sqrt(dx*dx + dy*dy);

    if (!levels[d]) {
      levels[d] = [];
    }
    levels[d].push({ idx: i, dist: dist });

    if (d < maxDepth) {
      for (const nb of delaunay.neighbors(i)) {
        if (!visited.has(nb)) {
          visited.add(nb);
          queue.push({ idx: nb, depth: d+1 });
        }
      }
    }
  }

  // Spiele Töne nur für Zellen derselben Farbe wie die Startzelle ab
  for (let d = 1; d <= maxDepth; d++) {
    if (!levels[d]) continue;
    const arr = levels[d];
    arr.sort((a,b) => a.dist - b.dist);

    const distanceFactor = 0.003; 

    for (const item of arr) {
      // Überprüfe, ob die Zelle die gleiche Farbe wie die Startzelle hat
      if (cellColorMap[item.idx].baseColor === startingColor) {
        const distDelay = item.dist * distanceFactor;
        const offsetTime = audioCtx.currentTime 
                          + (d - 1)*spreadSec 
                          + distDelay;
        scheduleNoteForCell(item.idx, offsetTime);
      }
    }
  }
}

// get largest neighbor for a cell
function getLargestNeighbor(cellIdx) {
  const delaunay = d3.Delaunay.from(points);
  const voronoi = delaunay.voronoi([0, 0, width, height]);
  const neighbors = delaunay.neighbors(cellIdx);
  let largestNeighbor = {
    "cellID": null,
    "maxArea": 0,
  }
  for (const nb of neighbors) {
    let area = polygonArea(voronoi.cellPolygon(nb));
    if (area > largestNeighbor.maxArea) {
      largestNeighbor.cellID = nb;
      largestNeighbor.maxArea = area;
    }
  }
  return largestNeighbor;
}

//BFS-artige Ausbreitung der Lautstärke, solange der Nutzer einen Punkt zieht.    
function spreadDragVolume(startCellIdx) {
  const dragVol = parseFloat(dragVolSlider.value);
  const maxDepth = 2;

  // BFS
  const delaunay = d3.Delaunay.from(points);
  const voronoi = delaunay.voronoi([0, 0, width, height]);
  const queue = [];
  const visited = new Set();

  queue.push({ idx: startCellIdx, depth: 1 });
  visited.add(startCellIdx);

  let largestNeighbor = {
    "cellID": null,
    "maxArea": 0,
  }

  // Wir erzeugen/aktualisieren Töne für jede Zelle im BFS
  while (queue.length > 0) {
    const node = queue.shift();
    const i    = node.idx;
    const d    = node.depth;
    if (d > maxDepth) continue;
    let area = polygonArea(voronoi.cellPolygon(i));
    if (area > largestNeighbor.maxArea) {
      largestNeighbor.cellID = i;
      largestNeighbor.maxArea = area;
    }

    // volume = (dragVol)^(d-1)
    const volume = Math.pow(dragVol, (d-1));

    // Nachbarn
    if (d < maxDepth) {
      for (const nb of delaunay.neighbors(i)) {
        if (!visited.has(nb)) {
          visited.add(nb);
          queue.push({ idx: nb, depth: d+1 });
        }
      }
    }
  }

  //let largestNeighbor = getLargestNeighborForRealYo(startCellIdx);

  // Starte / Updatet Ton
  startOrUpdateDragTone(startCellIdx, 1.0);
  startOrUpdateDragTone(largestNeighbor.cellID, 0.5);

  // Alle anderen Töne, die nicht im BFS sind, sollen gestoppt werden
  for (let cellIdxStr in dragToneMap) {
    const cellIdxNum = parseInt(cellIdxStr);
    if (!visited.has(cellIdxNum)) {
      stopDragTone(cellIdxNum);
    }
  }
}
    
//Erzeugt / aktualisiert einen Dauerton für cellIdx mit gegebener Lautstärke (0..1).
function startOrUpdateDragTone(cellIdx, volumeFactor) {
  // 5ms Attack für "neue" Töne
  const INITIAL_ATTACK_MS = 60;
  const INITIAL_ATTACK_SEC = INITIAL_ATTACK_MS / 1000; // => 0.005

  // (A) Prüfen, ob wir schon einen aktiven Ton haben
  let existing = dragToneMap[cellIdx];
  if (!existing) {
    // (A1) Neuer Ton => Oscillator + GainNode erstellen
    const osc = audioCtx.createOscillator();
    const g   = audioCtx.createGain();
    const f   = audioCtx.createBiquadFilter();

    // Setze die Filter-/Oszillator-Parameter
    osc.type   = waveTypeSel.value;
    f.type     = "lowpass";
    f.frequency.value = getCutoffValue();

    // Start des Osc
    osc.start();

    // Verkabeln
    osc.connect(f);
    f.connect(g);
    g.connect(limiterNode);

    // In 'dragToneMap' ablegen
    dragToneMap[cellIdx] = { 
      osc, 
      gain: g, 
      filter: f, 
      // Wir speichern uns, dass dieser Ton "frisch" ist
      isNew: true 
    };
    existing = dragToneMap[cellIdx];

    // Gain anfangs 0 => minimal clipping
    existing.gain.gain.setValueAtTime(0, audioCtx.currentTime);
  }

  // (B) Frequenz & Volume-Update
  const now     = audioCtx.currentTime;
  const newFreq = getCellFrequency(cellIdx);
  existing.osc.frequency.setValueAtTime(newFreq, now);

  // Volume-Faktor => BFS-Vol * global "dragToneVolume" vom Slider
  const baseVol = parseFloat(dragToneVolumeSlider.value);
  const finalVol = baseVol * volumeFactor;

  // (C) Attack-Logik
  const gNode = existing.gain.gain;
  gNode.cancelScheduledValues(now);

  if (existing.isNew) {
    // (C1) Wenn Ton *neu* ist => Attack = 5ms
    gNode.setValueAtTime(0, now); 
    gNode.linearRampToValueAtTime(finalVol, now + INITIAL_ATTACK_SEC);

    // Danach ist der Ton nicht mehr "neu"
    existing.isNew = false;
  } else {
    // (C2) Sonst => nur "smoother Übergang",
    //     z.B. 50ms Ramp (0.05s), um Frequenz-/Vol-Änderungen
    //     ohne harten Sprung zu machen
    const SMOOTH_SEC = 0.05;

    // Starte an aktuellem Wert
    const currentVal = gNode.value; 
    gNode.setValueAtTime(currentVal, now);
    gNode.linearRampToValueAtTime(finalVol, now + SMOOTH_SEC);
  }
}


// Sofortiges Stoppen des Dauertons einer Zelle
function stopDragTone(cellIdx) {
  let existing = dragToneMap[cellIdx];
  if (existing) {
    const now = audioCtx.currentTime;
    let R = parseFloat(releaseSlider.value);

    let gNode = existing.gain.gain; // das GainNode
    let theOsc = existing.osc;      // der Oscillator

    // ADSR Release => Lautstärke auf 0 in R Sekunden
    gNode.cancelScheduledValues(now);
    gNode.setValueAtTime(gNode.value, now);
    gNode.linearRampToValueAtTime(0, now + R);

    // Stop
    theOsc.stop(now + R + 0.1);

    // Remove from map
    delete dragToneMap[cellIdx];
  }
}

function rampDownAndStopDragTone(cellIdx) {
  let existing = dragToneMap[cellIdx];
  if (!existing) return;

  const now = audioCtx.currentTime;
  
  // Frequenz-Ramp: von der aktuellen Frequenz auf 20 Hz in 1 Sekunde
  existing.osc.frequency.cancelScheduledValues(now);
  // Falls noch nicht gesetzt, stelle sicher, dass wir vom aktuellen Wert starten
  const currentFreq = existing.osc.frequency.value;
  existing.osc.frequency.setValueAtTime(currentFreq, now);
  existing.osc.frequency.linearRampToValueAtTime(20, now + 0.4);

  // Optional: Auch den Gain über 1 Sekunde herunterfahren, sodass der Ton leise wird
  let gNode = existing.gain.gain;
  gNode.cancelScheduledValues(now);
  gNode.setValueAtTime(gNode.value, now);
  gNode.linearRampToValueAtTime(0, now + 1);

  // Den Oszillator nach 1 Sekunde (plus eine kurze Pufferzeit) stoppen
  existing.osc.stop(now + 0.4);

  // Den Drag-Ton aus der Map entfernen
  delete dragToneMap[cellIdx];
}

//Liest die Frequenz einer Zelle analog zu scheduleNoteForCell
function getCellFrequency(cellIdx) {
  // Hole Voronoi, area -> ratio -> freq
  const delaunay = d3.Delaunay.from(points);
  const voronoi  = delaunay.voronoi([0,0,width,height]);
  const cellPoly = voronoi.cellPolygon(cellIdx);
  if (!cellPoly) return 220; // fallback
  const area = polygonArea(cellPoly);
  let ratio  = area / canvasArea;
  if (ratio<0) ratio=0;
  if (ratio>1) ratio=1;

  const freqThreshold = parseFloat(freqThresSlider.value);
  if (ratio <= freqThreshold) {
    const t = ratio / freqThreshold;
    return 1200 - (1200 - 50)*t;
  } else {
    return 50;
  }
}    

// ===============================================
// 5) Web Audio: ADSR, Filter, Frequenz
// ===============================================
function scheduleNoteForCell(cellIdx, startTime) {
  const delaunay = d3.Delaunay.from(points);
  const voronoi  = delaunay.voronoi([0, 0, width, height]);

  const cellPoly = voronoi.cellPolygon(cellIdx);
  if (!cellPoly) return;

  const area = polygonArea(cellPoly);
  let ratio  = area / canvasArea;
  if (ratio < 0) ratio = 0;
  if (ratio > 1) ratio = 1;

  // Frequenz
  const freqThreshold = parseFloat(freqThresSlider.value);
  let freq;
  if (ratio <= freqThreshold) {
    const t = ratio / freqThreshold;
    freq = 1200 - (1200 - 50)*t; 
  } else {
    freq = 50;
  }

  // AudioNodes
  const osc = audioCtx.createOscillator();
  const g   = audioCtx.createGain();
  const f   = audioCtx.createBiquadFilter();

  osc.type = waveTypeSel.value;
  f.type   = "lowpass";
  f.frequency.value = getCutoffValue();

  // ADSR
  const A = parseFloat(attackSlider.value);
  const D = parseFloat(decaySlider.value);
  const S = parseFloat(sustainSlider.value);
  const R = parseFloat(releaseSlider.value);

  // Verkabelung
  osc.connect(f);
  f.connect(g);
  g.connect(limiterNode);

  // Envelope
  g.gain.setValueAtTime(0, startTime);
  // Attack
  g.gain.linearRampToValueAtTime(1.0, startTime + A);
  // Decay->Sustain
  g.gain.linearRampToValueAtTime(S, startTime + A + D);

  // Frequenz
  osc.frequency.setValueAtTime(freq, startTime);

  // Start
  osc.start(startTime);

  // Ton endet
  const noteDuration = 2; 
  const stopTime = startTime + noteDuration + R + 0.1;
  g.gain.linearRampToValueAtTime(0, startTime + noteDuration + R);
  osc.stop(stopTime);

  // Highlight
  highlightMap[cellIdx] = {
    start: startTime,
    end:   stopTime
  };
    
  //console.log("scheduleNoteForCell => start cell ", cellIdx, "time=", startTime);      
}

function stopNote() {
  // Falls globale Stop-Funktion nötig: 
  // Hier nicht implementiert, Töne enden automatisch.
}
    
function getCutoffValue() {
  return parseFloat(cutoffSlider.value);
}

// SpreadTime: 50..1000 ms (oder 50..3000 ms)
function getSpreadTimeMs() {
  const t = parseFloat(spreadTimeSlider.value);
  // z.B. 50..1000 => 50 * 20^t
  return 50 * Math.pow(20, t);
}
    
/**
 * Simple Mix: 
 * wir wandeln baseColor #RRGGBB -> HSL, 
 * dann verringern "Lightness" auf lum%. 
 */
function mixColorWithGrey(hexColor, lum) {
  // lum in [0..100]
  // parse hex
  let r = parseInt(hexColor.slice(1,3),16);
  let g = parseInt(hexColor.slice(3,5),16);
  let b = parseInt(hexColor.slice(5,7),16);

  // konvertiere (r,g,b) -> hsl
  let hsl = rgbToHsl(r,g,b);
  // hsl = [h, s, l] => l in [0..1]
  // wir normalisieren lum% => lum/100 => scale
  let newL = (lum / 100) * (hsl[2]); // wir multiplizieren "l" mit lum/100
  // du kannst es feiner anpassen

  // Zur Vorsicht: newL = Math.min(1, newL)
  if (newL>1) newL=1;

  // hsl->rgb-> hex
  let newRGB = hslToRgb(hsl[0], hsl[1], newL);
  return rgbToHex(newRGB[0], newRGB[1], newRGB[2]);
}

// Hilfsfunktionen rgb <-> hsl <-> hex
function rgbToHsl(r, g, b) {
  r/=255; g/=255; b/=255;
  let max = Math.max(r,g,b);
  let min = Math.min(r,g,b);
  let h,s,l = (max+min)/2;
  if (max==min) {
    h=s=0; 
  } else {
    let d = max-min;
    s = (l>0.5) ? d/(2-max-min) : d/(max+min);
    if (max==r) {
      h=(g-b)/d + (g<b?6:0);
    } else if (max==g) {
      h=(b-r)/d+2;
    } else {
      h=(r-g)/d+4;
    }
    h/=6;
  }
  return [h,s,l];
}
function hslToRgb(h,s,l){
  if(s==0){ 
    let val=Math.round(l*255); 
    return [val,val,val];
  }
  function hue2rgb(p,q,t){
    if(t<0) t+=1;
    if(t>1) t-=1;
    if(t<1/6) return p+(q-p)*6*t;
    if(t<1/2) return q;
    if(t<2/3) return p+(q-p)*(2/3 - t)*6;
    return p;
  }
  let q = (l<0.5)?(l*(1+s)):(l+s-l*s);
  let p=2*l-q;
  let r=hue2rgb(p,q,h+1/3);
  let g=hue2rgb(p,q,h);
  let b=hue2rgb(p,q,h-1/3);
  return [Math.round(r*255), Math.round(g*255), Math.round(b*255)];
}
function rgbToHex(r,g,b){
  let rr=r.toString(16).padStart(2,'0');
  let gg=g.toString(16).padStart(2,'0');
  let bb=b.toString(16).padStart(2,'0');
  return '#'+rr+gg+bb;
}

// ===============================================
// 7) Animations-Loop für Echtzeit-Highlight
// ===============================================
function animate() {
  requestAnimationFrame(animate);
  drawVoronoi();
}

// Event Listener
colorThresSlider.addEventListener("input", () => {
  // Wir müssen nichts Spezielles tun, 
  // da drawVoronoi() in animate() loop erfolgt
});
freqThresSlider.addEventListener("input", () => {
  // Frequenz ändert sich erst beim nächsten Klick
});
spreadTimeSlider.addEventListener("input", () => {
  // Ausbreitungstempo ändert sich erst beim nächsten Klick
});
spreadDepthSlider.addEventListener("input", () => {
  // Tiefe ändert sich erst beim nächsten Klick
});
cutoffSlider.addEventListener("input", () => {
  // Für neue Töne wirksam
});
waveTypeSel.addEventListener("change", () => {
  // Für neue Töne wirksam
});
cellCountSlider.addEventListener("input", () => {
  const n = parseInt(cellCountSlider.value, 10);
  points = generatePoints(n, width, height, 30, 0.2);
    
  // => mehr Iterationen, z.B. 30 anstatt 10, damit die Punkte sich nicht überlappen
  let relaxTimes = (n>50) ? 30 : 10;

  for (let i = 0; i < relaxTimes; i++) {
    // Rufe "pushPoints()" in einer "Light-Version", die NICHT computeCellWeights() nutzt.
    pushPointsNoWeight(); 
    clampToCanvas();
  }

  updateDelaunayAndVoronoi();    
    
  highlightMap = {};

  initColorTerritories();
  updateColorsByLargestNeighbor(12);
  drawVoronoi();
}); 

// ===============================================
// 8) Los geht's
// ===============================================
    
// Jetzt die Farbterritorien initialisieren
initColorTerritories();
updateColorsByLargestNeighbor();
    
// Starte den permanenten Animations-Loop für Echtzeit-Highlight
animate();
