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
	test_difficulty_defaults_for_fresh_account()
	test_difficulty_round_trip()
	test_loadout_and_difficulty_settings_coexist()
	test_ai_record_defaults_for_fresh_account()
	test_ai_record_only_personal_best_counts()
	test_ai_record_stores_loadout_privately()
	test_leaderboard_orders_by_level_then_time()
	test_apply_ai_win_moves_record_and_progress()
	test_apply_ai_win_rejects_locked_level()
	test_settings_defaults_for_fresh_account()
	test_settings_round_trip()
	test_settings_sanitized_on_write()
	test_settings_coexist_with_loadout_and_progress()
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


func test_difficulty_defaults_for_fresh_account() -> void:
	var db := _fresh_db()
	var reg := db.register("henry", "pw")
	_check(db.load_difficulty_unlocked(reg["user_id"]) == Difficulty.TIER,
		"свежий аккаунт: открыт только первый блок сложности (TIER)")
	_check(reg["difficulty_unlocked"] == Difficulty.TIER,
		"register() уже отдаёт тот же прогресс, что и load_difficulty_unlocked")
	db.close()


func test_difficulty_round_trip() -> void:
	var db := _fresh_db()
	var reg := db.register("iris", "pw")
	var target := Difficulty.TIER * 3
	db.save_difficulty_unlocked(reg["user_id"], target)
	_check(db.load_difficulty_unlocked(reg["user_id"]) == target, "прогресс сложности читается обратно без изменений")
	# запись не кратна TIER/вне диапазона — при чтении санируется, даже если записана напрямую
	db.save_difficulty_unlocked(reg["user_id"], 23)
	_check(db.load_difficulty_unlocked(reg["user_id"]) == 20,
		"чтение санирует прогресс до границы TIER, даже если в БД что-то нештатное")
	db.close()


# Регрессия: save_loadout/save_difficulty_unlocked живут в одном JSON-блобе player_settings.data —
# если бы каждый писал колонку целиком (а не read-modify-write), один затирал бы другого.
func test_loadout_and_difficulty_settings_coexist() -> void:
	var db := _fresh_db()
	var reg := db.register("jack", "pw")
	var custom_team: Array = Loadout.canon_team_net(Loadout.random_team())
	db.save_loadout(reg["user_id"], custom_team)
	db.save_difficulty_unlocked(reg["user_id"], Difficulty.TIER * 4)
	_check(db.load_loadout(reg["user_id"]) == custom_team, "сложность после себя не затёрла отряд")
	_check(db.load_difficulty_unlocked(reg["user_id"]) == Difficulty.TIER * 4,
		"отряд был записан первым — сложность записалась поверх, не потерявшись")
	# запись в обратном порядке — тоже не должна терять другую настройку
	var other_team: Array = Loadout.canon_team_net(Loadout.random_team())
	db.save_difficulty_unlocked(reg["user_id"], Difficulty.TIER * 2)
	db.save_loadout(reg["user_id"], other_team)
	_check(db.load_difficulty_unlocked(reg["user_id"]) == Difficulty.TIER * 2,
		"отряд после себя не затёр сложность")
	_check(db.load_loadout(reg["user_id"]) == other_team, "новый отряд сохранился")
	db.close()


func test_ai_record_defaults_for_fresh_account() -> void:
	var db := _fresh_db()
	var reg := db.register("kate", "pw")
	_check(db.load_ai_best(reg["user_id"]) == 0, "свежий аккаунт: рекорда против ИИ нет (0)")
	_check(reg["ai_best"] == 0, "register() уже отдаёт тот же рекорд, что и load_ai_best")
	_check(db.leaderboard().is_empty(), "без побед лидерборд пуст")
	db.close()


# Лидерборд двигают ЛИЧНЫЕ РЕКОРДЫ: победа на уровне не выше уже взятого его не трогает.
func test_ai_record_only_personal_best_counts() -> void:
	var db := _fresh_db()
	var reg := db.register("liam", "pw")
	var uid: int = reg["user_id"]
	var team: Array = Loadout.canon_team_net(Loadout.random_team())
	_check(db.record_ai_win(uid, 7, team) == true, "первая победа — рекорд")
	_check(db.load_ai_best(uid) == 7, "рекорд записан [%d]" % db.load_ai_best(uid))
	_check(db.record_ai_win(uid, 5, team) == false, "победа на уровне ниже рекорда — не рекорд")
	_check(db.record_ai_win(uid, 7, team) == false, "повтор того же уровня — не рекорд")
	_check(db.load_ai_best(uid) == 7, "рекорд не понизился [%d]" % db.load_ai_best(uid))
	_check(db.record_ai_win(uid, 9, team) == true, "победа выше рекорда — новый рекорд")
	_check(db.load_ai_best(uid) == 9, "рекорд поднялся до 9 [%d]" % db.load_ai_best(uid))
	# мусорный уровень от враждебного клиента не должен ни пролезать в таблицу, ни ронять сервер
	_check(db.record_ai_win(uid, 999, team) == false, "уровень выше MAX_LEVEL не принимается")
	_check(db.record_ai_win(uid, 0, team) == false, "уровень ниже MIN_LEVEL не принимается")
	_check(db.load_ai_best(uid) == 9, "мусорные уровни рекорд не изменили [%d]" % db.load_ai_best(uid))
	# рекорд переживает переоткрытие БД
	var relog := db.authenticate("liam", "pw")
	_check(relog["ai_best"] == 9, "authenticate() отдаёт сохранённый рекорд")
	db.close()
	var db2 := PlayerDB.new()
	db2.open(DB_PATH)
	_check(db2.resume_session(relog["token"])["ai_best"] == 9, "рекорд переживает переоткрытие БД")
	db2.close()


# Сборка пишется вместе с рекордом, но остаётся приватной: в лидерборде её нет.
func test_ai_record_stores_loadout_privately() -> void:
	var db := _fresh_db()
	var reg := db.register("mona", "pw")
	var uid: int = reg["user_id"]
	var team: Array = Loadout.canon_team_net(Loadout.random_team())
	db.record_ai_win(uid, 4, team)
	_check(db.load_ai_record_loadout(uid) == team, "сборка рекорда читается обратно без изменений")
	# новый рекорд — новая сборка; старая не остаётся висеть
	var team2: Array = Loadout.canon_team_net(Loadout.random_team())
	db.record_ai_win(uid, 6, team2)
	_check(db.load_ai_record_loadout(uid) == team2, "новый рекорд перезаписал сборку")
	# победа НЕ рекордом сборку не трогает — в БД остаётся та, которой рекорд и взят
	db.record_ai_win(uid, 2, Loadout.canon_team_net(Loadout.random_team()))
	_check(db.load_ai_record_loadout(uid) == team2, "не-рекорд сборку не перезаписал")
	var lb: Array = db.leaderboard()
	_check(lb.size() == 1 and lb[0]["login"] == "mona" and lb[0]["level"] == 6,
		"лидерборд отдаёт логин и уровень")
	_check(not lb[0].has("loadout"), "лидерборд НЕ отдаёт сборку игрока (приватные данные)")
	db.close()


func test_leaderboard_orders_by_level_then_time() -> void:
	var db := _fresh_db()
	var team: Array = Loadout.canon_team_net(Loadout.random_team())
	var nick := db.register("nick", "pw")
	var olga := db.register("olga", "pw")
	var pete := db.register("pete", "pw")
	db.record_ai_win(nick["user_id"], 12, team)
	db.record_ai_win(olga["user_id"], 30, team)
	db.record_ai_win(pete["user_id"], 12, team)
	var lb: Array = db.leaderboard()
	_check(lb.size() == 3, "в лидерборде все три игрока [%d]" % lb.size())
	_check(lb[0]["login"] == "olga" and lb[0]["level"] == 30, "лучший уровень — первым")
	# оба рекорда на 12 поставлены в одну секунду — порядок разрешает user_id, и он устойчив
	_check(lb[1]["login"] == "nick" and lb[2]["login"] == "pete",
		"равный уровень: порядок устойчивый (кто раньше — выше)")
	_check(db.leaderboard() == lb, "повторный запрос даёт ту же таблицу")
	# сколько строк отдавать — решает сервер; клиенту не нужен весь список
	_check(db.leaderboard(2).size() == 2, "limit ограничивает длину таблицы")
	db.close()


# Победа над ИИ глазами аккаунта: сервер зовёт apply_ai_win по СВОЕМУ резолву матча, и она одна
# решает и рекорд, и прогресс открытых уровней (см. Net._finish_ai_match).
func test_apply_ai_win_moves_record_and_progress() -> void:
	var db := _fresh_db()
	var reg := db.register("quinn", "pw")
	var uid: int = reg["user_id"]
	var team: Array = Loadout.canon_team_net(Loadout.random_team())
	var T := Difficulty.TIER

	# победа НЕ на потолке: рекорд ставит, новый блок не открывает
	var r1 := db.apply_ai_win(uid, 2, team)
	_check(r1["record"] == true and r1["unlock"] == false, "победа ниже потолка: рекорд да, блок нет")
	_check(db.load_ai_best(uid) == 2, "рекорд записан [%d]" % db.load_ai_best(uid))
	_check(db.load_difficulty_unlocked(uid) == T, "прогресс не сдвинулся [%d]" % db.load_difficulty_unlocked(uid))

	# победа на потолке: и рекорд, и следующий блок
	var r2 := db.apply_ai_win(uid, T, team)
	_check(r2["record"] == true and r2["unlock"] == true, "победа на потолке: и рекорд, и новый блок")
	_check(db.load_difficulty_unlocked(uid) == T * 2, "открылся следующий блок [%d]" % db.load_difficulty_unlocked(uid))
	_check(db.load_ai_best(uid) == T, "рекорд поднялся до потолка [%d]" % db.load_ai_best(uid))

	# повтор той же победы: ни рекорда, ни прогресса — фарм одного уровня ничего не даёт
	var r3 := db.apply_ai_win(uid, T, team)
	_check(r3["record"] == false and r3["unlock"] == false, "повтор той же победы ничего не меняет")
	_check(db.load_difficulty_unlocked(uid) == T * 2, "прогресс не убежал вперёд от повторов")

	# победа ниже уже взятого рекорда: рекорд не понижается
	db.apply_ai_win(uid, 1, team)
	_check(db.load_ai_best(uid) == T, "победа на первом уровне рекорд не понизила [%d]" % db.load_ai_best(uid))
	db.close()


# Ключевая защита: победа на уровне, который аккаунту НЕ открыт, не даёт ничего. Сервер такой
# бой и не начнёт (Difficulty.playable в req_start_ai_match), но правило продублировано в записи —
# иначе дыра в гейте сразу становилась бы рекордом на вершине лидерборда.
func test_apply_ai_win_rejects_locked_level() -> void:
	var db := _fresh_db()
	var reg := db.register("rita", "pw")
	var uid: int = reg["user_id"]
	var team: Array = Loadout.canon_team_net(Loadout.random_team())

	var res := db.apply_ai_win(uid, Difficulty.MAX_LEVEL, team)
	_check(res["record"] == false and res["unlock"] == false, "победа на закрытом уровне не даёт ничего")
	_check(db.load_ai_best(uid) == 0, "рекорд не записан [%d]" % db.load_ai_best(uid))
	_check(db.load_difficulty_unlocked(uid) == Difficulty.TIER, "прогресс не сдвинулся")
	_check(db.leaderboard().is_empty(), "в лидерборд игрок не попал")

	var junk := db.apply_ai_win(uid, "50", team)
	_check(junk["record"] == false and junk["unlock"] == false, "победа с уровнем-строкой не даёт ничего")
	_check(db.load_difficulty_unlocked(uid) == Difficulty.TIER, "мусорный уровень прогресс не сдвинул")
	db.close()


func test_settings_defaults_for_fresh_account() -> void:
	var db := _fresh_db()
	var reg := db.register("sam", "pw")
	var s: Dictionary = db.load_settings(reg["user_id"])
	_check(s["vol"] == Settings.VOLUME_DEFAULT and s["imp"] == false,
		"свежий аккаунт: настройки по умолчанию, а не пустышка")
	_check(reg["settings"] == s, "register() уже отдаёт те же настройки, что и load_settings")
	db.close()


func test_settings_round_trip() -> void:
	var db := _fresh_db()
	var reg := db.register("tina", "pw")
	var uid: int = reg["user_id"]
	db.save_settings(uid, {"vol": 0.3, "imp": true})
	var loaded: Dictionary = db.load_settings(uid)
	_check(is_equal_approx(loaded["vol"], 0.3) and loaded["imp"] == true,
		"настройки читаются обратно без изменений (в т.ч. типы после JSON)")
	var relog := db.authenticate("tina", "pw")
	_check(is_equal_approx(relog["settings"]["vol"], 0.3), "authenticate() отдаёт сохранённые настройки")
	db.close()
	# переоткрытие БД: настройки живут за аккаунтом, а не в памяти сервера
	var db2 := PlayerDB.new()
	db2.open(DB_PATH)
	var reopened := db2.resume_session(relog["token"])
	_check(is_equal_approx(reopened["settings"]["vol"], 0.3), "настройки переживают переоткрытие БД")
	db2.close()


# Клиенту не доверяем и здесь: мусор в пакете не должен ни лечь в БД как есть, ни уронить сервер.
func test_settings_sanitized_on_write() -> void:
	var db := _fresh_db()
	var reg := db.register("umar", "pw")
	var uid: int = reg["user_id"]
	db.save_settings(uid, {"vol": 99.0, "imp": "да"})
	var loaded: Dictionary = db.load_settings(uid)
	_check(loaded["vol"] == 1.0, "громкость вне диапазона зажата при записи [%f]" % loaded["vol"])
	_check(loaded["imp"] == false, "нештатный отладочный флаг -> выключен")
	db.save_settings(uid, "не словарь")
	_check(db.load_settings(uid)["vol"] == Settings.VOLUME_DEFAULT, "мусорный пакет -> дефолты, без падения")
	db.close()


# Регрессия: настройки лежат в том же JSON-блобе, что отряд и прогресс (player_settings.data) —
# запись одного не должна затирать другое.
func test_settings_coexist_with_loadout_and_progress() -> void:
	var db := _fresh_db()
	var reg := db.register("vera", "pw")
	var uid: int = reg["user_id"]
	var team: Array = Loadout.canon_team_net(Loadout.random_team())
	db.save_loadout(uid, team)
	db.save_difficulty_unlocked(uid, Difficulty.TIER * 3)
	db.save_settings(uid, {"vol": 0.1, "imp": true})
	_check(db.load_loadout(uid) == team, "настройки не затёрли отряд")
	_check(db.load_difficulty_unlocked(uid) == Difficulty.TIER * 3, "настройки не затёрли прогресс")
	db.save_loadout(uid, Loadout.default_team_net())
	_check(is_equal_approx(db.load_settings(uid)["vol"], 0.1), "отряд не затёр настройки")
	db.close()
