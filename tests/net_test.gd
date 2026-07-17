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
	test_leaderboard_protocol()
	test_ai_session_is_server_side()
	test_ai_match_lockstep_with_client_copy()
	test_reconnect_replay_matches_server()
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
	_check(not srv.has_orders(0) and not srv.has_orders(1), "гейт: до сабмита приказов нет ни у кого")
	_check(not srv.submit(0, oa), "гейт: после приказа A ещё ждём B")
	_check(srv.has_orders(0) and not srv.both_submitted(), "сервер зафиксировал A, но держит скрытым (B ещё нет)")
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


# Реконнект: вернувшийся клиент восстанавливает состояние, переиграв ИСТОРИЮ разрешённых раундов
# (как это делает main.gd/_on_match_resumed по данным Net.resume_match_rpc). Результат обязан до
# последнего HP совпасть с серверной сессией — иначе игрок «вернётся» в рассинхронизированный матч.
func test_reconnect_replay_matches_server() -> void:
	var afo := true
	var lo_a := Loadout.default_team_net()
	var lo_b := Loadout.default_team_net()

	# сервер играет несколько раундов, копя history ровно как Net.submit_orders
	var srv := MatchSession.new(afo, lo_a, lo_b, 0)
	var history: Array = []
	var moves := [
		[_move_slots(0, Vector2i(0, -1)), _move_slots(3, Vector2i(0, 1))],
		[_move_slots(1, Vector2i(1, 0)),  _move_slots(4, Vector2i(-1, 0))],
		[_move_slots(0, Vector2i(-1, 0)), _move_slots(5, Vector2i(0, -1))],
	]
	for pair in moves:
		srv.submit(0, pair[0])
		srv.submit(1, pair[1])
		var oa_data := NetProtocol.orders_to_data(srv.orders_of(0))
		var ob_data := NetProtocol.orders_to_data(srv.orders_of(1))
		var res := srv.resolve()
		_check(res.winner < 0, "реконнект-сетап: раунд %d не завершил матч" % res.round)
		history.append([oa_data, ob_data])

	# «переподключение»: копии клиента нет — собираем с нуля и переигрываем history молча
	var cli := MatchState.new()
	cli.setup(Loadout.sanitize_team_net(lo_a), Loadout.sanitize_team_net(lo_b), 0)
	cli.a_first_on_odd = afo
	cli.begin_round()
	var r := Resolver.new()
	for rd in history:
		var oa := NetProtocol.orders_from_data(rd[0])
		var ob := NetProtocol.orders_from_data(rd[1])
		r.resolve(cli, oa, ob, cli.first_player_this_round())
		var se: Array = []
		cli.score_round(se)
		cli.begin_round()

	_check(_snap_eq(srv.state, cli), "реконнект: переигранное состояние совпало с серверной сессией")
	_check(srv.current_round() == cli.round_num,
		"реконнект: догнали текущий раунд [%d == %d]" % [srv.current_round(), cli.round_num])

	# история пуста (дисконнект в 1-м раунде) — клиент просто на 1-м раунде, без рассинхрона
	var fresh := MatchState.new()
	fresh.setup(Loadout.sanitize_team_net(lo_a), Loadout.sanitize_team_net(lo_b), 0)
	fresh.a_first_on_odd = afo
	fresh.begin_round()
	var srv2 := MatchSession.new(afo, lo_a, lo_b, 0)
	_check(_snap_eq(srv2.state, fresh) and fresh.round_num == 1,
		"реконнект: пустая история -> клиент на 1-м раунде, совпадает с сервером")


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


func test_leaderboard_protocol() -> void:
	var rows := [{"login": "alice", "level": 12}, {"login": "bob", "level": 3}]
	var back := NetProtocol.leaderboard_from_data(NetProtocol.leaderboard_to_data(rows))
	_check(back == rows, "лидерборд: сериализация туда-обратно без изменений")
	# порядок задаёт сервер (лучшие сверху) — клиент его не пересортировывает
	_check(back[0]["login"] == "alice", "лидерборд: порядок строк сохраняется")
	# битая/враждебная таблица не должна ронять экран: плохие строки просто выбрасываются
	_check(NetProtocol.leaderboard_from_data("не массив").is_empty(), "лидерборд: не-массив → пусто")
	_check(NetProtocol.leaderboard_from_data([1, "x", null]).is_empty(), "лидерборд: не-словари → пусто")
	_check(NetProtocol.leaderboard_from_data([{"n": "a"}]).is_empty(), "лидерборд: строка без уровня → отброшена")
	_check(NetProtocol.leaderboard_from_data([{"n": 5, "l": 5}]).is_empty(), "лидерборд: логин не строка → отброшена")
	var mixed := NetProtocol.leaderboard_from_data([{"n": "ok", "l": 5}, "мусор", {"n": "ok2", "l": 6}])
	_check(mixed.size() == 2, "лидерборд: мусорная строка выброшена, валидные остались [%d]" % mixed.size())
	# уровень санируется тем же правилом, что и рекорд в БД
	_check(NetProtocol.leaderboard_from_data([{"n": "a", "l": 9999}])[0]["level"] == Difficulty.MAX_LEVEL,
		"лидерборд: уровень выше MAX_LEVEL зажат")
	_check(NetProtocol.leaderboard_from_data([{"n": "a", "l": -5}])[0]["level"] == 0,
		"лидерборд: отрицательный уровень зажат в 0")
	# санити-кэпы: длинный логин и бесконечная таблица не должны порвать вёрстку
	var long_rows: Array = []
	for i in NetProtocol.MAX_LEADERBOARD_ROWS + 20:
		long_rows.append({"n": "p%d" % i, "l": 1})
	_check(NetProtocol.leaderboard_from_data(long_rows).size() == NetProtocol.MAX_LEADERBOARD_ROWS,
		"лидерборд: длина таблицы обрезана по кэпу")
	var long_login := NetProtocol.leaderboard_from_data([{"n": "x".repeat(200), "l": 1}])
	_check(String(long_login[0]["login"]).length() == NetProtocol.MAX_LOGIN_LEN,
		"лидерборд: длинный логин обрезан по кэпу")


# Бой с ИИ — такая же серверная сессия, как PvP: живой пир один, за игрока 1 ходит сам сервер.
func test_ai_session_is_server_side() -> void:
	var s := MatchSession.new(true, Loadout.default_team_net(), Loadout.default_team_net(), 0, 7, 42)
	_check(s.ai_level == 7, "ИИ-сессия: уровень сложности запомнен [%d]" % s.ai_level)

	# слепой гейт работает и здесь: одних приказов человека мало, пока не сходил бот
	var oa := _move_slots(0, Vector2i(0, -1))
	_check(not s.submit(0, oa), "ИИ-сессия: после приказов человека раунд ещё не раскрыть")
	_check(s.plan_bot(), "ИИ-сессия: сервер сходил за бота -> раунд можно раскрывать")
	_check(s.has_orders(1) and s.orders_of(1).size() == Consts.ORDER_SLOTS,
		"ИИ-сессия: приказы бота — полный набор слотов")
	var res := s.resolve()
	_check(res.round == 1 and res.winner == -1, "ИИ-сессия: раунд 1 разрешён сервером")
	_check(s.current_round() == 2, "ИИ-сессия: сессия продвинулась на раунд 2")
	_check(not s.has_orders(0) and not s.has_orders(1),
		"ИИ-сессия: разрешённый раунд снял приказы — новый раунд ждёт обоих заново")

	# в PvP-сессии за соперника сервер не ходит — бот там взяться не может
	var pvp := MatchSession.new(true)
	_check(pvp.ai_level == 0, "PvP-сессия: уровня ИИ нет")
	pvp.submit(0, oa)
	_check(not pvp.plan_bot(), "PvP-сессия: сервер за живого соперника не ходит")
	_check(not pvp.both_submitted(), "PvP-сессия: приказов соперника так и нет — ждём живого игрока")


# Копия матча у клиента строится ТЕМИ ЖЕ аргументами, что и сессия на сервере (их присылает
# ai_match_found_rpc) — и обязана сойтись с ней по состоянию, иначе лок-степ разойдётся молча.
func test_ai_match_lockstep_with_client_copy() -> void:
	var afo := true
	var lo_a := Loadout.default_team_net()
	var lo_b: Array = Loadout.canon_team_net(Loadout.random_team())
	var level := 12
	var mod_seed := 20260716

	var srv := MatchSession.new(afo, lo_a, lo_b, 0, level, mod_seed)

	# то же самое делает main.gd/_on_ai_matched по данным из пакета сервера
	var cli := MatchState.new()
	cli.setup(Loadout.sanitize_team_net(lo_a), Loadout.sanitize_team_net(lo_b), 0)
	Difficulty.apply(cli, Consts.Player.B, level, mod_seed)
	cli.a_first_on_odd = afo
	cli.begin_round()
	_check(_snap_eq(srv.state, cli), "ИИ-лок-степ: копия клиента совпала с сессией сервера на старте")

	# раунд: человек шлёт приказы, сервер планирует бота и раскрывает ОБА — клиент резолвит у себя
	var oa := _move_slots(0, Vector2i(0, -1))
	srv.submit(0, oa)
	srv.plan_bot()
	var oa_net: Array = NetProtocol.orders_from_data(NetProtocol.orders_to_data(srv.orders_of(0)))
	var ob_net: Array = NetProtocol.orders_from_data(NetProtocol.orders_to_data(srv.orders_of(1)))
	srv.resolve()
	Resolver.new().resolve(cli, oa_net, ob_net, cli.first_player_this_round())
	var se: Array = []
	cli.score_round(se)
	cli.begin_round()
	_check(_snap_eq(srv.state, cli), "ИИ-лок-степ: после раунда сервер и клиент в одинаковом состоянии")

	# копия, построенная с ДРУГИМ seed (например, если бы клиент ролил усиления сам), разойдётся
	var wrong := MatchState.new()
	wrong.setup(Loadout.sanitize_team_net(lo_a), Loadout.sanitize_team_net(lo_b), 0)
	Difficulty.apply(wrong, Consts.Player.B, level, mod_seed + 1)
	wrong.a_first_on_odd = afo
	wrong.begin_round()
	_check(not _snap_eq(MatchSession.new(afo, lo_a, lo_b, 0, level, mod_seed).state, wrong),
		"ИИ-лок-степ: чужой seed даёт другого бота — seed обязан ехать от сервера")
