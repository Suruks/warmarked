class_name MatchSession
extends RefCounted

## Авторитетная сессия одного матча на сервере (транспортно-независимая).
## Держит приказы обоих игроков СКРЫТО, пока не пришли оба (слепой гейт), затем разрешает.
## Клиенты держат детерминированную копию и приходят к тому же результату по обмену приказами.
##
## Индексы игроков: 0 = Consts.Player.A, 1 = Consts.Player.B.

var state: MatchState
var _orders: Array = [null, null]   # приказы игроков 0/1 (Array[Order]) или null


# loadout_a / loadout_b — сетевые отряды игроков ([[type,s1,s2,s3],...]); санируются здесь же.
func _init(a_first_on_odd: bool, loadout_a: Array = [], loadout_b: Array = []) -> void:
	state = MatchState.new()
	state.setup(Loadout.sanitize_team_net(loadout_a), Loadout.sanitize_team_net(loadout_b))
	state.a_first_on_odd = a_first_on_odd
	state.begin_round()   # раунд 1: доход/хаускипинг


func current_round() -> int:
	return state.round_num


func both_submitted() -> bool:
	return _orders[0] != null and _orders[1] != null


# Приказы игрока приняты. Возвращает true, если теперь пришли оба (можно раскрывать).
# Приказы САНИРУЮТСЯ здесь, до сохранения: клиенту доверять нельзя, а раскрываем мы ровно то,
# что сами же и резолвим — иначе клиенты разойдутся с сервером (лок-степ сломается).
func submit(player_index: int, orders: Array) -> bool:
	var player: int = Consts.Player.A if player_index == 0 else Consts.Player.B
	_orders[player_index] = OrderValidator.sanitize(state, orders, player)
	return both_submitted()


func orders_of(player_index: int) -> Array:
	return _orders[player_index]


# Разрешить раунд, вернуть {winner:int, round:int}. Продвигает раунд, если игра не окончена.
func resolve() -> Dictionary:
	var resolved_round := state.round_num
	var oa: Array = _orders[0]
	var ob: Array = _orders[1]
	var first := state.first_player_this_round()
	var r := Resolver.new()
	r.resolve(state, oa, ob, first)
	var score_ev: Array = []
	state.score_round(score_ev)
	_orders = [null, null]
	var winner := state.winner
	if winner < 0:
		state.begin_round()   # следующий раунд
	return {"winner": winner, "round": resolved_round}
