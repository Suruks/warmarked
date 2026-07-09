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


# Возвращает описание способности по индексу (0..2 = ABILITY1..3)
static func ability(hero_type: int, idx: int) -> AbilityDef:
	match hero_type:
		Consts.HeroType.HUNTER:
			match idx:
				0: return AbilityDef.new("Капкан", Consts.TRAP_MANA, Target.CELL,
						"капкан в радиусе 2; враг вошёл -> %d урона + обездвижен" % Consts.TRAP_DMG)
				1: return AbilityDef.new("Снайп", Consts.SNIPE_MANA, Target.CELL,
						"прямая 2-7, %d урона (только слот 3-4)" % Consts.SNIPE_DMG, [2, 3])
				2: return AbilityDef.new("Дробь", Consts.SHOTGUN_MANA, Target.CELL,
						"квадрат 2x2 по диагонали: %d урона, отбрасывание 1" % Consts.SHOTGUN_DMG)
		Consts.HeroType.FAIRY:
			match idx:
				0: return AbilityDef.new("Отмена", Consts.CANCEL_MANA, Target.CELL,
						"щит себе или союзнику рядом: гасит следующий эффект по нему")
				1: return AbilityDef.new("Лечение", Consts.HEAL_MANA, Target.CELL,
						"хил %d союзнику в радиусе 2" % Consts.HEAL_AMOUNT)
				2: return AbilityDef.new("Вспышка", Consts.FLASH_MANA, Target.NONE,
						"%d урона всем вокруг (радиус 1), включая союзников" % Consts.FLASH_DMG)
		Consts.HeroType.CRYSTAL:
			match idx:
				0: return AbilityDef.new("Прыжок", Consts.JUMP_MANA, Target.CELL,
						"прыжок через соседа; если враг — %d урона" % Consts.JUMP_DMG)
				1: return AbilityDef.new("Засада", Consts.AMBUSH_MANA, Target.NONE,
						"стойка: первый вошедший рядом -> %d урона" % Consts.AMBUSH_DMG)
				2: return AbilityDef.new("Рывок", Consts.DASH_MANA, Target.CELL,
						"прямая сквозь всех, каждому на пути %d урона" % Consts.DASH_DMG)
	return AbilityDef.new("?", 0, Target.NONE, "")


# Возвращает описание действия по Action-коду (базовая атака или способность)
static func for_action(hero_type: int, action: int) -> AbilityDef:
	match action:
		Consts.Action.ATTACK:
			return basic_attack(hero_type)
		Consts.Action.ABILITY1:
			return ability(hero_type, 0)
		Consts.Action.ABILITY2:
			return ability(hero_type, 1)
		Consts.Action.ABILITY3:
			return ability(hero_type, 2)
		Consts.Action.MOVE:
			return AbilityDef.new("Ход", 0, Target.MOVE_PATH, "движение до %d клеток" % Consts.MOVE_RANGE)
	return AbilityDef.new("—", 0, Target.NONE, "пустой слот")
