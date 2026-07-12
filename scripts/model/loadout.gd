class_name Loadout
extends RefCounted

## Выбор отряда игрока («Коллекция»): ОТРЯД из TEAM_SIZE бойцов. Каждый боец — {type, skills},
## где type — класс героя (можно повторять: хоть три Охотника), skills — SKILLS_PER_HERO id.
##
## Живёт в статике (один локальный игрок на процесс) и переживает перезапуск через user://.
## По сети едет массивом слотов, каждый слот — плоский [type, s1, s2, s3].
##
## Сервер обязан САНИРОВАТЬ присланный клиентом отряд: иначе клиент подсунет чужие/повторные
## скиллы или несуществующий класс, и авторитетный резолвер разойдётся с честным оппонентом.

const PATH := "user://loadout.cfg"
const TEAM_SIZE := 3

# Классы для секций пула в «Коллекции» (не состав отряда — тот теперь свободный).
const HEROES := [Consts.HeroType.HUNTER, Consts.HeroType.FAIRY, Consts.HeroType.CRYSTAL]

static var _team: Array = []   # [{type:int, skills:Array}] длиной TEAM_SIZE


# ------------------------------------------------------------------ локальный выбор

static func _default_team() -> Array:
	var out: Array = []
	for h in HEROES:
		out.append({"type": h, "skills": HeroDefs.default_skills(h)})
	return out


# Копия текущего отряда (или дефолт, если ещё не задан/битый).
static func get_team() -> Array:
	if _team.size() != TEAM_SIZE:
		_team = _default_team()
	var out: Array = []
	for e in _team:
		out.append({"type": int(e.type), "skills": (e.skills as Array).duplicate()})
	return out


static func set_team(team: Array) -> void:
	_team = _sanitize_team(team)


# hero_type -> skills для одного класса (дефолтные скиллы класса). Нужен «Коллекции»
# как стартовое наполнение секций и совместимости.
static func default_hero_skills(hero_type: int) -> Array:
	return HeroDefs.default_skills(hero_type)


# ------------------------------------------------------------------ сеть

# Отряд плоским массивом слотов: [[type, s1, s2, s3], ...] — только int, дружелюбно к RPC.
static func team_net() -> Array:
	return _team_to_net(get_team())


static func default_team_net() -> Array:
	return _team_to_net(_default_team())


static func _team_to_net(team: Array) -> Array:
	var out: Array = []
	for e in team:
		var row: Array = [int(e.type)]
		for s in e.skills:
			row.append(int(s))
		out.append(row)
	return out


# Присланные байты → канонический сетевой отряд (санированный, снова [type,s1,s2,s3]).
# Сервер хранит именно его, чтобы обе стороны собрали идентичный матч из одинаковых данных.
static func canon_team_net(data: Variant) -> Array:
	return _team_to_net(_sanitize_team(data))


# Присланные байты → отряд для MatchState.setup: массив {type, skills} длиной TEAM_SIZE.
static func sanitize_team_net(data: Variant) -> Array:
	return _sanitize_team(data)


# Любая аномалия в слоте → дефолтный боец на этой позиции (матч не роняем, лок-степ держим).
static func _sanitize_team(data: Variant) -> Array:
	var arr: Array = data if typeof(data) == TYPE_ARRAY else []
	var defs := _default_team()
	var out: Array = []
	for i in TEAM_SIZE:
		out.append(_sanitize_slot(arr[i] if i < arr.size() else null, defs[i]))
	return out


# Слот принимается как {type, skills} ИЛИ как плоский [type, s1, s2, s3].
static func _sanitize_slot(entry: Variant, fallback: Dictionary) -> Dictionary:
	var type: int = -1
	var skills: Variant = null
	if typeof(entry) == TYPE_DICTIONARY:
		type = int(entry.get("type", -1)) if typeof(entry.get("type")) == TYPE_INT else -1
		skills = entry.get("skills")
	elif typeof(entry) == TYPE_ARRAY and (entry as Array).size() >= 1 and typeof(entry[0]) == TYPE_INT:
		type = int(entry[0])
		skills = (entry as Array).slice(1)
	if not (type in HEROES):
		return {"type": int(fallback.type), "skills": (fallback.skills as Array).duplicate()}
	return {"type": type, "skills": sanitize_hero(type, skills)}


# ------------------------------------------------------------------ санитайз кита одного бойца

# Ровно SKILLS_PER_HERO различных скиллов из пула класса (или нейтральных), иначе — дефолт класса.
static func sanitize_hero(hero_type: int, skills: Variant) -> Array:
	if typeof(skills) != TYPE_ARRAY:
		return HeroDefs.default_skills(hero_type)
	var p := HeroDefs.pool(hero_type)
	var out: Array = []
	for s in skills:
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
	var raw: Variant = cfg.get_value("loadout", "team", null)
	if raw != null:
		_team = _sanitize_team(raw)


static func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("loadout", "team", team_net())
	cfg.save(PATH)
