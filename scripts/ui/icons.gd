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
	Consts.Skill.SPIKES: "crystal_shot.png",   # переиспользуем существующий арт (диагональная тема)
	Consts.Skill.REFLEXES: "reflexes.png",
	Consts.Skill.HARDENING: "hardening.png",   # арт ещё не нарисован -> заглушка
	Consts.Skill.SHARDS: "shards.png",
	Consts.Skill.OVERLOAD: "overload.png",
	Consts.Skill.SWAP: "swap.png",
	Consts.Skill.PRECISE: "precise_shot.png",
	Consts.Skill.HUNT_MARK: "hunter_mark.png",
	Consts.Skill.RETREAT: "retreat.png",
	Consts.Skill.NET: "net.png",
	Consts.Skill.DEATHCROSS: "death_cross.png",
	Consts.Skill.MINEFIELD: "minefield.png",
	Consts.Skill.BLEED: "bleed.png",
	Consts.Skill.SPARK: "spark.png",
	Consts.Skill.DISORIENT: "disorient.png",
	Consts.Skill.MANASTEAL: "manasteal.png",
	Consts.Skill.SHACKLES: "shackles.png",
	Consts.Skill.SLOW: "slow.png",
	Consts.Skill.TELEPORT: "teleport.png",
	Consts.Skill.REVIVE: "revive.png",
	Consts.Skill.LIGHTNING: "lightning.png",
	Consts.Skill.SNIPER: "sniper.png",
	Consts.Skill.COLD_BLOOD: "cold_blood.png",
	Consts.Skill.BLESSING: "blessing.png",
	Consts.Skill.LIGHTNESS: "lightness.png",
	Consts.Skill.CRYSTAL_SHELL: "crystal_shell.png",
	Consts.Skill.DEATH_NOVA: "death_nova.png",
	Consts.Skill.PUSH: "push.png",
	Consts.Skill.STEP: "step.png",
	Consts.Skill.BLOCK: "block.png",
	Consts.Skill.SWAP_ALLY: "swap_ally.png",
	Consts.Skill.SELF_HEAL: "self_heal.png",
	Consts.Skill.MEDITATION: "meditation.png",
	Consts.Skill.KNOCKDOWN: "knockdown.png",   # арт ещё не нарисован -> заглушка
	Consts.Skill.GUST: "wind_blow.png",
	Consts.Skill.HOOK: "hook.png",
}


static func grave() -> Texture2D:
	return tex(DIR + "grave.png")


static func cancel() -> Texture2D:
	return tex(DIR + "cancel.png")


# Иконка дебаффа по имени файла (нет файла -> null, не рисуется)
static func effect(file: String) -> Texture2D:
	return tex_opt(DIR + file)


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
