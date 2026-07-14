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
