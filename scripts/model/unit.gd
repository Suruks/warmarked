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

# Метка «Охота началась» Охотника. Пока взведена, урон Охотника по этому юниту умножается. Сбрасывается в начале раунда.
var hunted: bool = false

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

# Кит: ровно SKILLS_PER_HERO id из Consts.Skill, слоты ABILITY1..3 по возрастанию маны
var skills: Array = []


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


func name_short() -> String:
	return "%s(%s)" % [Consts.hero_glyph(hero_type), Consts.player_name(owner)]


func full_name() -> String:
	return "%s %s" % [Consts.hero_name(hero_type), Consts.player_name(owner)]


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
		"hunted": hunted,
		"bleed": bleed_turns,
		"disoriented": disoriented,
		"no_attack": no_attack_turns,
		"slow": slow_turns,
	}
