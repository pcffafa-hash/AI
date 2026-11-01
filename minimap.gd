extends Control
## Quadratische Minikarte, Blickrichtung = oben.

signal expanded_changed(expanded: bool)

var main
var info_label: Control
var inventory
var expanded := false
const PX := 3.0
const VIEW := 40.0          # Sichtweite der Karte in Weltmetern (wie vorher)
const CELL := 20.0          # Rasterzellen für schnelles Aussortieren
const C_ROAD := Color(0.24, 0.24, 0.25)
const C_TREE := Color(0.18, 0.35, 0.13)
const C_ROCK := Color(0.47, 0.48, 0.44)

var _tree_grid := {}
var _rock_grid := {}
var _tree_n := -1
var _tree_v := -1
var _rock_n := -1

func setup(main_node, info: Control, inventory_module) -> void:
	main = main_node
	info_label = info
	inventory = inventory_module
	custom_minimum_size = Vector2(150, 150)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_apply_expanded(false)
	expanded_changed.connect(_apply_expanded)

func _gui_input(event: InputEvent) -> void:
	var clicked: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		clicked = event.pressed
	if clicked:
		expanded = not expanded
		expanded_changed.emit(expanded)
		accept_event()

func _apply_expanded(is_expanded: bool) -> void:
	custom_minimum_size = Vector2(300, 300) if is_expanded else Vector2(150, 150)
	offset_left = -347.0 if is_expanded else -197.0
	offset_right = -47.0
	offset_top = 80.0 if is_expanded else 16.0
	offset_bottom = 380.0 if is_expanded else 166.0
	if is_instance_valid(info_label):
		info_label.position.y = 390.0 if is_expanded else 176.0
	if inventory != null:
		inventory.set_map_expanded(is_expanded)

func _process(_d: float) -> void:
	if not is_visible_in_tree() or main == null or main.state == "menu" or get_tree().paused:
		return
	queue_redraw()

## Sortiert die Positionen in ein Raster ein (nur neu, wenn sich die Anzahl ändert).
func _build_grid(src: Array) -> Dictionary:
	var grid := {}
	for p: Vector2 in src:
		var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
		if not grid.has(key):
			grid[key] = PackedVector2Array()
		grid[key].append(p)
	return grid

func _ensure_grids() -> void:
	var tv: int = main.world.tree_version if main.world != null else 0
	if main.tree_pos.size() != _tree_n or tv != _tree_v:
		_tree_n = main.tree_pos.size()
		_tree_v = tv
		_tree_grid = _build_grid(main.tree_pos)
	if main.rock_pos.size() != _rock_n:
		_rock_n = main.rock_pos.size()
		_rock_grid = _build_grid(main.rock_pos)

## Zeichnet alle Punkte aus dem Raster, die im Sichtfenster liegen.
func _draw_grid(grid: Dictionary, pp: Vector2, fwd: Vector2, right: Vector2, radius: float, col: Color) -> void:
	var x0 := floori((pp.x - VIEW) / CELL)
	var x1 := floori((pp.x + VIEW) / CELL)
	var y0 := floori((pp.y - VIEW) / CELL)
	var y1 := floori((pp.y + VIEW) / CELL)
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var cell = grid.get(Vector2i(cx, cy))
			if cell == null:
				continue
			for p: Vector2 in cell:
				if absf(p.x - pp.x) < VIEW and absf(p.y - pp.y) < VIEW:
					draw_circle(_f(p, pp, fwd, right), radius, col)

func _f(w: Vector2, pp: Vector2, fwd: Vector2, right: Vector2) -> Vector2:
	var rel := w - pp
	return size / 2.0 + Vector2(rel.dot(right), -rel.dot(fwd)) * PX

func _draw() -> void:
	if main == null or main.player == null:
		return
	var pl = main.player
	var ry: float = pl.rotation.y
	var fwd := Vector2(-sin(ry), -cos(ry))
	var right := Vector2(cos(ry), -sin(ry))
	var pp := Vector2(pl.global_position.x, pl.global_position.z)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.08, 0.04))
	var road := PackedVector2Array([
		_f(Vector2(-3, pp.y - 60), pp, fwd, right), _f(Vector2(3, pp.y - 60), pp, fwd, right),
		_f(Vector2(3, pp.y + 60), pp, fwd, right), _f(Vector2(-3, pp.y + 60), pp, fwd, right)])
	draw_colored_polygon(road, C_ROAD)
	_ensure_grids()
	_draw_grid(_tree_grid, pp, fwd, right, 2.5, C_TREE)
	_draw_grid(_rock_grid, pp, fwd, right, 3.0, C_ROCK)
	for pk in main.pickups:
		var q := _f(Vector2(pk.position.x, pk.position.z), pp, fwd, right)
		draw_rect(Rect2(q - Vector2(3, 3), Vector2(6, 6)), Color(0.9, 0.75, 0.25))
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.dying:
			draw_circle(_f(Vector2(e.global_position.x, e.global_position.z), pp, fwd, right), 5.0, Color(0.88, 0.19, 0.19))
	var c := size / 2.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -10), c + Vector2(-7, 8), c + Vector2(7, 8)]), Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.55, 0.5), false, 2.0)
