extends SceneTree

## Проверки сетевого ядра (без сокетов): сериализация приказов, слепой гейт,
## лок-степ детерминизм сервера и клиента (через сериализацию, как по сети).

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("=== Warmarked net-core tests ===")
	test_protocol_roundtrip()
	test_protocol_rejects_malformed()
	test_session_sanitizes_orders()
	test_blind_gate_and_lockstep()
	print("=== Итог: %d PASS, %d FAIL ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(c: bool, label: String) -> void:
	if c:
		_pass += 1
		print("  PASS  " + label)
	else:
		_fail += 1
		print("  FAIL  " + label)


func _move_slots(hero: int, step: Vector2i) -> Array:
	var arr: Array = [Order.empty(), Order.empty(), Order.empty(), Order.empty()]
	arr[0] = Order.make_move(hero, [step] as Array[Vector2i])   # step — смещение
	return arr


func test_protocol_roundtrip() -> void:
	var o := Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 5))
	var back := NetProtocol.order_from_dict(NetProtocol.order_to_dict(o))
	_check(back.hero_id == 0 and back.action == Consts.Action.ABILITY2 and back.target == Vector2i(3, 5),
		"сериализация приказа туда-обратно")
	var sg := Order.make(0, Consts.Action.ABILITY3, Vector2i(3, 4), Vector2i(1, -1), true)
	var sgb := NetProtocol.order_from_dict(NetProtocol.order_to_dict(sg))
	_check(sgb.offset == Vector2i(1, -1) and sgb.relative, "сериализация offset/relative")
	var mv := Order.make_move(2, [Vector2i(5, 5), Vector2i(5, 4)] as Array[Vector2i])
	var mvb := NetProtocol.order_from_dict(NetProtocol.order_to_dict(mv))
	_check(mvb.path.size() == 2 and mvb.path[1] == Vector2i(5, 4), "сериализация пути хода")


func test_protocol_rejects_malformed() -> void:
	# битый/враждебный пакет не должен ронять сервер — вырождается в пустой приказ
	_check(NetProtocol.order_from_dict("не словарь").is_empty(), "протокол: не-словарь → пустой приказ")
	_check(NetProtocol.order_from_dict({}).is_empty(), "протокол: пустой словарь → пустой приказ")
	_check(NetProtocol.order_from_dict({"h": "x", "a": 1, "p": []}).is_empty(), "протокол: hero_id не int → пустой")
	_check(NetProtocol.order_from_dict({"h": 0, "a": 999, "p": []}).is_empty(), "протокол: неизвестный action → пустой")
	_check(NetProtocol.order_from_dict({"h": 0, "a": Consts.Action.MOVE, "p": "хех"}).is_empty(),
		"протокол: path не массив → пустой")
	_check(NetProtocol.order_from_dict({"h": 0, "a": Consts.Action.MOVE, "p": [1, 2]}).is_empty(),
		"протокол: элементы path не Vector2i → пустой")
	# orders_from_data всегда даёт ровно ORDER_SLOTS приказов
	_check(NetProtocol.orders_from_data("мусор").size() == Consts.ORDER_SLOTS, "протокол: мусор → 4 пустых слота")
	_check(NetProtocol.orders_from_data([]).size() == Consts.ORDER_SLOTS, "протокол: короткий массив дополнен до 4")


func test_session_sanitizes_orders() -> void:
	# Сервер режет только СТРУКТУРНО-опасное (телепорт-ход сквозь стены). Геометрию цели он
	# больше не режет: удар через всю доску доезжает до разрешения и там ФИЗЗЛИТ (никого не бьёт) —
	# это и есть «планируй невозможное, оно просто не сработает». Раскрывается ровно то, что
	# резолвится, поэтому лок-степ не ломается.
	var srv := MatchSession.new(true)
	var cheat: Array = [Order.empty(), Order.empty(), Order.empty(), Order.empty()]
	cheat[0] = Order.make_move(0, [Vector2i(0, -5)] as Array[Vector2i])                    # телепорт (структурно нелегален)
	cheat[1] = Order.make(1, Consts.Action.ATTACK, Vector2i(3, 0), Vector2i(0, -6), true)  # удар через доску (нелегальная геометрия)
	cheat[2] = Order.make_move(0, [Vector2i(0, -1)] as Array[Vector2i])                    # легальный ход
	srv.submit(0, cheat)
	var stored: Array = srv.orders_of(0)
	_check(stored[0].is_empty(), "сессия: телепорт-ход санирован (структурно)")
	_check(not stored[1].is_empty(), "сессия: удар через доску ПРОПУЩЕН сервером (физзлит на разрешении)")
	_check(not stored[2].is_empty(), "сессия: легальный ход сохранён")
	# запомним HP всех до разрешения — нелегальный удар не должен никого ранить
	var hp_before := {}
	for u in srv.state.units:
		hp_before[u.id] = u.hp
	srv.submit(1, [Order.empty(), Order.empty(), Order.empty(), Order.empty()])
	srv.resolve()
	var no_damage := true
	for u in srv.state.units:
		if u.hp != hp_before[u.id]:
			no_damage = false
	_check(no_damage, "сессия: удар с нелегальной геометрией физзлил — никто не ранен")
	# хантер A стартует на (1,6) и после резолва должен сдвинуться ровно на 1 клетку
	_check(srv.state.get_unit(0).cell == Vector2i(1, 5), "сессия: читер прошёл только легальный шаг [%s]"
		% str(srv.state.get_unit(0).cell))


func test_blind_gate_and_lockstep() -> void:
	var afo := true
	var srv := MatchSession.new(afo)
	# зеркальная копия клиента
	var cli := MatchState.new()
	cli.setup()
	cli.a_first_on_odd = afo
	cli.begin_round()
	_check(srv.current_round() == 1 and cli.round_num == 1, "оба на раунде 1")

	var oa := _move_slots(0, Vector2i(0, -1))  # A Охотник (1,6)->(1,5), смещение вверх
	var ob := _move_slots(3, Vector2i(0, 1))   # B Охотник (5,0)->(5,1), смещение вниз

	# слепой гейт: до прихода обоих — не раскрывать
	_check(not srv.both_submitted(), "гейт: изначально приказов нет")
	_check(not srv.submit(0, oa), "гейт: после приказа A ещё ждём B")
	_check(srv.orders_of(0) != null and not srv.both_submitted(), "сервер зафиксировал A, но держит скрытым (B ещё нет)")
	_check(srv.submit(1, ob), "гейт: пришёл B → можно раскрывать")

	# клиент получает ОБА приказа по сети (через сериализацию) и разрешает у себя
	var oa_net: Array = NetProtocol.orders_from_data(NetProtocol.orders_to_data(oa))
	var ob_net: Array = NetProtocol.orders_from_data(NetProtocol.orders_to_data(ob))

	var res := srv.resolve()
	_check(res.winner == -1, "раунд разрешён, победителя нет")

	var r := Resolver.new()
	r.resolve(cli, oa_net, ob_net, cli.first_player_this_round())
	var se: Array = []
	cli.score_round(se)
	cli.begin_round()

	_check(_snap_eq(srv.state, cli), "лок-степ: сервер и клиент в одинаковом состоянии")
	_check(srv.current_round() == 2 and cli.round_num == 2, "оба продвинулись на раунд 2")


func _snap_eq(a: MatchState, b: MatchState) -> bool:
	if a.round_num != b.round_num:
		return false
	if a.score[Consts.Player.A] != b.score[Consts.Player.A] or a.score[Consts.Player.B] != b.score[Consts.Player.B]:
		return false
	for i in a.units.size():
		var ua := a.units[i]
		var ub := b.get_unit(ua.id)
		if ua.cell != ub.cell or ua.hp != ub.hp or ua.mana != ub.mana or ua.alive != ub.alive:
			return false
	return true
