class_name Difficulty
extends RefCounted

## Сложность боя «против ИИ»: слайдер 1..50. Уровень 1 — игра без модификаторов. Каждый
## следующий уровень добавляет ОДИН модификатор поверх уже применённых на предыдущих уровнях —
## 5 типов по кругу (2 HP -> 2 мана -> урон умения -> дешевле умение -> бонусная способность ->
## снова HP -> ...). Модификаторы получает только команда бота — усиливают ИИ, игрока не касаются.
##
## Уровни открываются блоками по TIER: изначально доступны 1..TIER, победа на последнем открытом
## уровне открывает следующий блок, и так до MAX_LEVEL.
##
## `best` — личный рекорд: старший уровень, на котором игрок ПОБЕДИЛ (в отличие от unlocked, он
## растёт по одному и только за реальную победу). Это то, чем игроки меряются в лидерборде.
##
## И прогресс, и рекорд — СЕРВЕРНОЕ состояние: бой с ИИ идёт на сервере (Net.req_start_ai_match),
## там же считается его исход и пишется в БД. `unlocked`/`best` здесь — сессионные зеркала для
## UI: приходят при входе (main.gd/_on_auth_ok) и после каждого боя (ai_progress_rpc). Клиент их
## никуда не «сохраняет» — иначе он же и решал бы, что ему открыто.

const MIN_LEVEL := 1
const MAX_LEVEL := 50
const TIER := 5

enum ModType { HP, MANA, ATK_DMG, ABILITY_COST, EXTRA_ABILITY }
const _CYCLE := [ModType.HP, ModType.MANA, ModType.ATK_DMG, ModType.ABILITY_COST, ModType.EXTRA_ABILITY]

# Активные умения с прямым уроном за один каст — пул для модификатора ATK_DMG. Пассивки, ДоТы
# (Кровавый след), реактивки (Осколки) и урон по формуле (Перегрузка) сюда намеренно не входят.
const _DAMAGE_SKILLS := [
	Consts.Skill.TRAP, Consts.Skill.SNIPE, Consts.Skill.SHOTGUN, Consts.Skill.PRECISE,
	Consts.Skill.DEATHCROSS, Consts.Skill.MINEFIELD, Consts.Skill.KNOCKDOWN,
	Consts.Skill.FLASH, Consts.Skill.SPARK, Consts.Skill.LIGHTNING, Consts.Skill.MANASTEAL,
	Consts.Skill.JUMP, Consts.Skill.AMBUSH, Consts.Skill.DASH, Consts.Skill.ONSLAUGHT,
	Consts.Skill.SPIKES,
]

static var level: int = 1        # выбранный уровень сложности; живёт на сессию, как Loadout
static var unlocked: int = TIER  # старший доступный уровень (кратно TIER); источник истины — сервер
static var best: int = 0         # личный рекорд (0 = ни одной победы); источник истины — сервер


static func set_level(l: int) -> void:
	level = clampi(l, MIN_LEVEL, unlocked)


static func set_unlocked(v: int) -> void:
	unlocked = sanitize_unlocked(v)


static func set_best(v: Variant) -> void:
	best = sanitize_best(v)


# Рекорд, в отличие от unlocked, не квантуется по TIER — любой уровень 0..MAX_LEVEL валиден
# (0 = побед ещё нет). Аномалия (не число/вне диапазона) → 0, как у игрока без побед.
static func sanitize_best(v: Variant) -> int:
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return 0
	return clampi(int(v), 0, MAX_LEVEL)


# Любая аномалия (не число, не кратно TIER, вне диапазона) → ближе к дефолту, не роняем.
static func sanitize_unlocked(v: Variant) -> int:
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return TIER
	var n: int = (int(v) / TIER) * TIER   # округление вниз до границы тира
	return clampi(n, TIER, MAX_LEVEL)


# Прогресс после победы на level_played: победа на (как минимум) старшем доступном уровне
# открывает следующий блок из TIER уровней. Игра ниже текущего потолка (просто по фану)
# прогресс не двигает. Чистая функция без статики: прогресс ведёт СЕРВЕР по своей БД
# (см. Net.req_start_ai_match), а `unlocked` здесь — лишь зеркало для UI.
static func unlocked_after_win(current_unlocked: Variant, level_played: int) -> int:
	var u := sanitize_unlocked(current_unlocked)
	if level_played < u or u >= MAX_LEVEL:
		return u
	return mini(u + TIER, MAX_LEVEL)


# Разрешён ли игроку бой на этом уровне при таком прогрессе. Гейт СЕРВЕРНЫЙ: попросить клиент
# может любой уровень (в т.ч. 50 на свежем аккаунте), открытые считает сервер по своей БД.
static func playable(level: Variant, unlocked_progress: Variant) -> bool:
	if typeof(level) != TYPE_INT:
		return false
	return level >= MIN_LEVEL and level <= sanitize_unlocked(unlocked_progress)


# Применяет к команде бота (bot_player) все модификаторы уровня level. Вызывать ровно один раз,
# сразу после MatchState.setup(), до первого begin_round().
#
# Какие именно бойцы/умения усилены — решает жребий, поэтому он ДЕТЕРМИНИРОВАННЫЙ: и сервер, и
# клиент строят копию матча вызовом apply() с одним и тем же seed (сервер шлёт его в
# ai_match_found_rpc). Глобальный randi() тут нельзя — у сторон разошлись бы HP/мана/киты бота,
# а с ними и лок-степ. Порядок обхода тоже фиксирован: units_of отдаёт бойцов стабильно.
static func apply(state: MatchState, bot_player: int, level_played: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for m in level_played - 1:
		match _CYCLE[m % _CYCLE.size()]:
			ModType.HP: _mod_hp(state, bot_player, rng)
			ModType.MANA: _mod_mana(state, bot_player, rng)
			ModType.ATK_DMG: _mod_atk_dmg(state, bot_player, rng)
			ModType.ABILITY_COST: _mod_ability_cost(state, bot_player, rng)
			ModType.EXTRA_ABILITY: _mod_extra_ability(state, bot_player, rng)


static func _bot_units(state: MatchState, bot_player: int) -> Array[Unit]:
	return state.units_of(bot_player)


static func _random_unit(state: MatchState, bot_player: int, rng: RandomNumberGenerator) -> Unit:
	var us := _bot_units(state, bot_player)
	return us[rng.randi() % us.size()]


# +2 HP навсегда: max_hp ничем в MatchState не сбрасывается, поэтому бонус переживает респ сам.
static func _mod_hp(state: MatchState, bot_player: int, rng: RandomNumberGenerator) -> void:
	var u := _random_unit(state, bot_player, rng)
	u.max_hp += 2
	u.hp += 2


# +2 стартовой маны: сразу в банк и в перманентный бонус (переживает респ, см. MatchState._try_respawn).
static func _mod_mana(state: MatchState, bot_player: int, rng: RandomNumberGenerator) -> void:
	var u := _random_unit(state, bot_player, rng)
	u.start_mana_bonus += 2
	u.mana += 2


# +1 урон случайному активному атакующему умению из уже экипированного кита случайного бойца бота.
static func _mod_atk_dmg(state: MatchState, bot_player: int, rng: RandomNumberGenerator) -> void:
	var pool := _eligible(state, bot_player, func(s): return s in _DAMAGE_SKILLS)
	if pool.is_empty():
		return
	var pick: Dictionary = pool[rng.randi() % pool.size()]
	var u: Unit = pick.unit
	var skill: int = pick.skill
	u.dmg_bonus[skill] = int(u.dmg_bonus.get(skill, 0)) + 1


# -1 мана случайному экипированному умению бота (не дешевле 0).
static func _mod_ability_cost(state: MatchState, bot_player: int, rng: RandomNumberGenerator) -> void:
	var pool := _eligible(state, bot_player, func(s): return HeroDefs.skill_def(s).mana > 0)
	if pool.is_empty():
		return
	var pick: Dictionary = pool[rng.randi() % pool.size()]
	var u: Unit = pick.unit
	var skill: int = pick.skill
	u.mana_discount[skill] = int(u.mana_discount.get(skill, 0)) + 1


# {unit, skill} по всем экипированным умениям бота (кроме пассивок), прошедшим фильтр pred(skill).
static func _eligible(state: MatchState, bot_player: int, pred: Callable) -> Array:
	var out: Array = []
	for u in _bot_units(state, bot_player):
		for s in u.skills:
			if not HeroDefs.skill_def(s).passive and pred.call(s):
				out.append({"unit": u, "skill": s})
	return out


# Случайный боец бота без бонусной 4-й способности получает случайную новую способность из
# пула своего класса (+ нейтралы), которой у него ещё нет — реальный 4-й слот (ABILITY4).
# Если у ВСЕХ бойцов бота уже есть бонусный слот, модификатор пропускается (архитектурно
# поддержан только один бонусный слот на бойца).
static func _mod_extra_ability(state: MatchState, bot_player: int, rng: RandomNumberGenerator) -> void:
	var cands: Array[Unit] = []
	for u in _bot_units(state, bot_player):
		if u.skills.size() <= Consts.SKILLS_PER_HERO:
			cands.append(u)
	if cands.is_empty():
		return
	var u: Unit = cands[rng.randi() % cands.size()]
	var choices: Array = []
	for s in HeroDefs.pool(u.hero_type) + HeroDefs.neutrals():
		if not (s in u.skills):
			choices.append(s)
	if choices.is_empty():
		return
	u.skills.append(choices[rng.randi() % choices.size()])
