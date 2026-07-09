extends Control

## Оркестратор: меню → локальный hotseat ИЛИ онлайн (через автолоад Net).
## Заголовки запуска:
##   сервер:      godot --headless --path . -- server
##   автотест-кл: godot --headless --path . -- autoclient <host>

enum Phase { MENU, HANDOFF, PLAN, RESOLVE, VICTORY }

const BOARD_X := 4
const BOARD_Y := 42
const DEFAULT_HOST := "127.0.0.1"

var state: MatchState
var resolver := Resolver.new()

var board_view: BoardView
var _opp_bar: ScoreBar   # очки противника — сверху
var _my_bar: ScoreBar    # очки игрока — под доской
var panel_host: MarginContainer

# локальный режим
var round_order: Array = []
var plan_index: int = 0
var orders := {Consts.Player.A: [], Consts.Player.B: []}
var round_start_events: Array = []

# онлайн-режим
var online := false
var my_index := -1
var _auto := false
var _planning_pp: PlanningPanel = null


func _ready() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if args.has("server") or args.has("--server"):
		Net.start_server(Net.DEFAULT_PORT)
		return
	_build_layout()
	_connect_net()
	if args.has("autoclient") or args.has("--autoclient"):
		_auto = true
		_start_online(DEFAULT_HOST)
	else:
		_show_menu()


func _build_layout() -> void:
	var board_px := BoardView.CELL * Consts.BOARD_W
	var board_bottom := BOARD_Y + BoardView.CELL * Consts.BOARD_H

	# очки противника — сверху (вместо строки инфо)
	_opp_bar = ScoreBar.new()
	add_child(_opp_bar)
	_opp_bar.position = Vector2(BOARD_X, 8)
	_opp_bar.size = Vector2(board_px, 30)

	board_view = BoardView.new()
	board_view.position = Vector2(BOARD_X, BOARD_Y)
	add_child(board_view)
	board_view.setup(Board.new())

	# очки игрока — под доской, над панелью
	_my_bar = ScoreBar.new()
	add_child(_my_bar)
	_my_bar.position = Vector2(BOARD_X, board_bottom + 4)
	_my_bar.size = Vector2(board_px, 30)

	var panel_top := board_bottom + 44   # небольшой отступ между кружками очков и скиллами
	panel_host = MarginContainer.new()
	panel_host.position = Vector2(BOARD_X, panel_top)
	panel_host.custom_minimum_size = Vector2(board_px, 1200 - panel_top - 8)
	panel_host.size = panel_host.custom_minimum_size
	add_child(panel_host)

	_opp_bar.visible = false
	_my_bar.visible = false


func _connect_net() -> void:
	Net.connected_ok.connect(func(): _status("Соединение установлено. Поиск соперника…"))
	Net.connect_failed.connect(func(): _status("Не удалось подключиться к серверу."))
	Net.server_gone.connect(func(): _status("Сервер недоступен."))
	Net.matched.connect(_on_matched)
	Net.round_revealed.connect(_on_round_revealed)
	Net.opponent_progress.connect(_on_opponent_progress)
	Net.opponent_gone.connect(func(): _status("Соперник вышел. Матч окончен."))


func _on_opponent_progress(filled: Array) -> void:
	if is_instance_valid(_planning_pp) and _planning_pp.is_inside_tree():
		_planning_pp.set_opponent_progress(filled)


func _on_my_progress(filled: Array) -> void:
	if online:
		Net.send_progress(filled)


func _orders_filled(o: Array) -> Array:
	var f: Array = []
	for i in Consts.ORDER_SLOTS:
		f.append(o.size() > i and not o[i].is_empty())
	return f


func _set_panel(w: Control) -> void:
	for c in panel_host.get_children():
		c.queue_free()
	panel_host.add_child(w)


func _set_perspective(player: int) -> void:
	board_view.set_view(player)   # свой старт снизу, свои — синие
	_update_score_bars()


func _update_score_bars() -> void:
	if state == null:
		_opp_bar.visible = false
		_my_bar.visible = false
		return
	_opp_bar.visible = true
	_my_bar.visible = true
	var me := board_view.my_player
	_my_bar.set_score(state.score[me])
	_opp_bar.set_score(state.score[Consts.other_player(me)])


func _status(text: String) -> void:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 22)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	_set_panel(box)


# ============================================================ меню

func _show_menu() -> void:
	state = null
	_update_score_bars()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 30)
	title.text = "Warmarked"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var b_local := Button.new()
	b_local.text = "Локальная игра (hotseat)"
	b_local.custom_minimum_size = Vector2(0, 52)
	b_local.add_theme_font_size_override("font_size", 20)
	b_local.pressed.connect(_start_local)
	box.add_child(b_local)

	var host := LineEdit.new()
	host.text = DEFAULT_HOST
	host.placeholder_text = "IP сервера или wss://домен"
	host.add_theme_font_size_override("font_size", 18)
	box.add_child(host)
	var hint := Label.new()
	hint.text = "IP → ws://…:8910;  для Pages/HTTPS введи wss://твой-домен"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var b_online := Button.new()
	b_online.text = "Онлайн (найти игру)"
	b_online.custom_minimum_size = Vector2(0, 52)
	b_online.add_theme_font_size_override("font_size", 20)
	b_online.pressed.connect(func(): _start_online(host.text.strip_edges()))
	box.add_child(b_online)

	_set_panel(box)


# ============================================================ локальный hotseat

func _start_local() -> void:
	online = false
	state = MatchState.new()
	state.setup()
	board_view.setup(state.board)
	_local_new_round()


func _local_new_round() -> void:
	round_start_events = state.begin_round()
	board_view.render(state.snapshot())
	orders = {Consts.Player.A: [], Consts.Player.B: []}
	var first := state.first_player_this_round()
	round_order = [first, Consts.other_player(first)]
	plan_index = 0
	_update_score_bars()
	_show_handoff(round_order[0])


func _show_handoff(player: int) -> void:
	_set_perspective(player)
	board_view.render(state.snapshot())
	board_view.clear_highlights()
	board_view.set_ghosts([])
	board_view.set_markers([])
	board_view.set_selected_unit(-1)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 22)
	l.text = "Передайте устройство\nигроку %s" % Consts.player_name(player)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	var btn := Button.new()
	btn.text = "Я игрок %s — планировать" % Consts.player_name(player)
	btn.custom_minimum_size = Vector2(0, 46)
	btn.pressed.connect(_show_planning.bind(player))
	box.add_child(btn)
	_set_panel(box)


func _show_planning(player: int) -> void:
	_set_perspective(player)
	var pp := PlanningPanel.new()
	_planning_pp = pp
	_set_panel(pp)
	pp.orders_ready.connect(_on_local_orders_ready.bind(player))
	pp.progress_changed.connect(_on_my_progress)
	pp.begin(state, player, board_view)
	# в hotseat соперник уже мог спланировать (ходит первым) — показать его заполненные слоты
	pp.set_opponent_progress(_orders_filled(orders[Consts.other_player(player)]))


func _on_local_orders_ready(o: Array, player: int) -> void:
	orders[player] = o
	plan_index += 1
	if plan_index < 2:
		_show_handoff(round_order[1])
	else:
		_local_resolve()


func _local_resolve() -> void:
	_set_perspective(Consts.Player.A)   # разрешение — в каноническом виде (A снизу/синий)
	board_view.set_ghosts([])
	board_view.set_markers([])
	board_view.set_selected_unit(-1)
	var first: int = round_order[0]
	var combat := resolver.resolve(state, orders[Consts.Player.A], orders[Consts.Player.B], first)
	var score_events: Array = []
	state.score_round(score_events)
	_play_events(round_start_events + combat + score_events, _on_local_resolution_done)


func _on_local_resolution_done() -> void:
	board_view.render(state.snapshot())
	_update_score_bars()
	if state.winner >= 0:
		_show_victory()
	else:
		_local_new_round()


# ============================================================ онлайн

func _start_online(host: String) -> void:
	online = true
	if host == "":
		host = DEFAULT_HOST
	_status("Подключение к %s…" % host)
	Net.start_client(host)


func _on_matched(index: int, a_first_on_odd: bool) -> void:
	my_index = index
	state = MatchState.new()
	state.setup()
	state.a_first_on_odd = a_first_on_odd
	board_view.setup(state.board)
	_set_perspective(my_index)   # свой старт снизу, свои — синие (на весь матч)
	round_start_events = state.begin_round()
	board_view.render(state.snapshot())
	_update_score_bars()
	_online_plan()


func _online_plan() -> void:
	if _auto:
		Net.send_orders(state.round_num, Order.empty_slots())
		return
	board_view.render(state.snapshot())
	var pp := PlanningPanel.new()
	_planning_pp = pp
	_set_panel(pp)
	pp.orders_ready.connect(_on_online_orders_ready)
	pp.progress_changed.connect(_on_my_progress)
	pp.begin(state, my_index, board_view)


func _on_online_orders_ready(o: Array) -> void:
	Net.send_orders(state.round_num, o)
	_status("Приказы отправлены. Ожидание соперника…")


func _on_round_revealed(round_num: int, oa: Array, ob: Array) -> void:
	if round_num != state.round_num:
		return   # рассинхрон — игнор (сервер авторитетен)
	var first := state.first_player_this_round()
	var combat := resolver.resolve(state, oa, ob, first)
	var score_events: Array = []
	state.score_round(score_events)
	var all_events := round_start_events + combat + score_events
	if _auto:
		_on_online_resolution_done()
	else:
		_play_events(all_events, _on_online_resolution_done)


func _on_online_resolution_done() -> void:
	board_view.render(state.snapshot())
	_update_score_bars()
	if state.winner >= 0:
		if not _auto:
			_show_victory()
		else:
			get_tree().quit(0)
		return
	if _auto and state.round_num >= 2:
		print("[autoclient] отыграл %d раундов, выходим" % state.round_num)
		get_tree().quit(0)
		return
	round_start_events = state.begin_round()
	_online_plan()


# ============================================================ общее

func _play_events(events: Array, on_done: Callable) -> void:
	var rv := ResolutionView.new()
	_set_panel(rv)
	rv.finished.connect(func(): on_done.call())
	rv.begin(events, board_view)


func _show_victory() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 28)
	l.text = "Игрок %s победил!" % Consts.player_name(state.winner)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	var s := Label.new()
	s.text = "Счёт  A %d : %d B" % [state.score[Consts.Player.A], state.score[Consts.Player.B]]
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(s)
	var btn := Button.new()
	btn.text = "В меню"
	btn.custom_minimum_size = Vector2(0, 46)
	btn.pressed.connect(func(): Net.disconnect_net(); _show_menu())
	box.add_child(btn)
	_set_panel(box)
