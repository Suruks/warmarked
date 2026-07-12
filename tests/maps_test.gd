extends SceneTree

## Проверки ротации карт (Maps / Board / MatchState.setup). Запуск:
##   "…\godot.windows.opt.tools.64.exe" --headless --path E:\dev\warmarked --script res://tests/maps_test.gd

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("=== Warmarked maps tests ===")
	test_rotation_exists()
	test_each_map_wellformed()
	test_setup_places_units_on_spawns()
	test_bot_match_runs_on_every_map()
	print("=== Итог: %d PASS, %d FAIL ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  " + label)
	else:
		_fail += 1
		print("  FAIL  " + label)


func test_rotation_exists() -> void:
	_check(Maps.count() >= 2, "в ротации несколько карт [%d]" % Maps.count())


# Каждая карта: ровно TEAM_SIZE спаунов каждого игрока, размеры 7×7, спауны проходимы и
# не совпадают с точками/друг с другом.
func test_each_map_wellformed() -> void:
	for idx in Maps.count():
		var m := Maps.parse(idx)
		var sa: Array = m.spawns_a
		var sb: Array = m.spawns_b
		_check(sa.size() == Loadout.TEAM_SIZE, "карта %d: %d спаунов A [нужно %d]" % [idx, sa.size(), Loadout.TEAM_SIZE])
		_check(sb.size() == Loadout.TEAM_SIZE, "карта %d: %d спаунов B [нужно %d]" % [idx, sb.size(), Loadout.TEAM_SIZE])
		var occupied := {}
		var ok := true
		for cell in sa + sb:
			if cell.x < 0 or cell.x >= Consts.BOARD_W or cell.y < 0 or cell.y >= Consts.BOARD_H:
				ok = false
			if m.obstacles.has(cell) or (cell in m.control_points) or occupied.has(cell):
				ok = false
			occupied[cell] = true
		_check(ok, "карта %d: спауны проходимы, различны, не на точках/блоках" % idx)


# Board/MatchState на каждой карте кладут юнитов ровно на спауны карты, без наложений.
func test_setup_places_units_on_spawns() -> void:
	for idx in Maps.count():
		var s := MatchState.new()
		s.setup([], [], idx)
		var m := Maps.parse(idx)
		var cells := {}
		var all_on_spawn := true
		for u in s.units:
			var expect: Array = m.spawns_a if u.owner == Consts.Player.A else m.spawns_b
			if not (u.cell in expect):
				all_on_spawn = false
			cells[u.cell] = cells.get(u.cell, 0) + 1
		var no_overlap := true
		for c in cells:
			if cells[c] > 1:
				no_overlap = false
		_check(all_on_spawn, "карта %d: юниты стоят на спаунах карты" % idx)
		_check(no_overlap, "карта %d: нет двух юнитов на одной клетке" % idx)


# Полный бот-матч на КАЖДОЙ карте доходит до победителя без падений (респ/точки валидны).
func test_bot_match_runs_on_every_map() -> void:
	var resolver := Resolver.new()
	for idx in Maps.count():
		var s := MatchState.new()
		s.setup([], [], idx)
		s.round_num = 0
		var rounds := 0
		while s.winner < 0 and rounds < 120:
			s.begin_round()
			var first := s.first_player_this_round()
			resolver.resolve(s, AI.plan(s, Consts.Player.A), AI.plan(s, Consts.Player.B), first)
			s.score_round([])
			rounds += 1
		_check(s.winner >= 0, "карта %d: бот-матч завершился за %d раундов" % [idx, rounds])
