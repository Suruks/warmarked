class_name Icons
extends RefCounted

## Кэш текстур героев и скиллов. Файлы лежат в res://graphics/.

static var _cache := {}


static func tex(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


# Как tex(), но отсутствующий файл — не ошибка, а null (UI рисует заглушку).
# Нужен для скиллов, для которых иконка ещё не нарисована.
static func tex_opt(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


const DIR := "res://graphics/"

const SKILL_FILES := {
	Consts.Skill.TRAP: "trap.png",
	Consts.Skill.SNIPE: "snipe.png",
	Consts.Skill.SHOTGUN: "shotgun.png",
	Consts.Skill.CANCEL: "magic_shield.png",
	Consts.Skill.HEAL: "heal.png",
	Consts.Skill.FLASH: "flash.png",
	Consts.Skill.JUMP: "jump.png",
	Consts.Skill.AMBUSH: "ambush.png",
	Consts.Skill.DASH: "charge.png",
	Consts.Skill.ONSLAUGHT: "onslaught.png",
	Consts.Skill.CRYSTAL_SHOT: "crystal_shot.png",
	Consts.Skill.REFLEXES: "reflexes.png",
}


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


# Иконка конкретного скилла по id
static func for_skill(skill: int) -> Texture2D:
	if not SKILL_FILES.has(skill):
		return null
	return tex_opt(DIR + SKILL_FILES[skill])


# Иконка действия (ход / базовая атака / способность). Пустой слот → null.
# skills — кит юнита; пустой массив означает кит по умолчанию.
static func action(hero_type: int, act: int, skills: Array = []) -> Texture2D:
	if act == Consts.Action.MOVE:
		return tex_opt(DIR + "move.png")
	if act == Consts.Action.ATTACK:
		match hero_type:
			Consts.HeroType.HUNTER: return tex_opt(DIR + "shot.png")
			Consts.HeroType.FAIRY: return tex_opt(DIR + "wisp.png")
			Consts.HeroType.CRYSTAL: return tex_opt(DIR + "claws.png")
		return tex_opt(DIR + "base_attack.png")
	if act >= Consts.Action.ABILITY1 and act <= Consts.Action.ABILITY3:
		return for_skill(HeroDefs.skill_of_action(hero_type, act, skills))
	return null
