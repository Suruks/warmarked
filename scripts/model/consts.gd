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
	ONSLAUGHT, SPIKES, REFLEXES,          # Кристалкайнд — расширение пула
	HARDENING, SHARDS, OVERLOAD, SWAP,    # Кристалкайнд — новые
	PRECISE, HUNT_MARK, RETREAT, NET, DEATHCROSS, MINEFIELD,   # Охотник — новые
	BLEED,                                                     # Охотник — кровавый след
	SPARK, DISORIENT, MANASTEAL, SHACKLES, SLOW,               # Фея — новые
	TELEPORT, REVIVE,                                          # Фея — телепорт и возрождение
	LIGHTNING,                                                 # Фея — молния
	SNIPER, COLD_BLOOD,                                        # Охотник — пассивки
	BLESSING, LIGHTNESS,                                       # Фея — пассивки
	CRYSTAL_SHELL, DEATH_NOVA,                                 # Кристалкайнд — пассивки
	PUSH, STEP, BLOCK, SWAP_ALLY, SELF_HEAL, MEDITATION,       # Нейтральные (любому герою)
	KNOCKDOWN,                                                 # Охотник — сбить с ног
	GUST,                                                      # Фея — дуновение ветра
	HOOK,                                                      # Нейтральный — крюк
}

const SKILLS_PER_HERO := 3

# Версия детерминированного протокола. Клиент и сервер обязаны совпадать: обе стороны
# гоняют один и тот же резолвер по обмену приказами (лок-степ), и любое расхождение в
# правилах/формате приказов/каталоге скиллов ломает синхронность незаметно.
# БАМПАТЬ при любом изменении, влияющем на резолв: цифры баланса, новые скиллы, порядок
# слотов, сериализация Order. Чисто визуальные/UI-правки версию не трогают.
const PROTOCOL_VERSION := 24

# Действие в слоте приказа. PASS — явное «нет действия» (занимает слот, но резолвится в пустоту;
# нужно, чтобы соперник не видел, что слот пуст). В приказ уходит как пустой.
# ABILITY4 — бонусный 4-й слот способности: обычный кит несёт только 3 (SKILLS_PER_HERO),
# четвёртая появляется у бойца лишь как модификатор сложности «против ИИ» (Difficulty).
enum Action { EMPTY, MOVE, ATTACK, ABILITY1, ABILITY2, ABILITY3, ABILITY4, PASS }

# Типы событий разрешения (для лога и подсветки)
enum EventType {
	INFO, MOVE, ATTACK, ABILITY, DAMAGE, HEAL, DEATH, KILL,
	RESPAWN, RESPAWN_BLOCKED, TRAP_PLACED, TRAP_TRIGGER,
	AMBUSH_ARMED, AMBUSH_TRIGGER, SHIELD_ARMED, SHIELD_ABSORB,
	COLLISION, KNOCKBACK, IMMOBILIZE, FIZZLE, MANA, SCORE,
	REFLEX_ARMED, REFLEX_DODGE,
	HARDEN_ARMED, HARDEN_BLOCK, SHARDS_ARMED,
	HUNT_MARKED, BLEED_MARKED,
	DISORIENT_MARKED, DISORIENT_TRIGGER, SHACKLE_MARKED, SLOW_MARKED,
}

# --- Поле ---
const BOARD_W := 7
const BOARD_H := 7

# --- Матч ---
const WIN_SCORE := 6
# Ничья: оба игрока набрали WIN_SCORE в одном и том же раунде (например, взаимный размен
# киллами). Отдельное значение от Player, чтобы MatchState.winner мог различить «победил A/B»
# и «оба одновременно» без спецфлага.
const DRAW := 2

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
const CRYSTAL_HP := 13

const HUNTER_ATK_DMG := 2
const FAIRY_ATK_DMG := 2
const CRYSTAL_ATK_DMG := 3

const TRAP_MANA := 1
const TRAP_DMG := 4
const TRAP_RADIUS := 2

const SNIPE_MANA := 3
const SNIPE_DMG := 6
const SNIPE_MIN := 2
const SNIPE_MAX := 7

const SHOTGUN_MANA := 4
const SHOTGUN_DMG := 5
const SHOTGUN_KNOCKBACK := 1

# --- Охотник: новые скиллы ---
# Меткий выстрел: прямое попадание строго по клетке на дальности PRECISE_RANGE (не перехватывается)
const PRECISE_MANA := 1
const PRECISE_DMG := 3
const PRECISE_RANGE := 2

# Охота началась: метка на враге на HUNT_TURNS ходов — атаки/скиллы Охотника по нему бьют на
# HUNT_BONUS_DMG сильнее (держится через раунды, как Кровавый след/Оковы/Замедление)
const HUNT_MANA := 2
const HUNT_RANGE := 4
const HUNT_TURNS := 3
const HUNT_BONUS_DMG := 2

# Отступление: если враг в соседней клетке — путь до RETREAT_RANGE клеток (относительный, как ход)
const RETREAT_MANA := 1
const RETREAT_RANGE := 3

# Ловчая сеть: мгновенно обездвиживает цель до конца раунда, без урона
const NET_MANA := 1
const NET_RANGE := 3

# Крест смерти: DEATHCROSS_DMG первому ВРАГУ на каждой из 4 ортогональных линий
const DEATHCROSS_MANA := 4
const DEATHCROSS_DMG := 5

# Минное поле: за один каст Охотник ВРУЧНУЮ размещает до MINEFIELD_COUNT мин в отдельных
# клетках радиуса MINEFIELD_RADIUS (манхэттен) вокруг себя. Мины живут до конца хода и наносят
# MINEFIELD_DMG урона ЛЮБОМУ, кто войдёт на клетку (без обездвиживания).
const MINEFIELD_MANA := 4
const MINEFIELD_COUNT := 3
const MINEFIELD_RADIUS := 2
const MINEFIELD_DMG := 5

# Сбить с ног: прямая линия KNOCKDOWN_MIN..KNOCKDOWN_MAX — первому юниту на луче KNOCKDOWN_DMG
# урона и отброс на KNOCKDOWN_PUSH клетку от Охотника (в сторону выстрела)
const KNOCKDOWN_MANA := 2
const KNOCKDOWN_DMG := 2
const KNOCKDOWN_MIN := 2
const KNOCKDOWN_MAX := 3
const KNOCKDOWN_PUSH := 1

# Кровавый след: враг в радиусе BLEED_RANGE получает эффект на BLEED_TURNS ходов;
# каждое перемещение (вход в клетку) наносит ему BLEED_DMG
const BLEED_MANA := 2
const BLEED_DMG := 2
const BLEED_TURNS := 3
const BLEED_RANGE := 2

const CANCEL_MANA := 2

const HEAL_MANA := 4
const HEAL_AMOUNT := 5
const HEAL_RADIUS := 2

const FLASH_MANA := 1
const FLASH_DMG := 3

# --- Фея: новые скиллы ---
# Искра: прямой удар по клетке на дальности до SPARK_RANGE
const SPARK_MANA := 1
const SPARK_DMG := 3
const SPARK_RANGE := 2

# Молния: как Искра, но дороже и сильнее
const LIGHTNING_MANA := 3
const LIGHTNING_DMG := 5
const LIGHTNING_RANGE := 2

# Дуновение ветра: отталкивает юнита в радиусе GUST_RANGE (8 сторон) на GUST_PUSH клеток от Феи
const GUST_MANA := 2
const GUST_RANGE := 1
const GUST_PUSH := 2

# --- Пассивные способности (занимают слот кита, но не активируются и не стоят маны) ---
const SNIPER_ATK_BONUS := 2        # Снайпер: +урон к базовой атаке
const COLD_BLOOD_MANA := 3         # Хладнокровие: +мана за килл
const BLESSING_HEAL := 1           # Благословение: лечение союзников в радиусе 1 в начале раунда
const SHELL_REDUCTION := 1         # Кристальный панцирь: первый урон за раунд меньше на столько
const DEATH_NOVA_DMG := 5          # Осколки (пассив): урон всем соседям при смерти
const LIGHTNESS_MOVE_RANGE := 3    # Лёгкость: дальность хода Феи

# --- Нейтральные скиллы (общий пул, доступны любому герою) ---
const PUSH_MANA := 1               # Толкнуть: отброс соседа на 1
const STEP_MANA := 1               # Сходить: ход
const STEP_RANGE := 2              # на сколько клеток
const BLOCK_MANA := 0              # Блок: щит-буфер
const BLOCK_AMOUNT := 3            # сколько урона поглощает Блок
const SWAP_ALLY_MANA := 1          # Рокировка: обмен местами с соседним союзником
const SELF_HEAL_MANA := 1
const SELF_HEAL_AMOUNT := 3        # Хил себе: +HP
const MEDITATION_MANA := 0
const MEDITATION_GAIN := 1         # Медитация: +мана

# Крюк: прямая линия до HOOK_RANGE — притягивает первого ВРАГА на HOOK_PULL клетку к кастеру
const HOOK_MANA := 1
const HOOK_RANGE := 2
const HOOK_PULL := 1

# Дезориентация: враг в радиусе DISORIENT_RANGE; его следующий НАПРАВЛЕННЫЙ скилл в этом
# раунде срабатывает в обратную сторону (одноразово)
const DISORIENT_MANA := 3
const DISORIENT_RANGE := 2

# Кража маны: удар по соседнему врагу — MANASTEAL_DMG урона и похищение MANASTEAL_AMOUNT маны
const MANASTEAL_MANA := 4
const MANASTEAL_DMG := 3
const MANASTEAL_AMOUNT := 3

# Оковы: враг в радиусе SHACKLES_RANGE на SHACKLES_TURNS ходов теряет базовую атаку
const SHACKLES_MANA := 3
const SHACKLES_TURNS := 3
const SHACKLES_RANGE := 2

# Замедление: враг в радиусе SLOW_RANGE на SLOW_TURNS ходов получает -SLOW_MOVE_PENALTY к дальности хода
const SLOW_MANA := 1
const SLOW_TURNS := 3
const SLOW_RANGE := 2
const SLOW_MOVE_PENALTY := 1

# Телепорт: перемещает фею на свободную клетку в радиусе TELEPORT_RANGE (сквозь препятствия/юнитов)
const TELEPORT_MANA := 2
const TELEPORT_RANGE := 2

# Возрождение: воскрешает павшего союзника (любая могила на доске) на полном HP в соседней свободной клетке
const REVIVE_MANA := 4

const JUMP_MANA := 1
const JUMP_DMG := 4

const AMBUSH_MANA := 2
const AMBUSH_DMG := 5

const DASH_MANA := 3
const DASH_DMG := 4

# Натиск: бьёт соседа, отбрасывает его и занимает освободившуюся клетку
const ONSLAUGHT_MANA := 4
const ONSLAUGHT_DMG := 5

# Острые шипы: урон по 4 диагонально-соседним клеткам (по своим тоже)
const SPIKES_MANA := 2
const SPIKES_DMG := 3

# Затвердение: стойка, снижает весь входящий урон по кристаллу на HARDENING_REDUCTION до конца раунда
const HARDENING_MANA := 2
const HARDENING_REDUCTION := 2

# Осколки: стойка, ответка каждому врагу, нанёсшему кристаллу урон в этом раунде
const SHARDS_MANA := 2
const SHARDS_DMG := 3

# Перегрузка: тратит ВСЮ ману, урон соседу за каждую потраченную ману (мин. цена OVERLOAD_MANA)
const OVERLOAD_MANA := 1
const OVERLOAD_DMG_PER_MANA := 2

# Обмен местами: swap с соседним юнитом (своим или чужим)
const SWAP_MANA := 2

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
		HeroType.CRYSTAL: return "Камнешип"
	return "?"


static func hero_glyph(t: int) -> String:
	match t:
		HeroType.HUNTER: return "О"
		HeroType.FAIRY: return "Ф"
		HeroType.CRYSTAL: return "К"
	return "?"
