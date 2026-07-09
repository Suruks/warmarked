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

var alive: bool = true
var dead_timer: int = 0     # раундов до попытки респа (0 = не мёртв / готов к респу)
var death_cell: Vector2i = Vector2i(-1, -1)

# Активен ЭТОТ раунд (выставляется из immobilize_pending в начале раунда)
var immobilized: bool = false
# Взведено во время разрешения, станет активным immobilized в начале следующего раунда
var immobilize_pending: bool = false

# Щит Феи (Отмена). Взводится во время разрешения, гасит следующий эффект. Сбрасывается в начале раунда.
var shield_armed: bool = false


func _init(p_id: int, p_owner: int, p_hero_type: int, p_cell: Vector2i) -> void:
	id = p_id
	owner = p_owner
	hero_type = p_hero_type
	cell = p_cell
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
	}
