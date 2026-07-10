class_name Order
extends RefCounted

## Один приказ в слоте. No-retarget: фиксируется СМЕЩЕНИЕ цели от героя, а не абсолютная клетка,
## поэтому сдвинутый до своего действия герой бьёт «тем же жестом» из новой позиции.

var hero_id: int = -1
var action: int = Consts.Action.EMPTY   # Consts.Action
var target: Vector2i = Vector2i(-1, -1)  # целевая клетка (абсолютная; для отображения/маркеров)
var offset: Vector2i = Vector2i.ZERO     # СМЕЩЕНИЕ цели от планируемой позиции героя
var relative: bool = false               # true → эффект целится в (текущая_клетка + offset):
                                         # направление/дистанция фиксированы, а точка считается от
                                         # ТЕКУЩЕЙ позиции (устойчиво к отбросу/сдвигу). Все нацеленные
                                         # приказы из UI приходят именно такими.
var path: Array[Vector2i] = []           # для MOVE: последовательность ШАГОВ-СМЕЩЕНИЙ (dx,dy)


func _init(p_hero_id: int = -1, p_action: int = Consts.Action.EMPTY) -> void:
	hero_id = p_hero_id
	action = p_action


func is_empty() -> bool:
	return action == Consts.Action.EMPTY or hero_id < 0


static func empty() -> Order:
	return Order.new()


static func make(hero_id: int, action: int, target: Vector2i = Vector2i(-1, -1), offset: Vector2i = Vector2i.ZERO, relative: bool = false) -> Order:
	var o := Order.new(hero_id, action)
	o.target = target
	o.offset = offset
	o.relative = relative
	return o


static func make_move(hero_id: int, steps: Array[Vector2i]) -> Order:
	var o := Order.new(hero_id, Consts.Action.MOVE)
	o.path = steps   # шаги-смещения (относительные)
	return o


# Пустой набор из 4 слотов
static func empty_slots() -> Array:
	var arr: Array = []
	for i in Consts.ORDER_SLOTS:
		arr.append(Order.empty())
	return arr
