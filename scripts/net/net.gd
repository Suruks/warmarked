extends Node

## Автолоад /root/Net — сетевой хаб. В зависимости от запуска работает как авторитетный
## сервер (матчмейкинг + слепой гейт приказов + резолвинг) или как клиент.
## Транспорт — WebSocket (работает и на web/мобилке, дружелюбен к NAT/файрволам).
## RPC-пути совпадают на обоих концах, т.к. это автолоад на одном и том же пути.

signal connected_ok
signal connect_failed
signal server_gone
signal matched(your_index: int, a_first_on_odd: bool, loadout_a: Array, loadout_b: Array, map_index: int)
signal version_mismatch(server_version: int, client_version: int)
signal round_revealed(round_num: int, orders_a: Array, orders_b: Array)
signal opponent_progress(filled: Array)   # какие слоты соперник уже запланировал
signal opponent_gone
signal auth_ok(login: String, token: String, rating: int, loadout: Array, difficulty_unlocked: int, ai_best: int, settings: Dictionary, in_match: bool)
signal auth_failed(reason: String)
signal loadout_saved
signal leaderboard_updated(rows: Array)   # [{login, level}] — таблица рекордов против ИИ
# Бой против ИИ начат сервером: аргументы — всё, из чего клиент строит СВОЮ копию матча
signal ai_matched(a_first_on_odd: bool, loadout_a: Array, loadout_b: Array, map_index: int, level: int, mod_seed: int)
signal ai_match_denied(unlocked: int)     # сервер не дал играть этот уровень (прогресс не тот)
signal ai_progress(new_record: bool, new_unlock: bool)   # итог боя с ИИ; зеркала Difficulty уже обновлены
# Возврат в матч после переподключения: всё, из чего клиент заново собирает свою копию и догоняет
# текущий раунд, переиграв историю разрешённых раундов (см. main.gd/_on_match_resumed).
signal match_resumed(slot: int, a_first_on_odd: bool, loadout_a: Array, loadout_b: Array, map_index: int,
	ai_level: int, mod_seed: int, history: Array, already_submitted: bool, opp_submitted: bool)
signal opponent_disconnected   # соперник отвалился, но матч ждёт его возвращения (не окончен)
signal opponent_reconnected    # соперник вернулся в матч

const DEFAULT_PORT := 8910
const DB_PATH := "user://warmarked.db"
# Сколько сервер держит матч живым после дисконнекта игрока, ожидая его возвращения. Не вернулся —
# матч бросается (соперник узнаёт, что тот вышел). Иначе брошенные матчи копились бы вечно:
# состояние живёт в памяти сервера и переживает только его аптайм, но и в его пределах течёт.
const RECONNECT_GRACE_SEC := 90.0
const BOT_USER := -1   # заглушка user_id для слота бота в бою с ИИ (у аккаунтов id всегда ≥ 1)

var is_server := false
var my_index := -1
var player_db: PlayerDB   # только на сервере

# --- серверные структуры ---
# Матч живёт не по peer_id (тот эфемерен, меняется при переподключении), а по СЛОТАМ игроков.
# match_id -> {
#   session,                 MatchSession — авторитетное состояние
#   users:[uid0, uid1],      стабильная привязка к аккаунтам (BOT_USER для слота бота); по ней и находят матч на реконнекте
#   peers:[pid0, pid1],      текущий транспортный peer каждого слота; -1 — слот сейчас без связи
#   afo,map_index,lo_a,lo_b,ai_level,mod_seed,   параметры, из которых клиент пересобирает копию матча
#   history:[[oa,ob],...],   разрешённые раунды (сериализованные приказы) — для переигровки на реконнекте
# }
var _queue: Array = []                 # peer_id ожидающих
var _matches: Dictionary = {}
var _peer_match: Dictionary = {}       # peer_id -> match_id (эфемерная связь текущего сокета)
var _peer_index: Dictionary = {}       # peer_id -> слот 0/1
var _peer_loadout: Dictionary = {}     # peer_id -> сетевой кит (санированный)
var _peer_user: Dictionary = {}        # peer_id -> {user_id, login} — только авторизованные попадают в очередь
var _user_match: Dictionary = {}       # user_id -> match_id — переживает смену peer, по ней возвращают в матч
var _next_match_id := 1


# ============================================================ запуск

func start_server(port: int = DEFAULT_PORT) -> int:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		push_error("Не удалось поднять сервер на порту %d: %s" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	is_server = true
	player_db = PlayerDB.new()
	player_db.open(DB_PATH)
	print("[server] слушаю ws://0.0.0.0:%d" % port)
	return OK


# address: голый IP/хост → ws://host:8910; либо полный URL wss://домен (TLS через прокси, порт 443)
func start_client(address: String) -> int:
	var url := _build_ws_url(address)
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		push_error("Не удалось подключиться к %s: %s" % [url, err])
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	is_server = false
	print("[client] подключаюсь к %s" % url)
	return OK


func _build_ws_url(address: String) -> String:
	address = address.strip_edges()
	if address.begins_with("ws://") or address.begins_with("wss://"):
		return address              # пользователь задал схему сам (напр. wss://name.duckdns.org)
	return "ws://%s:%d" % [address, DEFAULT_PORT]   # голый IP/хост → ws:// на дефолтном порту


func disconnect_net() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


# ============================================================ клиент: события транспорта

func _on_connected() -> void:
	connected_ok.emit()


func _on_connect_failed() -> void:
	connect_failed.emit()


func _on_server_disconnected() -> void:
	server_gone.emit()


# ============================================================ клиент: вызовы к серверу

func register(login: String, password: String) -> void:
	rpc_id(1, "req_register", login, password)


func login(login: String, password: String) -> void:
	rpc_id(1, "req_login", login, password)


func resume_session(token: String) -> void:
	rpc_id(1, "req_resume_session", token)


func join_queue() -> void:
	rpc_id(1, "req_join_queue", Consts.PROTOCOL_VERSION, Loadout.team_net())


# false — связи нет, отряд на сервер НЕ уехал. Молчать тут нельзя: игрок собрал отряд, нажал
# «Сохранить», а на следующем входе сервер прислал бы ему старый — это потеря работы без единого
# слова. Раньше вызов просто сыпал ошибкой RPC в лог и терял отряд.
func save_loadout(team_net: Array) -> bool:
	if not _server_reachable():
		return false
	rpc_id(1, "req_save_loadout", team_net)
	return true


# Настройки живут за аккаунтом (см. Settings). Шлём весь набор целиком, а не по полю: он
# крохотный, а сохранение одной настройки не должно требовать знания об остальных.
func save_settings() -> void:
	if not _server_reachable():
		return   # сокет умер фоном — настройки останутся сессионными до следующего входа
	rpc_id(1, "req_save_settings", Settings.to_net())


# false — связи с сервером нет, лидерборд показать нечем (см. _server_reachable).
func request_leaderboard() -> bool:
	if not _server_reachable():
		return false
	rpc_id(1, "req_leaderboard")
	return true


# Начать бой против ИИ на уровне level. Сам бой идёт НА СЕРВЕРЕ (как и PvP): здесь мы только
# просим. Разрешён ли уровень, каким отрядом играет бот, кто победил и что за это записать в
# прогресс/лидерборд — решает сервер, клиент об этом не спрашивают.
# false — связи с сервером нет, а без него боя с ИИ не бывает.
func start_ai_match(level: int) -> bool:
	if not _server_reachable():
		return false
	rpc_id(1, "req_start_ai_match", Consts.PROTOCOL_VERSION, level, Loadout.team_net())
	return true


# Выйти из текущего матча, не рвя сокет (сдаться/уйти в меню из боя с ИИ). Матч на сервере
# закрывается, прогресс за брошенный бой не начисляется.
func leave_match() -> void:
	if not _server_reachable():
		return
	rpc_id(1, "req_leave_match")


# Сокет мог умереть фоном (см. main.gd/_on_connect_trouble), а UI это замечает не сразу —
# проверяем связь перед RPC: иначе вызов сыпал бы ошибкой в лог вместо честного false.
func _server_reachable() -> bool:
	if is_server or multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func send_orders(round_num: int, orders: Array) -> void:
	rpc_id(1, "submit_orders", round_num, NetProtocol.orders_to_data(orders))


func send_progress(filled: Array) -> void:
	if is_server:
		return
	rpc_id(1, "submit_progress", filled)


# ============================================================ сервер: события транспорта

func _on_peer_connected(id: int) -> void:
	print("[server] peer %d подключился" % id)


func _on_peer_disconnected(id: int) -> void:
	print("[server] peer %d отключился" % id)
	_queue.erase(id)
	_peer_loadout.erase(id)
	_peer_user.erase(id)
	if not _peer_match.has(id):
		return
	# Дисконнект больше НЕ рушит матч: слот освобождается (peers[slot] = -1), а сам матч ждёт
	# возвращения игрока по его user_id. Живой соперник узнаёт «отключился», а не «вышел» —
	# и продолжает ждать. Приказы уже сходившего слота остаются в session: раунд разрешится, как
	# только сходит второй, а догонит вернувшийся по history.
	var mid: int = _peer_match[id]
	var m: Dictionary = _matches.get(mid, {})
	var slot: int = _peer_index.get(id, -1)
	_peer_match.erase(id)     # старый peer мёртв — его эфемерные связи чистим
	_peer_index.erase(id)
	if m.is_empty() or slot < 0:
		return
	m.peers[slot] = -1
	for p in _connected_peers(m):
		rpc_id(p, "notify_opponent_disconnected")
	print("[server] матч %d: слот %d без связи, жду возвращения %.0fс" % [mid, slot, RECONNECT_GRACE_SEC])
	_schedule_abandon(mid)


# ============================================================ RPC: клиент → сервер

@rpc("any_peer", "call_remote", "reliable")
func req_register(login: String = "", password: String = "") -> void:
	if not is_server:
		return
	_respond_auth(multiplayer.get_remote_sender_id(), player_db.register(login, password))


@rpc("any_peer", "call_remote", "reliable")
func req_login(login: String = "", password: String = "") -> void:
	if not is_server:
		return
	_respond_auth(multiplayer.get_remote_sender_id(), player_db.authenticate(login, password))


@rpc("any_peer", "call_remote", "reliable")
func req_resume_session(token: String = "") -> void:
	if not is_server:
		return
	_respond_auth(multiplayer.get_remote_sender_id(), player_db.resume_session(token))


func _respond_auth(sender: int, res: Dictionary) -> void:
	if not res.get("ok", false):
		rpc_id(sender, "auth_failed_rpc", String(res.get("error", "unknown")))
		return
	var user_id: int = res["user_id"]
	_peer_user[sender] = {"user_id": user_id, "login": res["login"]}
	# Есть ли у этого аккаунта живой (брошенный на дисконнекте) матч, в который надо вернуть?
	# Флаг едет вместе с auth_ok, чтобы клиент не ушёл в меню/очередь, а дождался resume_match_rpc.
	var reattached := _reattach_to_match(sender, user_id)
	rpc_id(sender, "auth_ok_rpc", String(res["login"]), String(res["token"]), int(res["rating"]),
		res.get("loadout", []), int(res.get("difficulty_unlocked", Difficulty.TIER)),
		int(res.get("ai_best", 0)), res.get("settings", {}), reattached)
	if reattached:
		_send_resume(sender, _peer_match[sender])


@rpc("any_peer", "call_remote", "reliable")
func req_save_loadout(team_net: Variant = []) -> void:
	if not is_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _peer_user.has(sender):
		return   # анонимный пир — сохранять некому
	var user_id: int = _peer_user[sender]["user_id"]
	player_db.save_loadout(user_id, Loadout.canon_team_net(team_net))
	rpc_id(sender, "loadout_saved_rpc")


@rpc("any_peer", "call_remote", "reliable")
func req_save_settings(data: Variant = {}) -> void:
	if not is_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _peer_user.has(sender):
		return   # анонимный пир — сохранять некому
	player_db.save_settings(_peer_user[sender]["user_id"], data)


@rpc("any_peer", "call_remote", "reliable")
func req_leaderboard() -> void:
	if not is_server:
		return
	rpc_id(multiplayer.get_remote_sender_id(), "leaderboard_rpc",
		NetProtocol.leaderboard_to_data(player_db.leaderboard()))


## Бой против ИИ: как и PvP, он идёт НА СЕРВЕРЕ — клиент лишь просит начать. Всё, что раньше
## решал клиент (можно ли играть этот уровень, каким отрядом играет бот, кто победил, что
## записать в прогресс и лидерборд), решается здесь, поэтому подделать победу нельзя: у клиента
## просто нет способа сказать «я выиграл» — есть только приказы, которые сервер сам и резолвит.
@rpc("any_peer", "call_remote", "reliable")
func req_start_ai_match(version: Variant = 0, level: Variant = 0, loadout: Variant = []) -> void:
	if not is_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _peer_user.has(sender):
		return   # анонимный пир — не авторизован, играть не с кем и некому записывать
	if _peer_match.has(sender) or _queue.has(sender):
		return   # уже в матче/очереди
	var cv: int = version if typeof(version) == TYPE_INT else -1
	if cv != Consts.PROTOCOL_VERSION:
		print("[server] peer %d отклонён (ИИ): версия %s != %d" % [sender, str(version), Consts.PROTOCOL_VERSION])
		rpc_id(sender, "notify_version_mismatch", Consts.PROTOCOL_VERSION)
		return
	# Открытые уровни считает сервер по своей БД: попросить клиент может любой (в т.ч. 50 на
	# свежем аккаунте) — отклоняем, а не зажимаем, иначе «просьба на 50» тихо стала бы боем
	# на потолке прогресса.
	var user_id: int = _peer_user[sender]["user_id"]
	var unlocked := player_db.load_difficulty_unlocked(user_id)
	if not Difficulty.playable(level, unlocked):
		print("[server] peer %d отклонён (ИИ): уровень %s при открытых %d" % [sender, str(level), unlocked])
		rpc_id(sender, "ai_match_denied_rpc", unlocked)
		return
	# Клиенту не доверяем и здесь: отряд канонизируется ровно как в очереди PvP. Именно этот
	# отряд сервер и запишет в БД, если бой окончится рекордом (см. _finish_ai_match).
	_peer_loadout[sender] = Loadout.canon_team_net(loadout)
	_start_ai_match_for(sender, level)


func _start_ai_match_for(peer: int, level: int) -> void:
	var afo := (randi() % 2 == 0)
	var map_index := randi() % Maps.count()
	var mod_seed := randi()   # жребий модификаторов сложности; едет клиенту для его копии матча
	var mid := _next_match_id
	_next_match_id += 1
	# Отряд игрока сервер берёт из ПРИСЛАННОГО клиентом (как в PvP — санированным), отряд бота
	# ролит сам: бот не должен играть зеркалом кита игрока.
	var lo_a: Array = _peer_loadout.get(peer, Loadout.default_team_net())
	var lo_b: Array = Loadout.canon_team_net(Loadout.random_team())
	# Слот 1 — бот: без связи (peers[1] = -1) и без аккаунта (users[1] = BOT_USER) навсегда.
	# Человек (слот 0) так же может отвалиться и вернуться, как в PvP.
	var users := [_peer_user[peer]["user_id"], BOT_USER]
	_register_match(mid, MatchSession.new(afo, lo_a, lo_b, map_index, level, mod_seed), users, [peer, -1],
		lo_a, lo_b, afo, map_index, level, mod_seed)
	rpc_id(peer, "ai_match_found_rpc", afo, lo_a, lo_b, map_index, level, mod_seed)
	print("[server] матч %d: peer %d против ИИ, уровень %d (map=%d, seed=%d)" % [mid, peer, level, map_index, mod_seed])


## Выход по своей воле (сдался/ушёл в меню/отменил поиск), сокет при этом жив. Для сервера это
## то же самое, что отключение пира, только без отключения: игрок уходит и из очереди, и из
## матча, а живой соперник узнаёт об этом. Брошенный бой с ИИ не даёт ни рекорда, ни прогресса —
## исход считается только в resolve.
@rpc("any_peer", "call_remote", "reliable")
func req_leave_match() -> void:
	if not is_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	# Отмена поиска соперника: матча ещё нет, но в очереди игрок уже стоит — иначе его свело бы
	# с кем-то, пока он сидит в меню (раньше из очереди его выкидывал сам разрыв связи).
	if _queue.has(sender):
		_queue.erase(sender)
		print("[server] peer %d вышел из очереди (осталось %d)" % [sender, _queue.size()])
	if not _peer_match.has(sender):
		return
	var mid: int = _peer_match[sender]
	# Выход по своей воле — это КОНЕЦ матча (в отличие от дисконнекта): соперник узнаёт «вышел»,
	# возвращаться будет некуда. Именно поэтому дисконнект и явный выход разведены на два пути.
	for p in _connected_peers(_matches.get(mid, {})):
		if p != sender:
			rpc_id(p, "notify_opponent_gone")
	print("[server] матч %d: peer %d вышел" % [mid, sender])
	_end_match(mid)


## Исход боя с ИИ на стороне сервера: победа человека (игрок A) двигает прогресс и, если это
## личный рекорд, — лидерборд (что именно меняется, решает PlayerDB.apply_ai_win). Идентичность
## игрока берём из матча (users[0]), а не из peer: peer мог смениться после переподключения.
func _finish_ai_match(mid: int, winner: int) -> void:
	var m: Dictionary = _matches[mid]
	var user_id: int = m.users[0]
	var peer: int = m.peers[0]
	var res := {"record": false, "unlock": false}
	if winner == Consts.Player.A:
		# Отряд в БД пишется тот, которым сервер этот матч и играл, а не присланный «на слово».
		res = player_db.apply_ai_win(user_id, m.ai_level, m.lo_a)
		print("[server] user %d победил ИИ на уровне %d (рекорд=%s, открыт блок=%s)"
			% [user_id, m.ai_level, res.record, res.unlock])
	# Прогресс едет клиенту ДО раскрытия последнего раунда: раскрытие клиент проигрывает
	# анимацией в несколько секунд и лишь потом показывает экран победы, а порядок надёжных
	# RPC сохраняется — значит к экрану победы зеркала Difficulty гарантированно свежие.
	if peer >= 1:
		rpc_id(peer, "ai_progress_rpc", player_db.load_difficulty_unlocked(user_id),
			player_db.load_ai_best(user_id), res.record, res.unlock)
	if res.record:
		_broadcast_leaderboard()


func _broadcast_leaderboard() -> void:
	var data := NetProtocol.leaderboard_to_data(player_db.leaderboard())
	for p in multiplayer.get_peers():
		rpc_id(p, "leaderboard_rpc", data)


@rpc("any_peer", "call_remote", "reliable")
func req_join_queue(version: Variant = 0, loadout: Variant = []) -> void:
	if not is_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _peer_user.has(sender):
		return   # анонимный пир — не авторизован, в очередь не пускаем
	# Версии обязаны совпадать: иначе лок-степ разойдётся незаметно. Отклоняем в очередь не ставя.
	var cv: int = version if typeof(version) == TYPE_INT else -1
	if cv != Consts.PROTOCOL_VERSION:
		print("[server] peer %d отклонён: версия %s != %d" % [sender, str(version), Consts.PROTOCOL_VERSION])
		rpc_id(sender, "notify_version_mismatch", Consts.PROTOCOL_VERSION)
		return
	if _peer_match.has(sender) or _queue.has(sender):
		return
	# Клиенту не доверяем: чужой класс/повторные скиллы -> дефолт слота, иначе лок-степ разъедется.
	# Храним КАНОНИЧЕСКИЙ сетевой отряд, чтобы обе стороны собрали матч из одинаковых байт.
	_peer_loadout[sender] = Loadout.canon_team_net(loadout)
	_queue.append(sender)
	print("[server] peer %d в очереди (всего %d)" % [sender, _queue.size()])
	_try_matchmake()


@rpc("any_peer", "call_remote", "reliable")
func submit_progress(filled: Array) -> void:
	if not is_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _peer_match.has(sender):
		return
	var m: Dictionary = _matches[_peer_match[sender]]
	for p in _connected_peers(m):
		if p != sender:
			rpc_id(p, "opp_progress_rpc", filled)


@rpc("any_peer", "call_remote", "reliable")
func submit_orders(round_num: int, data: Array) -> void:
	if not is_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _peer_match.has(sender):
		return
	var mid: int = _peer_match[sender]
	var m: Dictionary = _matches[mid]
	var s: MatchSession = m.session
	if round_num != s.current_round():
		return   # устаревший/рассинхронный пакет — игнор
	var idx: int = _peer_index[sender]
	var orders := NetProtocol.orders_from_data(data)
	print("[server] матч %d: приказы игрока %d за раунд %d" % [mid, idx, round_num])
	var ready := s.submit(idx, orders)
	# В бою с ИИ второго пира нет — за него ходит сервер. Планируем бота ПОСЛЕ приказов человека:
	# на слепоту это не влияет (AI.plan видит только состояние, приказы человека в него не
	# внесены), зато бот не тратит время сервера на брошенные раунды.
	if s.ai_level > 0 and not ready:
		ready = s.plan_bot()
	if not ready:
		return
	var oa := NetProtocol.orders_to_data(s.orders_of(0))
	var ob := NetProtocol.orders_to_data(s.orders_of(1))
	var rn := s.current_round()
	var res := s.resolve()
	# Исход боя с ИИ считает сам сервер — по СВОЕМУ резолву, а не по слову клиента.
	if s.ai_level > 0 and res.winner >= 0:
		_finish_ai_match(mid, res.winner)
	# Незавершённый раунд копим в history: вернувшийся игрок переиграет его и догонит текущий.
	# Победный раунд не пишем — матч тут же кончается, возвращаться некуда (его удаляет _end_match).
	if res.winner < 0:
		(m.history as Array).append([oa, ob])
	for p in _connected_peers(m):
		rpc_id(p, "reveal_round", rn, oa, ob)
	print("[server] матч %d: раунд %d раскрыт (winner=%d)" % [mid, rn, res.winner])
	if res.winner >= 0:
		_end_match(mid)


# ============================================================ сервер: матчмейкинг

func _try_matchmake() -> void:
	while _queue.size() >= 2:
		var p0: int = _queue.pop_front()
		var p1: int = _queue.pop_front()
		var peers := multiplayer.get_peers()
		if not peers.has(p0):
			if peers.has(p1):
				_queue.push_front(p1)
			continue
		if not peers.has(p1):
			_queue.push_front(p0)
			continue
		_create_match(p0, p1)


func _create_match(p0: int, p1: int) -> void:
	var afo := (randi() % 2 == 0)
	var map_index := randi() % Maps.count()   # карту выбирает СЕРВЕР — обе стороны строят одинаковый матч
	var mid := _next_match_id
	_next_match_id += 1
	# Оба кита едут обоим клиентам: детерминированная копия матча должна совпасть с серверной
	var lo_a: Array = _peer_loadout.get(p0, Loadout.default_team_net())
	var lo_b: Array = _peer_loadout.get(p1, Loadout.default_team_net())
	var users := [_peer_user[p0]["user_id"], _peer_user[p1]["user_id"]]
	_register_match(mid, MatchSession.new(afo, lo_a, lo_b, map_index), users, [p0, p1],
		lo_a, lo_b, afo, map_index, 0, 0)
	rpc_id(p0, "match_found_rpc", 0, afo, lo_a, lo_b, map_index)
	rpc_id(p1, "match_found_rpc", 1, afo, lo_a, lo_b, map_index)
	print("[server] матч %d: peer %d = A, peer %d = B (a_first_on_odd=%s, map=%d)" % [mid, p0, p1, afo, map_index])


# Заносит матч во все серверные структуры разом (общее для PvP и боя с ИИ). Слот -1 в peers —
# «без связи» (у бота в бою с ИИ слот 1 такой всегда). users с BOT_USER в _user_match не попадают.
func _register_match(mid: int, session: MatchSession, users: Array, peers: Array,
		lo_a: Array, lo_b: Array, afo: bool, map_index: int, ai_level: int, mod_seed: int) -> void:
	_matches[mid] = {
		"session": session, "users": users, "peers": peers,
		"lo_a": lo_a, "lo_b": lo_b, "afo": afo, "map_index": map_index,
		"ai_level": ai_level, "mod_seed": mod_seed, "history": [],
	}
	for slot in peers.size():
		var pid: int = peers[slot]
		if pid >= 1:
			_peer_match[pid] = mid
			_peer_index[pid] = slot
		if users[slot] != BOT_USER:
			_user_match[users[slot]] = mid


func _end_match(mid: int) -> void:
	var m: Dictionary = _matches.get(mid, {})
	for p in m.get("peers", []):
		if p >= 1:   # -1 — слот без связи (бот или отвалившийся игрок), чистить нечего
			_peer_match.erase(p)
			_peer_index.erase(p)
			_peer_loadout.erase(p)
	for u in m.get("users", []):
		if u != BOT_USER:
			_user_match.erase(u)   # разрываем стабильную привязку — реконнект в этот матч больше не найдёт
	_matches.erase(mid)


# ============================================================ сервер: дисконнект/реконнект

# Peer'ы слотов, реально подключённые сейчас (пропускает -1 и уже отпавшие). По ним рассылаем.
func _connected_peers(m: Dictionary) -> Array:
	var out: Array = []
	for p in m.get("peers", []):
		if p >= 1 and multiplayer.get_peers().has(p):
			out.append(p)
	return out


# Вернуть только что вошедшего игрока в его брошенный матч, если такой есть. true — вернули
# (тогда _respond_auth дошлёт resume). Чужой живой слот не перехватываем: если место ещё держит
# подключённый peer (двойной вход одним аккаунтом), новый вход в матч не лезет.
func _reattach_to_match(sender: int, user_id: int) -> bool:
	var mid: int = _user_match.get(user_id, -1)
	if mid < 0 or not _matches.has(mid):
		_user_match.erase(user_id)   # висячая ссылка на закрытый матч — подчищаем
		return false
	var m: Dictionary = _matches[mid]
	var slot: int = (m.users as Array).find(user_id)
	if slot < 0:
		return false
	var held: int = m.peers[slot]
	if held >= 1 and multiplayer.get_peers().has(held):
		return false   # слот ещё за живым сокетом — не перехватываем
	m.peers[slot] = sender
	_peer_match[sender] = mid
	_peer_index[sender] = slot
	_peer_loadout[sender] = m.lo_a if slot == 0 else m.lo_b
	print("[server] матч %d: user %d вернулся в слот %d (peer %d)" % [mid, user_id, slot, sender])
	for p in _connected_peers(m):
		if p != sender:
			rpc_id(p, "notify_opponent_reconnected")
	return true


# Всё, из чего клиент заново собирает копию матча и догоняет текущий раунд переигровкой history.
func _send_resume(sender: int, mid: int) -> void:
	var m: Dictionary = _matches[mid]
	var s: MatchSession = m.session
	var slot: int = _peer_index[sender]
	rpc_id(sender, "resume_match_rpc", slot, m.afo, m.lo_a, m.lo_b, m.map_index, m.ai_level,
		m.mod_seed, m.history, s.has_orders(slot), s.has_orders(1 - slot))


# Через RECONNECT_GRACE_SEC проверяем, вернулся ли игрок; нет — бросаем матч. Таймер не отменяем
# при возврате: проверка идемпотентна (нет матча / все слоты на связи → ничего не делает).
func _schedule_abandon(mid: int) -> void:
	var t := get_tree().create_timer(RECONNECT_GRACE_SEC)
	t.timeout.connect(_abandon_if_still_gone.bind(mid))


func _abandon_if_still_gone(mid: int) -> void:
	var m: Dictionary = _matches.get(mid, {})
	if m.is_empty():
		return   # матч уже закрылся (доигран, покинут или другой таймер сработал)
	var someone_gone := false
	for slot in (m.users as Array).size():
		if m.users[slot] != BOT_USER and m.peers[slot] == -1:
			someone_gone = true
	if not someone_gone:
		return   # все живые слоты на связи — игрок вернулся
	print("[server] матч %d: игрок не вернулся за %.0fс — бросаю матч" % [mid, RECONNECT_GRACE_SEC])
	for p in _connected_peers(m):
		rpc_id(p, "notify_opponent_gone")
	_end_match(mid)


# ============================================================ RPC: сервер → клиент

@rpc("authority", "call_remote", "reliable")
func auth_ok_rpc(login: String, token: String, rating: int, loadout: Array, difficulty_unlocked: int,
		ai_best: int = 0, settings: Variant = {}, in_match: bool = false) -> void:
	auth_ok.emit(login, token, rating, loadout, difficulty_unlocked, ai_best, Settings.sanitize_net(settings), in_match)


@rpc("authority", "call_remote", "reliable")
func leaderboard_rpc(rows: Variant = []) -> void:
	leaderboard_updated.emit(NetProtocol.leaderboard_from_data(rows))


@rpc("authority", "call_remote", "reliable")
func auth_failed_rpc(reason: String) -> void:
	auth_failed.emit(reason)


@rpc("authority", "call_remote", "reliable")
func loadout_saved_rpc() -> void:
	loadout_saved.emit()


@rpc("authority", "call_remote", "reliable")
func match_found_rpc(your_index: int, a_first_on_odd: bool, loadout_a: Variant = [], loadout_b: Variant = [], map_index: int = 0) -> void:
	my_index = your_index
	matched.emit(your_index, a_first_on_odd, Loadout.sanitize_team_net(loadout_a), Loadout.sanitize_team_net(loadout_b), map_index)


@rpc("authority", "call_remote", "reliable")
func ai_match_found_rpc(a_first_on_odd: bool = true, loadout_a: Variant = [], loadout_b: Variant = [],
		map_index: int = 0, level: int = 1, mod_seed: int = 0) -> void:
	my_index = 0   # против ИИ человек всегда играет за A
	ai_matched.emit(a_first_on_odd, Loadout.sanitize_team_net(loadout_a),
		Loadout.sanitize_team_net(loadout_b), map_index, level, mod_seed)


@rpc("authority", "call_remote", "reliable")
func ai_match_denied_rpc(unlocked: int = Difficulty.TIER) -> void:
	Difficulty.set_unlocked(unlocked)   # зеркало разошлось с сервером — чиним по авторитету
	ai_match_denied.emit(unlocked)


@rpc("authority", "call_remote", "reliable")
func ai_progress_rpc(unlocked: int = Difficulty.TIER, best: int = 0, new_record: bool = false,
		new_unlock: bool = false) -> void:
	Difficulty.set_unlocked(unlocked)
	Difficulty.set_best(best)
	ai_progress.emit(new_record, new_unlock)


@rpc("authority", "call_remote", "reliable")
func reveal_round(round_num: int, oa_data: Array, ob_data: Array) -> void:
	round_revealed.emit(round_num, NetProtocol.orders_from_data(oa_data), NetProtocol.orders_from_data(ob_data))


@rpc("authority", "call_remote", "reliable")
func opp_progress_rpc(filled: Array) -> void:
	opponent_progress.emit(filled)


@rpc("authority", "call_remote", "reliable")
func notify_opponent_gone() -> void:
	opponent_gone.emit()


@rpc("authority", "call_remote", "reliable")
func notify_opponent_disconnected() -> void:
	opponent_disconnected.emit()


@rpc("authority", "call_remote", "reliable")
func notify_opponent_reconnected() -> void:
	opponent_reconnected.emit()


@rpc("authority", "call_remote", "reliable")
func resume_match_rpc(slot: int = 0, a_first_on_odd: bool = true, loadout_a: Variant = [],
		loadout_b: Variant = [], map_index: int = 0, ai_level: int = 0, mod_seed: int = 0,
		history: Variant = [], already_submitted: bool = false, opp_submitted: bool = false) -> void:
	my_index = slot
	match_resumed.emit(slot, a_first_on_odd, Loadout.sanitize_team_net(loadout_a),
		Loadout.sanitize_team_net(loadout_b), map_index, ai_level, mod_seed,
		history if typeof(history) == TYPE_ARRAY else [], already_submitted, opp_submitted)


@rpc("authority", "call_remote", "reliable")
func notify_version_mismatch(server_version: int) -> void:
	version_mismatch.emit(server_version, Consts.PROTOCOL_VERSION)
