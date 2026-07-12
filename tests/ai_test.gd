extends SceneTree

## Проверки эвристического бота (AI.plan). Запуск:
##   "…\godot.windows.opt.tools.64.exe" --headless --path E:\dev\warmarked --script res://tests/ai_test.gd

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("=== Warmarked AI tests ===")
	test_plan_is_legal_and_sized()
	test_kills_reachable_enemy()
	test_banks_mana_without_targets()
	test_no_crash_full_match()
	test_scores_by_control()
	print("=== Итог: %d PASS, %d FAIL ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  " + label)
	else:
		_fail += 1
		print("  FAIL  " + label)


func _fresh() -> MatchState:
	var s := MatchState.new()
	s.setup()
	s.round_num = 1
	return s


func _place(s: MatchState, id: int, cell: Vector2i, hp := -1, mana := -1) -> Unit:
	var u := s.get_unit(id)
	u.cell = cell
	if hp >= 0:
		u.hp = hp
	if mana >= 0:
		u.mana = mana
	return u


func _sum_hp(s: MatchState, player: int) -> int:
	var t := 0
	for u in s.units:
		if u.owner == player and u.alive:
			t += u.hp
	return t


# Бот всегда возвращает ровно ORDER_SLOTS приказов, и все они переживают повторную
# санитизацию (т.е. легальны по правилам сервера).
func test_plan_is_legal_and_sized() -> void:
	var s := _fresh()
	var plan := AI.plan(s, Consts.Player.B)
	_check(plan.size() == Consts.ORDER_SLOTS, "план из %d слотов [%d]" % [Consts.ORDER_SLOTS, plan.size()])
	var re := OrderValidator.sanitize(s, plan, Consts.Player.B)
	var stable := true
	for i in Consts.ORDER_SLOTS:
		if plan[i].is_empty() != re[i].is_empty():
			stable = false
	_check(stable, "план идемпотентен под санитизацией (легален)")


# Есть добиваемый враг в дальности базовой атаки → бот бьёт и забирает килл-очко.
func test_kills_reachable_enemy() -> void:
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4))                 # A Охотник
	_place(s, 1, Vector2i(0, 6))                 # A Фея — с глаз долой
	_place(s, 2, Vector2i(6, 6))                 # A Камнешип — с глаз долой
	var victim := _place(s, 4, Vector2i(3, 2), Consts.HUNTER_ATK_DMG)   # B Фея: одного выстрела хватит
	_place(s, 3, Vector2i(6, 0))                 # прочие B — далеко
	_place(s, 5, Vector2i(0, 0))
	var plan := AI.plan(s, Consts.Player.A)
	Resolver.new().resolve(s, plan, _empty(), Consts.Player.A)
	_check(not victim.alive, "бот добил врага в дальности")
	_check(s.score[Consts.Player.A] >= Consts.KILL_POINTS, "начислено килл-очко [%d]" % s.score[Consts.Player.A])


# Нет ни одной цели в дальности → бот НЕ сливает ману (offensive-скиллы физзлят и
# проигрывают «пустому слоту»). Мана копится сама.
func test_banks_mana_without_targets() -> void:
	var s := _fresh()
	_place(s, 0, Vector2i(0, 6))                 # A Охотник — в угол
	var fairy := _place(s, 1, Vector2i(3, 3), -1, 5)   # A Фея с запасом маны в центре
	_place(s, 2, Vector2i(6, 6))                 # A Камнешип — в угол
	_place(s, 3, Vector2i(6, 0))                 # все B — вне любой дальности
	_place(s, 4, Vector2i(3, 0))
	_place(s, 5, Vector2i(0, 0))
	var b_before := _sum_hp(s, Consts.Player.B)
	var plan := AI.plan(s, Consts.Player.A)
	Resolver.new().resolve(s, plan, _empty(), Consts.Player.A)
	_check(fairy.mana == 5, "мана не потрачена впустую [%d]" % fairy.mana)
	_check(_sum_hp(s, Consts.Player.B) == b_before, "враги без цели не получили урона")


# Полный матч бот-против-бота не падает и доходит до победителя (нет вечного пата).
func test_no_crash_full_match() -> void:
	var s := _fresh()
	s.round_num = 0
	var resolver := Resolver.new()
	var rounds := 0
	while s.winner < 0 and rounds < 80:
		s.begin_round()
		var first := s.first_player_this_round()
		var oa := AI.plan(s, Consts.Player.A)
		var ob := AI.plan(s, Consts.Player.B)
		resolver.resolve(s, oa, ob, first)
		s.score_round([])
		rounds += 1
	_check(s.winner >= 0, "матч бот-vs-бот завершился победителем за %d раундов" % rounds)


# Бот набирает очки КОНТРОЛЕМ: если соперник забился в угол, бот разбирает точки и
# берёт большинство → счёт растёт (а не липнет к одной точке всем отрядом).
func test_scores_by_control() -> void:
	var s := _fresh()
	s.round_num = 0
	_place(s, 3, Vector2i(6, 0))   # весь отряд B — в дальний угол, точки не контестит
	_place(s, 4, Vector2i(6, 1))
	_place(s, 5, Vector2i(5, 0))
	var resolver := Resolver.new()
	for i in 6:
		s.begin_round()
		var oa := AI.plan(s, Consts.Player.A)
		var ob := AI.plan(s, Consts.Player.B)
		resolver.resolve(s, oa, ob, s.first_player_this_round())
		s.score_round([])
	_check(s.score[Consts.Player.A] > 0, "бот набрал очки контролем за 6 раундов [A=%d]" % s.score[Consts.Player.A])


func _empty() -> Array:
	return Order.empty_slots()
