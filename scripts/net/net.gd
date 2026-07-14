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
signal auth_ok(login: String, token: String, rating: int)
signal auth_failed(reason: String)

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
		rpc_id(sender, "auth_ok_rpc", String(res["login"]), String(res["token"]), int(res["rating"]))
	else:
		rpc_id(sender, "auth_failed_rpc", String(res.get("error", "unknown")))


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
	if s.submit(idx, orders):
		var oa := NetProtocol.orders_to_data(s.orders_of(0))
		var ob := NetProtocol.orders_to_data(s.orders_of(1))
		var rn := s.current_round()
		var res := s.resolve()
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
func auth_ok_rpc(login: String, token: String, rating: int) -> void:
	auth_ok.emit(login, token, rating)


@rpc("authority", "call_remote", "reliable")
func auth_failed_rpc(reason: String) -> void:
	auth_failed.emit(reason)


@rpc("authority", "call_remote", "reliable")
func match_found_rpc(your_index: int, a_first_on_odd: bool, loadout_a: Variant = [], loadout_b: Variant = [], map_index: int = 0) -> void:
	my_index = your_index
	matched.emit(your_index, a_first_on_odd, Loadout.sanitize_team_net(loadout_a), Loadout.sanitize_team_net(loadout_b), map_index)


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
