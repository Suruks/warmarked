class_name Consts
extends RefCounted

## Глобальные константы и перечисления прототипа Warmarked.
## Все «дайлы» дизайна (цифры, помеченные в доке как крутибельные) собраны здесь,
## чтобы дизайнер мог править баланс в одном месте.

enum Player { A, B }
enum HeroType { HUNTER, FAIRY, CRYSTAL }

# Действие в слоте приказа. PASS — явное «нет действия» (занимает слот, но резолвится в пустоту;
# нужно, чтобы соперник не видел, что слот пуст). В приказ уходит как пустой.
enum Action { EMPTY, MOVE, ATTACK, ABILITY1, ABILITY2, ABILITY3, PASS }

# Типы событий разрешения (для лога и подсветки)
enum EventType {
	INFO, MOVE, ATTACK, ABILITY, DAMAGE, HEAL, DEATH, KILL,
	RESPAWN, RESPAWN_BLOCKED, TRAP_PLACED, TRAP_TRIGGER,
	AMBUSH_ARMED, AMBUSH_TRIGGER, SHIELD_ARMED, SHIELD_ABSORB,
	COLLISION, KNOCKBACK, IMMOBILIZE, FIZZLE, MANA, SCORE,
}

# --- Поле ---
const BOARD_W := 7
const BOARD_H := 7

# --- Матч ---
const WIN_SCORE := 10
const KILL_POINTS := 3
const CONTROL_POINTS_PER_ROUND := 1   # мажоритарная награда, кэп +1/раунд

# --- Юниты ---
const MOVE_RANGE := 2
const START_MANA := 1
const COLLISION_DMG := 4               # о край / стену / юнит (§7.1)
const RESPAWN_DELAY := 3               # респ через 3 раунда (§6.1)
const BLOCKER_DMG := 5                 # блокер клетки респа ест 5/раунд (вариант A)
const PERSIST_ROUNDS := 0              # капкан/засада живут раунд размещения + столько раундов (0 = только этот раунд)

# --- Способности: мана и урон (дайлы §9) ---
const HUNTER_HP := 11
const FAIRY_HP := 12
const CRYSTAL_HP := 10

const HUNTER_ATK_DMG := 2
const FAIRY_ATK_DMG := 2
const CRYSTAL_ATK_DMG := 3

const TRAP_MANA := 1
const TRAP_DMG := 4
const TRAP_RADIUS := 2

const SNIPE_MANA := 2
const SNIPE_DMG := 6
const SNIPE_MIN := 2
const SNIPE_MAX := 7

const SHOTGUN_MANA := 3
const SHOTGUN_DMG := 5
const SHOTGUN_KNOCKBACK := 1

const CANCEL_MANA := 1

const HEAL_MANA := 2
const HEAL_AMOUNT := 4
const HEAL_RADIUS := 2

const FLASH_MANA := 3
const FLASH_DMG := 4

const JUMP_MANA := 1
const JUMP_DMG := 3

const AMBUSH_MANA := 2
const AMBUSH_DMG := 5

const DASH_MANA := 3
const DASH_DMG := 4

const CRYSTAL_PASSIVE_REDUCTION := 1   # −1 урона от любого эффекта, пол 0

const ORDER_SLOTS := 4

# 4-связность (орто) — движение
const DIRS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
# диагонали
const DIRS_DIAG := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
# 8-связность — часть атак / радиус Вспышки
const DIRS8 := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


static func other_player(p: int) -> int:
	return Player.B if p == Player.A else Player.A


static func player_name(p: int) -> String:
	return "A" if p == Player.A else "B"


static func hero_name(t: int) -> String:
	match t:
		HeroType.HUNTER: return "Охотник"
		HeroType.FAIRY: return "Фея"
		HeroType.CRYSTAL: return "Кристалкайнд"
	return "?"


static func hero_glyph(t: int) -> String:
	match t:
		HeroType.HUNTER: return "О"
		HeroType.FAIRY: return "Ф"
		HeroType.CRYSTAL: return "К"
	return "?"
