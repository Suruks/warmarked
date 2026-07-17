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
	test_shotgun_knockback_into_edge()
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
	test_snipe_not_fired_when_blocked_point_blank()
	test_basic_attack_not_fired_when_blocked_point_blank()
	test_knockdown_not_fired_when_blocked_point_blank()
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
	test_onslaught_into_wall_blocks_advance()
	test_spikes_hits_diagonal_neighbors()
	test_spikes_ignore_distant_diagonal()
	test_hardening_reduces_damage()
	test_hardening_absorbs_small_hit()
	test_shards_retaliate_on_attacker()
	test_overload_spends_all_mana()
	test_swap_exchanges_positions()
	test_precise_hits_at_exact_range()
	test_precise_fizzles_off_range()
	test_hunt_mark_adds_flat_hunter_damage()
	test_retreat_moves_when_enemy_adjacent()
	test_retreat_fizzles_without_enemy()
	test_net_immobilizes_target()
	test_deathcross_hits_first_enemy_per_line()
	test_minefield_places_traps()
	test_minefield_damages_anyone()
	test_validator_minefield_cells()
	test_bleed_marks_and_ticks_per_cell()
	test_bleed_ticks_per_cell_across_actions()
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
	test_sniper_no_bonus_on_first_round()
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
	test_layout_recompute_matches_original_at_baseline()
	test_layout_recompute_grows_cell_on_wider_screen()
	test_layout_recompute_grows_cell_when_only_width_expands()
	test_difficulty_sanitize_unlocked()
	test_difficulty_tier_unlock()
	test_difficulty_playable_gate()
	test_difficulty_personal_best()
	test_difficulty_apply_is_deterministic()
	test_settings_sanitize_net()
	test_settings_round_trip()
	test_mana_sequence_ok()
	test_meditation_unlocks_expensive_skill()
	test_meditation_mana_spent_by_resolver()
	test_stay_away_hits_and_pushes()
	test_stay_away_no_pingpong()
	test_caltrops_ticks_each_round()
	test_fast_reload_repeats_ability()
	test_power_surge_self_damage_and_mana()
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
	var b := _place(s, 5, Vector2i(2, 2))            # B crystal (полное HP)
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 2))   # капкан на (3,2)
	oa[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 2))   # снайп по (3,2): дистанция 2 — легально
	var ob := _slots()
	ob[0] = Order.make_move(5, [Vector2i(1, 0)] as Array[Vector2i]) # (2,2)->(3,2) входит в капкан
	var r := Resolver.new()
	r.resolve(s, oa, ob, Consts.Player.A)
	var expect := Consts.CRYSTAL_HP - Consts.TRAP_DMG - Consts.SNIPE_DMG
	_check(b.hp == expect, "капкан+снайп по обездвиженному: HP %d [%d]" % [expect, b.hp])
	_check(b.immobilized, "капкан выставил обездвиживание сразу")
	_check(b.cell == Vector2i(3, 2), "жертва на клетке капкана")


func test_snipe_slot_gate() -> void:
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4))
	var b := _place(s, 5, Vector2i(3, 6), 10)
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 6))  # снайп в слот 1 → физзл
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	_check(b.hp == 10, "гейт снайпа: слот 1 физзлит, урона нет [%d]" % b.hp)


func test_shotgun_knockback_into_edge() -> void:
	var s := _fresh()
	s.board.obstacles = {}                            # чистое поле для предсказуемости
	_place(s, 0, Vector2i(5, 5)).mana = Consts.SHOTGUN_MANA            # A hunter (дробь 3)
	var b := _place(s, 4, Vector2i(6, 6), 12)         # B fairy на диагонали у угла
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY3, Vector2i(6, 6))  # дробь по диагонали
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	# дробь + отброс в угол (7,7 вне поля) → упор в край, урона за столкновение нет
	var expect := 12 - Consts.SHOTGUN_DMG
	_check(b.hp == expect, "дробь+упор в край: HP %d [%d]" % [expect, b.hp])
	_check(b.cell == Vector2i(6, 6), "дробь+упор в край: жертва не сдвинулась [%s]" % b.cell)


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


func test_snipe_not_fired_when_blocked_point_blank() -> void:
	# Снайп (мин. дальность 2) не производится, если линию перекрыл юнит вплотную (дистанция 1,
	# меньше минимума умения) — а не «бьёт по перехватчику в упор». Мана не тратится.
	var s := _fresh()
	s.board.obstacles = {}
	var h := _place(s, 0, Vector2i(0, 4))          # A hunter
	h.mana = Consts.SNIPE_MANA
	_place(s, 1, Vector2i(0, 0))
	_place(s, 2, Vector2i(6, 6))
	var blocker := _place(s, 4, Vector2i(1, 4), 12)    # B fairy вплотную (дистанция 1)
	var target := _place(s, 5, Vector2i(4, 4), 10)     # B crystal — задуманная цель
	_place(s, 3, Vector2i(6, 0))
	var oa := _slots()
	oa[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(4, 4))  # снайп в (4,4)
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(blocker.hp == 12, "снайп в упор: перехватчик цел [%d]" % blocker.hp)
	_check(target.hp == 10, "снайп в упор: дальняя цель тоже цела [%d]" % target.hp)
	_check(h.mana == Consts.SNIPE_MANA, "снайп в упор: мана не потрачена [%d]" % h.mana)


func test_basic_attack_not_fired_when_blocked_point_blank() -> void:
	# Выстрел Охотника (мин. дальность 2) не бьёт по перехватчику вплотную (дистанция 1).
	var s := _fresh()
	s.board.obstacles = {}
	_place(s, 0, Vector2i(0, 4))                   # A hunter
	_place(s, 1, Vector2i(0, 0))
	_place(s, 2, Vector2i(6, 6))
	var blocker := _place(s, 4, Vector2i(1, 4), 12)    # B fairy вплотную
	var target := _place(s, 5, Vector2i(3, 4), 10)     # B crystal — задуманная цель (дальность 3)
	_place(s, 3, Vector2i(6, 0))
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ATTACK, Vector2i(3, 4))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(blocker.hp == 12, "выстрел в упор: перехватчик цел [%d]" % blocker.hp)
	_check(target.hp == 10, "выстрел в упор: дальняя цель тоже цела [%d]" % target.hp)


func test_knockdown_not_fired_when_blocked_point_blank() -> void:
	# Сбить с ног (мин. дальность 2) не бьёт по перехватчику вплотную (дистанция 1).
	var s := _fresh()
	s.board.obstacles = {}
	var h := _place(s, 0, Vector2i(0, 4))
	h.skills = [Consts.Skill.KNOCKDOWN, Consts.Skill.TRAP, Consts.Skill.SNIPE]
	h.mana = Consts.KNOCKDOWN_MANA
	_place(s, 1, Vector2i(0, 0))
	_place(s, 2, Vector2i(6, 6))
	var blocker := _place(s, 4, Vector2i(1, 4), 12)
	var target := _place(s, 5, Vector2i(3, 4), 10)
	_place(s, 3, Vector2i(6, 0))
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 4))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(blocker.hp == 12, "сбить с ног в упор: перехватчик цел [%d]" % blocker.hp)
	_check(target.hp == 10, "сбить с ног в упор: дальняя цель тоже цела [%d]" % target.hp)
	_check(h.mana == Consts.KNOCKDOWN_MANA, "сбить с ног в упор: мана не потрачена [%d]" % h.mana)


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
	# Геометрию цели авторитетно проверяет OrderValidator._target_legal (его зовёт резолвер и
	# физзлит нелегальное). Проверяем ПРАВИЛО напрямую — sanitize геометрию уже не режет.
	var s := _fresh()
	var hunter := s.get_unit(0)
	hunter.skills = [Consts.Skill.TRAP, Consts.Skill.SNIPE, Consts.Skill.SHOTGUN]   # без «Снайпера» → строгие 2-3
	var fairy := s.get_unit(1)
	_check(OrderValidator._target_legal(hunter, Consts.Action.ATTACK, Vector2i(0, -3)),
		"геометрия: выстрел на 3 клетки — легален")
	_check(not OrderValidator._target_legal(hunter, Consts.Action.ATTACK, Vector2i(0, -1)),
		"геометрия: выстрел в упор (дистанция 1) — нелегален")
	_check(not OrderValidator._target_legal(hunter, Consts.Action.ATTACK, Vector2i(-1, -1)),
		"геометрия: выстрел по диагонали — нелегален")
	_check(not OrderValidator._target_legal(fairy, Consts.Action.ATTACK, Vector2i(4, 0)),
		"геометрия: ближний удар Феи через всю доску — нелегален")
	_check(OrderValidator._target_legal(fairy, Consts.Action.ATTACK, Vector2i(1, -1)),
		"геометрия: удар Феи по диагонали — легален")
	# Лечение — радиус 2 (ставим HEAL в ABILITY1)
	fairy.skills = [Consts.Skill.HEAL, Consts.Skill.CANCEL, Consts.Skill.FLASH]
	_check(not OrderValidator._target_legal(fairy, Consts.Action.ABILITY1, Vector2i(0, -4)),
		"геометрия: лечение через всю доску — нелегально")
	_check(OrderValidator._target_legal(fairy, Consts.Action.ABILITY1, Vector2i(0, -2)),
		"геометрия: лечение в радиусе 2 — легально")


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


func test_onslaught_into_wall_blocks_advance() -> void:
	# Жертва на (3,2), за ней стена (3,1): отброс невозможен → урона за упор нет, продвижения нет
	var s := _fresh()
	var c := _arm(s, 2, Vector2i(3, 3), Consts.Skill.ONSLAUGHT)
	var v := _place(s, 3, Vector2i(3, 2))
	var oa := _slots()
	oa[0] = Order.make(2, Consts.Action.ABILITY1, Vector2i(3, 2))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	var expect := Consts.HUNTER_HP - Consts.ONSLAUGHT_DMG
	_check(v.hp == expect, "натиск в стену: только урон натиска %d [%d]" % [expect, v.hp])
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
	# Охота началась (по прямой): помеченная цель получает +HUNT_BONUS_DMG урона от атаки Охотника
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.HUNT_MARK)  # A hunter
	h.mana = Consts.HUNT_MANA
	var v := _place(s, 3, Vector2i(3, 2), 10)                    # B hunter по прямой на дальности 2
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 2))  # метка
	oa[1] = Order.make(0, Consts.Action.ATTACK, Vector2i(3, 2))    # выстрел по помеченному
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	var expect := 10 - (Consts.HUNTER_ATK_DMG + Consts.HUNT_BONUS_DMG)
	_check(v.hp == expect, "охота: усиленный урон Охотника, HP %d [%d]" % [expect, v.hp])
	_check(v.hunt_turns == Consts.HUNT_TURNS, "охота: метка взведена на %d ходов [%d]" % [Consts.HUNT_TURNS, v.hunt_turns])


func test_hunt_mark_marks_first_on_line() -> void:
	# Охота бьёт по прямой: метит ПЕРВОГО врага на луче, дальний за ним не задет
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.HUNT_MARK)   # A hunter
	h.mana = Consts.HUNT_MANA
	var near := _place(s, 3, Vector2i(3, 3), 10)                  # ближний враг на линии
	var far := _place(s, 4, Vector2i(3, 2), 10)                   # дальний враг на той же линии
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 2))   # целим в дальнюю клетку
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(near.hunt_turns == Consts.HUNT_TURNS, "охота: помечен первый на линии [%d]" % near.hunt_turns)
	_check(far.hunt_turns == 0, "охота: дальний за первым не помечен [%d]" % far.hunt_turns)


func test_hunt_mark_fizzles_off_line() -> void:
	# Врага нет на прямой линии к цели — метка физзлит (никого не метит)
	var s := _fresh()
	var h := _arm(s, 0, Vector2i(3, 4), Consts.Skill.HUNT_MARK)   # A hunter
	h.mana = Consts.HUNT_MANA
	var off := _place(s, 3, Vector2i(5, 2), 10)                   # враг в стороне, не на луче x=3
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 2))   # прямая вверх, на линии пусто
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(off.hunt_turns == 0, "охота: враг вне линии не помечен [%d]" % off.hunt_turns)


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


func test_bleed_marks_and_ticks_per_cell() -> void:
	# Кровавый след: метка на враге в радиусе 2; ход на 2 клетки = ДВА тика (по клетке, не по действию)
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
	_check(foe.hp == 10 - 2 * Consts.BLEED_DMG, "кровавый след: ход на 2 клетки -> 2 тика, HP %d [%d]" % [10 - 2 * Consts.BLEED_DMG, foe.hp])


func test_bleed_ticks_per_cell_across_actions() -> void:
	# Два отдельных хода-действия по 1 клетке за раунд -> два тика (столько же клеток, столько тиков)
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
	_check(foe.hp == 10 - 2 * Consts.BLEED_DMG, "кровавый след: 2 клетки (в 2 действиях) -> 2 тика, HP %d [%d]" % [10 - 2 * Consts.BLEED_DMG, foe.hp])


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
	# дальность (правило геометрии): не двигался -> дальний выстрел легален; двигался -> нет
	var s3 := _fresh()
	var h3 := _place(s3, 0, Vector2i(0, 4))
	h3.skills = [Consts.Skill.SNIPER, Consts.Skill.TRAP, Consts.Skill.SNIPE]
	var far_off := Vector2i(6, 0)   # выстрел на 6 клеток по прямой
	h3.moved_last_round = false
	_check(OrderValidator._target_legal(h3, Consts.Action.ATTACK, far_off),
		"снайпер: не двигался -> дальний выстрел легален")
	h3.moved_last_round = true
	_check(not OrderValidator._target_legal(h3, Consts.Action.ATTACK, far_off),
		"снайпер: двигался -> дальний выстрел нелегален")


func test_sniper_no_bonus_on_first_round() -> void:
	# В 1-м раунде матча предыдущего раунда не было — «Снайпер» не должен давать бонус даже
	# на свежесозданном юните, который ещё физически никуда не ходил (moved_last_round=true по умолчанию).
	var s := _fresh()
	var h := _place(s, 0, Vector2i(0, 4))
	h.skills = [Consts.Skill.SNIPER, Consts.Skill.TRAP, Consts.Skill.SNIPE]
	var v := _place(s, 3, Vector2i(3, 4), 30)   # враг на дальности 3 (в обычном радиусе атаки)
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ATTACK, Vector2i(3, 4))
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(v.hp == 30 - Consts.HUNTER_ATK_DMG, "снайпер: 1-й раунд -> без бонуса урона [%d]" % v.hp)
	_check(not OrderValidator._target_legal(h, Consts.Action.ATTACK, Vector2i(6, 0)),
		"снайпер: 1-й раунд (moved_last_round) -> дальний выстрел нелегален")


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
	var px := Vector2(cell.x * bv.cell_size + bv.cell_size * 0.5, cell.y * bv.cell_size + bv.cell_size * 0.5)
	_check(bv._get_tooltip(px) == "Могила: %s" % Consts.hero_name(u.hero_type),
		"могила: тултип показывает класс [%s]" % bv._get_tooltip(px))
	_check(bv._get_tooltip(Vector2(bv.cell_size * 0.5, bv.cell_size * 0.5)) == "",
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


func test_layout_recompute_matches_original_at_baseline() -> void:
	# При исходном 540x1200 recompute() обязан воспроизвести старые фиксированные числа —
	# иначе обычные (не EXPAND) экраны получат другую раскладку, чем раньше.
	Layout.recompute(540.0, 1200.0)
	_check(is_equal_approx(Layout.cell_size, 76.0), "layout: клетка на базовом экране = 76 [%f]" % Layout.cell_size)
	_check(is_equal_approx(Layout.BOARD_PX, 532.0), "layout: BOARD_PX = 532 [%f]" % Layout.BOARD_PX)
	_check(is_equal_approx(Layout.SCREEN_W, 540.0), "layout: SCREEN_W = 540 [%f]" % Layout.SCREEN_W)
	_check(is_equal_approx(Layout.SCREEN_H, 1200.0), "layout: SCREEN_H = 1200 [%f]" % Layout.SCREEN_H)
	_check(is_equal_approx(Layout.PANEL_H, 461.0), "layout: PANEL_H = 461 [%f]" % Layout.PANEL_H)


func test_layout_recompute_grows_cell_on_wider_screen() -> void:
	# На экране шире и выше базового клетка доски растёт (поле «растягивается»), а не остаётся
	# приклеенной к исходным 76px — и лишняя высота отдаётся нижней панели (PANEL_H тоже растёт).
	Layout.recompute(700.0, 2000.0)
	_check(Layout.cell_size > 76.0, "layout: на широком экране клетка выросла [%f]" % Layout.cell_size)
	_check(is_equal_approx(Layout.SCREEN_W, 700.0), "layout: SCREEN_W подстроился под ширину [%f]" % Layout.SCREEN_W)
	_check(Layout.PANEL_H > 461.0, "layout: нижняя панель тоже выросла [%f]" % Layout.PANEL_H)
	# восстановить базовое состояние для остальных тестов (Layout — статический синглтон)
	Layout.recompute(540.0, 1200.0)


func test_layout_recompute_grows_cell_when_only_width_expands() -> void:
	# Регрессия на реальном баге: у типичного телефона экран ШИРЕ пропорции 540:1200, поэтому
	# EXPAND расширяет именно ширину канваса, а высота остаётся РОВНО 1200 (не растёт вообще) —
	# измерено на устройстве 1080x1929 -> canvas 671x1200. При старом MIN_PANEL_H=454 высотный
	# бюджет был расписан впритык под высоту 1200 при клетке 76 — клетка не росла, сколько бы
	# лишней ширины ни было. Теперь обязана вырасти заметно даже при неизменной высоте.
	Layout.recompute(671.0, 1200.0)
	_check(Layout.cell_size > 84.0, "layout: клетка выросла даже при неизменной высоте [%f]" % Layout.cell_size)
	_check(Layout.PANEL_H >= Layout.MIN_PANEL_H, "layout: панель не ушла ниже минимума [%f]" % Layout.PANEL_H)
	Layout.recompute(540.0, 1200.0)


func test_difficulty_sanitize_unlocked() -> void:
	_check(Difficulty.sanitize_unlocked(null) == Difficulty.TIER, "difficulty: не число -> TIER")
	_check(Difficulty.sanitize_unlocked("25") == Difficulty.TIER, "difficulty: строка (не число) -> TIER")
	_check(Difficulty.sanitize_unlocked(23) == 20, "difficulty: округление вниз до границы тира [23 -> 20]")
	_check(Difficulty.sanitize_unlocked(23.0) == 20, "difficulty: float санируется так же, как int")
	_check(Difficulty.sanitize_unlocked(0) == Difficulty.TIER, "difficulty: ниже минимума -> TIER")
	_check(Difficulty.sanitize_unlocked(-100) == Difficulty.TIER, "difficulty: отрицательное -> TIER")
	_check(Difficulty.sanitize_unlocked(9999) == Difficulty.MAX_LEVEL, "difficulty: выше максимума -> MAX_LEVEL")
	_check(Difficulty.sanitize_unlocked(Difficulty.MAX_LEVEL) == Difficulty.MAX_LEVEL,
		"difficulty: максимум остаётся максимумом")


# Прогресс считает СЕРВЕР по своей БД — чистой функцией, без статики клиента.
func test_difficulty_tier_unlock() -> void:
	var T := Difficulty.TIER
	# свежий аккаунт: открыты только 1..TIER
	_check(Difficulty.unlocked_after_win(T, 1) == T, "difficulty: победа ниже потолка не открывает новый блок")
	_check(Difficulty.unlocked_after_win(T, T) == T * 2, "difficulty: победа на потолке открывает следующий блок")
	_check(Difficulty.unlocked_after_win(T * 2, T * 2) == T * 3, "difficulty: следующий блок тоже открывается")

	_check(Difficulty.unlocked_after_win(Difficulty.MAX_LEVEL, Difficulty.MAX_LEVEL) == Difficulty.MAX_LEVEL,
		"difficulty: на максимуме больше открывать нечего")
	_check(Difficulty.unlocked_after_win(Difficulty.MAX_LEVEL - T, Difficulty.MAX_LEVEL - T) == Difficulty.MAX_LEVEL,
		"difficulty: последний блок доводит ровно до MAX_LEVEL")
	# победа ВЫШЕ потолка невозможна (сервер такой бой не начнёт), но и она не перескочит блок
	_check(Difficulty.unlocked_after_win(T, Difficulty.MAX_LEVEL) == T * 2,
		"difficulty: прогресс двигается ровно на один блок, каким бы ни был уровень победы")
	# прогресс из БД тоже внешние данные — санируется тем же правилом
	_check(Difficulty.unlocked_after_win("мусор", T) == T * 2, "difficulty: битый прогресс -> TIER, дальше как обычно")

	var saved_unlocked := Difficulty.unlocked
	var saved_level := Difficulty.level
	Difficulty.unlocked = T * 2
	Difficulty.set_level(999)
	_check(Difficulty.level == T * 2,
		"difficulty: set_level зажат текущим потолком unlocked, а не голым MAX_LEVEL")
	Difficulty.unlocked = saved_unlocked
	Difficulty.level = saved_level


# Гейт уровня — серверный: клиент может попросить любой, играть можно только открытое.
func test_difficulty_playable_gate() -> void:
	_check(Difficulty.playable(1, Difficulty.TIER), "difficulty: первый уровень открыт всегда")
	_check(Difficulty.playable(Difficulty.TIER, Difficulty.TIER), "difficulty: верхний открытый уровень играбелен")
	_check(not Difficulty.playable(Difficulty.TIER + 1, Difficulty.TIER),
		"difficulty: уровень выше прогресса не играбелен")
	_check(not Difficulty.playable(Difficulty.MAX_LEVEL, Difficulty.TIER),
		"difficulty: максимум на свежем аккаунте не играбелен")
	_check(Difficulty.playable(Difficulty.MAX_LEVEL, Difficulty.MAX_LEVEL),
		"difficulty: с полным прогрессом играбелен и максимум")
	_check(not Difficulty.playable(0, Difficulty.MAX_LEVEL), "difficulty: уровень ниже минимума не играбелен")
	_check(not Difficulty.playable(-5, Difficulty.MAX_LEVEL), "difficulty: отрицательный уровень не играбелен")
	# просьба «не числом» не должна ни пролезть, ни уронить сервер
	_check(not Difficulty.playable("50", Difficulty.MAX_LEVEL), "difficulty: уровень строкой не играбелен")
	_check(not Difficulty.playable(null, Difficulty.MAX_LEVEL), "difficulty: уровень null не играбелен")
	_check(not Difficulty.playable(3.0, Difficulty.MAX_LEVEL), "difficulty: уровень float не играбелен (только int)")


func test_difficulty_personal_best() -> void:
	var saved_best := Difficulty.best

	# set_best — приём серверного значения: аномалия не должна ронять экран лидерборда
	Difficulty.set_best(null)
	_check(Difficulty.best == 0, "difficulty: рекорд не число -> 0 (побед нет)")
	Difficulty.set_best("12")
	_check(Difficulty.best == 0, "difficulty: рекорд строкой -> 0")
	Difficulty.set_best(-7)
	_check(Difficulty.best == 0, "difficulty: отрицательный рекорд -> 0")
	Difficulty.set_best(9999)
	_check(Difficulty.best == Difficulty.MAX_LEVEL, "difficulty: рекорд выше максимума зажат в MAX_LEVEL")
	Difficulty.set_best(17.0)
	_check(Difficulty.best == 17, "difficulty: float-рекорд (после JSON) принимается как int")

	Difficulty.best = saved_best


# Сервер и клиент строят копию боя с ИИ независимо и обязаны получить ОДНОГО И ТОГО ЖЕ бота:
# усиления разыгрываются по seed, который сервер присылает клиенту (см. Net.ai_match_found_rpc).
# Разошлись бы усиления — разошёлся бы и лок-степ, причём незаметно.
func test_difficulty_apply_is_deterministic() -> void:
	var team_a := Loadout.default_team_net()
	var team_b := Loadout.default_team_net()
	var level := 30   # заведомо больше витка _CYCLE: задеты все 5 типов модификаторов

	var server := MatchState.new()
	server.setup(team_a, team_b, 0)
	Difficulty.apply(server, Consts.Player.B, level, 12345)

	var client := MatchState.new()
	client.setup(team_a, team_b, 0)
	Difficulty.apply(client, Consts.Player.B, level, 12345)

	_check(_bots_equal(server, client), "difficulty: тот же seed -> тот же бот у сервера и клиента")

	# ...а другой seed даёт другого бота (иначе seed ничего не решал бы и тест выше был бы пустым)
	var other := MatchState.new()
	other.setup(team_a, team_b, 0)
	Difficulty.apply(other, Consts.Player.B, level, 999)
	_check(not _bots_equal(server, other), "difficulty: другой seed -> другой набор усилений бота")

	# уровень 1 — игра без модификаторов, seed ни на что не влияет
	var plain := MatchState.new()
	plain.setup(team_a, team_b, 0)
	Difficulty.apply(plain, Consts.Player.B, 1, 777)
	var untouched := MatchState.new()
	untouched.setup(team_a, team_b, 0)
	_check(_bots_equal(plain, untouched), "difficulty: уровень 1 не даёт боту ничего")

	# усиления достаются ТОЛЬКО боту — команда игрока не тронута ни на каком уровне
	_check(_team_equal(server, untouched, Consts.Player.A), "difficulty: команда игрока не усилена")


# Всё, что модификаторы могут изменить у бота: HP/мана (в т.ч. перманентные бонусы),
# киты (бонусная 4-я способность), бонусы урона и скидки маны.
func _bots_equal(a: MatchState, b: MatchState) -> bool:
	return _team_equal(a, b, Consts.Player.B)


func _team_equal(a: MatchState, b: MatchState, player: int) -> bool:
	var ua := a.units_of(player)
	var ub := b.units_of(player)
	if ua.size() != ub.size():
		return false
	for i in ua.size():
		var x := ua[i]
		var y := ub[i]
		if x.max_hp != y.max_hp or x.hp != y.hp or x.mana != y.mana or x.start_mana_bonus != y.start_mana_bonus:
			return false
		if x.skills != y.skills or x.dmg_bonus != y.dmg_bonus or x.mana_discount != y.mana_discount:
			return false
	return true


# Настройки приходят от сервера и от клиента — оба внешние данные. Битое поле не должно ни
# ронять экран, ни включать втихую отладочный режим.
func test_settings_sanitize_net() -> void:
	var d := Settings.sanitize_net({"vol": 0.5, "imp": true})
	_check(d["vol"] == 0.5 and d["imp"] == true, "settings: валидный набор проходит как есть")

	# санитайзер всегда отдаёт ПОЛНЫЙ набор — вызывающему не нужно досанировать поля самому
	var empty := Settings.sanitize_net({})
	_check(empty["vol"] == Settings.VOLUME_DEFAULT and empty["imp"] == false,
		"settings: пустой набор -> дефолты обоих полей")
	_check(Settings.sanitize_net("не словарь") == empty, "settings: не-словарь -> дефолты")
	_check(Settings.sanitize_net(null) == empty, "settings: null -> дефолты")

	_check(Settings.sanitize_net({"vol": 5.0})["vol"] == 1.0, "settings: громкость выше 1 зажата")
	_check(Settings.sanitize_net({"vol": -3.0})["vol"] == 0.0, "settings: отрицательная громкость зажата в 0")
	_check(Settings.sanitize_net({"vol": 1})["vol"] == 1.0, "settings: громкость int (после JSON) принимается")
	_check(Settings.sanitize_net({"vol": "громко"})["vol"] == Settings.VOLUME_DEFAULT,
		"settings: громкость строкой -> дефолт")
	# отладочный флаг — только явный bool: «1»/«true» строкой его не включают
	_check(Settings.sanitize_net({"imp": 1})["imp"] == false, "settings: отладочный флаг числом -> выключен")
	_check(Settings.sanitize_net({"imp": "true"})["imp"] == false, "settings: отладочный флаг строкой -> выключен")


# Круг «изменил -> уехало на сервер -> вернулось при входе»: to_net/apply_net обязаны сходиться,
# иначе настройка молча терялась бы на перезаходе.
func test_settings_round_trip() -> void:
	var saved_vol := Settings.volume
	var saved_imp := Settings.allow_impossible_targets

	Settings.set_volume(0.25)
	Settings.allow_impossible_targets = true
	var packet := Settings.to_net()

	# другое устройство/сессия: состояние иное, вход его перезаписывает присланным
	Settings.set_volume(1.0)
	Settings.allow_impossible_targets = false
	Settings.apply_net(packet)
	_check(is_equal_approx(Settings.volume, 0.25), "settings: громкость вернулась с сервера [%f]" % Settings.volume)
	_check(Settings.allow_impossible_targets, "settings: отладочный флаг вернулся с сервера")

	# громкость применяется к звуку, а не только к полю — иначе «вернулась» была бы на бумаге
	var bus := AudioServer.get_bus_index("Master")
	_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(bus)), 0.25),
		"settings: громкость применена к мастер-шине [%f]" % db_to_linear(AudioServer.get_bus_volume_db(bus)))
	_check(not AudioServer.is_bus_mute(bus), "settings: ненулевая громкость шину не глушит")

	# ноль — это тишина (mute), а не «очень тихо»
	Settings.set_volume(0.0)
	_check(AudioServer.is_bus_mute(bus), "settings: нулевая громкость глушит шину")
	Settings.set_volume(0.7)
	_check(not AudioServer.is_bus_mute(bus), "settings: звук снова включается после нуля")

	Settings.set_volume(saved_vol)
	Settings.allow_impossible_targets = saved_imp


# Единая мана-модель (клиент и сервер зовут её же): бегущий банк тратит cost в слоте, прирост
# gain достаётся ПОЗДНИМ слотам. Ни разу в минус -> ок.
func test_mana_sequence_ok() -> void:
	# без прироста модель совпадает со «суммой костов» — как было раньше
	_check(OrderValidator.mana_sequence_ok([[2, 0], null, [2, 0], null], 4), "мана: косты 2+2 при старте 4 — ок")
	_check(not OrderValidator.mana_sequence_ok([[2, 0], null, [2, 0], null], 3), "мана: косты 2+2 при старте 3 — нет")
	# прирост в РАННЕМ слоте оплачивает поздний
	_check(OrderValidator.mana_sequence_ok([[0, 1], null, [4, 0], null], 3),
		"мана: медитация(+1) в слоте 0 оплачивает скилл 4 в слоте 2 при старте 3")
	# ...а в ПОЗДНЕМ — уже нет (мана тратится по порядку)
	_check(not OrderValidator.mana_sequence_ok([[4, 0], null, [0, 1], null], 3),
		"мана: прирост в позднем слоте не оплачивает ранний скилл")
	# прирост своему слоту не помогает: скилл кост 1 при 0 маны не проходит, даже если сам даёт +1
	_check(not OrderValidator.mana_sequence_ok([[1, 1]], 0), "мана: свой прирост своему косту не помогает")
	_check(OrderValidator.mana_sequence_ok([[0, 1]], 0), "мана: медитация (кост 0) кастуется при 0 маны")
	_check(OrderValidator.mana_sequence_ok([null, null, null, null], 0), "мана: нет действий -> ок")
	# цепочка из двух медитаций копит на дорогой скилл в третьем слоте
	_check(OrderValidator.mana_sequence_ok([[0, 1], [0, 1], [4, 0], null], 2),
		"мана: две медитации (+2) оплачивают скилл 4 при старте 2")


# Сервер (OrderValidator) обязан согласиться с разблокировкой: скилл, разблокированный приростом
# медитации в раннем слоте, НЕ должен срезаться в пустой — иначе клиент показал бы доступным то,
# что сервер молча выкинет.
func test_meditation_unlocks_expensive_skill() -> void:
	var s := _fresh()
	var u := _place(s, 0, Vector2i(3, 3))
	# AB1 = Медитация, AB2 = Крест смерти (кост 4). Старт маны 3 — на крест «в лоб» не хватает.
	u.skills = [Consts.Skill.MEDITATION, Consts.Skill.DEATHCROSS, Consts.Skill.PRECISE]
	u.mana = Consts.DEATHCROSS_MANA - 1

	var orders := _slots()
	orders[0] = Order.make(0, Consts.Action.ABILITY1)   # медитация (без цели)
	orders[2] = Order.make(0, Consts.Action.ABILITY2)   # крест
	var sane := OrderValidator.sanitize(s, orders, Consts.Player.A)
	_check(not sane[0].is_empty(), "медитация в слоте 0 сохранена")
	_check(not sane[2].is_empty(), "крест в слоте 2 РАЗБЛОКИРОВАН приростом медитации (сервер согласен)")

	# без медитации тот же крест на 3 маны сервер режет
	var no_med := _slots()
	no_med[2] = Order.make(0, Consts.Action.ABILITY2)
	_check(OrderValidator.sanitize(s, no_med, Consts.Player.A)[2].is_empty(),
		"без медитации крест на нехватку маны срезан в пустой")

	# медитация ПОСЛЕ креста — прирост опаздывает, крест не оплачен
	var late := _slots()
	late[0] = Order.make(0, Consts.Action.ABILITY2)   # крест в раннем слоте
	late[2] = Order.make(0, Consts.Action.ABILITY1)   # медитация в позднем
	var sane_late := OrderValidator.sanitize(s, late, Consts.Player.A)
	_check(sane_late[0].is_empty(), "крест в раннем слоте поздней медитацией не оплачен — срезан")
	_check(not sane_late[2].is_empty(), "поздняя медитация сама по себе валидна")


# Крайне важно: разрешение валидатора должно совпадать с РЕАЛЬНОСТЬЮ резолвера — прирощенная мана
# действительно тратится, а не оказывается фикцией (иначе скилл физзлил бы на разрешении).
func test_meditation_mana_spent_by_resolver() -> void:
	var s := _fresh()
	var u := _place(s, 0, Vector2i(3, 3))
	u.skills = [Consts.Skill.MEDITATION, Consts.Skill.DEATHCROSS, Consts.Skill.PRECISE]
	u.mana = Consts.DEATHCROSS_MANA - 1   # 3
	var orders := _slots()
	orders[0] = Order.make(0, Consts.Action.ABILITY1)   # медитация -> +1
	orders[2] = Order.make(0, Consts.Action.ABILITY2)   # крест -> тратит 4
	Resolver.new().resolve(s, orders, _slots(), Consts.Player.A)
	_check(u.mana == 0, "резолвер: медитация(+1) оплатила крест(4) при старте 3 -> мана 0 [%d]" % u.mana)

	# контроль: без медитации крест на нехватку маны физзлит, мана цела
	var s2 := _fresh()
	var u2 := _place(s2, 0, Vector2i(3, 3))
	u2.skills = [Consts.Skill.MEDITATION, Consts.Skill.DEATHCROSS, Consts.Skill.PRECISE]
	u2.mana = Consts.DEATHCROSS_MANA - 1
	var no_med := _slots()
	no_med[2] = Order.make(0, Consts.Action.ABILITY2)
	Resolver.new().resolve(s2, no_med, _slots(), Consts.Player.A)
	_check(u2.mana == 3, "резолвер: без медитации крест физзлит, мана цела [%d]" % u2.mana)


# ---------------------------------------------------------------- новые скиллы

# Разводит всех юнитов, кроме keep_ids, по углам — чтобы не мешали в тесте.
func _park(s: MatchState, keep_ids: Array) -> void:
	var spots := [Vector2i(0, 0), Vector2i(6, 0), Vector2i(0, 6), Vector2i(6, 6), Vector2i(0, 3), Vector2i(6, 3)]
	var i := 0
	for u in s.units:
		if not (u.id in keep_ids):
			u.cell = spots[i]
			i += 1


# Держись подальше: враг, вошедший в соседнюю клетку с Охотником, получает урон и отбрасывается.
func test_stay_away_hits_and_pushes() -> void:
	# Ряд y=4 полностью открыт (на карте стены в (3,1),(3,5),(1,3),(5,3)).
	var s := _fresh()
	var hunter := _place(s, 0, Vector2i(2, 4))
	hunter.skills = [Consts.Skill.STAY_AWAY, Consts.Skill.SNIPE, Consts.Skill.SHOTGUN]
	var enemy := _place(s, 3, Vector2i(4, 4))
	_park(s, [0, 3])
	var hp0 := enemy.hp
	var ob := _slots()
	ob[0] = Order.make_move(3, [Vector2i(-1, 0)] as Array[Vector2i])   # (4,4)->(3,4), рядом с охотником (2,4)
	Resolver.new().resolve(s, _slots(), ob, Consts.Player.B)
	_check(enemy.hp == hp0 - Consts.STAY_AWAY_DMG, "держись подальше: враг получил урон [%d]" % enemy.hp)
	_check(enemy.cell == Vector2i(4, 4), "держись подальше: враг отброшен обратно на (4,4) [%s]" % str(enemy.cell))


# Отброс от «Держись подальше» не должен ловиться ВТОРЫМ таким же Охотником (иначе бесконечный
# пинг-понг). Проверяем: враг получает урон РОВНО раз и останавливается.
func test_stay_away_no_pingpong() -> void:
	# h0 отбросит врага на (4,4), где рядом стоит h1 с тем же пассивом — тот НЕ должен поймать
	# отброс (иначе бесконечный пинг-понг между двумя Охотниками).
	var s := _fresh()
	var h0 := _place(s, 0, Vector2i(2, 4))
	h0.skills = [Consts.Skill.STAY_AWAY, Consts.Skill.SNIPE, Consts.Skill.SHOTGUN]
	var h1 := _place(s, 1, Vector2i(5, 4))   # рядом с клеткой отброса (4,4)
	h1.skills = [Consts.Skill.STAY_AWAY, Consts.Skill.HEAL, Consts.Skill.FLASH]
	var enemy := _place(s, 3, Vector2i(3, 3))
	_park(s, [0, 1, 3])
	var hp0 := enemy.hp
	var ob := _slots()
	ob[0] = Order.make_move(3, [Vector2i(0, 1)] as Array[Vector2i])   # (3,3)->(3,4) рядом с h0
	Resolver.new().resolve(s, _slots(), ob, Consts.Player.B)
	_check(enemy.hp == hp0 - Consts.STAY_AWAY_DMG, "держись подальше: урон РОВНО один раз, без пинг-понга [%d]" % enemy.hp)
	_check(enemy.cell == Vector2i(4, 4), "держись подальше: отброшен на (4,4) и там остановлен [%s]" % str(enemy.cell))
	_check(enemy.alive, "держись подальше: враг жив (не зациклило до смерти)")


# Шипы: тикают в конце каждого раунда CALTROPS_ROUNDS раз, затем снимаются.
func test_caltrops_ticks_each_round() -> void:
	var s := _fresh()
	var hunter := _place(s, 0, Vector2i(3, 3))
	hunter.skills = [Consts.Skill.CALTROPS, Consts.Skill.SNIPE, Consts.Skill.SHOTGUN]
	hunter.mana = Consts.CALTROPS_MANA
	var enemy := _place(s, 3, Vector2i(3, 4))
	_park(s, [0, 3])
	var hp0 := enemy.hp
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(3, 4))   # шипы на клетку врага
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(enemy.hp == hp0 - Consts.CALTROPS_DMG, "шипы: тик 1 (раунд размещения) [%d]" % enemy.hp)
	# ещё два раунда врагу стоять на шипах
	for tick in [2, 3]:
		s.begin_round()
		Resolver.new().resolve(s, _slots(), _slots(), s.first_player_this_round())
		_check(enemy.hp == hp0 - tick * Consts.CALTROPS_DMG, "шипы: тик %d [%d]" % [tick, enemy.hp])
	# 4-й раунд — шипы уже сняты, урона больше нет
	s.begin_round()
	Resolver.new().resolve(s, _slots(), _slots(), s.first_player_this_round())
	_check(enemy.hp == hp0 - Consts.CALTROPS_ROUNDS * Consts.CALTROPS_DMG,
		"шипы: после %d раундов больше не бьют [%d]" % [Consts.CALTROPS_ROUNDS, enemy.hp])
	_check(s.spikes.is_empty(), "шипы: сняты после экспирации")


# Быстрая перезарядка: одну способность можно занять в двух слотах (сервер это принимает).
func test_fast_reload_repeats_ability() -> void:
	var s := _fresh()
	# Дробь (ABILITY1) без гейта слота — берём её, чтобы проверялся именно дедуп, а не гейт.
	var u := _place(s, 0, Vector2i(3, 3))
	u.skills = [Consts.Skill.SHOTGUN, Consts.Skill.PRECISE, Consts.Skill.FAST_RELOAD]  # AB1 = Дробь
	u.mana = 10
	var orders := _slots()
	orders[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(4, 4))
	orders[2] = Order.make(0, Consts.Action.ABILITY1, Vector2i(2, 2))
	var sane := OrderValidator.sanitize(s, orders, Consts.Player.A)
	_check(not sane[0].is_empty() and not sane[2].is_empty(), "быстрая перезарядка: дробь дважды разрешена")

	# без пассивки второй тот же скилл срезается
	u.skills = [Consts.Skill.SHOTGUN, Consts.Skill.PRECISE, Consts.Skill.SNIPER]
	var sane2 := OrderValidator.sanitize(s, orders, Consts.Player.A)
	_check(not sane2[0].is_empty() and sane2[2].is_empty(), "без быстрой перезарядки вторая дробь срезана")


# Переполняющая мощь: -3 HP себе, +2 маны; суицид не даёт сопернику очков; прирост разблокирует.
func test_power_surge_self_damage_and_mana() -> void:
	var s := _fresh()
	var u := _place(s, 2, Vector2i(3, 3))
	u.skills = [Consts.Skill.POWER_SURGE, Consts.Skill.JUMP, Consts.Skill.AMBUSH]
	u.mana = 0
	u.hp = 10
	_park(s, [2])
	var orders := _slots()
	orders[0] = Order.make(2, Consts.Action.ABILITY1)
	Resolver.new().resolve(s, orders, _slots(), Consts.Player.A)
	_check(u.mana == Consts.POWER_SURGE_MANA_GAIN, "переполняющая мощь: +%d маны [%d]" % [Consts.POWER_SURGE_MANA_GAIN, u.mana])
	_check(u.hp == 10 - Consts.POWER_SURGE_SELF_DMG, "переполняющая мощь: -%d HP себе [%d]" % [Consts.POWER_SURGE_SELF_DMG, u.hp])

	# суицид: HP ровно под урон — Камнешип гибнет, сопернику очков не капает
	var s2 := _fresh()
	var u2 := _place(s2, 2, Vector2i(3, 3))
	u2.skills = [Consts.Skill.POWER_SURGE, Consts.Skill.JUMP, Consts.Skill.AMBUSH]
	u2.mana = 0
	u2.hp = Consts.POWER_SURGE_SELF_DMG
	var sc_before: int = s2.score[Consts.Player.B]
	var o2 := _slots()
	o2[0] = Order.make(2, Consts.Action.ABILITY1)
	Resolver.new().resolve(s2, o2, _slots(), Consts.Player.A)
	_check(not u2.alive, "переполняющая мощь: добила себя")
	_check(s2.score[Consts.Player.B] == sc_before, "переполняющая мощь: за суицид сопернику очков нет")

	# прирост маны разблокирует дорогой скилл (та же модель, что у Медитации)
	var s3 := _fresh()
	var u3 := _place(s3, 2, Vector2i(3, 3))
	u3.skills = [Consts.Skill.POWER_SURGE, Consts.Skill.ONSLAUGHT, Consts.Skill.JUMP]  # AB2 = Натиск (4)
	u3.mana = Consts.ONSLAUGHT_MANA - 2   # без прироста на натиск не хватает
	var o3 := _slots()
	o3[0] = Order.make(2, Consts.Action.ABILITY1)               # мощь: +2 маны
	o3[2] = Order.make(2, Consts.Action.ABILITY2, Vector2i(3, 4))   # натиск
	_check(not OrderValidator.sanitize(s3, o3, Consts.Player.A)[2].is_empty(),
		"переполняющая мощь разблокирует натиск приростом маны")
