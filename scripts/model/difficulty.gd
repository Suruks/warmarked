class_name Difficulty
extends RefCounted

## Сложность боя «против ИИ»: слайдер 1..50. Уровень 1 — игра без модификаторов. Каждый
## следующий уровень добавляет ОДИН модификатор поверх уже применённых на предыдущих уровнях —
## 5 типов по кругу (2 HP -> 2 мана -> урон умения -> дешевле умение -> бонусная способность ->
## снова HP -> ...). Модификаторы получает только команда бота — усиливают ИИ, игрока не касаются.
##
## Уровни открываются блоками по TIER: изначально доступны 1..TIER, победа на последнем открытом
## уровне открывает следующий блок, и так до MAX_LEVEL. `unlocked` — сессионное зеркало серверного
## прогресса аккаунта (грузится при входе, см. main.gd/_on_auth_ok, сохраняется через Net).

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


static func set_level(l: int) -> void:
	level = clampi(l, MIN_LEVEL, unlocked)


static func set_unlocked(v: int) -> void:
	unlocked = sanitize_unlocked(v)


# Любая аномалия (не число, не кратно TIER, вне диапазона) → ближе к дефолту, не роняем.
static func sanitize_unlocked(v: Variant) -> int:
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return TIER
	var n: int = (int(v) / TIER) * TIER   # округление вниз до границы тира
	return clampi(n, TIER, MAX_LEVEL)


# Победа на level_played: если это был (как минимум) старший доступный уровень и есть куда расти —
# открывает следующий блок из TIER уровней и возвращает true (для UI-уведомления). Игра ниже
# текущего потолка (просто по фану) прогресс не двигает.
static func record_win(level_played: int) -> bool:
	if level_played < unlocked or unlocked >= MAX_LEVEL:
		return false
	unlocked = mini(unlocked + TIER, MAX_LEVEL)
	return true


# Применяет к команде бота (bot_player) все модификаторы уровня level. Вызывать ровно один раз,
# сразу после MatchState.setup(), до первого begin_round().
static func apply(state: MatchState, bot_player: int) -> void:
	for m in level - 1:
		match _CYCLE[m % _CYCLE.size()]:
			ModType.HP: _mod_hp(state, bot_player)
			ModType.MANA: _mod_mana(state, bot_player)
			ModType.ATK_DMG: _mod_atk_dmg(state, bot_player)
			ModType.ABILITY_COST: _mod_ability_cost(state, bot_player)
			ModType.EXTRA_ABILITY: _mod_extra_ability(state, bot_player)


static func _bot_units(state: MatchState, bot_player: int) -> Array[Unit]:
	return state.units_of(bot_player)


static func _random_unit(state: MatchState, bot_player: int) -> Unit:
	var us := _bot_units(state, bot_player)
	return us[randi() % us.size()]


# +2 HP навсегда: max_hp ничем в MatchState не сбрасывается, поэтому бонус переживает респ сам.
static func _mod_hp(state: MatchState, bot_player: int) -> void:
	var u := _random_unit(state, bot_player)
	u.max_hp += 2
	u.hp += 2


# +2 стартовой маны: сразу в банк и в перманентный бонус (переживает респ, см. MatchState._try_respawn).
static func _mod_mana(state: MatchState, bot_player: int) -> void:
	var u := _random_unit(state, bot_player)
	u.start_mana_bonus += 2
	u.mana += 2


# +1 урон случайному активному атакующему умению из уже экипированного кита случайного бойца бота.
static func _mod_atk_dmg(state: MatchState, bot_player: int) -> void:
	var pool := _eligible(state, bot_player, func(s): return s in _DAMAGE_SKILLS)
	if pool.is_empty():
		return
	var pick: Dictionary = pool[randi() % pool.size()]
	var u: Unit = pick.unit
	var skill: int = pick.skill
	u.dmg_bonus[skill] = int(u.dmg_bonus.get(skill, 0)) + 1


# -1 мана случайному экипированному умению бота (не дешевле 0).
static func _mod_ability_cost(state: MatchState, bot_player: int) -> void:
	var pool := _eligible(state, bot_player, func(s): return HeroDefs.skill_def(s).mana > 0)
	if pool.is_empty():
		return
	var pick: Dictionary = pool[randi() % pool.size()]
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
static func _mod_extra_ability(state: MatchState, bot_player: int) -> void:
	var cands: Array[Unit] = []
	for u in _bot_units(state, bot_player):
		if u.skills.size() <= Consts.SKILLS_PER_HERO:
			cands.append(u)
	if cands.is_empty():
		return
	var u: Unit = cands[randi() % cands.size()]
	var choices: Array = []
	for s in HeroDefs.pool(u.hero_type) + HeroDefs.neutrals():
		if not (s in u.skills):
			choices.append(s)
	if choices.is_empty():
		return
	u.skills.append(choices[randi() % choices.size()])
