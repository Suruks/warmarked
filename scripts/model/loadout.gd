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

# Дефолтная/случайная тройка: по одному каждого из базовых классов (ровно TEAM_SIZE).
const HEROES := [Consts.HeroType.HUNTER, Consts.HeroType.FAIRY, Consts.HeroType.CRYSTAL]

# Все выбираемые классы героя (секции пула в «Коллекции» + белый список валидных type при
# санитизации). Драконид доступен для набора, но в дефолтную/случайную тройку не входит.
const CLASSES := [Consts.HeroType.HUNTER, Consts.HeroType.FAIRY, Consts.HeroType.CRYSTAL,
		Consts.HeroType.DRACONID]

static var _team: Array = []   # [{type:int, skills:Array}] длиной TEAM_SIZE
# Режим «случайный бой»: игрок собрал отряд кнопкой «Рандом» и не правил руками. Тогда в
# ЛОКАЛЬНЫХ режимах сопернику ролится свой независимый случайный отряд. Сессионный (не на диск).
static var _random_battle := false


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


# ------------------------------------------------------------------ случайный отряд

static func set_random_battle(v: bool) -> void:
	_random_battle = v


static func is_random_battle() -> bool:
	return _random_battle


# Случайный отряд: ровно по одному каждого класса, случайны только скиллы.
static func random_team() -> Array:
	var out: Array = []
	for h in HEROES:
		out.append({"type": h, "skills": random_hero(h)})
	return out


# Случайный СБАЛАНСИРОВАННЫЙ кит одного героя из его пула + нейтралов. Rejection sampling по
# правилам _kit_ok (см. ниже). Не сошлось за 50 попыток → дефолтный кит класса (он тоже валиден).
static func random_hero(hero_type: int) -> Array:
	var pool: Array = []
	for s in HeroDefs.pool(hero_type):
		pool.append(int(s))
	for n in HeroDefs.neutrals():
		pool.append(int(n))
	for _attempt in 50:
		var kit := _sample3(pool)
		if _kit_ok(kit):
			return HeroDefs.sorted_by_mana(kit)
	return HeroDefs.default_skills(hero_type)


# 3 различных случайных скилла из пула.
static func _sample3(pool: Array) -> Array:
	var p := pool.duplicate()
	p.shuffle()
	return [p[0], p[1], p[2]]


# Правила баланса кита (активный = не пассивка):
#  R1 ≥1 классовый скилл (не нейтрал) — тройке нужен класс, герой тематичен;
#  R2 ≤1 пассивка — не «мёртвый» кит, ≥2 кастуемых активки;
#  R3 ≥1 активка маны ≤1 — играбельно с 1-го хода (старт маны 1);
#  R4 ≥1 активка маны ≥2 — есть содержание (не «всё по 1»);
#  R5 ≤1 активка маны ≥4 — кит подъёмен по доходу маны.
static func _kit_ok(skills: Array) -> bool:
	var passives := 0
	var has_class := false
	var cheap_active := false
	var meaty_active := false
	var expensive := 0
	for s in skills:
		var def := HeroDefs.skill_def(s)
		if not HeroDefs.is_neutral(s):
			has_class = true
		if def.passive:
			passives += 1
			continue
		if def.mana <= 1:
			cheap_active = true
		if def.mana >= 2:
			meaty_active = true
		if def.mana >= 4:
			expensive += 1
	return has_class and passives <= 1 and cheap_active and meaty_active and expensive <= 1


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
	if not (type in CLASSES):
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
