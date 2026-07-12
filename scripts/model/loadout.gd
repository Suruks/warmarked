class_name Loadout
extends RefCounted

## Выбор скиллов игрока («Коллекция»): hero_type -> Array из SKILLS_PER_HERO id скиллов.
##
## Живёт в статике (один локальный игрок на процесс) и переживает перезапуск через user://.
## По сети едет плоским массивом, проиндексированным hero_type: [[..],[..],[..]].
##
## Сервер обязан САНИРОВАТЬ присланный клиентом кит: иначе клиент подсунет чужие/повторные
## скиллы, и авторитетный резолвер разойдётся с честным оппонентом (лок-степ сломается).

const PATH := "user://loadout.cfg"

const HEROES := [Consts.HeroType.HUNTER, Consts.HeroType.FAIRY, Consts.HeroType.CRYSTAL]

static var _chosen: Dictionary = {}


# ------------------------------------------------------------------ локальный выбор

static func get_skills(hero_type: int) -> Array:
	if not _chosen.has(hero_type):
		_chosen[hero_type] = HeroDefs.default_skills(hero_type)
	return (_chosen[hero_type] as Array).duplicate()


static func set_skills(hero_type: int, skills: Array) -> void:
	_chosen[hero_type] = sanitize_hero(hero_type, skills)


# hero_type -> skills, как этого ждёт MatchState.setup
static func all() -> Dictionary:
	var d := {}
	for h in HEROES:
		d[h] = get_skills(h)
	return d


# ------------------------------------------------------------------ сеть

static func to_net() -> Array:
	var out: Array = []
	for h in HEROES:
		out.append(get_skills(h))
	return out


static func defaults_net() -> Array:
	var out: Array = []
	for h in HEROES:
		out.append(HeroDefs.default_skills(h))
	return out


# Любая аномалия в присланных данных -> кит героя по умолчанию (не роняем матч).
static func sanitize_net(data: Variant) -> Array:
	var arr: Array = data if typeof(data) == TYPE_ARRAY else []
	var out: Array = []
	for h in HEROES:
		out.append(sanitize_hero(h, arr[h] if h < arr.size() else null))
	return out


static func dict_from_net(data: Variant) -> Dictionary:
	var arr := sanitize_net(data)
	var d := {}
	for h in HEROES:
		d[h] = arr[h]
	return d


# Ровно SKILLS_PER_HERO различных скиллов из пула героя, иначе — дефолт.
static func sanitize_hero(hero_type: int, skills: Variant) -> Array:
	if typeof(skills) != TYPE_ARRAY:
		return HeroDefs.default_skills(hero_type)
	var p := HeroDefs.pool(hero_type)
	var out: Array = []
	for s in skills:
		# в кит героя годятся его классовые скиллы ИЛИ нейтральные
		if typeof(s) == TYPE_INT and (s in p or HeroDefs.is_neutral(s)) and not (s in out):
			out.append(s)
	if out.size() != Consts.SKILLS_PER_HERO:
		return HeroDefs.default_skills(hero_type)
	return out


# ------------------------------------------------------------------ диск

static func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for h in HEROES:
		var v: Variant = cfg.get_value("loadout", str(h), null)
		if v != null:
			_chosen[h] = sanitize_hero(h, v)


static func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	for h in HEROES:
		cfg.set_value("loadout", str(h), get_skills(h))
	cfg.save(PATH)
