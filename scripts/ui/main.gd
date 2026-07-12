extends Control

## Оркестратор: меню → локальный hotseat ИЛИ онлайн (через автолоад Net).
## Заголовки запуска:
##   сервер:      godot --headless --path . -- server
##   автотест-кл: godot --headless --path . -- autoclient <host>

enum Phase { MENU, HANDOFF, PLAN, RESOLVE, VICTORY }

const DEFAULT_HOST := "wss://warmarked.duckdns.org"

var state: MatchState
var resolver := Resolver.new()

var board_view: BoardView
var _opp_bar: ScoreBar   # очки противника — сверху
var _my_bar: ScoreBar    # очки игрока — под доской
var panel_host: MarginContainer
var _menu_art: TextureRect   # арт в пустой верхней области меню (вне матча)
var _background: TextureRect   # фон в матче и коллекции (позади всего)
var _effect_panel: RichTextLabel   # эффекты выделенного юнита — между очками и скиллами

# локальный режим
var _vs_ai := false          # PvE hotseat: игрок B — бот (AI.plan), человек играет за A
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
	# Коллекция живёт только в памяти на сессию — с диска не читаем и на диск не пишем.
	_build_layout()
	_connect_net()
	if args.has("autoclient") or args.has("--autoclient"):
		_auto = true
		_start_online(_arg_value(args, ["autoclient", "--autoclient"], "127.0.0.1"))
	else:
		_show_menu()


# Значение аргумента, идущего сразу за одним из ключей (для «-- autoclient <host>»).
func _arg_value(args: Array, keys: Array, fallback: String) -> String:
	for i in args.size():
		if args[i] in keys and i + 1 < args.size():
			return args[i + 1]
	return fallback


func _build_layout() -> void:
	Layout.verify_project_settings()

	# Фон матча и коллекции — на весь экран, позади всего остального (первым в дереве).
	_background = TextureRect.new()
	_background.texture = Icons.tex_opt("res://graphics/background.png")
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.visible = false
	add_child(_background)

	# Арт-заставка меню в верхней области, где вне матча нет доски. Позади всего остального.
	_menu_art = TextureRect.new()
	_menu_art.texture = Icons.tex_opt("res://graphics/art.jpg")
	_menu_art.position = Vector2.ZERO
	_menu_art.size = Vector2(Layout.SCREEN_W, Layout.PANEL_TOP)
	_menu_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_menu_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_menu_art.visible = false
	add_child(_menu_art)

	# очки противника — сверху (вместо строки инфо)
	_opp_bar = ScoreBar.new()
	add_child(_opp_bar)
	_opp_bar.position = Vector2(Layout.BOARD_X, Layout.SCORE_TOP_Y)
	_opp_bar.size = Vector2(Layout.BOARD_PX, Layout.SCORE_H)

	board_view = BoardView.new()
	board_view.position = Vector2(Layout.BOARD_X, Layout.BOARD_Y)
	add_child(board_view)
	board_view.setup(Board.new())   # инициализация пустой доской; матч подменит на state.board

	# очки игрока — под доской, над панелью
	_my_bar = ScoreBar.new()
	add_child(_my_bar)
	_my_bar.position = Vector2(Layout.BOARD_X, Layout.SCORE_BOTTOM_Y)
	_my_bar.size = Vector2(Layout.BOARD_PX, Layout.SCORE_H)

	# полоса эффектов выделенного юнита — между очками и скиллами
	_effect_panel = RichTextLabel.new()
	_effect_panel.bbcode_enabled = true
	_effect_panel.scroll_active = false
	_effect_panel.clip_contents = true
	_effect_panel.add_theme_font_size_override("normal_font_size", 15)
	_effect_panel.add_theme_font_size_override("bold_font_size", 16)
	_effect_panel.position = Vector2(Layout.BOARD_X + 6, Layout.EFFECT_Y)
	_effect_panel.size = Vector2(Layout.PANEL_W - 12, Layout.EFFECT_H)
	add_child(_effect_panel)
	board_view.selected_effects_changed.connect(func(text): _effect_panel.text = text)

	panel_host = MarginContainer.new()
	panel_host.position = Vector2(Layout.BOARD_X, Layout.PANEL_TOP)
	panel_host.custom_minimum_size = Vector2(Layout.PANEL_W, Layout.PANEL_H)
	panel_host.size = panel_host.custom_minimum_size
	add_child(panel_host)

	# доска и счёт скрыты вне матча — в меню/коллекции их нет, только в игре
	board_view.visible = false
	_opp_bar.visible = false
	_my_bar.visible = false
	_effect_panel.visible = false


func _connect_net() -> void:
	Net.connected_ok.connect(func(): _status("Соединение установлено. Поиск соперника…"))
	Net.connect_failed.connect(func(): _status("Не удалось подключиться к серверу."))
	Net.server_gone.connect(func(): _status("Сервер недоступен."))
	Net.matched.connect(_on_matched)
	Net.round_revealed.connect(_on_round_revealed)
	Net.opponent_progress.connect(_on_opponent_progress)
	Net.opponent_gone.connect(func(): _status("Соперник вышел. Матч окончен."))
	Net.version_mismatch.connect(_on_version_mismatch)


func _on_version_mismatch(server_version: int, client_version: int) -> void:
	Net.disconnect_net()
	if _auto:
		push_error("[autoclient] версия %d != сервер %d" % [client_version, server_version])
		get_tree().quit(1)
		return
	_status("Версия игры не совпадает с сервером.\nСервер: v%d, у вас: v%d.\nОбновите страницу (Ctrl+Shift+R) или клиент." % [server_version, client_version])


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
	# доска видна только во время матча (state != null): в меню и коллекции её нет
	board_view.visible = state != null
	_effect_panel.visible = state != null
	_background.visible = state != null   # фон матча (в коллекции включается отдельно)
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
	_menu_art.visible = true
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var b_local := Button.new()
	b_local.text = "Локальная игра (hotseat)"
	b_local.custom_minimum_size = Vector2(0, 52)
	b_local.add_theme_font_size_override("font_size", 20)
	b_local.pressed.connect(_start_local.bind(false))
	box.add_child(b_local)

	var b_ai := Button.new()
	b_ai.text = "Игра против ИИ"
	b_ai.custom_minimum_size = Vector2(0, 52)
	b_ai.add_theme_font_size_override("font_size", 20)
	b_ai.pressed.connect(_start_local.bind(true))
	box.add_child(b_ai)

	var b_online := Button.new()
	b_online.text = "Онлайн (найти игру)"
	b_online.custom_minimum_size = Vector2(0, 52)
	b_online.add_theme_font_size_override("font_size", 20)
	b_online.pressed.connect(func(): _start_online(DEFAULT_HOST))
	box.add_child(b_online)

	var b_coll := Button.new()
	b_coll.text = "Коллекция"
	b_coll.custom_minimum_size = Vector2(0, 52)
	b_coll.add_theme_font_size_override("font_size", 20)
	b_coll.pressed.connect(_show_collection)
	box.add_child(b_coll)

	_set_panel(box)


func _show_collection() -> void:
	# коллекция — на весь экран, а не в нижней панели (panel_host): доски в меню нет,
	# так что место свободно. Кладём отдельным оверлеем поверх корня, чиним меню на выходе.
	_menu_art.visible = false
	_background.visible = true   # фон под коллекцией
	for c in panel_host.get_children():
		c.queue_free()
	var cp := CollectionPanel.new()
	cp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cp.offset_left = Layout.BOARD_X
	cp.offset_right = -Layout.BOARD_X
	cp.offset_top = Layout.SCORE_TOP_Y
	cp.offset_bottom = -Layout.PANEL_BOTTOM_MARGIN
	add_child(cp)
	cp.closed.connect(func():
		cp.queue_free()
		_show_menu())


# ============================================================ локальный hotseat

func _start_local(vs_ai: bool = false) -> void:
	online = false
	_vs_ai = vs_ai
	_menu_art.visible = false
	state = MatchState.new()
	var team_a := Loadout.get_team()
	# В «случайном бою» соперник (бот/2-й игрок) получает свой независимый случайный отряд;
	# иначе — зеркало (оба за одним устройством играют одним составом).
	var team_b := Loadout.random_team() if Loadout.is_random_battle() else team_a
	state.setup(team_a, team_b, randi() % Maps.count())   # случайная карта из ротации
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
	_local_begin_plan(round_order[0])


func _show_handoff(player: int) -> void:
	_set_perspective(player)
	board_view.render(state.snapshot())
	board_view.clear_highlights()
	board_view.set_ghosts([])
	board_view.set_markers([])
	board_view.set_routes([])
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
	# Против бота его ход определён целиком и сразу — пустой слот у него это осознанный «пас»,
	# а не «ещё думает», поэтому показываем ВСЕ слоты соперника занятыми. В hotseat двух людей —
	# реальный прогресс соперника (какие слоты он уже заполнил, если ходит первым).
	if _vs_ai:
		var all_filled: Array = []
		for i in Consts.ORDER_SLOTS:
			all_filled.append(true)
		pp.set_opponent_progress(all_filled)
	else:
		pp.set_opponent_progress(_orders_filled(orders[Consts.other_player(player)]))


func _on_local_orders_ready(o: Array, player: int) -> void:
	orders[player] = o
	plan_index += 1
	if plan_index < 2:
		_local_begin_plan(round_order[1])
	else:
		_local_resolve()


# Кто планирует этот слот раунда: бот (за B в PvE) считает приказы сразу, человек идёт
# в панель планирования. «Передайте устройство» показываем только в hotseat двух людей.
func _local_begin_plan(player: int) -> void:
	if _vs_ai and player == Consts.Player.B:
		# Бот планирует слепо: state ещё не разрешён, приказы соперника ему не видны.
		_on_local_orders_ready(AI.plan(state, player), player)
	elif _vs_ai:
		_show_planning(player)
	else:
		_show_handoff(player)


func _local_resolve() -> void:
	_set_perspective(Consts.Player.A)   # разрешение — в каноническом виде (A снизу/синий)
	board_view.set_ghosts([])
	board_view.set_markers([])
	board_view.set_routes([])
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
	_menu_art.visible = false
	if host == "":
		host = DEFAULT_HOST
	_status("Подключение к %s…" % host)
	Net.start_client(host)


func _on_matched(index: int, a_first_on_odd: bool, loadout_a: Array, loadout_b: Array, map_index: int) -> void:
	my_index = index
	state = MatchState.new()
	state.setup(loadout_a, loadout_b, map_index)   # карта и отряды пришли от сервера (лок-степ)
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
