class_name Unit
extends RefCounted

## Один герой на доске. Чистые данные + производные хелперы, без узлов сцены.

var id: int
var owner: int              # Consts.Player
var hero_type: int          # Consts.HeroType
var max_hp: int
var hp: int
var mana: int
var cell: Vector2i
var home_cell: Vector2i     # стартовая клетка: сюда (или рядом) юнит воскресает

var alive: bool = true
var dead_timer: int = 0     # раундов до попытки респа (0 = не мёртв / готов к респу)
var death_cell: Vector2i = Vector2i(-1, -1)   # где лежит могила, пока юнит мёртв

# Обездвижен: не может двигаться сам (ход и скиллы-перемещения). Ставится при срабатывании
# капкана и держится до конца ТЕКУЩЕГО раунда; сбрасывается в начале следующего (см. begin_round).
var immobilized: bool = false

# Щит Феи (Отмена). Взводится во время разрешения, гасит следующий эффект. Сбрасывается в начале раунда.
var shield_armed: bool = false

# Рефлексы Кристалкайнда. Взводится во время разрешения, срабатывает один раз. Сбрасывается в начале раунда.
var reflexes_armed: bool = false

# Затвердение Кристалкайнда. Пока взведено, весь урон по юниту поглощается. Сбрасывается в начале раунда.
var hardened: bool = false

# Осколки Кристалкайнда. Пока взведено, враг, нанёсший урон, получает ответку. Сбрасывается в начале раунда.
var shards_armed: bool = false

# «Держись подальше» Охотника (стойка). Пока взведено, вошедший в соседнюю клетку враг получает
# урон и отброс. Держит свой раунд (может сработать не раз), сбрасывается в начале следующего.
var stay_away_armed: bool = false

# «Охота началась» Охотника: пока hunt_turns > 0, атаки/скиллы Охотника по этому юниту бьют
# на HUNT_BONUS_DMG сильнее. Держится через раунды (убывает), как Кровавый след/Оковы/Замедление.
var hunt_turns: int = 0

# «Кровавый след» Охотника. Пока bleed_turns > 0, каждое перемещение юнита наносит ему урон.
# В ОТЛИЧИЕ от стоек — держится через раунды: убывает в начале раунда, а не сбрасывается.
var bleed_turns: int = 0
var bleed_owner: int = -1   # чей эффект (кому идёт килл-очко за смерть от кровотечения)

# «Дезориентация» Феи. Следующий направленный скилл юнита в этом раунде развернётся. Сбрасывается в начале раунда.
var disoriented: bool = false

# «Оковы» Феи: пока > 0, юнит не может использовать базовую атаку. Держится через раунды (убывает).
var no_attack_turns: int = 0

# «Замедление» Феи: пока > 0, дальность хода юнита снижена. Держится через раунды (убывает).
var slow_turns: int = 0

# --- Пассивки ---
var moved_this_round: bool = false   # менял ли клетку в этом раунде (для «Снайпер»)
# менял ли клетку в прошлом раунде; старт — true (не «стоял на месте»), чтобы «Снайпер»
# не работал в 1-м раунде матча — предыдущего раунда, в котором можно было простоять, ещё не было
var moved_last_round: bool = true
var shell_used: bool = false         # «Кристальный панцирь»: срезка первого урона уже сработала
var block_amount: int = 0            # «Блок» (нейтрал): запас поглощения урона на раунд

# Кит: ровно SKILLS_PER_HERO id из Consts.Skill, слоты ABILITY1..3 по возрастанию маны.
# Может вырасти до SKILLS_PER_HERO+1 — 4-й (ABILITY4) добавляет только Difficulty (сложность
# «против ИИ»), обычная сборка (Loadout) всегда даёт ровно SKILLS_PER_HERO.
var skills: Array = []

# --- Модификаторы сложности «против ИИ» (Difficulty). У игрока и в онлайне всегда пусты/0. ---
var start_mana_bonus: int = 0     # перманентная надбавка к стартовой мане (переживает респ)
var dmg_bonus: Dictionary = {}    # skill_id -> доп. урон каста этим бойцом
var mana_discount: Dictionary = {}   # skill_id -> скидка к стоимости этим бойцом (не дешевле 0)


func _init(p_id: int, p_owner: int, p_hero_type: int, p_cell: Vector2i, p_skills: Array = []) -> void:
	id = p_id
	owner = p_owner
	hero_type = p_hero_type
	cell = p_cell
	home_cell = p_cell
	skills = HeroDefs.sorted_by_mana(Loadout.sanitize_hero(p_hero_type, p_skills))
	match hero_type:
		Consts.HeroType.HUNTER: max_hp = Consts.HUNTER_HP
		Consts.HeroType.FAIRY: max_hp = Consts.FAIRY_HP
		Consts.HeroType.CRYSTAL: max_hp = Consts.CRYSTAL_HP
	hp = max_hp
	mana = Consts.START_MANA


func has_skill(id: int) -> bool:
	return id in skills


# «Быстрая перезарядка»: снимает запрет «одну способность не дважды за раунд» (только для
# способностей — ход и базовая атака остаются одноразовыми). Проверяют и валидатор, и планировщик.
func repeats_abilities() -> bool:
	return has_skill(Consts.Skill.FAST_RELOAD)


# Эффективная дальность хода: «Лёгкость» повышает, «Замедление» понижает.
func move_range() -> int:
	var r: int = Consts.LIGHTNESS_MOVE_RANGE if has_skill(Consts.Skill.LIGHTNESS) else Consts.MOVE_RANGE
	if slow_turns > 0:
		r -= Consts.SLOW_MOVE_PENALTY
	return maxi(0, r)


func name_short() -> String:
	return "%s(%s)" % [Consts.hero_glyph(hero_type), Consts.player_name(owner)]


func full_name() -> String:
	return "%s %s" % [Consts.hero_name(hero_type), Consts.player_name(owner)]


# Глубокая копия для просчёта: AI прогоняет варианты приказов на клоне через настоящий
# Resolver, не трогая боевое состояние. Копируем ВСЕ поля (snapshot для этого не годится —
# он терятельный: без home_cell/skills/флагов симуляция разошлась бы).
func clone() -> Unit:
	var u := Unit.new(id, owner, hero_type, cell, skills)
	u.skills = skills.duplicate()
	u.max_hp = max_hp
	u.hp = hp
	u.mana = mana
	u.cell = cell
	u.home_cell = home_cell
	u.alive = alive
	u.dead_timer = dead_timer
	u.death_cell = death_cell
	u.immobilized = immobilized
	u.shield_armed = shield_armed
	u.reflexes_armed = reflexes_armed
	u.hardened = hardened
	u.shards_armed = shards_armed
	u.stay_away_armed = stay_away_armed
	u.hunt_turns = hunt_turns
	u.bleed_turns = bleed_turns
	u.bleed_owner = bleed_owner
	u.disoriented = disoriented
	u.no_attack_turns = no_attack_turns
	u.slow_turns = slow_turns
	u.moved_this_round = moved_this_round
	u.moved_last_round = moved_last_round
	u.shell_used = shell_used
	u.block_amount = block_amount
	u.start_mana_bonus = start_mana_bonus
	u.dmg_bonus = dmg_bonus.duplicate()
	u.mana_discount = mana_discount.duplicate()
	return u


func snapshot() -> Dictionary:
	return {
		"id": id,
		"owner": owner,
		"type": hero_type,
		"hp": hp,
		"max_hp": max_hp,
		"mana": mana,
		"cell": cell,
		"alive": alive,
		"dead_timer": dead_timer,
		"immobilized": immobilized,
		"shield": shield_armed,
		"reflex": reflexes_armed,
		"hardened": hardened,
		"shards": shards_armed,
		"stay_away": stay_away_armed,
		"hunted": hunt_turns,
		"bleed": bleed_turns,
		"disoriented": disoriented,
		"no_attack": no_attack_turns,
		"slow": slow_turns,
	}
