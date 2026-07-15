extends SceneTree

## Проверки слоя аккаунтов (PlayerDB / SQLite): регистрация, логин, коллизии.
## Запуск:
##   godot --headless --path E:\dev\warmarked --script res://tests/db_test.gd

const DB_PATH := "user://db_test.db"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("=== Warmarked db tests ===")
	_wipe_db_file()
	test_register_and_login()
	test_duplicate_login_rejected()
	test_wrong_password_rejected()
	test_unknown_login_rejected()
	test_session_resume()
	test_invalid_session_rejected()
	test_logout_revokes_session()
	test_loadout_defaults_for_fresh_account()
	test_loadout_round_trip()
	_wipe_db_file()
	print("=== Итог: %d PASS, %d FAIL ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(c: bool, label: String) -> void:
	if c:
		_pass += 1
		print("  PASS  " + label)
	else:
		_fail += 1
		print("  FAIL  " + label)


func _wipe_db_file() -> void:
	var real_path := ProjectSettings.globalize_path(DB_PATH)
	if FileAccess.file_exists(real_path):
		DirAccess.remove_absolute(real_path)


func _fresh_db() -> PlayerDB:
	_wipe_db_file()
	var db := PlayerDB.new()
	db.open(DB_PATH)
	return db


func test_register_and_login() -> void:
	var db := _fresh_db()
	var reg := db.register("alice", "hunter2")
	_check(reg["ok"] == true, "регистрация нового логина проходит")
	var log_in := db.authenticate("alice", "hunter2")
	_check(log_in["ok"] == true and log_in["user_id"] == reg["user_id"], "логин с верным паролем даёт тот же user_id")
	db.close()


func test_duplicate_login_rejected() -> void:
	var db := _fresh_db()
	db.register("bob", "pw1")
	var dup := db.register("bob", "pw2")
	_check(dup["ok"] == false and dup["error"] == "login_taken", "повторная регистрация того же логина отклоняется")
	db.close()


func test_wrong_password_rejected() -> void:
	var db := _fresh_db()
	db.register("carol", "correct")
	var bad := db.authenticate("carol", "incorrect")
	_check(bad["ok"] == false and bad["error"] == "wrong_password", "неверный пароль отклоняется")
	db.close()


func test_unknown_login_rejected() -> void:
	var db := _fresh_db()
	var res := db.authenticate("nobody", "whatever")
	_check(res["ok"] == false and res["error"] == "not_found", "несуществующий логин отклоняется")
	db.close()


func test_session_resume() -> void:
	var db := _fresh_db()
	var reg := db.register("dave", "pw")
	_check(not String(reg["token"]).is_empty(), "регистрация выдаёт токен сессии")
	var resumed := db.resume_session(reg["token"])
	_check(resumed["ok"] == true and resumed["user_id"] == reg["user_id"] and resumed["login"] == "dave",
		"resume_session по токену регистрации восстанавливает того же игрока")
	var log_in := db.authenticate("dave", "pw")
	var resumed2 := db.resume_session(log_in["token"])
	_check(resumed2["ok"] == true and resumed2["user_id"] == reg["user_id"],
		"resume_session по токену логина тоже восстанавливает игрока")
	db.close()


func test_invalid_session_rejected() -> void:
	var db := _fresh_db()
	var res := db.resume_session("не существующий токен")
	_check(res["ok"] == false and res["error"] == "invalid_session", "неизвестный токен сессии отклоняется")
	db.close()


func test_logout_revokes_session() -> void:
	var db := _fresh_db()
	var reg := db.register("erin", "pw")
	db.logout(reg["token"])
	var res := db.resume_session(reg["token"])
	_check(res["ok"] == false and res["error"] == "invalid_session", "после logout токен больше не работает")
	db.close()


func test_loadout_defaults_for_fresh_account() -> void:
	var db := _fresh_db()
	var reg := db.register("frank", "pw")
	var loaded: Array = db.load_loadout(reg["user_id"])
	_check(loaded == Loadout.default_team_net(), "свежий аккаунт получает дефолтный отряд, а не пустышку")
	_check(reg["loadout"] == loaded, "register() уже отдаёт тот же отряд, что и load_loadout")
	db.close()


func test_loadout_round_trip() -> void:
	var db := _fresh_db()
	var reg := db.register("grace", "pw")
	var custom_team: Array = Loadout.canon_team_net(Loadout.random_team())
	db.save_loadout(reg["user_id"], custom_team)
	var loaded: Array = db.load_loadout(reg["user_id"])
	_check(loaded == custom_team, "сохранённый отряд читается обратно без изменений (в т.ч. типы после JSON)")
	var relog := db.authenticate("grace", "pw")
	_check(relog["loadout"] == custom_team, "authenticate() тоже отдаёт сохранённый отряд")
	db.close()
	# переоткрытие того же файла БД — отряд должен пережить закрытие соединения
	var db2 := PlayerDB.new()
	db2.open(DB_PATH)
	var reopened := db2.resume_session(relog["token"])
	_check(reopened["loadout"] == custom_team, "отряд переживает переоткрытие БД")
	db2.close()
