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
## Gemeinsame Grenzlaenge je Zelle und Nachbar.
var edge_lengths: Array = []


static func from_voronoi(voronoi: Voronoi, include_topological := false) -> CellGeometry:
	var geometry := CellGeometry.new()
	var count := voronoi.real_count
	geometry.areas.resize(count)
	geometry.neighbors.resize(count)
	geometry.edge_lengths.resize(count)
	for i in range(count):
		geometry.areas[i] = voronoi.area(i)
		var neighbors := {}
		for neighbor in voronoi.visible_neighbors_of(i):
			neighbors[neighbor] = true
		if include_topological:
			# Delaunay-Nachbarn sind die vollstaendige topologische Nachbarschaft.
			# Die sichtbare Kantenpruefung kann bei Randzellen ohne Dummy-Punkte
			# eine gemeinsame Kante als zu kurz verwerfen.
			for neighbor in voronoi.delaunay().neighbors(i):
				if neighbor < count:
					neighbors[neighbor] = true
		var sorted := neighbors.keys()
		sorted.sort()
		geometry.neighbors[i] = PackedInt32Array(sorted)
		var lengths := {}
		for neighbor in sorted:
			lengths[neighbor] = voronoi.visible_common_edge_length(i, neighbor)
		geometry.edge_lengths[i] = lengths
	return geometry


## Anzahl der Zellen dieses Ausschnitts.
func count() -> int:
	return areas.size()
