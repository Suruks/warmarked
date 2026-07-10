class_name Consts
extends RefCounted

## Глобальные константы и перечисления прототипа Warmarked.
## Все «дайлы» дизайна (цифры, помеченные в доке как крутибельные) собраны здесь,
## чтобы дизайнер мог править баланс в одном месте.

enum Player { A, B }
enum HeroType { HUNTER, FAIRY, CRYSTAL }

# Глобальный каталог скиллов. Герой берёт в бой SKILLS_PER_HERO штук из своего пула
# (HeroDefs.pool). Резолвер/таргетинг диспетчеризуются по этому id, а не по индексу слота,
# поэтому набор скиллов можно менять, не трогая логику.
enum Skill {
	TRAP, SNIPE, SHOTGUN,                 # Охотник
	CANCEL, HEAL, FLASH,                  # Фея
	JUMP, AMBUSH, DASH,                   # Кристалкайнд — базовые
	ONSLAUGHT, CRYSTAL_SHOT, REFLEXES,    # Кристалкайнд — расширение пула
}

const SKILLS_PER_HERO := 3

# Действие в слоте приказа. PASS — явное «нет действия» (занимает слот, но резолвится в пустоту;
# нужно, чтобы соперник не видел, что слот пуст). В приказ уходит как пустой.
enum Action { EMPTY, MOVE, ATTACK, ABILITY1, ABILITY2, ABILITY3, PASS }

# Типы событий разрешения (для лога и подсветки)
enum EventType {
	INFO, MOVE, ATTACK, ABILITY, DAMAGE, HEAL, DEATH, KILL,
	RESPAWN, RESPAWN_BLOCKED, TRAP_PLACED, TRAP_TRIGGER,
	AMBUSH_ARMED, AMBUSH_TRIGGER, SHIELD_ARMED, SHIELD_ABSORB,
	COLLISION, KNOCKBACK, IMMOBILIZE, FIZZLE, MANA, SCORE,
	REFLEX_ARMED, REFLEX_DODGE,
}

# --- Поле ---
const BOARD_W := 7
const BOARD_H := 7

# --- Матч ---
const WIN_SCORE := 7
# Килл — это ТЕМП, а не победа: пока враг лежит, вы и так забираете точки. Прямая награда
# держится маленькой, иначе килл суммарно стоит больше половины матча.
const KILL_POINTS := 1
const CONTROL_POINTS_PER_ROUND := 1   # мажоритарная награда, кэп +1/раунд

# --- Юниты ---
const MOVE_RANGE := 2
const START_MANA := 1
const COLLISION_DMG := 3               # о край / стену / юнит (§7.1)
# Убитый в раунде N возвращается в начале N+RESPAWN_DELAY, т.е. пропускает (DELAY-1) полных
# раундов. 2 → теряет остаток своего раунда и один следующий. Цена смерти — ещё и сброс маны.
const RESPAWN_DELAY := 2
const PERSIST_ROUNDS := 0              # капкан/засада живут раунд размещения + столько раундов (0 = только этот раунд)

# --- Способности: мана и урон (дайлы §9) ---
# Спред HP разведён по-настоящему: разница в 1-2 HP ниже разрешающей способности чисел урона
# и не создаёт ни одного осмысленного порога. Кристалкайнд без пассивки держится за счёт HP.
const HUNTER_HP := 9
const FAIRY_HP := 11
const CRYSTAL_HP := 15

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

const CANCEL_MANA := 2

const HEAL_MANA := 3
const HEAL_AMOUNT := 5
const HEAL_RADIUS := 2

const FLASH_MANA := 2
const FLASH_DMG := 4

const JUMP_MANA := 1
const JUMP_DMG := 3

const AMBUSH_MANA := 2
const AMBUSH_DMG := 5

const DASH_MANA := 3
const DASH_DMG := 4

# Натиск: бьёт соседа, отбрасывает его и занимает освободившуюся клетку
const ONSLAUGHT_MANA := 2
const ONSLAUGHT_DMG := 3

# Отстрел кристаллов: первый юнит на каждой из 4 диагоналей (по своим тоже)
const CRYSTAL_SHOT_MANA := 2
const CRYSTAL_SHOT_DMG := 3

# Рефлексы: стойка; соседний враг целит в эту клетку -> отступить на 1 и получить ману
const REFLEXES_MANA := 1
const REFLEXES_MANA_GAIN := 1

const CRYSTAL_PASSIVE_REDUCTION := 0   # пассивка снята (0 = без снижения урона)

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
