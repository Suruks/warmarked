class_name PlayerDB
extends RefCounted

## Слой доступа к БД аккаунтов (SQLite). Пароли хранятся только как соль+хэш
## (SHA-256), не в открытом виде. Остальной серверный код не видит SQL напрямую.

const LEADERBOARD_SIZE := 20   # сколько строк таблицы рекордов уезжает клиентам

var _db: SQLite


func open(path: String) -> void:
	_db = SQLite.new()
	_db.path = path
	_db.foreign_keys = true
	_db.open_db()
	_create_tables()


func close() -> void:
	if _db != null:
		_db.close_db()
		_db = null


func register(login: String, password: String) -> Dictionary:
	login = login.strip_edges()
	if login.is_empty() or password.is_empty():
		return {"ok": false, "error": "empty_fields"}
	if not _find_user(login).is_empty():
		return {"ok": false, "error": "login_taken"}
	var salt := Crypto.new().generate_random_bytes(16).hex_encode()
	var pass_hash := _hash_password(password, salt)
	var now := int(Time.get_unix_time_from_system())
	_db.query_with_bindings(
		"INSERT INTO users (login, pass_hash, salt, rating, created_at) VALUES (?, ?, ?, 1000, ?);",
		[login, pass_hash, salt, now])
	var user_id: int = _db.last_insert_rowid
	_db.query_with_bindings("INSERT INTO player_settings (user_id, data) VALUES (?, '{}');", [user_id])
	return {"ok": true, "user_id": user_id, "login": login, "rating": 1000, "token": create_session(user_id),
		"loadout": load_loadout(user_id), "difficulty_unlocked": load_difficulty_unlocked(user_id),
		"ai_best": load_ai_best(user_id), "settings": load_settings(user_id)}


func authenticate(login: String, password: String) -> Dictionary:
	var row := _find_user(login.strip_edges())
	if row.is_empty():
		return {"ok": false, "error": "not_found"}
	if _hash_password(password, row["salt"]) != row["pass_hash"]:
		return {"ok": false, "error": "wrong_password"}
	return {"ok": true, "user_id": row["id"], "login": row["login"], "rating": row["rating"],
		"token": create_session(row["id"]), "loadout": load_loadout(row["id"]),
		"difficulty_unlocked": load_difficulty_unlocked(row["id"]), "ai_best": load_ai_best(row["id"]),
		"settings": load_settings(row["id"])}


## Выдаёт новый непрозрачный токен «запомнить меня» для user_id (клиент хранит его
## на диске и предъявляет через resume_session вместо повторного пароля).
func create_session(user_id: int) -> String:
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	var now := int(Time.get_unix_time_from_system())
	_db.query_with_bindings(
		"INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?);", [token, user_id, now])
	return token


func resume_session(token: String) -> Dictionary:
	_db.query_with_bindings(
		"""SELECT users.id AS id, users.login AS login, users.rating AS rating
		FROM sessions JOIN users ON users.id = sessions.user_id
		WHERE sessions.token = ?;""", [token])
	var rows: Array = _db.query_result
	if rows.is_empty():
		return {"ok": false, "error": "invalid_session"}
	var row: Dictionary = rows[0]
	return {"ok": true, "user_id": row["id"], "login": row["login"], "rating": row["rating"], "token": token,
		"loadout": load_loadout(row["id"]), "difficulty_unlocked": load_difficulty_unlocked(row["id"]),
		"ai_best": load_ai_best(row["id"]), "settings": load_settings(row["id"])}


func logout(token: String) -> void:
	_db.query_with_bindings("DELETE FROM sessions WHERE token = ?;", [token])


## Сохраняет текущий отряд игрока (team_net-массив, см. Loadout.canon_team_net) —
## переживает переустановку клиента, следует за аккаунтом, а не за диском.
func save_loadout(user_id: int, team_net: Array) -> void:
	_write_settings(user_id, {"loadout": team_net})


## Санируем и здесь (не только при записи в save_loadout) — БД тоже внешний источник данных,
## поэтому свежий аккаунт (ещё нет сохранённого отряда) получает готовый дефолтный team_net,
## а не пустышку, которую каждому вызывающему пришлось бы досанировать самому.
func load_loadout(user_id: int) -> Array:
	return Loadout.canon_team_net(_ints_from_json(_read_settings(user_id).get("loadout")))


## Настройки игрока (громкость и пр., см. Settings). Ключ "settings" внутри блоба
## player_settings.data — блоб хранит ВСЁ, что привязано к аккаунту (отряд, прогресс,
## настройки), поэтому имя таблицы шире, чем эта одна настройка.
func save_settings(user_id: int, settings: Variant) -> void:
	_write_settings(user_id, {"settings": Settings.sanitize_net(settings)})


func load_settings(user_id: int) -> Dictionary:
	return Settings.sanitize_net(_read_settings(user_id).get("settings"))


## Прогресс сложности «против ИИ» (старший открытый уровень, кратно Difficulty.TIER). Пишется
## ТОЛЬКО сервером по исходу боя, который он сам же и отрезолвил (Net._finish_ai_match): клиент
## своим прогрессом не распоряжается, иначе он бы просто объявил себе открытым весь диапазон.
func save_difficulty_unlocked(user_id: int, unlocked: int) -> void:
	_write_settings(user_id, {"difficulty_unlocked": unlocked})


func load_difficulty_unlocked(user_id: int) -> int:
	return Difficulty.sanitize_unlocked(_read_settings(user_id).get("difficulty_unlocked"))


## Победа над ИИ на уровне level. Рекорд обновляется, только если уровень СТРОГО выше уже
## записанного (лидерборд двигают личные рекорды, а не каждая победа) — тогда вместе с ним
## пишется отряд, которым игрок этот рекорд взял. Возвращает true, если рекорд обновился
## (сервер по этому признаку решает, рассылать ли всем новый лидерборд).
##
## Отряд — приватные данные: он не выходит из этой таблицы, `leaderboard()` его не отдаёт.
##
## level приходит от клиента, поэтому нештатное значение здесь ОТКЛОНЯЕТСЯ, а не зажимается
## в диапазон (как Difficulty.sanitize_best делает для показа): зажатие превратило бы «level:
## 999» от враждебного клиента в честный рекорд MAX_LEVEL на вершине лидерборда.
func record_ai_win(user_id: int, level: Variant, team_net: Array) -> bool:
	if typeof(level) != TYPE_INT:
		return false
	var lvl: int = level
	if lvl < Difficulty.MIN_LEVEL or lvl > Difficulty.MAX_LEVEL:
		return false
	if lvl <= load_ai_best(user_id):
		return false
	var now := int(Time.get_unix_time_from_system())
	var loadout := JSON.stringify(Loadout.canon_team_net(team_net))
	# INSERT OR REPLACE, а не UPDATE: у игрока может ещё не быть строки (первая победа).
	_db.query_with_bindings(
		"INSERT OR REPLACE INTO ai_records (user_id, best_level, loadout, updated_at) VALUES (?, ?, ?, ?);",
		[user_id, lvl, loadout, now])
	return true


## Что победа над ИИ на уровне level делает с аккаунтом: личный рекорд (+ отряд, которым он взят)
## и прогресс открытых уровней. Оба решения живут здесь, а не в транспорте: считают их одни и те
## же данные из БД, а вызывает — сервер, по СВОЕМУ резолву матча (Net._finish_ai_match).
## Возвращает {record, unlock} — что именно изменилось (это и покажет игроку экран победы).
func apply_ai_win(user_id: int, level: Variant, team_net: Array) -> Dictionary:
	var out := {"record": false, "unlock": false}
	# Победы на неоткрытом (или нештатном) уровне быть не могло: сервер такой бой не начинает.
	if not Difficulty.playable(level, load_difficulty_unlocked(user_id)):
		return out
	out["record"] = record_ai_win(user_id, level, team_net)
	var unlocked := load_difficulty_unlocked(user_id)
	var next := Difficulty.unlocked_after_win(unlocked, level)
	if next != unlocked:
		save_difficulty_unlocked(user_id, next)
		out["unlock"] = true
	return out


func load_ai_best(user_id: int) -> int:
	_db.query_with_bindings("SELECT best_level FROM ai_records WHERE user_id = ?;", [user_id])
	var rows: Array = _db.query_result
	return Difficulty.sanitize_best(rows[0]["best_level"]) if not rows.is_empty() else 0


## Публичная таблица рекордов: [{login, level}], лучшие сверху. При равном уровне выше тот, кто
## взял его раньше; у попавших в одну секунду (updated_at — целые секунды) порядок разрешает
## user_id — иначе сортировка была бы неустойчивой и таблица прыгала бы между запросами.
## Отряд игрока сюда НЕ попадает — он приватен (см. record_ai_win).
func leaderboard(limit: int = LEADERBOARD_SIZE) -> Array:
	_db.query_with_bindings(
		"""SELECT users.login AS login, ai_records.best_level AS best_level
		FROM ai_records JOIN users ON users.id = ai_records.user_id
		ORDER BY ai_records.best_level DESC, ai_records.updated_at ASC, ai_records.user_id ASC
		LIMIT ?;""", [limit])
	var out: Array = []
	for row in _db.query_result:
		out.append({"login": String(row["login"]), "level": int(row["best_level"])})
	return out


## Отряд, которым игрок взял свой рекорд (пусто, если побед ещё нет). Только для серверной
## аналитики: в лидерборд и вообще к клиентам эти данные не уходят.
func load_ai_record_loadout(user_id: int) -> Array:
	_db.query_with_bindings("SELECT loadout FROM ai_records WHERE user_id = ?;", [user_id])
	var rows: Array = _db.query_result
	if rows.is_empty():
		return []
	return Loadout.canon_team_net(_ints_from_json(JSON.parse_string(String(rows[0]["loadout"]))))


## Обе настройки (отряд, сложность) живут в одном JSON-блобе player_settings.data — читаем
## текущий блоб и точечно подменяем только переданные ключи, иначе сохранение одной настройки
## затирало бы другую (INSERT/UPDATE всей колонки целиком).
func _read_settings(user_id: int) -> Dictionary:
	_db.query_with_bindings("SELECT data FROM player_settings WHERE user_id = ?;", [user_id])
	var rows: Array = _db.query_result
	if rows.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(String(rows[0]["data"]))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _write_settings(user_id: int, patch: Dictionary) -> void:
	var settings := _read_settings(user_id)
	for k in patch:
		settings[k] = patch[k]
	_db.query_with_bindings(
		"UPDATE player_settings SET data = ? WHERE user_id = ?;",
		[JSON.stringify(settings), user_id])


## JSON не различает int/float по значению — приводим числа к int до санитайзера, иначе
## Loadout._sanitize_slot (строгий typeof(...) == TYPE_INT) молча отбросит валидный сохранённый
## отряд как «битый по типу» и подставит дефолт.
func _ints_from_json(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for row in raw:
		if typeof(row) != TYPE_ARRAY:
			continue
		var r: Array = []
		for v in row:
			r.append(int(v) if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) else v)
		out.append(r)
	return out


func _find_user(login: String) -> Dictionary:
	_db.query_with_bindings(
		"SELECT id, login, pass_hash, salt, rating FROM users WHERE login = ?;", [login])
	var rows: Array = _db.query_result
	return rows[0] if not rows.is_empty() else {}


func _hash_password(password: String, salt: String) -> String:
	return (password + salt).sha256_text()


func _create_tables() -> void:
	_db.create_table("users", {
		"id": {"data_type": "int", "primary_key": true, "auto_increment": true},
		"login": {"data_type": "text", "not_null": true, "unique": true},
		"pass_hash": {"data_type": "text", "not_null": true},
		"salt": {"data_type": "text", "not_null": true},
		"rating": {"data_type": "int", "not_null": true, "default": 1000},
		"created_at": {"data_type": "int", "not_null": true},
	})
	_db.create_table("player_settings", {
		"user_id": {"data_type": "int", "primary_key": true, "foreign_key": "users.id"},
		"data": {"data_type": "text", "not_null": true, "default": "'{}'"},
	})
	_db.create_table("sessions", {
		"token": {"data_type": "text", "primary_key": true},
		"user_id": {"data_type": "int", "not_null": true, "foreign_key": "users.id"},
		"created_at": {"data_type": "int", "not_null": true},
	})
	# Рекорд игрока против ИИ + отряд, которым он взят. Одна строка на игрока: рекорд —
	# это максимум, история попыток не нужна. loadout приватен (клиентам не отдаётся).
	_db.create_table("ai_records", {
		"user_id": {"data_type": "int", "primary_key": true, "foreign_key": "users.id"},
		"best_level": {"data_type": "int", "not_null": true, "default": 0},
		"loadout": {"data_type": "text", "not_null": true, "default": "'[]'"},
		"updated_at": {"data_type": "int", "not_null": true},
	})
	_db.create_table("player_collection", {
		"user_id": {"data_type": "int", "primary_key": true, "foreign_key": "users.id"},
		"item_id": {"data_type": "int", "primary_key": true},
		"unlocked_at": {"data_type": "int", "not_null": true},
	})
	_db.create_table("match_history", {
		"id": {"data_type": "int", "primary_key": true, "auto_increment": true},
		"player_a": {"data_type": "int", "foreign_key": "users.id"},
		"player_b": {"data_type": "int", "foreign_key": "users.id"},
		"winner": {"data_type": "int"},
		"played_at": {"data_type": "int", "not_null": true},
	})
