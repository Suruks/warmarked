class_name MatchSession
extends RefCounted

## Авторитетная сессия одного матча на сервере (транспортно-независимая).
## Держит приказы обоих игроков СКРЫТО, пока не пришли оба (слепой гейт), затем разрешает.
## Клиенты держат детерминированную копию и приходят к тому же результату по обмену приказами.
##
## Индексы игроков: 0 = Consts.Player.A, 1 = Consts.Player.B.
##
## Бой против ИИ — такая же сессия, только за игрока 1 приказы подаёт сам сервер (plan_bot):
## живой пир там всего один, но всё остальное (слепой гейт, резолвинг, лок-степ с копией у
## клиента) работает ровно так же, как в PvP.

var state: MatchState
var ai_level := 0   # >0 — бой против ИИ этого уровня сложности (игрок 1 = бот); 0 — PvP
# Приказы игроков 0/1: Array[Order] длиной ORDER_SLOTS, либо null — «ещё не сходил». Именно null,
# а не пустой массив: сходить пустыми слотами — законный ход (осознанный пас, см. Order.PASS), и
# путать его с «хода не было» нельзя — на этом различии стоит слепой гейт. Спрашивать приказы,
# которых нет, нельзя (см. orders_of), поэтому наружу null не выходит.
var _orders: Array = [null, null]


# loadout_a / loadout_b — сетевые отряды игроков ([[type,s1,s2,s3],...]); санируются здесь же.
# map_index — карта матча (выбрана сервером, едет клиентам тем же RPC).
# p_ai_level > 0 — бой против ИИ: команда игрока 1 получает модификаторы сложности этого уровня,
# разыгранные по ai_seed. Клиент строит свою копию тем же вызовом с теми же аргументами, поэтому
# seed обязан приехать ему вместе с отрядами (см. Net.req_start_ai_match) — иначе бот у сторон
# получит разные усиления и лок-степ разойдётся.
func _init(a_first_on_odd: bool, loadout_a: Array = [], loadout_b: Array = [], map_index: int = 0,
		p_ai_level: int = 0, ai_seed: int = 0) -> void:
	state = MatchState.new()
	state.setup(Loadout.sanitize_team_net(loadout_a), Loadout.sanitize_team_net(loadout_b), map_index)
	state.a_first_on_odd = a_first_on_odd
	ai_level = p_ai_level
	if ai_level > 0:
		# строго между setup() и первым begin_round() — так требует Difficulty.apply
		Difficulty.apply(state, Consts.Player.B, ai_level, ai_seed)
	state.begin_round()   # раунд 1: доход/хаускипинг


func current_round() -> int:
	return state.round_num


func has_orders(player_index: int) -> bool:
	return _orders[player_index] != null


func both_submitted() -> bool:
	return has_orders(0) and has_orders(1)


# Приказы игрока приняты. Возвращает true, если теперь пришли оба (можно раскрывать).
# Приказы САНИРУЮТСЯ здесь, до сохранения: клиенту доверять нельзя, а раскрываем мы ровно то,
# что сами же и резолвим — иначе клиенты разойдутся с сервером (лок-степ сломается).
func submit(player_index: int, orders: Array) -> bool:
	var player: int = Consts.Player.A if player_index == 0 else Consts.Player.B
	_orders[player_index] = OrderValidator.sanitize(state, orders, player)
	return both_submitted()


## Приказы игрока — ТОЛЬКО когда они есть (has_orders/both_submitted). До сабмита приказов не
## существует, и спросить их — ошибка вызывающего, а не «пустой ответ»: пустой набор слотов это
## законный пас, вернуть его вместо «хода не было» значило бы соврать резолверу. Единственный
## законный момент — после both_submitted(): раньше слепой гейт всё равно держит их скрытыми.
func orders_of(player_index: int) -> Array:
	assert(has_orders(player_index),
		"orders_of(%d): приказов ещё нет — сначала has_orders()/both_submitted()" % player_index)
	return _orders[player_index]


## Приказы бота за игрока 1 (только для ai_level > 0). Бот планирует СЛЕПО — как и живой
## соперник: AI.plan видит одно лишь состояние, приказы человека ему не передаются, и вызвать
## это можно в любой момент раунда (submit чужие приказы в state не вносит). Возвращает true,
## если после этого пришли оба (то есть человек уже сходил и раунд можно раскрывать).
func plan_bot() -> bool:
	if ai_level <= 0:
		return false
	return submit(1, AI.plan(state, Consts.Player.B))


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
