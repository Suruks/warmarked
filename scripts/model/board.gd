class_name Board
extends RefCounted

## Статическая геометрия поля: грид 7x7, препятствия террейна, точки контроля и спауны.
## Всё берётся из выбранной карты (Maps). Динамика (юниты, капканы) живёт в MatchState.

var width: int = Consts.BOARD_W
var height: int = Consts.BOARD_H
var obstacles: Dictionary = {}       # Vector2i -> true
var control_points: Array[Vector2i] = []
var spawns_a: Array[Vector2i] = []   # стартовые клетки игрока A (индекс = позиция в отряде)
var spawns_b: Array[Vector2i] = []
var map_index: int = 0


# По умолчанию — карта 0 (базовая). Матч подставляет случайную/сетевую карту.
func _init(p_map_index: int = 0) -> void:
	map_index = p_map_index
	var m := Maps.parse(p_map_index)
	obstacles = m.obstacles
	control_points = m.control_points
	spawns_a = m.spawns_a
	spawns_b = m.spawns_b


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < width and c.y >= 0 and c.y < height


func is_obstacle(c: Vector2i) -> bool:
	return obstacles.has(c)


func is_passable(c: Vector2i) -> bool:
	return in_bounds(c) and not is_obstacle(c)


func is_control_point(c: Vector2i) -> bool:
	return control_points.has(c)


func neighbors4(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in Consts.DIRS4:
		var n: Vector2i = c + d
		if in_bounds(n):
			out.append(n)
	return out


# Есть ли прямая (орто ИЛИ диагональ) от a к b, и чист ли путь по террейну.
# Проверяем только препятствия (статичны) — не юнитов (ради легибельности слепого просчёта).
func is_clear_line(a: Vector2i, b: Vector2i) -> bool:
	var delta := b - a
	if delta == Vector2i.ZERO:
		return false
	var is_ortho: bool = (delta.x == 0) != (delta.y == 0)
	var is_diag: bool = absi(delta.x) == absi(delta.y)
	if not (is_ortho or is_diag):
		return false
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var cur := a + step
	while cur != b:
		if not is_passable(cur):
			return false
		cur += step
	return is_passable(b)
