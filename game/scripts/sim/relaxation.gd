class_name Relaxation
extends RefCounted

## Abstandskraefte, Gewichte, Geschwindigkeiten und Rand-Clamping.
##
## Paritaet zu pushPoints / pushPointsNoWeight / computeCellWeights /
## updatePointPositions / clampToCanvas aus src/core.js.

## Gewicht je Zelle: Basis ist die Zellflaeche (Voronoi ohne Dummy-Punkte),
## danach erben kleine Zellen das Gewicht gleichfarbiger Nachbarn.
static func compute_cell_weights(board: BoardState, voronoi: Voronoi, iterations := GameConfig.WEIGHT_INHERITANCE_ITERATIONS) -> PackedFloat32Array:
	var count := board.points.size()
	var weight := PackedFloat32Array()
	weight.resize(count)
	for i in range(count):
		weight[i] = voronoi.area(i)

	var ids := board.color_ids()
	var changed := true
	var it := 0
	while changed and it < iterations:
		changed = false
		it += 1
		for i in range(count):
			var my_id := ids[i]
			if my_id == 0:
				continue
			for nb in voronoi.delaunay().neighbors(i):
				if nb >= count or ids[nb] != my_id:
					continue
				var bigger := maxf(weight[i], weight[nb])
				if weight[i] != bigger:
					weight[i] = bigger
					changed = true
				if weight[nb] != bigger:
					weight[nb] = bigger
					changed = true
	return weight


## Abstandskraft mit Gewichten (pushPoints).
static func push_points(board: BoardState, config: GameConfig, weights: PackedFloat32Array) -> void:
	var points := board.points
	var count := points.size()
	var size_influence := config.weight_influence
	var push_factor := config.push_factor
	var push_radius := config.push_radius
	var push_radius_sq := push_radius * push_radius
	var grid := _build_spatial_grid(points, push_radius)
	for i in range(count):
		var grid_pos := _grid_position(points[i], push_radius)
		for gx in range(grid_pos.x - 2, grid_pos.x + 3):
			for gy in range(grid_pos.y - 2, grid_pos.y + 3):
				for j in grid.get(Vector2i(gx, gy), []):
					if j <= i:
						continue
					var pi := points[i]
					var pj := points[j]
					var diff := pj - pi
					var dist_sq := diff.length_squared()
					if dist_sq >= push_radius_sq or dist_sq <= 0.00000001:
						continue
					var dist := sqrt(dist_sq)
					var direction := diff / dist
					var overlap := (push_radius - dist) * push_factor
					var half := overlap * 0.5
					var w_i := weights[i]
					var w_j := weights[j]
					if absf(size_influence - 1.0) < 0.000001 and w_i != w_j:
						if w_i > w_j:
							points[j] = pj + direction * overlap
						else:
							points[i] = pi - direction * overlap
					else:
						var eff_i := 1.0 + (w_i - 1.0) * size_influence
						var eff_j := 1.0 + (w_j - 1.0) * size_influence
						var total := eff_i + eff_j
						points[i] = pi - direction * (half * (eff_j / total))
						points[j] = pj + direction * (half * (eff_i / total))
	board.points = points


## Abstandskraft ohne Gewichte (pushPointsNoWeight).
static func push_points_no_weight(board: BoardState, config: GameConfig) -> void:
	var points := board.points
	var count := points.size()
	var push_factor := config.push_factor
	var push_radius := config.push_radius
	var push_radius_sq := push_radius * push_radius
	var grid := _build_spatial_grid(points, push_radius)
	for i in range(count):
		var grid_pos := _grid_position(points[i], push_radius)
		for gx in range(grid_pos.x - 2, grid_pos.x + 3):
			for gy in range(grid_pos.y - 2, grid_pos.y + 3):
				for j in grid.get(Vector2i(gx, gy), []):
					if j <= i:
						continue
					var pi := points[i]
					var pj := points[j]
					var diff := pj - pi
					var dist_sq := diff.length_squared()
					if dist_sq >= push_radius_sq or dist_sq <= 0.00000001:
						continue
					var dist := sqrt(dist_sq)
					var direction := diff / dist
					var half := (push_radius - dist) * push_factor * 0.5
					points[i] = pi - direction * half
					points[j] = pj + direction * half
	board.points = points


## Spatial Hash statt eines vollstaendigen Paarscans. Das Raster wird pro
## Kraeftepass einmal aufgebaut; ein Radius von zwei Rasterzellen deckt auch
## Paare ab, die durch vorherige Verschiebungen innerhalb des Passes naeher
## zusammenruecken. Die Reihenfolge bleibt deterministisch.
static func _build_spatial_grid(points: PackedVector2Array, cell_size: float) -> Dictionary:
	var grid := {}
	var safe_size := maxf(cell_size, 1.0)
	for i in range(points.size()):
		var key := _grid_position(points[i], safe_size)
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	return grid


static func _grid_position(point: Vector2, cell_size: float) -> Vector2i:
	var safe_size := maxf(cell_size, 1.0)
	return Vector2i(floori(point.x / safe_size), floori(point.y / safe_size))


## Geschwindigkeiten daempfen und anwenden (updatePointPositions).
## Die Kraefte oben verschieben Punkte direkt; die Geschwindigkeiten
## bleiben deshalb bei 0. Die Funktion bleibt aus Paritaetsgruenden
## erhalten.
static func update_point_positions(board: BoardState) -> void:
	if board.velocities.size() != board.points.size():
		return
	var points := board.points
	for i in range(points.size()):
		var v := board.velocities[i] * GameConfig.RELAX_DAMPING
		board.velocities[i] = v
		points[i] = points[i] + v
	board.points = points


## Punkte am Brettrand halten (clampToCanvas).
static func clamp_to_canvas(board: BoardState, config: GameConfig) -> void:
	var boundary := config.border_margin
	var max_x := GameConfig.BOARD_WIDTH - boundary
	var max_y := GameConfig.BOARD_HEIGHT - boundary
	var points := board.points
	for i in range(points.size()):
		var p := points[i]
		p.x = clampf(p.x, boundary, max_x)
		p.y = clampf(p.y, boundary, max_y)
		points[i] = p
	board.points = points
