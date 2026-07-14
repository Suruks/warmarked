extends SceneTree

## Headless-проверки чистой логики резолвера/состояния.
## Запуск:
##   "…\godot.windows.opt.tools.64.exe" --headless --path E:\dev\warmarked --script res://tests/headless_test.gd

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("=== Warmarked headless tests ===")
	test_interleave_blocks_collision()
	test_trap_immobilize_then_snipe()
	test_snipe_slot_gate()
	test_shotgun_knockback_collision()
	test_shotgun_area_2x2()
	test_shotgun_fixed_direction()
	test_snipe_relative()
	test_kill_scoring()
	test_respawn_at_home_row()
	test_respawn_delay_misses_one_full_round()
	test_control_point_majority()
	test_crystal_no_passive()
	test_immobilize_same_turn_only()
	test_grave_at_respawn_cell()
	test_multi_round_income_and_control()
	test_fairy_shield_ally()
	test_shield_nontarget_and_order()
	test_shield_gates_trap()
	test_bullet_blocked_by_unit()
	test_trap_excludes_occupied_and_graves()
	test_trap_fizzle_on_occupied()
	test_trap_lives_one_round()
	test_relative_move_after_knockback()
	test_ambush_ignores_allies()
	test_allies_do_not_block_movement()
	test_respawn_resets_mana()
	test_validator_move_rules()
	test_validator_rejects_second_move()
	test_validator_target_geometry()
	test_validator_mana_gate_and_double_cast()
	test_validator_rejects_foreign_and_dead()
	test_onslaught_pushes_and_advances()
	test_onslaught_into_wall_collides_and_blocks_advance()
	test_spikes_hits_diagonal_neighbors()
	test_spikes_ignore_distant_diagonal()
	test_hardening_reduces_damage()
	test_hardening_absorbs_small_hit()
	test_shards_retaliate_on_attacker()
	test_overload_spends_all_mana()
	test_swap_exchanges_positions()
	test_precise_hits_at_exact_range()
	test_precise_fizzles_off_range()
	test_hunt_mark_doubles_hunter_damage()
	test_retreat_moves_when_enemy_adjacent()
	test_retreat_fizzles_without_enemy()
	test_net_immobilizes_target()
	test_deathcross_hits_first_enemy_per_line()
	test_minefield_places_traps()
	test_minefield_damages_anyone()
	test_validator_minefield_cells()
	test_bleed_marks_and_ticks_per_action()
	test_bleed_ticks_once_per_move_action()
	test_bleed_ticks_on_swap()
	test_bleed_no_tick_without_move()
	test_bleed_expires_after_turns()
	test_spark_hits_target()
	test_lightning_hits_harder()
	test_disorient_reverses_direction()
	test_manasteal_steals_and_damages()
	test_shackles_blocks_basic_attack()
	test_slow_reduces_move_range()
	test_teleport_moves_self()
	test_teleport_blocked_when_occupied()
	test_revive_raises_fallen_ally()
	test_sniper_boosts_basic_attack_when_still()
	test_cold_blood_mana_on_kill()
	test_blessing_heals_allies_in_radius()
	test_lightness_move_range_3()
	test_lightness_move_path_to_control_point()
	test_drag_step_traces_manual_path()
	test_drag_flow_writes_move_order()
	test_grave_tooltip_shows_class()
	test_crystal_shell_reduces_first_hit_only()
	test_death_nova_hits_neighbors()
	test_passive_cannot_be_activated()
	test_neutral_push_knocks_neighbor()
	test_neutral_step_moves_two()
	test_neutral_block_absorbs()
	test_neutral_swap_ally()
	test_neutral_self_heal()
	test_neutral_meditation()
	test_neutral_allowed_on_any_hero()
	test_second_player_skips_last_slot()
	test_validator_drops_second_player_last_slot()
	test_reflexes_dodges_and_gains_mana()
	test_reflexes_blocked_when_cornered()
	test_skill_slot_follows_loadout()
	test_loadout_sanitize()
	test_team_allows_duplicate_heroes()
	test_immobilize_blocks_movement_skills()
	print("=== Итог: %d PASS, %d FAIL ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------- helpers

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  " + label)
	else:
		_fail += 1
		print("  FAIL  " + label)


func _slots() -> Array:
	return [Order.empty(), Order.empty(), Order.empty(), Order.empty()]


func _fresh() -> MatchState:
	var s := MatchState.new()
	s.setup()
	s.round_num = 1
	# развести всех подальше, чтобы не мешали (перекроем по месту в конкретном тесте)
	return s


func _place(s: MatchState, id: int, cell: Vector2i, hp := -1) -> Unit:
	var u := s.get_unit(id)
	u.cell = cell
	if hp >= 0:
		u.hp = hp
	return u


# ---------------------------------------------------------------- tests

func test_interleave_blocks_collision() -> void:
	# A первым; A и B оба идут на (3,3) → A занимает, B блокируется (нет коллизии)
	var s := _fresh()
	var a := _place(s, 0, Vector2i(3, 4))   # A hunter
	var b := _place(s, 3, Vector2i(3, 2))   # B hunter
	var oa := _slots(); oa[0] = Order.make_move(0, [Vector2i(0, -1)] as Array[Vector2i])  # (3,4)->(3,3)
	var ob := _slots(); ob[0] = Order.make_move(3, [Vector2i(0, 1)] as Array[Vector2i])   # (3,2)->(3,3)
	var r := Resolver.new()
	r.resolve(s, oa, ob, Consts.Player.A)
	_check(a.cell == Vector2i(3, 3), "интерливинг: A занял (3,3)")
	_check(b.cell == Vector2i(3, 2), "интерливинг: B заблокирован, остался на (3,2)")


func test_trap_immobilize_then_snipe() -> void:
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4)).mana = Consts.TRAP_MANA + Consts.SNIPE_MANA   # A hunter
	var b := _place(s, 5, Vector2i(1, 4))            # B crystal (полное HP)
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(2, 4))   # капкан
	oa[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(2, 4))   # снайп (слот 3)
	var ob := _slots()
	ob[0] = Order.make_move(5, [Vector2i(1, 0)] as Array[Vector2i]) # (1,4)->(2,4) входит в капкан
	var r := Resolver.new()
	r.resolve(s, oa, ob, Consts.Player.A)
	var expect := Consts.CRYSTAL_HP - Consts.TRAP_DMG - Consts.SNIPE_DMG
	_check(b.hp == expect, "капкан+снайп по обездвиженному: HP %d [%d]" % [expect, b.hp])
	_check(b.immobilized, "капкан выставил обездвиживание сразу")
	_check(b.cell == Vector2i(2, 4), "жертва на клетке капкана")


func test_snipe_slot_gate() -> void:
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4))
	var b := _place(s, 5, Vector2i(3, 6), 10)
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 6))  # снайп в слот 1 → физзл
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	_check(b.hp == 10, "гейт снайпа: слот 1 физзлит, урона нет [%d]" % b.hp)


func test_shotgun_knockback_collision() -> void:
	var s := _fresh()
	s.board.obstacles = {}                            # чистое поле для предсказуемости
	_place(s, 0, Vector2i(5, 5)).mana = Consts.SHOTGUN_MANA            # A hunter (дробь 3)
	var b := _place(s, 4, Vector2i(6, 6), 12)         # B fairy на диагонали у угла
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY3, Vector2i(6, 6))  # дробь по диагонали
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	# дробь + отброс в угол (7,7 вне поля) → столкновение
	var expect := 12 - Consts.SHOTGUN_DMG - Consts.COLLISION_DMG
	_check(b.hp == expect, "дробь+столкновение о край: HP %d [%d]" % [expect, b.hp])


func test_kill_scoring() -> void:
	var s := _fresh()
	_place(s, 1, Vector2i(0, 0))                      # увести A fairy
	_place(s, 0, Vector2i(3, 4)).mana = Consts.SNIPE_MANA            # A hunter (снайп 2)
	var b := _place(s, 4, Vector2i(3, 2), 5)          # B fairy hp5 (линия (3,4)->(3,2) чиста)
	var oa := _slots()
	oa[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 2))  # снайп 7 в слот 3
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	_check(not b.alive, "килл: цель мертва")
	_check(s.score[Consts.Player.A] == Consts.KILL_POINTS, "килл: +3 очка A [%d]" % s.score[Consts.Player.A])
	_check(b.dead_timer == Consts.RESPAWN_DELAY, "килл: таймер респа = 3")
	_check(b.death_cell == Vector2i(3, 2), "килл: клетка смерти запомнена")


func test_mutual_kill_at_win_score_is_a_draw() -> void:
	# Оба игрока уже на WIN_SCORE-1; взаимный размен киллами в ОДНОМ раунде поднимает
	# обоих до WIN_SCORE одновременно -> ничья, а не победа того, чей килл засчитался первым.
	var s := _fresh()
	s.score[Consts.Player.A] = Consts.WIN_SCORE - Consts.KILL_POINTS
	s.score[Consts.Player.B] = Consts.WIN_SCORE - Consts.KILL_POINTS
	_place(s, 0, Vector2i(3, 4)).mana = Consts.SNIPE_MANA   # A hunter
	_place(s, 3, Vector2i(0, 4)).mana = Consts.SNIPE_MANA   # B hunter
	var av := _place(s, 1, Vector2i(0, 2), 5)                # A fairy — цель B hunter'а
	var bv := _place(s, 4, Vector2i(3, 2), 5)                # B fairy — цель A hunter'а
	_place(s, 2, Vector2i(6, 6))                             # A crystal, вне линий огня
	_place(s, 5, Vector2i(6, 0))                             # B crystal, вне линий огня
	var oa := _slots()
	oa[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 2))   # A снайпит B fairy
	var ob := _slots()
	ob[2] = Order.make(3, Consts.Action.ABILITY2, Vector2i(0, 2))   # B снайпит A fairy
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(not av.alive and not bv.alive, "взаимный размен: обе феи мертвы")
	var ev: Array = []
	s.score_round(ev)
	_check(s.score[Consts.Player.A] == Consts.WIN_SCORE, "ничья: A набрал WIN_SCORE [%d]" % s.score[Consts.Player.A])
	_check(s.score[Consts.Player.B] == Consts.WIN_SCORE, "ничья: B набрал WIN_SCORE [%d]" % s.score[Consts.Player.B])
	_check(s.winner == Consts.DRAW, "ничья: winner == DRAW [%d]" % s.winner)


func test_single_win_still_declares_winner() -> void:
	# Контроль: если порог набрал только один игрок, ничьей быть не должно.
	var s := _fresh()
	s.score[Consts.Player.A] = Consts.WIN_SCORE - Consts.CONTROL_POINTS_PER_ROUND
	_place(s, 2, s.board.control_points[0])   # A crystal стоит на точке контроля один
	var ev: Array = []
	s.score_round(ev)
	_check(s.winner == Consts.Player.A, "победа: одиночный триггер даёт победителя, не ничью [%d]" % s.winner)


func test_respawn_at_home_row() -> void:
	# респ идёт в РОДНУЮ клетку, а не на клетку смерти; стоящий на клетке смерти не наказывается
	var s := _fresh()
	s.round_num = 5
	var dead := s.get_unit(4)                          # B Фея, дом (3,0)
	dead.alive = false
	dead.hp = 0
	dead.cell = Vector2i(3, 3)
	dead.death_cell = Vector2i(3, 3)
	dead.dead_timer = 1
	var camper := _place(s, 0, Vector2i(3, 3), Consts.HUNTER_HP)   # A Охотник на клетке смерти
	var ev := s.begin_round()
	_check(dead.alive and dead.cell == dead.home_cell, "респ: воскрес в родной клетке [%s]" % str(dead.cell))
	_check(dead.hp == dead.max_hp, "респ: полное HP")
	_check(camper.hp == Consts.HUNTER_HP, "респ: стоящий на клетке смерти не получает урона [%d]" % camper.hp)
	_check(_has_type(ev, Consts.EventType.RESPAWN), "респ: событие RESPAWN")

	# дом занят → ближайшая свободная клетка родного ряда
	var s2 := _fresh()
	var dead2 := s2.get_unit(4)
	dead2.alive = false
	dead2.hp = 0
	dead2.cell = Vector2i(6, 6)
	dead2.death_cell = Vector2i(6, 6)
	dead2.dead_timer = 1
	_place(s2, 0, Vector2i(3, 0))                      # чужой юнит занял дом (3,0)
	s2.begin_round()
	_check(dead2.alive and dead2.cell == Vector2i(2, 0),
		"респ: дом занят → соседняя клетка ряда (2,0) [%s]" % str(dead2.cell))


func test_respawn_delay_misses_one_full_round() -> void:
	# убит в раунде N → возвращается в начале N+RESPAWN_DELAY, пропустив (DELAY-1) полных раундов
	var s := _fresh()
	var u := s.get_unit(4)
	u.alive = false
	u.hp = 0
	u.death_cell = Vector2i(3, 3)
	u.cell = Vector2i(3, 3)
	u.dead_timer = Consts.RESPAWN_DELAY
	s.begin_round()
	_check(not u.alive, "респ-кулдаун: в следующем раунде ещё мёртв")
	s.begin_round()
	_check(u.alive, "респ-кулдаун: вернулся через %d раунда" % Consts.RESPAWN_DELAY)


func test_control_point_majority() -> void:
	var s := _fresh()
	# точки: (2,2),(3,3),(4,4)
	_place(s, 0, Vector2i(2, 2))    # A
	_place(s, 1, Vector2i(3, 3))    # A → 2 точки
	_place(s, 2, Vector2i(0, 0))    # A вне точек
	_place(s, 3, Vector2i(4, 4))    # B → 1 точка
	_place(s, 4, Vector2i(6, 6))    # B вне точек
	_place(s, 5, Vector2i(0, 6))    # B вне точек
	var ev: Array = []
	s.score[Consts.Player.A] = 0
	s.score[Consts.Player.B] = 0
	s.score_round(ev)
	_check(s.score[Consts.Player.A] == 1 and s.score[Consts.Player.B] == 0, "точки: строгое большинство A → +1 A")
	# равенство 1:1: увести A с (3,3)
	_place(s, 1, Vector2i(0, 3))    # A уходит с (3,3) → A: (2,2)=1, B: (4,4)=1
	s.score[Consts.Player.A] = 0
	s.score[Consts.Player.B] = 0
	s.score_round(ev)
	_check(s.score[Consts.Player.A] == 0 and s.score[Consts.Player.B] == 0, "точки: равенство 1:1 → очко никому")


func test_crystal_no_passive() -> void:
	# пассивка снята (CRYSTAL_PASSIVE_REDUCTION = 0) → кристалл ест урон полностью
	var s := _fresh()
	var fairy := _place(s, 1, Vector2i(3, 3))      # A fairy кастует вспышку
	var crystal := _place(s, 5, Vector2i(3, 4), 10)  # B crystal рядом
	fairy.mana = Consts.FLASH_MANA
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY1, Vector2i(3, 3))  # вспышка (радиус 1)
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	var expect := 10 - (Consts.FLASH_DMG - Consts.CRYSTAL_PASSIVE_REDUCTION)
	_check(crystal.hp == expect, "кристалл без пассивки: вспышка бьёт полностью, HP %d [%d]" % [expect, crystal.hp])


func test_grave_at_respawn_cell() -> void:
	# Могила ставится в клетку воскрешения (домашнюю), а death_cell помнит, где реально убили.
	var s := _fresh()
	_place(s, 1, Vector2i(0, 0))                       # увести A fairy с линии
	_place(s, 0, Vector2i(3, 4)).mana = Consts.SNIPE_MANA
	var b := _place(s, 4, Vector2i(3, 2), 3)           # B fairy (дом (3,0)), hp3 — снайп убьёт
	var oa := _slots()
	oa[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 2))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(not b.alive, "снайп убил цель")
	_check(b.death_cell == Vector2i(3, 2), "death_cell помнит место гибели (3,2) [%s]" % b.death_cell)
	_check(b.cell == b.home_cell, "могила стоит в клетке воскрешения (дом) [%s]" % b.cell)


func test_immobilize_same_turn_only() -> void:
	# Капкан замораживает В ТОМ ЖЕ раунде: остаток движения гасится, но следующий раунд свободен.
	var s := _fresh()
	var c := _place(s, 5, Vector2i(1, 4))   # B crystal
	s.traps.append({"cell": Vector2i(2, 4), "owner_player": Consts.Player.A,
			"owner_id": 0, "expire_round": s.round_num})
	var ob := _slots()
	ob[0] = Order.make_move(5, [Vector2i(1, 0)] as Array[Vector2i])   # (1,4)->(2,4) в капкан
	ob[1] = Order.make_move(5, [Vector2i(1, 0)] as Array[Vector2i])   # попытка идти дальше тем же ходом
	Resolver.new().resolve(s, _slots(), ob, Consts.Player.A)
	_check(c.immobilized, "капкан: обездвижен сразу в этом же раунде")
	_check(c.cell == Vector2i(2, 4), "капкан: застрял на месте, второй слот-ход не сработал [%s]" % c.cell)
	# следующий раунд — обездвиживание снято, снова ходит
	s.begin_round()
	_check(not c.immobilized, "новый раунд: обездвиживание снято")
	var ob2 := _slots()
	ob2[0] = Order.make_move(5, [Vector2i(1, 0)] as Array[Vector2i])   # (2,4)->(3,4)
	Resolver.new().resolve(s, _slots(), ob2, Consts.Player.A)
	_check(c.cell == Vector2i(3, 4), "новый раунд: снова может ходить [%s]" % c.cell)


func test_multi_round_income_and_control() -> void:
	# 3 раунда: A держит большинство точек, оба пасуют → +1 A/раунд, мана растёт +1/раунд
	var s := MatchState.new()
	s.setup()
	_place(s, 0, Vector2i(2, 2))   # A → точка
	_place(s, 1, Vector2i(3, 3))   # A → точка
	_place(s, 2, Vector2i(4, 4))   # A → точка (3 из 3)
	_place(s, 3, Vector2i(0, 0))   # B вне точек
	_place(s, 4, Vector2i(6, 6))   # B вне точек
	_place(s, 5, Vector2i(0, 6))   # B вне точек
	var r := Resolver.new()
	for _i in 3:
		s.begin_round()
		var ev := r.resolve(s, Order.empty_slots(), Order.empty_slots(), s.first_player_this_round())
		s.score_round(ev)
	_check(s.score[Consts.Player.A] == 3, "3 раунда контроля большинства → 3 очка A [%d]" % s.score[Consts.Player.A])
	_check(s.score[Consts.Player.B] == 0, "B без большинства → 0 очков [%d]" % s.score[Consts.Player.B])
	_check(s.get_unit(0).mana == 3, "мана: старт 1 + доход в раундах 2,3 = 3 [%d]" % s.get_unit(0).mana)
	_check(s.winner < 0, "победитель ещё не определён (<10)")


func test_fairy_shield_ally() -> void:
	# Фея ставит щит на соседнего союзника; вражеский снайп по нему поглощается
	var s := _fresh()
	var fairy := _place(s, 1, Vector2i(3, 3))   # A fairy
	fairy.mana = Consts.CANCEL_MANA
	var hunter := _place(s, 0, Vector2i(3, 4), Consts.HUNTER_HP)   # A hunter рядом с Феей
	var enemy := _place(s, 3, Vector2i(5, 4))   # B hunter (снайпер), линия (5,4)->(3,4) чиста
	enemy.mana = Consts.SNIPE_MANA
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY2, Vector2i(3, 4))   # щит на союзника
	var ob := _slots()
	ob[2] = Order.make(3, Consts.Action.ABILITY2, Vector2i(3, 4))   # снайп по нему (слот 3)
	var r := Resolver.new()
	r.resolve(s, oa, ob, Consts.Player.A)
	_check(hunter.hp == Consts.HUNTER_HP, "щит на союзнике поглотил снайп: HP %d [%d]" % [Consts.HUNTER_HP, hunter.hp])
	_check(not hunter.shield_armed, "щит израсходован после поглощения")


func test_bullet_blocked_by_unit() -> void:
	# Снайп нацелен в дальнюю цель, но на линии стоит блокер → пуля попадает в блокера
	var s := _fresh()
	s.board.obstacles = {}                       # чистая линия
	_place(s, 0, Vector2i(0, 4)).mana = Consts.SNIPE_MANA       # A hunter
	_place(s, 1, Vector2i(0, 0))                 # увести своих
	_place(s, 2, Vector2i(6, 6))
	var blocker := _place(s, 4, Vector2i(2, 4), 12)   # B fairy на пути
	var target := _place(s, 5, Vector2i(4, 4), 10)    # B crystal — задуманная цель
	_place(s, 3, Vector2i(6, 0))
	var oa := _slots()
	oa[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(4, 4))  # снайп в (4,4)
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	_check(blocker.hp == 12 - Consts.SNIPE_DMG, "пуля попала в блокера на пути [%d]" % blocker.hp)
	_check(target.hp == 10, "цель за блокером не задета [%d]" % target.hp)


func test_trap_excludes_occupied_and_graves() -> void:
	var s := _fresh()
	var hunter := _place(s, 0, Vector2i(3, 4))     # A hunter
	_place(s, 5, Vector2i(2, 4))                    # живой враг рядом (радиус 1)
	var dead := _place(s, 3, Vector2i(4, 4))        # могила рядом
	dead.alive = false
	dead.death_cell = Vector2i(4, 4)
	var occ := Targeting.build_occupancy(s)
	var cands := Targeting.candidates(s, hunter, Consts.Action.ABILITY1, hunter.cell, occ)
	_check(not (Vector2i(2, 4) in cands), "капкан: занятая юнитом клетка исключена")
	_check(not (Vector2i(4, 4) in cands), "капкан: могила исключена")
	_check(Vector2i(3, 3) in cands, "капкан: свободная клетка доступна")


func test_trap_fizzle_on_occupied() -> void:
	# занято живым юнитом (сценарий no-retarget) → капкан не ставится
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4)).mana = 1           # A hunter
	_place(s, 5, Vector2i(2, 4))                     # враг стоит на целевой клетке
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(2, 4))
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	_check(s.traps.size() == 0, "капкан не поставлен в клетку с юнитом [%d]" % s.traps.size())

	# занято могилой → тоже не ставится
	var s2 := _fresh()
	_place(s2, 0, Vector2i(3, 4)).mana = 1
	var dead := _place(s2, 5, Vector2i(2, 4))
	dead.alive = false
	dead.death_cell = Vector2i(2, 4)
	var oa2 := _slots()
	oa2[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(2, 4))
	Resolver.new().resolve(s2, oa2, _slots(), Consts.Player.A)
	_check(s2.traps.size() == 0, "капкан не поставлен в клетку с могилой [%d]" % s2.traps.size())


func test_trap_lives_one_round() -> void:
	var s := _fresh()                               # round_num = 1
	_place(s, 0, Vector2i(3, 4)).mana = 1           # A hunter
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(2, 4))   # капкан на пустую клетку
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(s.traps.size() == 1, "капкан стоит в раунде размещения [%d]" % s.traps.size())
	s.begin_round()                                 # -> раунд 2
	_check(s.traps.size() == 0, "капкан исчез в следующем раунде (живёт 1 раунд) [%d]" % s.traps.size())


func test_relative_move_after_knockback() -> void:
	# Фею отбрасывают Дробью до её хода → её ход применяется от НОВОЙ клетки (относительно)
	var s := _fresh()
	s.board.obstacles = {}
	_place(s, 0, Vector2i(0, 3)).mana = Consts.SHOTGUN_MANA           # A hunter (Дробь)
	var fairy := _place(s, 4, Vector2i(1, 4), 12)    # B fairy на диагонали
	# развести остальных
	_place(s, 1, Vector2i(0, 0)); _place(s, 2, Vector2i(6, 6))
	_place(s, 3, Vector2i(6, 0)); _place(s, 5, Vector2i(0, 6))
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY3, Vector2i(1, 4))   # Дробь: отбрасывает Фею на (2,5)
	var ob := _slots()
	ob[0] = Order.make_move(4, [Vector2i(0, -1)] as Array[Vector2i])  # Фея планирует «вверх на 1»
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	# A первым: Дробь (0,3)->цель(1,4), отброс dir(1,1) → Фея на (2,5); затем её ход (0,-1) → (2,4)
	_check(fairy.cell == Vector2i(2, 4), "относительный ход после отброса: (2,5)+(0,-1)=(2,4) [%s]" % str(fairy.cell))


func test_shield_nontarget_and_order() -> void:
	# 1) щит — нон-таргет: пустая соседняя клетка теперь валидная цель
	var s := _fresh()
	var fairy := _place(s, 1, Vector2i(3, 3))
	fairy.mana = Consts.CANCEL_MANA
	var occ := Targeting.build_occupancy(s)
	var cands := Targeting.candidates(s, fairy, Consts.Action.ABILITY2, fairy.cell, occ)
	_check(Vector2i(3, 2) in cands, "щит: пустая соседняя клетка — валидная цель (нон-таргет)")

	# 2) порядок важен: щит РАНЬШЕ прихода союзника → физзл (клетка пуста в этот тик)
	var s1 := _fresh()
	_place(s1, 1, Vector2i(3, 3)).mana = Consts.CANCEL_MANA   # A fairy
	var hunter1 := _place(s1, 0, Vector2i(2, 2))    # A hunter, придёт на (3,2) вторым
	var oa1 := _slots()
	oa1[0] = Order.make(1, Consts.Action.ABILITY2, Vector2i(3, 2))       # щит на (3,2)
	oa1[1] = Order.make_move(0, [Vector2i(1, 0)] as Array[Vector2i])     # (2,2)->(3,2)
	Resolver.new().resolve(s1, oa1, _slots(), Consts.Player.A)
	_check(not hunter1.shield_armed, "порядок: щит до прихода — не наложился")

	# 3) правильный порядок: сначала приход, потом щит → наложился
	var s2 := _fresh()
	_place(s2, 1, Vector2i(3, 3)).mana = Consts.CANCEL_MANA
	var hunter2 := _place(s2, 0, Vector2i(2, 2))
	var oa2 := _slots()
	oa2[0] = Order.make_move(0, [Vector2i(1, 0)] as Array[Vector2i])     # (2,2)->(3,2)
	oa2[1] = Order.make(1, Consts.Action.ABILITY2, Vector2i(3, 2))       # щит на (3,2)
	Resolver.new().resolve(s2, oa2, _slots(), Consts.Player.A)
	_check(hunter2.shield_armed, "порядок: щит после прихода — наложился")


func test_shield_gates_trap() -> void:
	# щит гасит капкан ЦЕЛИКОМ: ни урона, ни обездвиживания
	var s := _fresh()
	var crystal := _place(s, 5, Vector2i(1, 4), 10)   # B crystal со щитом
	crystal.shield_armed = true
	s.traps.append({"cell": Vector2i(2, 4), "owner_player": Consts.Player.A,
		"owner_id": 0, "expire_round": s.round_num + Consts.PERSIST_ROUNDS})
	var ob := _slots()
	ob[0] = Order.make_move(5, [Vector2i(1, 0)] as Array[Vector2i])   # (1,4)->(2,4) в капкан
	Resolver.new().resolve(s, _slots(), ob, Consts.Player.A)
	_check(crystal.cell == Vector2i(2, 4), "кристалл дошёл до капкана")
	_check(crystal.hp == 10, "щит погасил урон капкана [%d]" % crystal.hp)
	_check(not crystal.immobilized, "щит погасил и обездвиживание капкана")
	_check(not crystal.shield_armed, "щит израсходован капканом")


func test_shotgun_area_2x2() -> void:
	# Дробь вверх-вправо из (2,3): квадрат (3,2),(3,3),(2,2). Клетка снизу (2,4) НЕ задета.
	var s := _fresh()
	s.board.obstacles = {}
	_place(s, 0, Vector2i(2, 3)).mana = Consts.SHOTGUN_MANA         # A hunter (стрелок)
	var d1 := _place(s, 1, Vector2i(3, 2), 20)     # диагональ (A fairy)
	var d2 := _place(s, 3, Vector2i(3, 3), 20)     # право (B hunter)
	var d3 := _place(s, 4, Vector2i(2, 2), 20)     # верх (B fairy)
	var outside := _place(s, 2, Vector2i(2, 4), 20)  # снизу — вне квадрата (A crystal)
	_place(s, 5, Vector2i(6, 6))                    # убрать с дороги
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY3, Vector2i(3, 2))   # цель — диагональ вверх-вправо
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(d1.hp == 15, "дробь: диагональ задета (-5) [%d]" % d1.hp)
	_check(d2.hp == 15, "дробь: клетка справа задета (-5) [%d]" % d2.hp)
	_check(d3.hp == 15, "дробь: клетка сверху задета (-5) [%d]" % d3.hp)
	_check(outside.hp == 20, "дробь: клетка вне квадрата НЕ задета [%d]" % outside.hp)


func test_shotgun_fixed_direction() -> void:
	# нон-таргет: бьёт по offset от текущей позиции, а не по абсолютной target
	var s := _fresh()
	s.board.obstacles = {}
	_place(s, 0, Vector2i(2, 3)).mana = Consts.SHOTGUN_MANA
	var e := _place(s, 3, Vector2i(3, 2), 20)   # клетка квадранта для offset (1,-1)
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY3, Vector2i(5, 5), Vector2i(1, -1), true)  # target «мимо», offset фикс
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(e.hp == 15, "дробь бьёт по offset от текущей позиции, не по цели [%d]" % e.hp)


func test_snipe_relative() -> void:
	# снайп нон-таргет: пуля летит по offset от текущей клетки стрелка
	var s := _fresh()
	_place(s, 0, Vector2i(2, 3)).mana = Consts.SNIPE_MANA
	var e := _place(s, 4, Vector2i(2, 1), 20)   # 2 клетки вверх (offset (0,-2))
	var oa := _slots()
	oa[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(9, 9), Vector2i(0, -2), true)  # target мимо
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(e.hp == 20 - Consts.SNIPE_DMG, "снайп бьёт по offset от текущей позиции [%d]" % e.hp)


func test_ambush_ignores_allies() -> void:
	# союзник, вошедший рядом с засадой, не получает урона и не тратит её
	var s := _fresh()
	_place(s, 2, Vector2i(3, 3)).mana = Consts.AMBUSH_MANA   # A crystal встаёт в засаду
	var ally := _place(s, 1, Vector2i(1, 4))                 # A fairy подойдёт вплотную
	var oa := _slots()
	oa[0] = Order.make(2, Consts.Action.ABILITY2)                      # засада (без цели)
	oa[1] = Order.make_move(1, [Vector2i(1, 0)] as Array[Vector2i])    # (1,4)->(2,4): рядом с (3,3)
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(ally.cell == Vector2i(2, 4), "засада: союзник дошёл вплотную")
	_check(ally.hp == ally.max_hp, "засада не бьёт союзника [%d]" % ally.hp)
	_check(s.ambushes.size() == 1, "засада не израсходована союзником [%d]" % s.ambushes.size())

	# а вражеский юнит её срабатывает
	var s2 := _fresh()
	_place(s2, 2, Vector2i(3, 3)).mana = Consts.AMBUSH_MANA   # A crystal
	var foe := _place(s2, 5, Vector2i(1, 4))                  # B crystal
	var oa2 := _slots()
	oa2[0] = Order.make(2, Consts.Action.ABILITY2)
	var ob2 := _slots()
	ob2[0] = Order.make_move(5, [Vector2i(1, 0)] as Array[Vector2i])   # (1,4)->(2,4)
	Resolver.new().resolve(s2, oa2, ob2, Consts.Player.A)
	_check(foe.hp == foe.max_hp - Consts.AMBUSH_DMG, "засада бьёт врага [%d]" % foe.hp)
	_check(s2.ambushes.size() == 0, "засада израсходована врагом [%d]" % s2.ambushes.size())


func test_allies_do_not_block_movement() -> void:
	# 1) резолвер: проходим сквозь союзника и встаём за ним
	var s := _fresh()
	s.board.obstacles = {}
	var hunter := _place(s, 0, Vector2i(3, 4))   # A hunter
	_place(s, 1, Vector2i(3, 3))                 # A fairy — прямо на пути
	var oa := _slots()
	oa[0] = Order.make_move(0, [Vector2i(0, -1), Vector2i(0, -1)] as Array[Vector2i])
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(hunter.cell == Vector2i(3, 2), "ход: прошёл сквозь союзника на (3,2) [%s]" % str(hunter.cell))

	# 2) резолвер: встать НА союзника нельзя — ход упирается
	var s2 := _fresh()
	s2.board.obstacles = {}
	var h2 := _place(s2, 0, Vector2i(3, 4))
	_place(s2, 1, Vector2i(3, 3))
	var oa2 := _slots()
	oa2[0] = Order.make_move(0, [Vector2i(0, -1)] as Array[Vector2i])   # финиш на союзнике
	Resolver.new().resolve(s2, oa2, _slots(), Consts.Player.A)
	_check(h2.cell == Vector2i(3, 4), "ход: остановка на клетке союзника запрещена [%s]" % str(h2.cell))

	# 3) резолвер: враг блокирует полностью (даже как транзит)
	var s3 := _fresh()
	s3.board.obstacles = {}
	var h3 := _place(s3, 0, Vector2i(3, 4))
	_place(s3, 3, Vector2i(3, 3))                # B hunter на пути
	var oa3 := _slots()
	oa3[0] = Order.make_move(0, [Vector2i(0, -1), Vector2i(0, -1)] as Array[Vector2i])
	Resolver.new().resolve(s3, oa3, _slots(), Consts.Player.A)
	_check(h3.cell == Vector2i(3, 4), "ход: враг блокирует проход [%s]" % str(h3.cell))

	# 4) планирование: клетка ЗА союзником достижима, клетка союзника — нет
	var s4 := _fresh()
	s4.board.obstacles = {}
	var h4 := _place(s4, 0, Vector2i(3, 4))
	_place(s4, 1, Vector2i(3, 3))                # союзник
	var cells := Targeting.move_paths(s4, h4.cell, h4.id)
	_check(not cells.has(Vector2i(3, 3)), "план: клетка союзника не пункт назначения")
	_check(cells.has(Vector2i(3, 2)), "план: клетка за союзником достижима")

	# 5) планирование: за врагом — недостижимо
	var s5 := _fresh()
	s5.board.obstacles = {}
	var h5 := _place(s5, 0, Vector2i(3, 4))
	_place(s5, 3, Vector2i(3, 3))                # враг
	var cells5 := Targeting.move_paths(s5, h5.cell, h5.id)
	_check(not cells5.has(Vector2i(3, 2)), "план: за врагом пройти нельзя")


func test_respawn_resets_mana() -> void:
	# банк маны, накопленный до смерти, не переживает респ
	var s := _fresh()
	var u := s.get_unit(4)          # B fairy
	u.alive = false
	u.hp = 0
	u.cell = Vector2i(0, 0)
	u.death_cell = Vector2i(0, 0)
	u.dead_timer = 1
	u.mana = 7
	s.begin_round()
	_check(u.alive and u.hp == u.max_hp, "респ: воскрес с полным HP")
	_check(u.mana == Consts.START_MANA, "респ: мана сброшена к стартовой [%d]" % u.mana)
	_check(u.cell == u.home_cell, "респ: вернулся в родную клетку [%s]" % str(u.cell))


func test_validator_move_rules() -> void:
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4))     # A hunter
	var o := _slots()
	o[0] = Order.make_move(0, [Vector2i(0, -5)] as Array[Vector2i])                     # телепорт
	o[1] = Order.make_move(0, [Vector2i(0, -1), Vector2i(0, -1)] as Array[Vector2i])    # легально (2 шага)
	o[2] = Order.make_move(0, [Vector2i(0, -1), Vector2i(0, -1), Vector2i(0, -1)] as Array[Vector2i])
	o[3] = Order.make_move(0, [Vector2i(1, 1)] as Array[Vector2i])                      # диагональ
	var out := OrderValidator.sanitize(s, o, Consts.Player.A)
	_check(out[0].is_empty(), "валидатор: шаг-телепорт отклонён")
	_check(not out[1].is_empty(), "валидатор: ход из двух орто-шагов принят")
	_check(out[2].is_empty(), "валидатор: ход длиннее MOVE_RANGE отклонён")
	_check(out[3].is_empty(), "валидатор: диагональный шаг отклонён")


func test_validator_rejects_second_move() -> void:
	# Новое правило: один герой не ходит дважды за раунд (Ход, как и скилл, — один раз).
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4))     # A hunter
	var o := _slots()
	o[0] = Order.make_move(0, [Vector2i(0, -1)] as Array[Vector2i])   # первый ход — легален
	o[1] = Order.make_move(0, [Vector2i(0, -1)] as Array[Vector2i])   # второй ход тем же героем
	var out := OrderValidator.sanitize(s, o, Consts.Player.A)
	_check(not out[0].is_empty(), "валидатор: первый Ход принят")
	_check(out[1].is_empty(), "валидатор: второй Ход того же героя отклонён")
	# но Ход другим героем в том же раунде — можно
	_place(s, 1, Vector2i(1, 4))
	var o2 := _slots()
	o2[0] = Order.make_move(0, [Vector2i(0, -1)] as Array[Vector2i])
	o2[1] = Order.make_move(1, [Vector2i(1, 0)] as Array[Vector2i])
	var out2 := OrderValidator.sanitize(s, o2, Consts.Player.A)
	_check(not out2[0].is_empty() and not out2[1].is_empty(), "валидатор: ходы РАЗНЫХ героев приняты")


func test_validator_target_geometry() -> void:
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4))     # A hunter
	_place(s, 1, Vector2i(2, 4))     # A fairy
	_check(not _san1(s, Order.make(0, Consts.Action.ATTACK, Vector2i(3, 1), Vector2i(0, -3), true)).is_empty(),
		"валидатор: выстрел на 3 клетки принят")
	_check(_san1(s, Order.make(0, Consts.Action.ATTACK, Vector2i(3, 3), Vector2i(0, -1), true)).is_empty(),
		"валидатор: выстрел в упор (дистанция 1) отклонён")
	_check(_san1(s, Order.make(0, Consts.Action.ATTACK, Vector2i(2, 3), Vector2i(-1, -1), true)).is_empty(),
		"валидатор: выстрел по диагонали отклонён")
	_check(_san1(s, Order.make(1, Consts.Action.ATTACK, Vector2i(6, 4), Vector2i(4, 0), true)).is_empty(),
		"валидатор: ближний удар Феи через всю доску отклонён")
	_check(not _san1(s, Order.make(1, Consts.Action.ATTACK, Vector2i(3, 3), Vector2i(1, -1), true)).is_empty(),
		"валидатор: удар Феи по диагонали принят")
	# Лечение вне радиуса 2
	_place(s, 1, Vector2i(2, 4)).mana = Consts.HEAL_MANA
	_check(_san1(s, Order.make(1, Consts.Action.ABILITY3, Vector2i(2, 0), Vector2i(0, -4), true)).is_empty(),
		"валидатор: лечение через всю доску отклонено")


func test_validator_mana_gate_and_double_cast() -> void:
	# один и тот же скилл дважды за раунд — нельзя
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4)).mana = Consts.SNIPE_MANA * 2
	var o := _slots()
	o[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 2), Vector2i(0, -2), true)
	o[3] = Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 2), Vector2i(0, -2), true)
	var out := OrderValidator.sanitize(s, o, Consts.Player.A)
	_check(not out[2].is_empty(), "валидатор: первый снайп принят")
	_check(out[3].is_empty(), "валидатор: повторный каст того же скилла отклонён")

	# суммарная мана героя за раунд
	var s2 := _fresh()
	_place(s2, 0, Vector2i(3, 4)).mana = Consts.TRAP_MANA   # хватает только на капкан
	var o2 := _slots()
	o2[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(2, 4), Vector2i(-1, 0), true)   # капкан
	o2[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 2), Vector2i(0, -2), true)   # снайп
	var out2 := OrderValidator.sanitize(s2, o2, Consts.Player.A)
	_check(not out2[0].is_empty(), "валидатор: капкан по мане прошёл")
	_check(out2[2].is_empty(), "валидатор: снайп сверх суммарной маны отклонён")

	# гейт слотов: снайп только в слотах 3-4
	var s3 := _fresh()
	_place(s3, 0, Vector2i(3, 4)).mana = Consts.SNIPE_MANA
	_check(_san_at(s3, Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 2), Vector2i(0, -2), true), 0).is_empty(),
		"валидатор: снайп вне слотов 3-4 отклонён")


func test_validator_rejects_foreign_and_dead() -> void:
	var s := _fresh()
	var o := _slots()
	o[0] = Order.make_move(3, [Vector2i(0, 1)] as Array[Vector2i])   # приказ юниту игрока B
	_check(OrderValidator.sanitize(s, o, Consts.Player.A)[0].is_empty(), "валидатор: приказ чужому юниту отклонён")
	s.get_unit(0).alive = false
	var o2 := _slots()
	o2[0] = Order.make_move(0, [Vector2i(0, -1)] as Array[Vector2i])
	_check(OrderValidator.sanitize(s, o2, Consts.Player.A)[0].is_empty(), "валидатор: приказ мёртвому юниту отклонён")


# Прогнать один приказ через валидатор в слоте 0 (или указанном) и вернуть результат
func _san1(s: MatchState, o: Order) -> Order:
	return _san_at(s, o, 0)


func _san_at(s: MatchState, o: Order, slot: int) -> Order:
	var arr := _slots()
	arr[slot] = o
	return OrderValidator.sanitize(s, arr, Consts.Player.A)[slot]


func _has_type(events: Array, t: int) -> bool:
	for e in events:
		if e.type == t:
			return true
	return false


# ---------------------------------------------------------------- новые скиллы Кристалкайнда

# Ставит герою кит, в котором нужный скилл стоит в ABILITY1, и выдаёт ману под него.
func _arm(s: MatchState, id: int, cell: Vector2i, skill: int) -> Unit:
	var u := _place(s, id, cell)
	u.skills = [skill, Consts.Skill.JUMP, Consts.Skill.AMBUSH]
	u.mana = HeroDefs.skill_def(skill).mana
	return u


func test_onslaught_pushes_and_advances() -> void:
	# A crystal (3,4) бьёт врага на (3,3): урон, отброс на (3,2), продвижение на (3,3)
	var s := _fresh()
	var c := _arm(s, 2, Vector2i(3, 4), Consts.Skill.ONSLAUGHT)
	var v := _place(s, 3, Vector2i(3, 3))            # B hunter
	var oa := _slots()
	oa[0] = Order.make(2, Consts.Action.ABILITY1, Vector2i(3, 3))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	var expect := Consts.HUNTER_HP - Consts.ONSLAUGHT_DMG
	_check(v.hp == expect, "натиск: урон %d [%d]" % [expect, v.hp])
	_check(v.cell == Vector2i(3, 2), "натиск: жертва отброшена на (3,2) [%s]" % v.cell)
	_check(c.cell == Vector2i(3, 3), "натиск: атакующий занял клетку жертвы [%s]" % c.cell)


func test_onslaught_into_wall_collides_and_blocks_advance() -> void:
	# Жертва на (3,2), за ней стена (3,1): отброс невозможен → столкновение, продвижения нет
	var s := _fresh()
	var c := _arm(s, 2, Vector2i(3, 3), Consts.Skill.ONSLAUGHT)
	var v := _place(s, 3, Vector2i(3, 2))
	var oa := _slots()
	oa[0] = Order.make(2, Consts.Action.ABILITY1, Vector2i(3, 2))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	var expect := Consts.HUNTER_HP - Consts.ONSLAUGHT_DMG - Consts.COLLISION_DMG
	_check(v.hp == expect, "натиск в стену: урон + столкновение %d [%d]" % [expect, v.hp])
	_check(v.cell == Vector2i(3, 2), "натиск в стену: жертва не сдвинулась")
	_check(c.cell == Vector2i(3, 3), "натиск в стену: продвижения нет — клетка занята")


func test_spikes_hits_diagonal_neighbors() -> void:
	# Из (3,3) по 4 диагонально-СОСЕДНИМ клеткам; бьёт и врага, и союзника (как Вспышка)
	var s := _fresh()
	_arm(s, 2, Vector2i(3, 3), Consts.Skill.SPIKES)         # A crystal
	var foe := _place(s, 3, Vector2i(4, 4))                 # B hunter — диагональ (+1,+1)
	var ally := _place(s, 1, Vector2i(2, 2))                # A fairy — диагональ (-1,-1)
	var oa := _slots()
	oa[0] = Order.make(2, Consts.Action.ABILITY1)           # без цели
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(foe.hp == Consts.HUNTER_HP - Consts.SPIKES_DMG,
		"шипы: враг на диагонали получил урон [%d]" % foe.hp)
	_check(ally.hp == Consts.FAIRY_HP - Consts.SPIKES_DMG,
		"шипы: союзник на диагонали тоже получил урон [%d]" % ally.hp)


func test_spikes_ignore_distant_diagonal() -> void:
	# Шипы бьют только СОСЕДНЮЮ диагональ: юнит на (5,5) — за радиусом — не задет
	var s := _fresh()
	_arm(s, 2, Vector2i(3, 3), Consts.Skill.SPIKES)
	var far := _place(s, 3, Vector2i(5, 5))                 # диагональ, но дистанция 2
	var oa := _slots()
	oa[0] = Order.make(2, Consts.Action.ABILITY1)
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(far.hp == Consts.HUNTER_HP, "шипы: дальняя диагональ не задета [%d]" % far.hp)


func test_hardening_reduces_damage() -> void:
	# Затвердение срезает входящий урон на HARDENING_REDUCTION (удар 3 -> 1)
	var s := _fresh()
	var c := _arm(s, 5, Vector2i(3, 3), Consts.Skill.HARDENING)   # B crystal затвердевает
	c.mana = Consts.HARDENING_MANA
	_place(s, 2, Vector2i(3, 4))                                  # A crystal бьёт в упор (урон 3)
	var oa := _slots()
	oa[1] = Order.make(2, Consts.Action.ATTACK, Vector2i(3, 3))   # удар после затвердения
	var ob := _slots()
	ob[0] = Order.make(5, Consts.Action.ABILITY1)                # затвердение (слот 1)
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	var expect := Consts.CRYSTAL_HP - (Consts.CRYSTAL_ATK_DMG - Consts.HARDENING_REDUCTION)
	_check(c.hp == expect, "затвердение: урон срезан на %d, HP %d [%d]" % [Consts.HARDENING_REDUCTION, expect, c.hp])


func test_hardening_absorbs_small_hit() -> void:
	# Урон <= HARDENING_REDUCTION поглощается полностью (удар Феи 2 -> 0)
	var s := _fresh()
	var c := _arm(s, 5, Vector2i(3, 3), Consts.Skill.HARDENING)   # B crystal
	c.mana = Consts.HARDENING_MANA
	_place(s, 1, Vector2i(3, 4))                                  # A fairy бьёт (урон 2)
	var oa := _slots()
	oa[1] = Order.make(1, Consts.Action.ATTACK, Vector2i(3, 3))
	var ob := _slots()
	ob[0] = Order.make(5, Consts.Action.ABILITY1)
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(c.hp == Consts.CRYSTAL_HP, "затвердение: слабый удар (%d) поглощён [%d]" % [Consts.FAIRY_ATK_DMG, c.hp])


func test_shards_retaliate_on_attacker() -> void:
	# Осколки: атакующий враг получает ответку в тот же раунд
	var s := _fresh()
	var c := _arm(s, 5, Vector2i(3, 3), Consts.Skill.SHARDS)      # B crystal со шипами-осколками
	c.mana = Consts.SHARDS_MANA
	var atk := _place(s, 2, Vector2i(3, 4), 10)                   # A crystal, HP 10
	var ob := _slots()
	ob[0] = Order.make(5, Consts.Action.ABILITY1)                # осколки (слот 1)
	var oa := _slots()
	oa[1] = Order.make(2, Consts.Action.ATTACK, Vector2i(3, 3))  # A бьёт кристалла (слот 2)
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(c.hp == Consts.CRYSTAL_HP - Consts.CRYSTAL_ATK_DMG, "осколки: жертва всё равно получила удар [%d]" % c.hp)
	_check(atk.hp == 10 - Consts.SHARDS_DMG, "осколки: атакующий получил ответку [%d]" % atk.hp)


func test_overload_spends_all_mana() -> void:
	# Перегрузка: 3 маны -> 6 урона соседу, мана обнуляется
	var s := _fresh()
	var c := _arm(s, 2, Vector2i(3, 4), Consts.Skill.OVERLOAD)   # A crystal
	c.mana = 3
	var v := _place(s, 3, Vector2i(3, 3), 12)                    # B hunter сосед
	var oa := _slots()
	oa[0] = Order.make(2, Consts.Action.ABILITY1, Vector2i(3, 3))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(v.hp == 12 - 3 * Consts.OVERLOAD_DMG_PER_MANA, "перегрузка: 3 маны -> %d урона [%d]" % [3 * Consts.OVERLOAD_DMG_PER_MANA, v.hp])
	_check(c.mana == 0, "перегрузка: вся мана потрачена [%d]" % c.mana)


func test_swap_exchanges_positions() -> void:
	# Обмен местами: кристалл и соседний враг меняются клетками
	var s := _fresh()
	var c := _arm(s, 2, Vector2i(3, 4), Consts.Skill.SWAP)       # A crystal
	c.mana = Consts.SWAP_MANA
	var other := _place(s, 3, Vector2i(3, 3))                    # B hunter сосед (орто)
	var oa := _slots()
	oa[0] = Order.make(2, Consts.Action.ABILITY1, Vector2i(3, 3))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(c.cell == Vector2i(3, 3), "обмен: кристалл встал на клетку врага [%s]" % c.cell)
	_check(other.cell == Vector2i(3, 4), "обмен: враг встал на клетку кристалла [%s]" % other.cell)


# ---------------------------------------------------------------- новые скиллы Охотника

func test_precise_hits_at_exact_range() -> void:
	# Меткий выстрел: прямое попадание строго на дальности 2, сквозь блокера на линии
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.PRECISE)   # A hunter
	h.mana = Consts.PRECISE_MANA
	var blocker := _place(s, 1, Vector2i(3, 3))                 # A fairy на линии (снайп бы застрял)
	var v := _place(s, 3, Vector2i(3, 2), 10)                   # B hunter на дальности 2
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 2))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(v.hp == 10 - Consts.PRECISE_DMG, "меткий: попал на дальности 2 сквозь блокера [%d]" % v.hp)
	_check(blocker.hp == Consts.FAIRY_HP, "меткий: блокер на линии не задет [%d]" % blocker.hp)


func test_precise_fizzles_off_range() -> void:
	# Меткий выстрел строго дальность 2: цель в упор (дистанция 1) не поражается
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.PRECISE)
	h.mana = Consts.PRECISE_MANA
	var v := _place(s, 3, Vector2i(3, 3), 10)                   # дистанция 1
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 3))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(v.hp == 10, "меткий: цель в упор не поражена [%d]" % v.hp)


func test_hunt_mark_adds_flat_hunter_damage() -> void:
	# Охота началась: помеченная цель получает +HUNT_BONUS_DMG урона от атаки Охотника
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.HUNT_MARK)  # A hunter
	h.mana = Consts.HUNT_MANA
	var v := _place(s, 3, Vector2i(3, 2), 10)                    # B hunter на дальности 2
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 2))  # метка
	oa[1] = Order.make(0, Consts.Action.ATTACK, Vector2i(3, 2))    # выстрел по помеченному
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	var expect := 10 - (Consts.HUNTER_ATK_DMG + Consts.HUNT_BONUS_DMG)
	_check(v.hp == expect, "охота: усиленный урон Охотника, HP %d [%d]" % [expect, v.hp])
	_check(v.hunt_turns == Consts.HUNT_TURNS, "охота: метка взведена на %d ходов [%d]" % [Consts.HUNT_TURNS, v.hunt_turns])


func test_hunt_mark_expires_after_turns() -> void:
	# Метка держится через раунды и истекает через HUNT_TURNS ходов (как Кровавый след)
	var s := _fresh()
	var foe := _place(s, 3, Vector2i(3, 2), 10)
	foe.hunt_turns = Consts.HUNT_TURNS
	for i in Consts.HUNT_TURNS:
		s.begin_round()
	_check(foe.hunt_turns == 0, "охота: истекла после %d ходов [%d]" % [Consts.HUNT_TURNS, foe.hunt_turns])


func test_retreat_moves_when_enemy_adjacent() -> void:
	# Отступление: враг рядом → уходит по относительному пути
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.RETREAT)
	h.mana = Consts.RETREAT_MANA
	_place(s, 3, Vector2i(4, 4))                                 # B hunter — сосед справа
	var o := Order.new(0, Consts.Action.ABILITY1)
	o.path = [Vector2i(-1, 0), Vector2i(-1, 0)] as Array[Vector2i]  # влево дважды -> (1,4)
	var oa := _slots()
	oa[0] = o
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(h.cell == Vector2i(1, 4), "отступление: ушёл по пути на (1,4) [%s]" % h.cell)


func test_retreat_fizzles_without_enemy() -> void:
	# Отступление: рядом нет врага → физзл, герой на месте
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.RETREAT)
	h.mana = Consts.RETREAT_MANA
	_place(s, 3, Vector2i(6, 0))                                 # враг далеко
	var o := Order.new(0, Consts.Action.ABILITY1)
	o.path = [Vector2i(-1, 0)] as Array[Vector2i]
	var oa := _slots()
	oa[0] = o
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(h.cell == Vector2i(3, 4), "отступление: без врага рядом не сдвинулся [%s]" % h.cell)


func test_net_immobilizes_target() -> void:
	# Ловчая сеть: цель обездвижена, её ход в этом раунде отменяется
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.NET)
	h.mana = Consts.NET_MANA
	var foe := _place(s, 3, Vector2i(3, 2))                      # B hunter, дальность 2
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 2))    # сеть
	var ob := _slots()
	ob[0] = Order.make_move(3, [Vector2i(0, -1)] as Array[Vector2i])  # попытка хода
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(foe.immobilized, "сеть: цель обездвижена")
	_check(foe.cell == Vector2i(3, 2), "сеть: обездвиженный не сдвинулся [%s]" % foe.cell)


func test_deathcross_hits_first_enemy_per_line() -> void:
	# Крест смерти: первый ВРАГ на каждой из 4 прямых; союзник блокирует свою линию
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 3), Consts.Skill.DEATHCROSS)  # A hunter (клетки вокруг чисты от стен)
	h.mana = Consts.DEATHCROSS_MANA
	var e_up := _place(s, 3, Vector2i(3, 2), 10)                  # B hunter — линия вверх
	var e_right := _place(s, 4, Vector2i(4, 3), 12)             # B fairy — линия вправо
	var ally_left := _place(s, 1, Vector2i(2, 3))              # A fairy — линия влево (блокирует)
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1)                # без цели
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(e_up.hp == 10 - Consts.DEATHCROSS_DMG, "крест: враг вверх задет [%d]" % e_up.hp)
	_check(e_right.hp == 12 - Consts.DEATHCROSS_DMG, "крест: враг вправо задет [%d]" % e_right.hp)
	_check(ally_left.hp == Consts.FAIRY_HP, "крест: союзник (влево) не задет [%d]" % ally_left.hp)


# Собрать приказ Минного поля: относительные офсеты выбранных вручную клеток от кастера.
func _minefield_order(hero_id: int, origin: Vector2i, cells: Array) -> Order:
	var o := Order.new(hero_id, Consts.Action.ABILITY1)
	o.relative = true
	var offs: Array[Vector2i] = []
	for c in cells:
		offs.append(c - origin)
	o.path = offs
	o.offset = offs[0]
	o.target = cells[0]
	return o


func test_minefield_places_traps() -> void:
	# Минное поле: за один каст ставит мины в выбранных ВРУЧНУЮ клетках радиуса 2 от Охотника.
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.MINEFIELD)
	h.mana = Consts.MINEFIELD_MANA
	var cells := [Vector2i(3, 2), Vector2i(2, 4), Vector2i(4, 4)]   # 3 клетки в радиусе 2
	var oa := _slots()
	oa[0] = _minefield_order(0, h.cell, cells)
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(s.traps.size() == cells.size(),
		"минное поле: поставлено %d мин [%d]" % [cells.size(), s.traps.size()])


func test_minefield_damages_anyone() -> void:
	# Мина живёт до конца хода и бьёт ЛЮБОГО (врага и союзника) на MINEFIELD_DMG, без обездвиживания.
	# Охотник (3,4); вручную ставим мины на (2,3) и (4,3) (обе в радиусе 2).
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.MINEFIELD)   # A hunter кладёт поле
	h.mana = Consts.MINEFIELD_MANA
	var foe := _place(s, 5, Vector2i(2, 2))          # B crystal зайдёт на мину (2,3)
	var foe_hp0 := foe.hp
	var ally := _place(s, 1, Vector2i(4, 2))         # A fairy зайдёт на свою мину (4,3)
	var ally_hp0 := ally.hp
	var oa := _slots()
	oa[0] = _minefield_order(0, h.cell, [Vector2i(2, 3), Vector2i(4, 3)])  # ставим мины
	oa[1] = Order.make_move(1, [Vector2i(0, 1)] as Array[Vector2i])        # (4,2)->(4,3)
	var ob := _slots()
	ob[1] = Order.make_move(5, [Vector2i(0, 1)] as Array[Vector2i])        # (2,2)->(2,3)
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(foe.hp == foe_hp0 - Consts.MINEFIELD_DMG,
		"мина: враг получил %d урона [%d]" % [Consts.MINEFIELD_DMG, foe_hp0 - foe.hp])
	_check(not foe.immobilized, "мина: не обездвиживает (в отличие от капкана)")
	_check(ally.hp == ally_hp0 - Consts.MINEFIELD_DMG,
		"мина: бьёт и своего на %d урона [%d]" % [Consts.MINEFIELD_DMG, ally_hp0 - ally.hp])


func test_validator_minefield_cells() -> void:
	# Серверная санитизация приказа Минного поля: список клеток в o.path (1..3, радиус 2, различны).
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.MINEFIELD)
	h.mana = Consts.MINEFIELD_MANA
	var ok := _minefield_order(0, h.cell, [Vector2i(3, 2), Vector2i(2, 4), Vector2i(4, 4)])
	_check(not _san1(s, ok).is_empty(), "валидатор: 3 мины в радиусе 2 приняты")
	var many := _minefield_order(0, h.cell, [Vector2i(3, 2), Vector2i(2, 4), Vector2i(4, 4), Vector2i(3, 3)])
	_check(_san1(s, many).is_empty(), "валидатор: >%d мин отклонено" % Consts.MINEFIELD_COUNT)
	var far := _minefield_order(0, h.cell, [Vector2i(3, 1)])   # офсет (0,-3), манхэттен 3 > радиуса 2
	_check(_san1(s, far).is_empty(), "валидатор: мина вне радиуса 2 отклонена")
	var dup := _minefield_order(0, h.cell, [Vector2i(2, 4), Vector2i(2, 4)])
	_check(_san1(s, dup).is_empty(), "валидатор: две мины в одну клетку отклонены")


func test_bleed_marks_and_ticks_per_action() -> void:
	# Кровавый след: метка на враге в радиусе 2; ход на 2 клетки = ОДНО действие = ОДИН тик
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.BLEED)   # A hunter
	h.mana = Consts.BLEED_MANA
	var foe := _place(s, 3, Vector2i(3, 2), 10)               # B hunter на дальности 2
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 2))       # метка
	var ob := _slots()
	ob[1] = Order.make_move(3, [Vector2i(-1, 0), Vector2i(-1, 0)] as Array[Vector2i])  # ход на 2 клетки
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(foe.bleed_turns == Consts.BLEED_TURNS, "кровавый след: метка на %d хода [%d]" % [Consts.BLEED_TURNS, foe.bleed_turns])
	_check(foe.cell == Vector2i(1, 2), "кровавый след: цель переместилась [%s]" % foe.cell)
	_check(foe.hp == 10 - Consts.BLEED_DMG, "кровавый след: ход на 2 клетки -> 1 тик, HP %d [%d]" % [10 - Consts.BLEED_DMG, foe.hp])


func test_bleed_ticks_once_per_move_action() -> void:
	# Два отдельных хода-действия за раунд -> два тика (подтверждает «за действие», а не за клетку)
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.BLEED)
	h.mana = Consts.BLEED_MANA
	var foe := _place(s, 3, Vector2i(3, 2), 10)
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 2))       # метка (слот 0)
	var ob := _slots()
	ob[0] = Order.make_move(3, [Vector2i(-1, 0)] as Array[Vector2i])    # действие 1
	ob[1] = Order.make_move(3, [Vector2i(-1, 0)] as Array[Vector2i])    # действие 2
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(foe.cell == Vector2i(1, 2), "кровавый след: 2 хода -> сдвинулся на 2 [%s]" % foe.cell)
	_check(foe.hp == 10 - 2 * Consts.BLEED_DMG, "кровавый след: 2 действия -> 2 тика, HP %d [%d]" % [10 - 2 * Consts.BLEED_DMG, foe.hp])


func test_bleed_ticks_on_swap() -> void:
	# Обмен местами — тоже перемещение: свопнутый помеченный юнит получает тик
	var s := _fresh()
	var c := _arm(s, 2, Vector2i(3, 4), Consts.Skill.SWAP)    # A crystal
	c.mana = Consts.SWAP_MANA
	var foe := _place(s, 3, Vector2i(3, 3), 10)               # B hunter — сосед
	foe.bleed_turns = Consts.BLEED_TURNS                      # помечен заранее
	foe.bleed_owner = Consts.Player.A
	var oa := _slots()
	oa[0] = Order.make(2, Consts.Action.ABILITY1, Vector2i(3, 3))   # своп с врагом
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(foe.cell == Vector2i(3, 4), "своп: помеченный переместился [%s]" % foe.cell)
	_check(foe.hp == 10 - Consts.BLEED_DMG, "своп: кровавый след тикнул, HP %d [%d]" % [10 - Consts.BLEED_DMG, foe.hp])


func test_bleed_no_tick_without_move() -> void:
	# Без перемещения кровавый след урона не наносит (только сама метка)
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.BLEED)
	h.mana = Consts.BLEED_MANA
	var foe := _place(s, 3, Vector2i(3, 2), 10)
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 2))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(foe.hp == 10, "кровавый след: без движения урона нет [%d]" % foe.hp)


func test_bleed_expires_after_turns() -> void:
	# Эффект держится через раунды и истекает через BLEED_TURNS ходов
	var s := _fresh()
	var foe := _place(s, 3, Vector2i(3, 2), 10)
	foe.bleed_turns = Consts.BLEED_TURNS
	foe.bleed_owner = Consts.Player.A
	for i in Consts.BLEED_TURNS:
		s.begin_round()
	_check(foe.bleed_turns == 0, "кровавый след: истёк после %d ходов [%d]" % [Consts.BLEED_TURNS, foe.bleed_turns])
	_check(foe.bleed_owner == -1, "кровавый след: владелец сброшен по истечении")


# ---------------------------------------------------------------- новые скиллы Феи

func test_spark_hits_target() -> void:
	# Искра: SPARK_DMG урона цели на дальности до SPARK_RANGE
	var s := _fresh()
	var f := _arm(s, 1, Vector2i(3, 4), Consts.Skill.SPARK)   # A fairy
	f.mana = Consts.SPARK_MANA
	var v := _place(s, 3, Vector2i(3, 2), 10)                 # B hunter на дальности 2
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY1, Vector2i(3, 2))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(v.hp == 10 - Consts.SPARK_DMG, "искра: урон %d, HP %d [%d]" % [Consts.SPARK_DMG, 10 - Consts.SPARK_DMG, v.hp])


func test_lightning_hits_harder() -> void:
	# Молния: как искра, но LIGHTNING_DMG урона
	var s := _fresh()
	var f := _arm(s, 1, Vector2i(3, 4), Consts.Skill.LIGHTNING)   # A fairy
	f.mana = Consts.LIGHTNING_MANA
	var v := _place(s, 3, Vector2i(3, 2), 10)                     # B hunter на дальности 2
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY1, Vector2i(3, 2))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(v.hp == 10 - Consts.LIGHTNING_DMG, "молния: урон %d, HP %d [%d]" % [Consts.LIGHTNING_DMG, 10 - Consts.LIGHTNING_DMG, v.hp])


func test_disorient_reverses_direction() -> void:
	# Дезориентация: направленная атака цели разворачивается на этом ходу
	var s := _fresh()   # A первый
	var f := _arm(s, 1, Vector2i(2, 3), Consts.Skill.DISORIENT)   # A fairy
	f.mana = Consts.DISORIENT_MANA
	_place(s, 5, Vector2i(3, 3))                                  # B crystal (атакующий)
	var target := _place(s, 2, Vector2i(3, 4), 10)               # A crystal — под развёрнутой атакой
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY1, Vector2i(3, 3))   # дезориентация B crystal
	var ob := _slots()
	ob[1] = Order.make(5, Consts.Action.ATTACK, Vector2i(3, 2))     # B целит ВВЕРХ (3,2) -> развернётся вниз
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(target.hp == 10 - Consts.CRYSTAL_ATK_DMG, "дезориентация: удар развёрнут в (3,4) [%d]" % target.hp)


func test_manasteal_steals_and_damages() -> void:
	# Кража маны: MANASTEAL_DMG урона + похищение MANASTEAL_AMOUNT маны
	var s := _fresh()
	var f := _arm(s, 1, Vector2i(3, 4), Consts.Skill.MANASTEAL)   # A fairy
	f.mana = Consts.MANASTEAL_MANA
	var v := _place(s, 3, Vector2i(3, 3), 10)                     # B hunter сосед
	v.mana = 5
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY1, Vector2i(3, 3))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(v.hp == 10 - Consts.MANASTEAL_DMG, "кража: урон [%d]" % v.hp)
	_check(v.mana == 5 - Consts.MANASTEAL_AMOUNT, "кража: у цели -%d маны [%d]" % [Consts.MANASTEAL_AMOUNT, v.mana])
	_check(f.mana == Consts.MANASTEAL_AMOUNT, "кража: фее +%d маны [%d]" % [Consts.MANASTEAL_AMOUNT, f.mana])


func test_shackles_blocks_basic_attack() -> void:
	# Оковы: цель не может использовать базовую атаку
	var s := _fresh()
	var f := _arm(s, 1, Vector2i(4, 3), Consts.Skill.SHACKLES)   # A fairy
	f.mana = Consts.SHACKLES_MANA
	var c := _place(s, 5, Vector2i(3, 3))                        # B crystal
	var target := _place(s, 2, Vector2i(3, 4), 10)             # A crystal — цель атаки
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY1, Vector2i(3, 3))   # оковы
	var ob := _slots()
	ob[1] = Order.make(5, Consts.Action.ATTACK, Vector2i(3, 4))     # попытка атаки
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(c.no_attack_turns == Consts.SHACKLES_TURNS, "оковы: метка на %d хода [%d]" % [Consts.SHACKLES_TURNS, c.no_attack_turns])
	_check(target.hp == 10, "оковы: базовая атака заблокирована, цель цела [%d]" % target.hp)


func test_slow_reduces_move_range() -> void:
	# Замедление: дальность хода снижена на SLOW_MOVE_PENALTY (ход 2 -> 1)
	var s := _fresh()
	var f := _arm(s, 1, Vector2i(3, 4), Consts.Skill.SLOW)   # A fairy
	f.mana = Consts.SLOW_MANA
	var v := _place(s, 5, Vector2i(3, 2))                    # B crystal, дальность 2
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY1, Vector2i(3, 2))    # замедление
	var ob := _slots()
	ob[1] = Order.make_move(5, [Vector2i(-1, 0), Vector2i(-1, 0)] as Array[Vector2i])  # 2 шага влево
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(v.slow_turns == Consts.SLOW_TURNS, "замедление: метка поставлена")
	_check(v.cell == Vector2i(2, 2), "замедление: прошёл только 1 клетку [%s]" % v.cell)


func test_teleport_moves_self() -> void:
	# Телепорт: фея переносится на свободную клетку в радиусе 2
	var s := _fresh()
	var f := _arm(s, 1, Vector2i(3, 4), Consts.Skill.TELEPORT)   # A fairy
	f.mana = Consts.TELEPORT_MANA
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY1, Vector2i(4, 3))   # дистанция 2 (диагональ)
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(f.cell == Vector2i(4, 3), "телепорт: фея на (4,3) [%s]" % f.cell)


func test_teleport_blocked_when_occupied() -> void:
	# Телепорт на занятую клетку физзлит
	var s := _fresh()
	var f := _arm(s, 1, Vector2i(3, 4), Consts.Skill.TELEPORT)
	f.mana = Consts.TELEPORT_MANA
	_place(s, 3, Vector2i(4, 3))   # занято врагом
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY1, Vector2i(4, 3))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(f.cell == Vector2i(3, 4), "телепорт: на занятую клетку не сработал [%s]" % f.cell)


func test_revive_raises_fallen_ally() -> void:
	# Возрождение: могила ВДАЛИ от феи (радиус не ограничен) поднимается на полном HP рядом с могилой
	var s := _fresh()
	var f := _arm(s, 1, Vector2i(5, 4), Consts.Skill.REVIVE)   # A fairy — далеко
	f.mana = Consts.REVIVE_MANA
	var dead := _place(s, 2, Vector2i(1, 4))                   # A crystal — могила в 4 клетках
	dead.alive = false
	dead.hp = 0
	dead.dead_timer = Consts.RESPAWN_DELAY
	dead.death_cell = Vector2i(1, 4)
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY1, Vector2i(1, 4))   # цель — далёкая могила
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(dead.alive, "возрождение: союзник ожил (могила вдали)")
	_check(dead.hp == dead.max_hp, "возрождение: полный HP [%d/%d]" % [dead.hp, dead.max_hp])
	_check(dead.cell == Vector2i(2, 4), "возрождение: поднят в соседней с могилой клетке (2,4) [%s]" % dead.cell)


# ---------------------------------------------------------------- пассивки

func test_sniper_boosts_basic_attack_when_still() -> void:
	# Снайпер: не двигался в прошлом раунде -> +SNIPER_ATK_BONUS к урону; двигался -> обычный урон
	var s := _fresh()
	var h := _place(s, 0, Vector2i(3, 4))
	h.skills = [Consts.Skill.SNIPER, Consts.Skill.TRAP, Consts.Skill.SNIPE]
	h.moved_last_round = false
	var v := _place(s, 3, Vector2i(3, 2), 30)   # враг на дальности 2
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ATTACK, Vector2i(3, 2))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(v.hp == 30 - (Consts.HUNTER_ATK_DMG + Consts.SNIPER_ATK_BONUS),
		"снайпер: не двигался -> +%d к урону [%d]" % [Consts.SNIPER_ATK_BONUS, v.hp])
	# теперь двигался в прошлом раунде — бонуса нет
	var s2 := _fresh()
	var h2 := _place(s2, 0, Vector2i(3, 4))
	h2.skills = [Consts.Skill.SNIPER, Consts.Skill.TRAP, Consts.Skill.SNIPE]
	h2.moved_last_round = true
	var v2 := _place(s2, 3, Vector2i(3, 2), 30)
	var ob := _slots()
	ob[0] = Order.make(0, Consts.Action.ATTACK, Vector2i(3, 2))
	Resolver.new().resolve(s2, ob, _slots(), Consts.Player.A)
	_check(v2.hp == 30 - Consts.HUNTER_ATK_DMG, "снайпер: двигался -> без бонуса [%d]" % v2.hp)
	# дальность: не двигался -> дальний выстрел разрешён валидатором; двигался -> отклонён
	var s3 := _fresh()
	var h3 := _place(s3, 0, Vector2i(0, 4))
	h3.skills = [Consts.Skill.SNIPER, Consts.Skill.TRAP, Consts.Skill.SNIPE]
	var far := _slots()
	far[0] = Order.make(0, Consts.Action.ATTACK, Vector2i(6, 4))   # дальность 6
	h3.moved_last_round = false
	_check(not OrderValidator.sanitize(s3, far, Consts.Player.A)[0].is_empty(),
		"снайпер: не двигался -> дальний выстрел разрешён")
	h3.moved_last_round = true
	_check(OrderValidator.sanitize(s3, far, Consts.Player.A)[0].is_empty(),
		"снайпер: двигался -> дальний выстрел отклонён")


func test_cold_blood_mana_on_kill() -> void:
	# Хладнокровие: убийца получает COLD_BLOOD_MANA маны
	var s := _fresh()
	var h := _place(s, 0, Vector2i(3, 4))
	h.skills = [Consts.Skill.COLD_BLOOD, Consts.Skill.TRAP, Consts.Skill.SNIPE]
	h.mana = 0
	var v := _place(s, 3, Vector2i(3, 2), 1)   # враг на дальности 2, 1 HP
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ATTACK, Vector2i(3, 2))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(not v.alive, "хладнокровие: враг убит")
	_check(h.mana == Consts.COLD_BLOOD_MANA, "хладнокровие: +%d маны за килл [%d]" % [Consts.COLD_BLOOD_MANA, h.mana])


func test_blessing_heals_allies_in_radius() -> void:
	# Благословение: в начале раунда +BLESSING_HEAL HP союзникам в радиусе 1; себя и дальних — нет
	var s := _fresh()
	var f := _place(s, 1, Vector2i(3, 3))
	f.skills = [Consts.Skill.BLESSING, Consts.Skill.CANCEL, Consts.Skill.HEAL]
	f.hp = f.max_hp - 2
	var ally := _place(s, 2, Vector2i(3, 4), 5)   # A crystal — сосед
	var far := _place(s, 0, Vector2i(6, 6), 5)     # A hunter — далеко
	s.begin_round()
	_check(ally.hp == 5 + Consts.BLESSING_HEAL, "благословение: сосед-союзник +%d [%d]" % [Consts.BLESSING_HEAL, ally.hp])
	_check(f.hp == f.max_hp - 2, "благословение: сама Фея НЕ лечится [%d]" % f.hp)
	_check(far.hp == 5, "благословение: дальний союзник не лечится [%d]" % far.hp)


func test_lightness_move_range_3() -> void:
	# Лёгкость: дальность хода = 3
	var s := _fresh()
	var f := _place(s, 1, Vector2i(0, 6))
	f.skills = [Consts.Skill.LIGHTNESS, Consts.Skill.CANCEL, Consts.Skill.HEAL]
	_check(f.move_range() == Consts.LIGHTNESS_MOVE_RANGE, "лёгкость: move_range = %d [%d]" % [Consts.LIGHTNESS_MOVE_RANGE, f.move_range()])
	var oa := _slots()
	oa[0] = Order.make_move(1, [Vector2i(0, -1), Vector2i(0, -1), Vector2i(0, -1)] as Array[Vector2i])
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(f.cell == Vector2i(0, 3), "лёгкость: прошёл 3 клетки [%s]" % f.cell)


func test_lightness_move_path_to_control_point() -> void:
	# Регресс: Фея с «Лёгкостью» (дальность 3) идёт со старта (3,6) на ближайшую достижимую
	# победную точку (4,4) в обход стены (3,5). Путь ОБЯЗАН находиться той же дальностью, что и
	# подсветка (move_range()=3). Раньше _commit искал путь дефолтной MOVE_RANGE=2 → пустой ход.
	var s := _fresh()
	var f := _place(s, 1, Vector2i(3, 6))   # A fairy на старте
	f.skills = [Consts.Skill.LIGHTNESS, Consts.Skill.CANCEL, Consts.Skill.HEAL]
	var cp := Vector2i(4, 4)
	var cands := Targeting.candidates(s, f, Consts.Action.MOVE, f.cell)
	_check(cp in cands, "лёгкость: победная точка (4,4) подсвечена достижимой")
	# Корень бага: дальностью 2 путь к (4,4) не находится...
	_check(not Targeting.move_paths(s, f.cell, f.id).has(cp),
		"лёгкость: дальностью 2 путь к (4,4) отсутствует (был баг)")
	# ...а дальностью move_range()=3 путь есть, и это 3 шага в обход стены.
	var paths := Targeting.move_paths(s, f.cell, f.id, {}, f.move_range())
	_check(paths.has(cp) and paths[cp].size() == 3,
		"лёгкость: дальностью 3 путь к (4,4) есть, 3 шага [%s]" % [paths.get(cp, [])])


func test_drag_step_traces_manual_path() -> void:
	# Ручная прокладка перетаскиванием: пошаговое наращивание, откат, сброс, границы.
	var s := _fresh()
	var f := _place(s, 1, Vector2i(3, 6))
	f.skills = [Consts.Skill.LIGHTNESS, Consts.Skill.CANCEL, Consts.Skill.HEAL]
	var mr: int = f.move_range()   # 3
	var occ := Targeting.build_occupancy(s)
	var org := Vector2i(3, 6)
	var p: Array = []
	p = Targeting.drag_step(s, org, f.id, occ, mr, p, Vector2i(4, 6))
	_check(p == [Vector2i(4, 6)], "drag: шаг на соседа [%s]" % [p])
	p = Targeting.drag_step(s, org, f.id, occ, mr, p, Vector2i(4, 5))
	p = Targeting.drag_step(s, org, f.id, occ, mr, p, Vector2i(4, 4))
	_check(p == [Vector2i(4, 6), Vector2i(4, 5), Vector2i(4, 4)], "drag: маршрут в 3 шага [%s]" % [p])
	_check(Targeting.drag_step(s, org, f.id, occ, mr, p, Vector2i(4, 3)) == p, "drag: превышение дальности игнорируется")
	_check(Targeting.drag_step(s, org, f.id, occ, mr, p, Vector2i(4, 5)) == [Vector2i(4, 6), Vector2i(4, 5)], "drag: откат по клетке пути")
	_check(Targeting.drag_step(s, org, f.id, occ, mr, p, org) == [], "drag: возврат на старт очищает маршрут")
	_check(Targeting.drag_step(s, org, f.id, occ, mr, [], Vector2i(4, 5)) == [], "drag: несоседняя клетка игнорируется")
	_check(Targeting.drag_step(s, org, f.id, occ, mr, [], Vector2i(3, 5)) == [], "drag: стена (3,5) не добавляется")
	_place(s, 3, Vector2i(4, 6))   # B hunter занимает (4,6)
	var occ2 := Targeting.build_occupancy(s)
	_check(Targeting.drag_step(s, org, f.id, occ2, mr, [], Vector2i(4, 6)) == [], "drag: занятая клетка не добавляется")


func test_drag_flow_writes_move_order() -> void:
	# Сквозной прогон ручной прокладки через реальные BoardView+PlanningPanel: перетаскивание
	# феи A id1 (3,6) → (4,6) → (4,5) записывает ход с этим точным путём в активный слот.
	var s := _fresh()
	var bv := BoardView.new()
	root.add_child(bv)
	bv.setup(s.board)
	bv.set_view(Consts.Player.A)
	bv.render(s.snapshot())
	var pp := PlanningPanel.new()
	root.add_child(pp)
	pp.begin(s, Consts.Player.A, bv)
	pp._on_drag_started(Vector2i(3, 6))
	pp._on_drag_updated(Vector2i(4, 6))
	pp._on_drag_updated(Vector2i(4, 5))
	pp._on_drag_ended()
	_check(pp.slot_action[0] == Consts.Action.MOVE, "drag-flow: активный слот стал ходом")
	_check(pp.slot_hero[0] == 1, "drag-flow: ход феи id1 [%d]" % pp.slot_hero[0])
	_check(pp.slot_path[0] == [Vector2i(4, 6), Vector2i(4, 5)],
		"drag-flow: записан именно ручной путь [%s]" % [pp.slot_path[0]])
	pp.queue_free()
	bv.queue_free()


func test_grave_tooltip_shows_class() -> void:
	# Наведение на могилу даёт тултип с классом лежащего героя; над пустой клеткой — пусто.
	var s := _fresh()
	var u := s.get_unit(2)          # A Камнешип на (5,6)
	u.alive = false
	u.dead_timer = 2
	var bv := BoardView.new()
	root.add_child(bv)
	bv.setup(s.board)
	bv.set_view(Consts.Player.A)    # без флипа: экранная клетка == реальной
	bv.render(s.snapshot())
	var cell := u.cell
	var px := Vector2(cell.x * BoardView.CELL + BoardView.CELL * 0.5, cell.y * BoardView.CELL + BoardView.CELL * 0.5)
	_check(bv._get_tooltip(px) == "Могила: %s" % Consts.hero_name(u.hero_type),
		"могила: тултип показывает класс [%s]" % bv._get_tooltip(px))
	_check(bv._get_tooltip(Vector2(BoardView.CELL * 0.5, BoardView.CELL * 0.5)) == "",
		"могила: над клеткой без могилы тултипа нет")
	bv.queue_free()


func test_crystal_shell_reduces_first_hit_only() -> void:
	# Кристальный панцирь: первый урон за раунд -1, второй — полный
	var s := _fresh()
	var c := _place(s, 5, Vector2i(3, 4), 10)
	c.skills = [Consts.Skill.CRYSTAL_SHELL, Consts.Skill.JUMP, Consts.Skill.AMBUSH]
	_place(s, 2, Vector2i(4, 4))   # A crystal — удар 3 (срежется до 2)
	_place(s, 1, Vector2i(2, 4))   # A fairy — удар 2 (полный)
	var oa := _slots()
	oa[0] = Order.make(2, Consts.Action.ATTACK, Vector2i(3, 4))
	oa[1] = Order.make(1, Consts.Action.ATTACK, Vector2i(3, 4))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	var expect := 10 - (Consts.CRYSTAL_ATK_DMG - Consts.SHELL_REDUCTION) - Consts.FAIRY_ATK_DMG
	_check(c.hp == expect, "панцирь: только первый урон -1, HP %d [%d]" % [expect, c.hp])


func test_death_nova_hits_neighbors() -> void:
	# Осколки (пассив): при смерти DEATH_NOVA_DMG всем соседям
	var s := _fresh()
	var c := _place(s, 5, Vector2i(3, 3), 2)
	c.skills = [Consts.Skill.DEATH_NOVA, Consts.Skill.JUMP, Consts.Skill.AMBUSH]
	var atk := _place(s, 2, Vector2i(3, 4), 20)   # A crystal, добьёт c (и сам сосед)
	var bystander := _place(s, 1, Vector2i(2, 3), 20)   # A fairy — сосед c
	var oa := _slots()
	oa[0] = Order.make(2, Consts.Action.ATTACK, Vector2i(3, 3))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(not c.alive, "осколки-пассив: кристалл убит")
	_check(atk.hp == 20 - Consts.DEATH_NOVA_DMG, "осколки-пассив: сосед-атакующий задет [%d]" % atk.hp)
	_check(bystander.hp == 20 - Consts.DEATH_NOVA_DMG, "осколки-пассив: сосед задет [%d]" % bystander.hp)


func test_passive_cannot_be_activated() -> void:
	# Пассивку нельзя активировать: приказ ABILITY на неё срезается валидатором
	var s := _fresh()
	var h := _place(s, 0, Vector2i(3, 4))
	h.skills = [Consts.Skill.SNIPER, Consts.Skill.TRAP, Consts.Skill.SHOTGUN]   # ABILITY1 = Снайпер (пассив)
	h.mana = 5
	var o := _slots()
	o[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 3))
	_check(OrderValidator.sanitize(s, o, Consts.Player.A)[0].is_empty(),
		"пассив: активация отклонена валидатором")


# ---------------------------------------------------------------- нейтральные скиллы

func test_neutral_push_knocks_neighbor() -> void:
	var s := _fresh()
	var h := _place(s, 0, Vector2i(3, 4))
	h.skills = [Consts.Skill.PUSH, Consts.Skill.TRAP, Consts.Skill.SNIPE]
	h.mana = Consts.PUSH_MANA
	var v := _place(s, 3, Vector2i(3, 3))   # сосед сверху
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 3))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(v.cell == Vector2i(3, 2), "толкнуть: сосед отброшен на (3,2) [%s]" % v.cell)


func test_neutral_step_moves_two() -> void:
	var s := _fresh()
	var h := _place(s, 0, Vector2i(3, 4))
	h.skills = [Consts.Skill.STEP, Consts.Skill.TRAP, Consts.Skill.SNIPE]
	var o := Order.new(0, Consts.Action.ABILITY1)
	o.path = [Vector2i(-1, 0), Vector2i(-1, 0)] as Array[Vector2i]   # влево на 2
	var oa := _slots()
	oa[0] = o
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(h.cell == Vector2i(1, 4), "сходить: ход на 2 клетки до (1,4) [%s]" % h.cell)


func test_neutral_block_absorbs() -> void:
	var s := _fresh()
	var c := _place(s, 5, Vector2i(3, 3), 10)
	c.skills = [Consts.Skill.BLOCK, Consts.Skill.JUMP, Consts.Skill.AMBUSH]
	c.mana = Consts.BLOCK_MANA
	_place(s, 2, Vector2i(3, 4))   # A crystal — удар 3
	var ob := _slots(); ob[0] = Order.make(5, Consts.Action.ABILITY1)   # блок (слот 1)
	var oa := _slots(); oa[1] = Order.make(2, Consts.Action.ATTACK, Vector2i(3, 3))
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(c.hp == 10, "блок: урон поглощён [%d]" % c.hp)
	_check(c.block_amount == Consts.BLOCK_AMOUNT - Consts.CRYSTAL_ATK_DMG, "блок: остаток запаса [%d]" % c.block_amount)


func test_neutral_swap_ally() -> void:
	var s := _fresh()
	var h := _place(s, 0, Vector2i(3, 4))
	h.skills = [Consts.Skill.SWAP_ALLY, Consts.Skill.TRAP, Consts.Skill.SNIPE]
	h.mana = Consts.SWAP_ALLY_MANA
	var ally := _place(s, 1, Vector2i(3, 3))   # A fairy — сосед
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 3))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(h.cell == Vector2i(3, 3) and ally.cell == Vector2i(3, 4), "рокировка: поменялись местами")


func test_neutral_self_heal() -> void:
	var s := _fresh()
	var h := _place(s, 0, Vector2i(3, 4), 3)
	h.skills = [Consts.Skill.SELF_HEAL, Consts.Skill.TRAP, Consts.Skill.SNIPE]
	h.mana = Consts.SELF_HEAL_MANA
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1)
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(h.hp == 3 + Consts.SELF_HEAL_AMOUNT, "хил себе: +%d HP [%d]" % [Consts.SELF_HEAL_AMOUNT, h.hp])


func test_neutral_meditation() -> void:
	var s := _fresh()
	var h := _place(s, 0, Vector2i(3, 4))
	h.skills = [Consts.Skill.MEDITATION, Consts.Skill.TRAP, Consts.Skill.SNIPE]
	h.mana = 0
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1)
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(h.mana == Consts.MEDITATION_GAIN, "медитация: +%d маны [%d]" % [Consts.MEDITATION_GAIN, h.mana])


func test_neutral_allowed_on_any_hero() -> void:
	# Нейтрал годится в кит любого героя (санитайзер не режет)
	var kit := Loadout.sanitize_hero(Consts.HeroType.HUNTER,
		[Consts.Skill.PUSH, Consts.Skill.MEDITATION, Consts.Skill.TRAP])
	_check(kit == [Consts.Skill.PUSH, Consts.Skill.MEDITATION, Consts.Skill.TRAP],
		"нейтрал: принят в кит Охотника [%s]" % str(kit))


func test_second_player_skips_last_slot() -> void:
	# Второй игрок раунда не действует в последнем слоте; первый — действует (чередование)
	var s := _fresh()   # раунд 1: первый — A
	var a := _place(s, 0, Vector2i(3, 4))   # A hunter (первый)
	var b := _place(s, 3, Vector2i(5, 4))   # B hunter (второй)
	var oa := _slots()
	oa[Consts.ORDER_SLOTS - 1] = Order.make_move(0, [Vector2i(0, -1)] as Array[Vector2i])  # A в послед. слоте
	var ob := _slots()
	ob[Consts.ORDER_SLOTS - 1] = Order.make_move(3, [Vector2i(0, 1)] as Array[Vector2i])   # B в послед. слоте
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(a.cell == Vector2i(3, 3), "первый: действие в последнем слоте выполнено [%s]" % a.cell)
	_check(b.cell == Vector2i(5, 4), "второй: действие в последнем слоте проигнорировано [%s]" % b.cell)


func test_validator_drops_second_player_last_slot() -> void:
	# Санитайзер срезает приказ второго игрока в последнем слоте
	var s := _fresh()   # раунд 1: первый — A, второй — B
	_place(s, 3, Vector2i(5, 4))
	var o := _slots()
	o[Consts.ORDER_SLOTS - 1] = Order.make_move(3, [Vector2i(0, 1)] as Array[Vector2i])
	var out := OrderValidator.sanitize(s, o, Consts.Player.B)
	_check(out[Consts.ORDER_SLOTS - 1].is_empty(), "валидатор: последний слот второго игрока срезан")
	# у первого игрока (A) тот же слот легален
	var oa := _slots()
	oa[Consts.ORDER_SLOTS - 1] = Order.make_move(0, [Vector2i(0, -1)] as Array[Vector2i])
	var outa := OrderValidator.sanitize(s, oa, Consts.Player.A)
	_check(not outa[Consts.ORDER_SLOTS - 1].is_empty(), "валидатор: последний слот первого игрока сохранён")


func test_reflexes_dodges_and_gains_mana() -> void:
	# B взводит рефлексы в слоте 1; в слоте 2 сосед бьёт в его клетку → отступ + мана + промах
	var s := _fresh()
	var a := _place(s, 2, Vector2i(3, 4))                     # A crystal — атакующий
	var b := _arm(s, 5, Vector2i(3, 3), Consts.Skill.REFLEXES)  # B crystal
	var oa := _slots()
	oa[1] = Order.make(2, Consts.Action.ATTACK, Vector2i(3, 3))
	var ob := _slots()
	ob[0] = Order.make(5, Consts.Action.ABILITY1)             # стойка, без цели
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(b.cell == Vector2i(3, 2), "рефлексы: отступил на (3,2) [%s]" % b.cell)
	_check(b.hp == Consts.CRYSTAL_HP, "рефлексы: удар прошёл мимо, HP цел [%d]" % b.hp)
	_check(b.mana == Consts.REFLEXES_MANA_GAIN, "рефлексы: +%d маны [%d]" % [Consts.REFLEXES_MANA_GAIN, b.mana])
	_check(a.cell == Vector2i(3, 4), "рефлексы: атакующий остался на месте")


func test_reflexes_blocked_when_cornered() -> void:
	# Отступать некуда (за спиной юнит) → стойка не тратится, удар проходит
	var s := _fresh()
	_place(s, 2, Vector2i(3, 4))                              # A crystal — атакующий
	var b := _arm(s, 5, Vector2i(3, 3), Consts.Skill.REFLEXES)
	_place(s, 1, Vector2i(3, 2))                              # A fairy перекрывает отступ
	var oa := _slots()
	oa[1] = Order.make(2, Consts.Action.ATTACK, Vector2i(3, 3))
	var ob := _slots()
	ob[0] = Order.make(5, Consts.Action.ABILITY1)
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	var expect := Consts.CRYSTAL_HP - Consts.CRYSTAL_ATK_DMG
	_check(b.cell == Vector2i(3, 3), "рефлексы в углу: юнит не сдвинулся")
	_check(b.hp == expect, "рефлексы в углу: удар прошёл, HP %d [%d]" % [expect, b.hp])
	_check(b.reflexes_armed, "рефлексы в углу: стойка не израсходована")


# ---------------------------------------------------------------- кит / коллекция

func test_skill_slot_follows_loadout() -> void:
	# ABILITY1 диспетчеризуется по КИТУ, а не по «первому скиллу героя»:
	# ставим Рывок в первый слот и ждём рывка, а не Прыжка.
	var s := _fresh()
	var c := _place(s, 2, Vector2i(3, 4))
	c.skills = [Consts.Skill.DASH, Consts.Skill.JUMP, Consts.Skill.AMBUSH]
	c.mana = Consts.DASH_MANA
	var oa := _slots()
	oa[0] = Order.make(2, Consts.Action.ABILITY1, Vector2i(3, 2))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(c.cell == Vector2i(3, 2), "кит: в ABILITY1 сработал Рывок, а не Прыжок [%s]" % c.cell)


func test_immobilize_blocks_movement_skills() -> void:
	# Обездвиженный Кристалл не может двигаться скиллами (Прыжок/Натиск) — иначе капкан бесполезен
	var s := _fresh()
	var c := _place(s, 2, Vector2i(3, 4))
	c.skills = [Consts.Skill.JUMP, Consts.Skill.ONSLAUGHT, Consts.Skill.AMBUSH]
	c.immobilized = true
	c.mana = 5
	var foe := _place(s, 3, Vector2i(3, 3))            # враг вплотную сверху
	# Прыжок через врага (ABILITY1) — должен физзлить, Кристалл не двигается
	var oa := _slots()
	oa[0] = Order.make(2, Consts.Action.ABILITY1, Vector2i(3, 3))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(c.cell == Vector2i(3, 4), "обездвижен: Прыжок не сдвинул Кристалл [%s]" % c.cell)
	_check(c.mana == 5, "обездвижен: физзл Прыжка не списал ману [%d]" % c.mana)
	_check(foe.hp == Consts.HUNTER_HP, "обездвижен: Прыжок не нанёс урона")
	# Натиск (ABILITY2) — тоже физзл (двигает кастера)
	var oa2 := _slots()
	oa2[0] = Order.make(2, Consts.Action.ABILITY2, Vector2i(3, 3))
	Resolver.new().resolve(s, oa2, _slots(), Consts.Player.A)
	_check(c.cell == Vector2i(3, 4) and foe.hp == Consts.HUNTER_HP,
		"обездвижен: Натиск физзлит (нет урона и продвижения)")


func test_loadout_sanitize() -> void:
	var def := HeroDefs.default_skills(Consts.HeroType.CRYSTAL)
	_check(Loadout.sanitize_hero(Consts.HeroType.CRYSTAL,
			[Consts.Skill.ONSLAUGHT, Consts.Skill.REFLEXES, Consts.Skill.DASH]).size() == 3,
		"кит: валидная тройка принята")
	_check(Loadout.sanitize_hero(Consts.HeroType.CRYSTAL,
			[Consts.Skill.JUMP, Consts.Skill.JUMP, Consts.Skill.DASH]) == def,
		"кит: дубликат скилла → дефолт")
	_check(Loadout.sanitize_hero(Consts.HeroType.CRYSTAL,
			[Consts.Skill.TRAP, Consts.Skill.JUMP, Consts.Skill.DASH]) == def,
		"кит: чужой скилл героя → дефолт")
	_check(Loadout.sanitize_hero(Consts.HeroType.CRYSTAL, [Consts.Skill.JUMP]) == def,
		"кит: неверное число скиллов → дефолт")
	_check(Loadout.sanitize_hero(Consts.HeroType.CRYSTAL, "мусор") == def,
		"кит: не-массив → дефолт")
	# сетевой отряд: мусорные слоты → дефолтные бойцы соответствующих позиций
	var team := Loadout.sanitize_team_net(["мусор", 5, null])
	_check(team.size() == Loadout.TEAM_SIZE, "отряд по сети: ровно %d бойца" % Loadout.TEAM_SIZE)
	_check(team[0].type == Consts.HeroType.HUNTER
			and team[0].skills == HeroDefs.default_skills(Consts.HeroType.HUNTER),
		"отряд по сети: мусор в слоте 0 → дефолтный Охотник")
	_check(team[2].type == Consts.HeroType.CRYSTAL and team[2].skills == def,
		"отряд по сети: мусор в слоте 2 → дефолтный Кристалкайнд")


func test_team_allows_duplicate_heroes() -> void:
	# Ключевая фича: можно взять нескольких одинаковых героев. Три Охотника — валидный отряд.
	var kit := HeroDefs.default_skills(Consts.HeroType.HUNTER)
	var team := [
		{"type": Consts.HeroType.HUNTER, "skills": kit},
		{"type": Consts.HeroType.HUNTER, "skills": kit},
		{"type": Consts.HeroType.HUNTER, "skills": kit},
	]
	var s := MatchState.new()
	s.setup(team, team)
	_check(s.get_unit(0).hero_type == Consts.HeroType.HUNTER
			and s.get_unit(1).hero_type == Consts.HeroType.HUNTER
			and s.get_unit(2).hero_type == Consts.HeroType.HUNTER,
		"отряд: три Охотника у игрока A")
	_check(s.get_unit(0).cell == Vector2i(1, 6) and s.get_unit(2).cell == Vector2i(5, 6),
		"отряд: дубликаты расставлены по своим клеткам")
	# переживает сетевую канонизацию (дубликат класса не «схлопывается»)
	var round_trip := Loadout.sanitize_team_net(Loadout.canon_team_net(team))
	_check(round_trip[0].type == Consts.HeroType.HUNTER and round_trip[1].type == Consts.HeroType.HUNTER
			and round_trip[2].type == Consts.HeroType.HUNTER,
		"отряд по сети: три Охотника сохранены")
