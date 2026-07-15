class_name PlayerDB
extends RefCounted

## Слой доступа к БД аккаунтов (SQLite). Пароли хранятся только как соль+хэш
## (SHA-256), не в открытом виде. Остальной серверный код не видит SQL напрямую.

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
		"loadout": load_loadout(user_id), "difficulty_unlocked": load_difficulty_unlocked(user_id)}


func authenticate(login: String, password: String) -> Dictionary:
	var row := _find_user(login.strip_edges())
	if row.is_empty():
		return {"ok": false, "error": "not_found"}
	if _hash_password(password, row["salt"]) != row["pass_hash"]:
		return {"ok": false, "error": "wrong_password"}
	return {"ok": true, "user_id": row["id"], "login": row["login"], "rating": row["rating"],
		"token": create_session(row["id"]), "loadout": load_loadout(row["id"]),
		"difficulty_unlocked": load_difficulty_unlocked(row["id"])}


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
		"loadout": load_loadout(row["id"]), "difficulty_unlocked": load_difficulty_unlocked(row["id"])}


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


## Прогресс сложности «против ИИ» (старший открытый уровень, кратно Difficulty.TIER).
func save_difficulty_unlocked(user_id: int, unlocked: int) -> void:
	_write_settings(user_id, {"difficulty_unlocked": unlocked})


func load_difficulty_unlocked(user_id: int) -> int:
	return Difficulty.sanitize_unlocked(_read_settings(user_id).get("difficulty_unlocked"))


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
