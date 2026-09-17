class_name CellGeometry
extends RefCounted

## Geometrie der Farbausbreitung: Flaeche und sichtbare Nachbarn je Zelle.
##
## Die Ausbreitung braucht nur diese beiden Angaben. Sie einmal aus dem
## Voronoi zu ziehen ist billig. Die Drag-Vorschau kann damit einzelne
## Flaechen austauschen, ohne das ganze Voronoi neu zu bauen (ein kompletter
## Aufbau kostet rund 4 ms und waere fuer 60 Hz zu teuer).

## Flaeche je Zelle, Index wie im Voronoi.
var areas := PackedFloat32Array()
## Sichtbare Nachbarn je Zelle. Eintraege koennen auf Dummy-Punkte zeigen;
## die Ausbreitung ueberspringt sie.
var neighbors: Array = []


static func from_voronoi(voronoi: Voronoi) -> CellGeometry:
	var geometry := CellGeometry.new()
	var count := voronoi.real_count
	geometry.areas.resize(count)
	geometry.neighbors.resize(count)
	for i in range(count):
		geometry.areas[i] = voronoi.area(i)
		geometry.neighbors[i] = voronoi.visible_neighbors_of(i)
	return geometry


## Anzahl der Zellen dieses Ausschnitts.
func count() -> int:
	return areas.size()
