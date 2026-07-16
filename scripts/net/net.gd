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
signal auth_ok(login: String, token: String, rating: int, loadout: Array, difficulty_unlocked: int, ai_best: int, settings: Dictionary)
signal auth_failed(reason: String)
signal loadout_saved
signal leaderboard_updated(rows: Array)   # [{login, level}] — таблица рекордов против ИИ
# Бой против ИИ начат сервером: аргументы — всё, из чего клиент строит СВОЮ копию матча
signal ai_matched(a_first_on_odd: bool, loadout_a: Array, loadout_b: Array, map_index: int, level: int, mod_seed: int)
signal ai_match_denied(unlocked: int)     # сервер не дал играть этот уровень (прогресс не тот)
signal ai_progress(new_record: bool, new_unlock: bool)   # итог боя с ИИ; зеркала Difficulty уже обновлены

const DEFAULT_PORT := 8910
const DB_PATH := "user://warmarked.db"

var is_server := false
var my_index := -1
var player_db: PlayerDB   # только на сервере

# --- серверные структуры ---
var _queue: Array = []                 # peer_id ожидающих
var _matches: Dictionary = {}          # match_id -> {session, peers:[p0,p1]}
var _peer_match: Dictionary = {}       # peer_id -> match_id
var _peer_index: Dictionary = {}       # peer_id -> 0/1
var _peer_loadout: Dictionary = {}     # peer_id -> сетевой кит (санированный)
var _peer_user: Dictionary = {}        # peer_id -> {user_id, login} — только авторизованные попадают в очередь
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


func save_loadout(team_net: Array) -> void:
	rpc_id(1, "req_save_loadout", team_net)


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
	if _peer_match.has(id):
		var mid: int = _peer_match[id]
		var m: Dictionary = _matches.get(mid, {})
		for p in m.get("peers", []):
			if p != id and multiplayer.get_peers().has(p):
				rpc_id(p, "notify_opponent_gone")
		_end_match(mid)


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
	if res.get("ok", false):
		_peer_user[sender] = {"user_id": res["user_id"], "login": res["login"]}
		rpc_id(sender, "auth_ok_rpc", String(res["login"]), String(res["token"]), int(res["rating"]),
			res.get("loadout", []), int(res.get("difficulty_unlocked", Difficulty.TIER)),
			int(res.get("ai_best", 0)), res.get("settings", {}))
	else:
		rpc_id(sender, "auth_failed_rpc", String(res.get("error", "unknown")))


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
	_matches[mid] = {"session": MatchSession.new(afo, lo_a, lo_b, map_index, level, mod_seed), "peers": [peer]}
	_peer_match[peer] = mid
	_peer_index[peer] = 0   # человек всегда играет за A, бот — за B
	rpc_id(peer, "ai_match_found_rpc", afo, lo_a, lo_b, map_index, level, mod_seed)
	print("[server] матч %d: peer %d против ИИ, уровень %d (map=%d, seed=%d)" % [mid, peer, level, map_index, mod_seed])


## Выход из матча по своей воле (сдался/ушёл в меню), сокет при этом жив. Для сервера это то же
## самое, что отключение пира: матч закрывается, соперник (если он живой) узнаёт об этом.
## Брошенный бой с ИИ не даёт ни рекорда, ни прогресса — исход считается только в resolve.
@rpc("any_peer", "call_remote", "reliable")
func req_leave_match() -> void:
	if not is_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _peer_match.has(sender):
		return
	var mid: int = _peer_match[sender]
	for p in _matches.get(mid, {}).get("peers", []):
		if p != sender and multiplayer.get_peers().has(p):
			rpc_id(p, "notify_opponent_gone")
	print("[server] матч %d: peer %d вышел" % [mid, sender])
	_end_match(mid)


## Исход боя с ИИ на стороне сервера: победа человека (игрок A) двигает прогресс и, если это
## личный рекорд, — лидерборд (что именно меняется, решает PlayerDB.apply_ai_win).
func _finish_ai_match(peer: int, s: MatchSession, winner: int) -> void:
	if not _peer_user.has(peer):
		return
	var user_id: int = _peer_user[peer]["user_id"]
	var res := {"record": false, "unlock": false}
	if winner == Consts.Player.A:
		# Отряд в БД пишется тот, которым сервер этот матч и играл, а не присланный «на слово».
		res = player_db.apply_ai_win(user_id, s.ai_level, _peer_loadout.get(peer, []))
		print("[server] peer %d победил ИИ на уровне %d (рекорд=%s, открыт блок=%s)"
			% [peer, s.ai_level, res.record, res.unlock])
	# Прогресс едет клиенту ДО раскрытия последнего раунда: раскрытие клиент проигрывает
	# анимацией в несколько секунд и лишь потом показывает экран победы, а порядок надёжных
	# RPC сохраняется — значит к экрану победы зеркала Difficulty гарантированно свежие.
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
	for p in m.peers:
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
		_finish_ai_match(sender, s, res.winner)
	for p in m.peers:
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
	_matches[mid] = {"session": MatchSession.new(afo, lo_a, lo_b, map_index), "peers": [p0, p1]}
	_peer_match[p0] = mid
	_peer_match[p1] = mid
	_peer_index[p0] = 0
	_peer_index[p1] = 1
	rpc_id(p0, "match_found_rpc", 0, afo, lo_a, lo_b, map_index)
	rpc_id(p1, "match_found_rpc", 1, afo, lo_a, lo_b, map_index)
	print("[server] матч %d: peer %d = A, peer %d = B (a_first_on_odd=%s, map=%d)" % [mid, p0, p1, afo, map_index])


func _end_match(mid: int) -> void:
	var m: Dictionary = _matches.get(mid, {})
	for p in m.get("peers", []):
		_peer_match.erase(p)
		_peer_index.erase(p)
		_peer_loadout.erase(p)
	_matches.erase(mid)


# ============================================================ RPC: сервер → клиент

@rpc("authority", "call_remote", "reliable")
func auth_ok_rpc(login: String, token: String, rating: int, loadout: Array, difficulty_unlocked: int,
		ai_best: int = 0, settings: Variant = {}) -> void:
	auth_ok.emit(login, token, rating, loadout, difficulty_unlocked, ai_best, Settings.sanitize_net(settings))


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
func notify_version_mismatch(server_version: int) -> void:
	version_mismatch.emit(server_version, Consts.PROTOCOL_VERSION)
