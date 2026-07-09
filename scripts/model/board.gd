class_name Board
extends RefCounted

## Статическая геометрия поля: грид 7x7, препятствия террейна, точки контроля.
## Динамика (юниты, капканы) живёт в MatchState. Раскладка симметрична на 180°
## (зеркало честно по построению, §7).

var width: int = Consts.BOARD_W
var height: int = Consts.BOARD_H
var obstacles: Dictionary = {}       # Vector2i -> true
var control_points: Array[Vector2i] = []


func _init() -> void:
	_build_default_map()


func _build_default_map() -> void:
	# Точки контроля: диагональ через центр (180°-симметрия)
	control_points = [
		Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4),
	]
	# Террейн: «ромб» стен вокруг центра (180°-симметрично, точки/старт свободны)
	var walls := [
		Vector2i(3, 1),
		Vector2i(1, 3), Vector2i(5, 3),
		Vector2i(3, 5),
	]
	for w in walls:
		obstacles[w] = true


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
