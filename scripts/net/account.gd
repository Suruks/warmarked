class_name Account
extends RefCounted

## Локальное хранилище сессии игрока (user://account.cfg) — логин и токен
## «запомнить меня», выданный сервером, чтобы не вводить пароль при каждом запуске.

const PATH := "user://account.cfg"


static func load_session() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return {}
	var login: String = cfg.get_value("account", "login", "")
	var token: String = cfg.get_value("account", "token", "")
	if login.is_empty() or token.is_empty():
		return {}
	return {"login": login, "token": token}


static func save_session(login: String, token: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("account", "login", login)
	cfg.set_value("account", "token", token)
	cfg.save(PATH)


static func clear_session() -> void:
	var real_path := ProjectSettings.globalize_path(PATH)
	if FileAccess.file_exists(real_path):
		DirAccess.remove_absolute(real_path)
