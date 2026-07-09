class_name Icons
extends RefCounted

## Кэш текстур героев и скиллов. Пути соответствуют PNG в корне проекта.

static var _cache := {}


static func tex(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


const DIR := "res://graphics/"


static func grave() -> Texture2D:
	return tex(DIR + "grave.png")


static func cancel() -> Texture2D:
	return tex(DIR + "cancel.png")


static func hero(hero_type: int) -> Texture2D:
	match hero_type:
		Consts.HeroType.HUNTER: return tex(DIR + "hunter.png")
		Consts.HeroType.FAIRY: return tex(DIR + "fairy.png")
		Consts.HeroType.CRYSTAL: return tex(DIR + "crystalkind.png")
	return null


# Иконка действия (ход / базовая атака / способность). Пустой слот → null.
static func skill(hero_type: int, action: int) -> Texture2D:
	if action == Consts.Action.MOVE:
		return tex(DIR + "move.png")
	if action == Consts.Action.ATTACK:
		match hero_type:
			Consts.HeroType.HUNTER: return tex(DIR + "shot.png")
			Consts.HeroType.FAIRY: return tex(DIR + "wisp.png")
			Consts.HeroType.CRYSTAL: return tex(DIR + "claws.png")
		return tex(DIR + "base_attack.png")
	if action == Consts.Action.EMPTY:
		return null
	var idx := action - Consts.Action.ABILITY1   # 0..2
	match hero_type:
		Consts.HeroType.HUNTER:
			return tex([DIR + "trap.png", DIR + "snipe.png", DIR + "shotgun.png"][idx])
		Consts.HeroType.FAIRY:
			return tex([DIR + "magic_shield.png", DIR + "heal.png", DIR + "flash.png"][idx])
		Consts.HeroType.CRYSTAL:
			return tex([DIR + "jump.png", DIR + "ambush.png", DIR + "charge.png"][idx])
	return null
