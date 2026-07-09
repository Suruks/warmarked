class_name NetProtocol
extends RefCounted

## Сериализация приказов для передачи по сети (Godot RPC умеет Variant: int/Vector2i/Array).
## Компактные ключи, чтобы пакет был меньше.


static func order_to_dict(o: Order) -> Dictionary:
	return {"h": o.hero_id, "a": o.action, "t": o.target, "o": o.offset, "r": o.relative, "p": o.path}


static func order_from_dict(d: Dictionary) -> Order:
	var o := Order.new(int(d["h"]), int(d["a"]))
	o.target = d["t"]
	o.offset = d.get("o", Vector2i.ZERO)
	o.relative = d.get("r", false)
	var p: Array[Vector2i] = []
	for c in d["p"]:
		p.append(c)
	o.path = p
	return o


static func orders_to_data(orders: Array) -> Array:
	var out: Array = []
	for o in orders:
		out.append(order_to_dict(o))
	return out


static func orders_from_data(data: Array) -> Array:
	var out: Array = []
	for d in data:
		out.append(order_from_dict(d))
	return out
