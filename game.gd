extends Node2D

# IcePuzzle mobile/web prototype.
# Core rule: a straight cut splits the current ice; the smaller side falls away.
# Reaching the target removed area wins. Losing a penguin loses the level.

const ICE_COLOR := Color("#8DDCF0")
const ICE_OUTLINE := Color("#DDF8FF")
const CUT_COLOR := Color("#FF6B6B")
const UI_BG := Color(0.03, 0.08, 0.12, 0.82)
const PENGUIN_BODY := Color("#202833")
const PENGUIN_BELLY := Color("#F5F7FA")
const PENGUIN_BEAK := Color("#F2A93B")
const EPS := 0.0001
const MIN_CUT_LENGTH := 20.0
const EDGE_GESTURE_MARGIN := 2.0
const DUPLICATE_DISTANCE := 0.5
const MIN_VALID_AREA := 1.0
const TARGET_REMOVED_PERCENT := 57.0
const RESTART_RECT := Rect2(720, 22, 250, 64)

var ice_polygon := PackedVector2Array([
	Vector2(100, 300), Vector2(250, 180), Vector2(550, 160), Vector2(850, 250),
	Vector2(900, 600), Vector2(720, 850), Vector2(300, 880), Vector2(100, 650)
])
var initial_polygon := PackedVector2Array()
var initial_area := 0.0
var dragging := false
var cut_start := Vector2.ZERO
var cut_end := Vector2.ZERO
var level_finished := false
var level_won := false
var message := "Glisse d'un côté à l'autre de la glace pour couper"
var penguins: Array[Dictionary] = [
	{"position": Vector2(505, 500), "mobile": false, "alive": true}
]

func _ready() -> void:
	ice_polygon = sanitize_polygon(ice_polygon)
	initial_polygon = ice_polygon.duplicate()
	initial_area = polygon_area(initial_polygon)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			pointer_pressed(event.position)
		else:
			pointer_released(event.position)
	elif event is InputEventScreenDrag and dragging:
		pointer_moved(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			pointer_pressed(event.position)
		else:
			pointer_released(event.position)
	elif event is InputEventMouseMotion and dragging:
		pointer_moved(event.position)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		restart_level()

func pointer_pressed(position: Vector2) -> void:
	if RESTART_RECT.has_point(position):
		restart_level()
		return
	if level_finished:
		return
	dragging = true
	cut_start = position
	cut_end = position
	message = "Relâche après avoir traversé toute la plaque"
	queue_redraw()

func pointer_moved(position: Vector2) -> void:
	cut_end = position
	queue_redraw()

func pointer_released(position: Vector2) -> void:
	if not dragging:
		return
	cut_end = position
	dragging = false
	try_cut(cut_start, cut_end)
	queue_redraw()

func restart_level() -> void:
	ice_polygon = initial_polygon.duplicate()
	for penguin in penguins:
		penguin.alive = true
	level_finished = false
	level_won = false
	dragging = false
	message = "Niveau recommencé • Coupe la glace sans perdre le pingouin"
	queue_redraw()

func _draw() -> void:
	if ice_polygon.size() >= 3:
		draw_colored_polygon(ice_polygon, ICE_COLOR)
		var outline := ice_polygon.duplicate()
		outline.append(ice_polygon[0])
		draw_polyline(outline, ICE_OUTLINE, 5.0, true)

	for penguin in penguins:
		if penguin.alive:
			draw_penguin(penguin.position)

	if dragging and cut_start.distance_to(cut_end) > 2.0:
		draw_line(cut_start, cut_end, CUT_COLOR, 7.0, true)
		draw_circle(cut_start, 8.0, CUT_COLOR)
		draw_circle(cut_end, 8.0, CUT_COLOR)

	draw_ui()

func draw_ui() -> void:
	draw_rect(Rect2(20, 20, 680, 112), UI_BG, true)
	draw_string(ThemeDB.fallback_font, Vector2(38, 54), "IcePuzzle • Niveau prototype",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	var progress := removed_percent()
	draw_string(ThemeDB.fallback_font, Vector2(38, 88), "Surface supprimée : %.1f%% / %.0f%%" % [progress, TARGET_REMOVED_PERCENT],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(38, 119), message,
		HORIZONTAL_ALIGNMENT_LEFT, 640, 18, Color("#DDE7ED"))

	draw_rect(RESTART_RECT, UI_BG, true)
	draw_string(ThemeDB.fallback_font, Vector2(RESTART_RECT.position.x + 28, RESTART_RECT.position.y + 41),
		"RECOMMENCER", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	if level_finished:
		draw_rect(Rect2(155, 400, 690, 180), Color(0.02, 0.04, 0.07, 0.92), true)
		var title := "NIVEAU RÉUSSI !" if level_won else "NIVEAU PERDU"
		var subtitle := "Objectif atteint sans perdre de pingouin." if level_won else "Un pingouin est tombé avec la glace."
		draw_string(ThemeDB.fallback_font, Vector2(0, 465), title, HORIZONTAL_ALIGNMENT_CENTER, 1000, 42, Color.WHITE)
		draw_string(ThemeDB.fallback_font, Vector2(0, 510), subtitle, HORIZONTAL_ALIGNMENT_CENTER, 1000, 21, Color.WHITE)
		draw_string(ThemeDB.fallback_font, Vector2(0, 550), "Appuie sur RECOMMENCER pour rejouer", HORIZONTAL_ALIGNMENT_CENTER, 1000, 18, Color("#DDE7ED"))

func draw_penguin(pos: Vector2) -> void:
	# Placeholder readable at phone size; art/animation comes after the core loop.
	draw_circle(pos, 30.0, PENGUIN_BODY)
	draw_circle(pos + Vector2(0, 7), 19.0, PENGUIN_BELLY)
	draw_circle(pos + Vector2(-10, -7), 4.0, Color.WHITE)
	draw_circle(pos + Vector2(10, -7), 4.0, Color.WHITE)
	draw_circle(pos + Vector2(-10, -7), 2.0, Color.BLACK)
	draw_circle(pos + Vector2(10, -7), 2.0, Color.BLACK)
	var beak := PackedVector2Array([pos + Vector2(-7, 0), pos + Vector2(7, 0), pos + Vector2(0, 8)])
	draw_colored_polygon(beak, PENGUIN_BEAK)

func try_cut(a: Vector2, b: Vector2) -> bool:
	if level_finished:
		return false
	if a.distance_to(b) < MIN_CUT_LENGTH:
		message = "Coupe trop courte"
		return false

	var intersections := segment_polygon_intersections(a, b, ice_polygon)
	if intersections.size() != 2:
		message = "La coupe doit traverser la glace une seule fois, d'un bord à l'autre"
		return false

	var cut_length := a.distance_to(b)
	var t0 := segment_parameter(intersections[0], a, b)
	var t1 := segment_parameter(intersections[1], a, b)
	if t0 > t1:
		var swap := t0
		t0 = t1
		t1 = swap
	var margin_t := EDGE_GESTURE_MARGIN / cut_length
	if t0 <= margin_t or t1 >= 1.0 - margin_t or t1 - t0 <= margin_t:
		message = "Commence et termine légèrement hors de la glace"
		return false

	var side_a := sanitize_polygon(clip_polygon_half_plane(ice_polygon, a, b, true))
	var side_b := sanitize_polygon(clip_polygon_half_plane(ice_polygon, a, b, false))
	if not is_valid_polygon(side_a) or not is_valid_polygon(side_b):
		message = "Coupe invalide • Essaie une autre direction"
		return false

	var area_before := polygon_area(ice_polygon)
	var area_a := polygon_area(side_a)
	var area_b := polygon_area(side_b)
	if abs((area_a + area_b) - area_before) > max(1.0, area_before * 0.001):
		message = "Coupe annulée : géométrie instable"
		return false

	var kept := side_a if area_a >= area_b else side_b
	var removed := side_b if area_a >= area_b else side_a
	ice_polygon = kept

	var lost_penguin := false
	for penguin in penguins:
		if penguin.alive and point_in_or_on_polygon(penguin.position, removed):
			penguin.alive = false
			lost_penguin = true

	if lost_penguin:
		level_finished = true
		level_won = false
		message = "Pingouin perdu !"
	elif removed_percent() + 0.001 >= TARGET_REMOVED_PERCENT:
		level_finished = true
		level_won = true
		message = "Objectif atteint !"
	else:
		message = "Bonne coupe • Continue jusqu'à %.0f%%" % TARGET_REMOVED_PERCENT
	return true

func removed_percent() -> float:
	if initial_area <= EPS:
		return 0.0
	return clamp(100.0 * (initial_area - polygon_area(ice_polygon)) / initial_area, 0.0, 100.0)

func point_in_or_on_polygon(point: Vector2, poly: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(point, poly):
		return true
	for i in range(poly.size()):
		if point_to_segment_distance(point, poly[i], poly[(i + 1) % poly.size()]) <= 0.5:
			return true
	return false

func point_to_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	if ab.length_squared() <= EPS:
		return p.distance_to(a)
	var t := clamp((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func signed_side(p: Vector2, a: Vector2, b: Vector2) -> float:
	return (b - a).cross(p - a)

func clip_polygon_half_plane(poly: PackedVector2Array, a: Vector2, b: Vector2, keep_positive: bool) -> PackedVector2Array:
	var output := PackedVector2Array()
	if poly.is_empty(): return output
	for i in range(poly.size()):
		var current := poly[i]
		var next := poly[(i + 1) % poly.size()]
		var dc := signed_side(current, a, b)
		var dn := signed_side(next, a, b)
		var current_inside := dc >= -EPS if keep_positive else dc <= EPS
		var next_inside := dn >= -EPS if keep_positive else dn <= EPS
		if current_inside: output.append(current)
		if current_inside != next_inside:
			var denom := dc - dn
			if abs(denom) > EPS: output.append(current.lerp(next, dc / denom))
	return output

func sanitize_polygon(poly: PackedVector2Array) -> PackedVector2Array:
	var clean := PackedVector2Array()
	for p in poly:
		if clean.is_empty() or clean[clean.size() - 1].distance_to(p) > DUPLICATE_DISTANCE: clean.append(p)
	if clean.size() > 2 and clean[0].distance_to(clean[clean.size() - 1]) <= DUPLICATE_DISTANCE: clean.remove_at(clean.size() - 1)
	var changed := true
	while changed and clean.size() > 3:
		changed = false
		for i in range(clean.size()):
			var prev := clean[(i - 1 + clean.size()) % clean.size()]
			var current := clean[i]
			var next := clean[(i + 1) % clean.size()]
			var v1 := current - prev
			var v2 := next - current
			if v1.length() <= DUPLICATE_DISTANCE or v2.length() <= DUPLICATE_DISTANCE or abs(v1.cross(v2)) <= 0.01:
				clean.remove_at(i)
				changed = true
				break
	return clean

func is_valid_polygon(poly: PackedVector2Array) -> bool:
	return poly.size() >= 3 and polygon_area(poly) >= MIN_VALID_AREA

func segment_parameter(p: Vector2, a: Vector2, b: Vector2) -> float:
	var delta := b - a
	if delta.length_squared() <= EPS: return 0.0
	return (p - a).dot(delta) / delta.length_squared()

func segment_polygon_intersections(a: Vector2, b: Vector2, poly: PackedVector2Array) -> Array[Vector2]:
	var hits: Array[Vector2] = []
	for i in range(poly.size()):
		var hit = Geometry2D.segment_intersects_segment(a, b, poly[i], poly[(i + 1) % poly.size()])
		if hit != null:
			var p: Vector2 = hit
			var duplicate := false
			for old in hits:
				if old.distance_to(p) < 1.0:
					duplicate = true
					break
			if not duplicate: hits.append(p)
	return hits

func polygon_area(poly: PackedVector2Array) -> float:
	var sum := 0.0
	for i in range(poly.size()):
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		sum += p.x * q.y - q.x * p.y
	return abs(sum) * 0.5
