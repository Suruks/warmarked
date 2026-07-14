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
	return {"ok": true, "user_id": user_id, "rating": 1000}


func authenticate(login: String, password: String) -> Dictionary:
	var row := _find_user(login.strip_edges())
	if row.is_empty():
		return {"ok": false, "error": "not_found"}
	if _hash_password(password, row["salt"]) != row["pass_hash"]:
		return {"ok": false, "error": "wrong_password"}
	return {"ok": true, "user_id": row["id"], "rating": row["rating"]}


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
