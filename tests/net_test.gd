extends SceneTree

## Проверки сетевого ядра (без сокетов): сериализация приказов, слепой гейт,
## лок-степ детерминизм сервера и клиента (через сериализацию, как по сети).

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("=== Warmarked net-core tests ===")
	test_protocol_roundtrip()
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
