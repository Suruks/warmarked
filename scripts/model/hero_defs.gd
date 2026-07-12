class_name HeroDefs
extends RefCounted

## Каталог способностей троицы как данные.
## Используется и панелью планирования (какие действия доступны, сколько стоят,
## как целиться), и резолвером (валидация цели, стоимость маны).

# Как целится действие
enum Target {
	NONE,        # без цели (Отмена, Засада — на себя)
	MOVE_PATH,   # путь орто <= MOVE_RANGE
	CELL,        # любая клетка (валидность считает can_target)
}

# Одна запись действия
class AbilityDef:
	extends RefCounted
	var name: String
	var mana: int
	var target: int          # Target
	var slot_gate: Array = []  # если непусто — разрешённые индексы слотов (0..3)
	var desc: String

	func _init(p_name: String, p_mana: int, p_target: int, p_desc: String, p_gate: Array = []) -> void:
		name = p_name
		mana = p_mana
		target = p_target
		desc = p_desc
		slot_gate = p_gate


# Возвращает описание базовой атаки героя
static func basic_attack(hero_type: int) -> AbilityDef:
	match hero_type:
		Consts.HeroType.HUNTER:
			return AbilityDef.new("Выстрел", 0, Target.CELL,
				"по прямой, рэйндж 2-3, %d урона" % Consts.HUNTER_ATK_DMG)
		Consts.HeroType.FAIRY:
			return AbilityDef.new("Удар", 0, Target.CELL,
				"%d урона, соседняя или диагональ" % Consts.FAIRY_ATK_DMG)
		Consts.HeroType.CRYSTAL:
			return AbilityDef.new("Удар", 0, Target.CELL,
				"%d урона соседней клетке" % Consts.CRYSTAL_ATK_DMG)
	return AbilityDef.new("?", 0, Target.NONE, "")


# Пул скиллов героя: из него игрок набирает SKILLS_PER_HERO штук в «Коллекции».
# Первые SKILLS_PER_HERO — кит по умолчанию.
static func pool(hero_type: int) -> Array:
	match hero_type:
		Consts.HeroType.HUNTER:
			return [Consts.Skill.TRAP, Consts.Skill.SNIPE, Consts.Skill.SHOTGUN,
					Consts.Skill.PRECISE, Consts.Skill.HUNT_MARK, Consts.Skill.RETREAT,
					Consts.Skill.NET, Consts.Skill.DEATHCROSS, Consts.Skill.MINEFIELD,
					Consts.Skill.BLEED]
		Consts.HeroType.FAIRY:
			return [Consts.Skill.CANCEL, Consts.Skill.HEAL, Consts.Skill.FLASH,
					Consts.Skill.SPARK, Consts.Skill.DISORIENT, Consts.Skill.MANASTEAL,
					Consts.Skill.SHACKLES, Consts.Skill.SLOW, Consts.Skill.TELEPORT,
					Consts.Skill.REVIVE]
		Consts.HeroType.CRYSTAL:
			return [Consts.Skill.JUMP, Consts.Skill.AMBUSH, Consts.Skill.ONSLAUGHT,
					Consts.Skill.DASH, Consts.Skill.SPIKES, Consts.Skill.REFLEXES,
					Consts.Skill.HARDENING, Consts.Skill.SHARDS, Consts.Skill.OVERLOAD,
					Consts.Skill.SWAP]
	return []


static func default_skills(hero_type: int) -> Array:
	return pool(hero_type).slice(0, Consts.SKILLS_PER_HERO)


# Порядок слотов ABILITY1..3 в бою: по возрастанию маны, id скилла как
# детерминированный вторичный ключ (одинаково у обоих пиров -> лок-степ цел).
static func sorted_by_mana(skills: Array) -> Array:
	var out := skills.duplicate()
	out.sort_custom(func(a, b):
		var ma := skill_def(a).mana
		var mb := skill_def(b).mana
		return a < b if ma == mb else ma < mb)
	return out


# Единственный каталог: описание по id скилла. Всё остальное (резолвер, таргетинг,
# валидатор, иконки) диспетчеризуется по тому же id.
static func skill_def(skill: int) -> AbilityDef:
	match skill:
		Consts.Skill.TRAP:
			return AbilityDef.new("Капкан", Consts.TRAP_MANA, Target.CELL,
				"капкан в радиусе 2; враг вошёл -> %d урона + обездвижен; действует до конца хода" % Consts.TRAP_DMG)
		Consts.Skill.SNIPE:
			return AbilityDef.new("Снайп", Consts.SNIPE_MANA, Target.CELL,
				"прямая 2-7, %d урона (только слот 3-4)" % Consts.SNIPE_DMG, [2, 3])
		Consts.Skill.SHOTGUN:
			return AbilityDef.new("Дробь", Consts.SHOTGUN_MANA, Target.CELL,
				"квадрат 2x2 по диагонали: %d урона, отбрасывание 1" % Consts.SHOTGUN_DMG)
		Consts.Skill.PRECISE:
			return AbilityDef.new("Меткий выстрел", Consts.PRECISE_MANA, Target.CELL,
				"%d урона строго по клетке на дальности %d (прямое попадание, не перехватывается)" % [Consts.PRECISE_DMG, Consts.PRECISE_RANGE])
		Consts.Skill.HUNT_MARK:
			return AbilityDef.new("Охота началась", Consts.HUNT_MANA, Target.CELL,
				"метка на враге: ×%d урона по нему от атак и скиллов Охотника до конца раунда" % Consts.HUNT_MULT)
		Consts.Skill.RETREAT:
			return AbilityDef.new("Отступление", Consts.RETREAT_MANA, Target.MOVE_PATH,
				"если враг в соседней клетке — путь до %d клеток (относительный, как ход)" % Consts.RETREAT_RANGE)
		Consts.Skill.NET:
			return AbilityDef.new("Ловчая сеть", Consts.NET_MANA, Target.CELL,
				"обездвиживает цель до конца раунда, без урона (дальность %d)" % Consts.NET_RANGE)
		Consts.Skill.DEATHCROSS:
			return AbilityDef.new("Крест смерти", Consts.DEATHCROSS_MANA, Target.NONE,
				"%d урона первому врагу на каждой из 4 прямых линий" % Consts.DEATHCROSS_DMG)
		Consts.Skill.MINEFIELD:
			return AbilityDef.new("Минное поле", Consts.MINEFIELD_MANA, Target.CELL,
				"ставит %d капкана в радиусе %d вокруг цели" % [Consts.MINEFIELD_COUNT, Consts.MINEFIELD_RADIUS])
		Consts.Skill.BLEED:
			return AbilityDef.new("Кровавый след", Consts.BLEED_MANA, Target.CELL,
				"метка на враге в радиусе %d на %d хода: каждое перемещение цели -> %d урона" % [Consts.BLEED_RANGE, Consts.BLEED_TURNS, Consts.BLEED_DMG])
		Consts.Skill.CANCEL:
			return AbilityDef.new("Отмена", Consts.CANCEL_MANA, Target.CELL,
				"щит себе или союзнику рядом: отменяет следующий эффект по нему")
		Consts.Skill.HEAL:
			return AbilityDef.new("Лечение", Consts.HEAL_MANA, Target.CELL,
				"хил %d союзнику в радиусе 2" % Consts.HEAL_AMOUNT)
		Consts.Skill.FLASH:
			return AbilityDef.new("Вспышка", Consts.FLASH_MANA, Target.NONE,
				"%d урона всем вокруг (радиус 1), включая союзников" % Consts.FLASH_DMG)
		Consts.Skill.SPARK:
			return AbilityDef.new("Искра", Consts.SPARK_MANA, Target.CELL,
				"%d урона одиночной цели на дальности до %d" % [Consts.SPARK_DMG, Consts.SPARK_RANGE])
		Consts.Skill.DISORIENT:
			return AbilityDef.new("Дезориентация", Consts.DISORIENT_MANA, Target.CELL,
				"враг в радиусе %d: его следующий направленный скилл в этом раунде срабатывает в обратную сторону" % Consts.DISORIENT_RANGE)
		Consts.Skill.MANASTEAL:
			return AbilityDef.new("Кража маны", Consts.MANASTEAL_MANA, Target.CELL,
				"удар по соседнему врагу: %d урона и похищение %d маны" % [Consts.MANASTEAL_DMG, Consts.MANASTEAL_AMOUNT])
		Consts.Skill.SHACKLES:
			return AbilityDef.new("Оковы", Consts.SHACKLES_MANA, Target.CELL,
				"враг в радиусе %d на %d хода теряет базовую атаку" % [Consts.SHACKLES_RANGE, Consts.SHACKLES_TURNS])
		Consts.Skill.SLOW:
			return AbilityDef.new("Замедление", Consts.SLOW_MANA, Target.CELL,
				"враг в радиусе %d на %d хода получает -%d к дальности хода" % [Consts.SLOW_RANGE, Consts.SLOW_TURNS, Consts.SLOW_MOVE_PENALTY])
		Consts.Skill.TELEPORT:
			return AbilityDef.new("Телепорт", Consts.TELEPORT_MANA, Target.CELL,
				"телепорт себя на свободную клетку в радиусе %d (сквозь препятствия и юнитов)" % Consts.TELEPORT_RANGE)
		Consts.Skill.REVIVE:
			return AbilityDef.new("Возрождение", Consts.REVIVE_MANA, Target.CELL,
				"воскрешает павшего союзника (любая могила на доске) на полном HP в соседней свободной клетке")
		Consts.Skill.JUMP:
			return AbilityDef.new("Прыжок", Consts.JUMP_MANA, Target.CELL,
				"прыжок через соседа; если враг — %d урона" % Consts.JUMP_DMG)
		Consts.Skill.AMBUSH:
			return AbilityDef.new("Засада", Consts.AMBUSH_MANA, Target.NONE,
				"стойка: первый вошедший рядом -> %d урона" % Consts.AMBUSH_DMG)
		Consts.Skill.DASH:
			return AbilityDef.new("Рывок", Consts.DASH_MANA, Target.CELL,
				"прямая сквозь всех, каждому на пути %d урона" % Consts.DASH_DMG)
		Consts.Skill.ONSLAUGHT:
			return AbilityDef.new("Натиск", Consts.ONSLAUGHT_MANA, Target.CELL,
				"соседняя клетка: %d урона, отбрасывает на 1 и занимает освободившуюся клетку" % Consts.ONSLAUGHT_DMG)
		Consts.Skill.SPIKES:
			return AbilityDef.new("Острые шипы", Consts.SPIKES_MANA, Target.NONE,
				"%d урона по 4 диагонально-соседним клеткам, включая союзников" % Consts.SPIKES_DMG)
		Consts.Skill.REFLEXES:
			return AbilityDef.new("Рефлексы", Consts.REFLEXES_MANA, Target.NONE,
				"стойка: соседний враг целит в эту клетку -> отступить на 1 и получить %d маны" % Consts.REFLEXES_MANA_GAIN)
		Consts.Skill.HARDENING:
			return AbilityDef.new("Затвердение", Consts.HARDENING_MANA, Target.NONE,
				"стойка: снижает весь входящий урон на %d до конца раунда" % Consts.HARDENING_REDUCTION)
		Consts.Skill.SHARDS:
			return AbilityDef.new("Осколки", Consts.SHARDS_MANA, Target.NONE,
				"стойка: враг, нанёсший урон в этом раунде, получает %d в ответ" % Consts.SHARDS_DMG)
		Consts.Skill.OVERLOAD:
			return AbilityDef.new("Перегрузка", Consts.OVERLOAD_MANA, Target.CELL,
				"соседняя цель: тратит всю ману, %d урона за каждую потраченную" % Consts.OVERLOAD_DMG_PER_MANA)
		Consts.Skill.SWAP:
			return AbilityDef.new("Обмен местами", Consts.SWAP_MANA, Target.CELL,
				"меняется местами с соседним юнитом (своим или чужим)")
	return AbilityDef.new("?", 0, Target.NONE, "")


# Скилл, стоящий в слоте idx (0..2). skills — кит юнита; пустой -> кит по умолчанию.
static func skill_at(hero_type: int, idx: int, skills: Array = []) -> int:
	var s: Array = skills if skills.size() == Consts.SKILLS_PER_HERO else default_skills(hero_type)
	return s[idx]


# Скилл, стоящий за Action-кодом ABILITY1..3; для прочих действий -1.
static func skill_of_action(hero_type: int, action: int, skills: Array = []) -> int:
	if action < Consts.Action.ABILITY1 or action > Consts.Action.ABILITY3:
		return -1
	return skill_at(hero_type, action - Consts.Action.ABILITY1, skills)


# Возвращает описание способности по индексу (0..2 = ABILITY1..3)
static func ability(hero_type: int, idx: int, skills: Array = []) -> AbilityDef:
	return skill_def(skill_at(hero_type, idx, skills))


# Возвращает описание действия по Action-коду (базовая атака или способность)
static func for_action(hero_type: int, action: int, skills: Array = []) -> AbilityDef:
	match action:
		Consts.Action.ATTACK:
			return basic_attack(hero_type)
		Consts.Action.ABILITY1, Consts.Action.ABILITY2, Consts.Action.ABILITY3:
			return ability(hero_type, action - Consts.Action.ABILITY1, skills)
		Consts.Action.MOVE:
			return AbilityDef.new("Ход", 0, Target.MOVE_PATH, "движение до %d клеток" % Consts.MOVE_RANGE)
	return AbilityDef.new("—", 0, Target.NONE, "пустой слот")
