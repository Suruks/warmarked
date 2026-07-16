class_name NetProtocol
extends RefCounted

## Сериализация приказов для передачи по сети (Godot RPC умеет Variant: int/Vector2i/Array).
## Компактные ключи, чтобы пакет был меньше.
##
## Десериализация ЗАЩИЩЁННАЯ: сервер один на все матчи, поэтому битый/враждебный пакет
## не должен ронять процесс. Любое поле неверного типа → приказ вырождается в пустой.


const MAX_PATH_STEPS := 16   # санити-кэп на длину пути (легальность считает OrderValidator)


static func order_to_dict(o: Order) -> Dictionary:
	return {"h": o.hero_id, "a": o.action, "t": o.target, "o": o.offset, "r": o.relative, "p": o.path}


# Возвращает валидный по ТИПАМ Order; при любой аномалии — Order.empty().
# Игровую легальность (дальность, мана, слоты) проверяет OrderValidator.
static func order_from_dict(d: Variant) -> Order:
	if typeof(d) != TYPE_DICTIONARY:
		return Order.empty()
	if not (_is_int(d.get("h")) and _is_int(d.get("a"))):
		return Order.empty()
	var action: int = int(d["a"])
	if action < Consts.Action.EMPTY or action > Consts.Action.PASS:
		return Order.empty()
	var o := Order.new(int(d["h"]), action)
	o.target = _as_vec(d.get("t"), Vector2i(-1, -1))
	o.offset = _as_vec(d.get("o"), Vector2i.ZERO)
	o.relative = bool(d.get("r", false)) if typeof(d.get("r")) == TYPE_BOOL else false
	var raw: Variant = d.get("p", [])
	if typeof(raw) != TYPE_ARRAY:
		return Order.empty()
	if (raw as Array).size() > MAX_PATH_STEPS:
		return Order.empty()
	var p: Array[Vector2i] = []
	for c in raw:
		if typeof(c) != TYPE_VECTOR2I:
			return Order.empty()
		p.append(c)
	o.path = p
	return o


static func orders_to_data(orders: Array) -> Array:
	var out: Array = []
	for o in orders:
		out.append(order_to_dict(o))
	return out


# Всегда возвращает ровно ORDER_SLOTS приказов (лишние отбрасываются, недостающие — пустые).
static func orders_from_data(data: Variant) -> Array:
	var out: Array = []
	var arr: Array = data if typeof(data) == TYPE_ARRAY else []
	for i in Consts.ORDER_SLOTS:
		out.append(order_from_dict(arr[i]) if i < arr.size() else Order.empty())
	return out


# ------------------------------------------------------------------ лидерборд

const MAX_LEADERBOARD_ROWS := 50   # санити-кэп на длину присланной таблицы
const MAX_LOGIN_LEN := 32          # длинный логин порвал бы вёрстку строки таблицы

# [{login, level}] → компактные ключи для RPC.
static func leaderboard_to_data(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		out.append({"n": String(r.get("login", "")), "l": int(r.get("level", 0))})
	return out


# Сервер авторитетен, но клиент всё равно не обязан ему доверять слепо: битая/враждебная
# строка молча выбрасывается, а не роняет экран лидерборда. Порядок (лучшие сверху) —
# от сервера, клиент его не пересортировывает.
static func leaderboard_from_data(data: Variant) -> Array:
	var out: Array = []
	if typeof(data) != TYPE_ARRAY:
		return out
	for r in (data as Array).slice(0, MAX_LEADERBOARD_ROWS):
		if typeof(r) != TYPE_DICTIONARY:
			continue
		if typeof(r.get("n")) != TYPE_STRING or not _is_int(r.get("l")):
			continue
		out.append({"login": String(r["n"]).substr(0, MAX_LOGIN_LEN),
			"level": Difficulty.sanitize_best(r["l"])})
	return out


static func _is_int(v: Variant) -> bool:
	return typeof(v) == TYPE_INT


static func _as_vec(v: Variant, fallback: Vector2i) -> Vector2i:
	return v if typeof(v) == TYPE_VECTOR2I else fallback
