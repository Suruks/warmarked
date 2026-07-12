extends SceneTree

## Проверки генератора случайного отряда (Loadout.random_team / random_hero). Запуск:
##   "…\godot.windows.opt.tools.64.exe" --headless --path E:\dev\warmarked --script res://tests/random_loadout_test.gd

var _pass := 0
var _fail := 0

const _SAMPLES := 400


func _initialize() -> void:
	print("=== Warmarked random-loadout tests ===")
	test_team_shape()
	test_kits_balanced_and_valid()
	test_survives_sanitize_and_class_inferable()
	test_bot_match_on_random_teams()
	print("=== Итог: %d PASS, %d FAIL ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  " + label)
	else:
		_fail += 1
		print("  FAIL  " + label)


# Проверка R1–R5 для одного кита (независимая от Loadout реализация — чтобы поймать расхождение).
func _kit_balanced(skills: Array) -> bool:
	var passives := 0
	var has_class := false
	var cheap := false
	var meaty := false
	var expensive := 0
	for s in skills:
		var def := HeroDefs.skill_def(s)
		if not HeroDefs.is_neutral(s):
			has_class = true
		if def.passive:
			passives += 1
			continue
		if def.mana <= 1: cheap = true
		if def.mana >= 2: meaty = true
		if def.mana >= 4: expensive += 1
	return has_class and passives <= 1 and cheap and meaty and expensive <= 1


func test_team_shape() -> void:
	var ok := true
	for _i in 50:
		var team := Loadout.random_team()
		if team.size() != Loadout.TEAM_SIZE:
			ok = false
		# ровно по одному каждого класса, в порядке HEROES
		for t in Loadout.TEAM_SIZE:
			if int(team[t].type) != Loadout.HEROES[t]:
				ok = false
	_check(ok, "команда: %d бойцов, по одному Охотник/Фея/Камнешип" % Loadout.TEAM_SIZE)


func test_kits_balanced_and_valid() -> void:
	var all_balanced := true
	var all_wellformed := true
	for _i in _SAMPLES:
		for h in Loadout.HEROES:
			var kit: Array = Loadout.random_hero(h)
			# 3 различных скилла из пула класса или нейтралов
			if kit.size() != Consts.SKILLS_PER_HERO:
				all_wellformed = false
			var seen := {}
			var pool: Array = HeroDefs.pool(h)
			for s in kit:
				if seen.has(s): all_wellformed = false
				seen[s] = true
				if not (s in pool or HeroDefs.is_neutral(s)):
					all_wellformed = false
			if not _kit_balanced(kit):
				all_balanced = false
				print("    несбалансированный кит: %s (класс %d)" % [str(kit), h])
	_check(all_wellformed, "все киты: 3 различных легальных скилла (%d проб)" % (_SAMPLES * 3))
	_check(all_balanced, "все киты проходят R1–R5 (%d проб)" % (_SAMPLES * 3))


func test_survives_sanitize_and_class_inferable() -> void:
	var stable := true
	var classable := true
	for _i in _SAMPLES:
		for h in Loadout.HEROES:
			var kit: Array = Loadout.random_hero(h)
			# sanitize_hero не должен ничего менять (кит уже валиден)
			var san := Loadout.sanitize_hero(h, kit.duplicate())
			if HeroDefs.sorted_by_mana(kit) != HeroDefs.sorted_by_mana(san):
				stable = false
			# в ките есть классовый скилл → Коллекция выведет класс (иначе _on_save дропнет тройку)
			var has_class := false
			for s in kit:
				if HeroDefs.hero_of_skill(s) >= 0:
					has_class = true
			if not has_class:
				classable = false
	_check(stable, "киты переживают sanitize_hero без изменений")
	_check(classable, "у каждого кита есть классовый скилл (сохранится в Коллекции)")


func test_bot_match_on_random_teams() -> void:
	# Полный бот-матч на независимых случайных отрядах доходит до победителя без падений.
	var resolver := Resolver.new()
	var winners := 0
	for _i in 8:
		var s := MatchState.new()
		s.setup(Loadout.random_team(), Loadout.random_team(), 0)
		s.round_num = 0
		var rounds := 0
		while s.winner < 0 and rounds < 120:
			s.begin_round()
			var first := s.first_player_this_round()
			resolver.resolve(s, AI.plan(s, Consts.Player.A), AI.plan(s, Consts.Player.B), first)
			s.score_round([])
			rounds += 1
		if s.winner >= 0:
			winners += 1
	_check(winners == 8, "8 бот-матчей на случайных отрядах завершились победителем [%d/8]" % winners)
