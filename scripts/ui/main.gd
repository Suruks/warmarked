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
var _background: TextureRect   # фон в матче и коллекции (позади всего, на весь реальный экран)
var _effect_panel: RichTextLabel   # эффекты выделенного юнита — между очками и скиллами
var _options_btn: TextureButton    # кнопка настроек — справа в верхнем отступе экрана боя
# Фиксированная область раскладки (Layout.SCREEN_W x Layout.SCREEN_H), заякоренная по центру
# реального экрана. Все элементы боя/меню — её дети: их абсолютные координаты (Layout.*)
# остаются как есть, а центрирование/края реального (возможно более широкого — EXPAND) экрана
# обеспечивает сам _content своими анкорами. Фон (_background) — вне неё, на весь экран.
var _content: Control

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
	get_window().size_changed.connect(_adapt_stretch_for_orientation)
	_adapt_stretch_for_orientation()
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


# На портретном экране (выше, чем шире — телефон/планшет вертикально) растягиваем канвас без
# чёрных полос по бокам: EXPAND сам расширяет сверх базовых 540x1200 ту ось (обычно высоту),
# которой не хватает, чтобы покрыть экран целиком, — ничего в раскладке менять не нужно, она
# вся отсчитана от верхнего края. На ландшафте (ПК и т.п.) оставляем как есть: полосы там при
# несовпадающих пропорциях ожидаемы, трогать не просили. Держим в актуальном состоянии
# отдельным колбэком на size_changed — так работает и разворот устройства, и ресайз окна.
func _adapt_stretch_for_orientation() -> void:
	var sz := DisplayServer.window_get_size()
	var portrait := sz.y > sz.x
	var target := Window.CONTENT_SCALE_ASPECT_EXPAND if portrait else Window.CONTENT_SCALE_ASPECT_KEEP
	if get_window().content_scale_aspect != target:
		get_window().content_scale_aspect = target


func _build_layout() -> void:
	Layout.verify_project_settings()

	# Фон матча и коллекции — на весь РЕАЛЬНЫЙ экран (не только раскладку), позади всего
	# остального (первым в дереве, вне _content) — иначе на широких/EXPAND-экранах по бокам
	# от центрированной раскладки было бы пусто.
	_background = TextureRect.new()
	_background.texture = Icons.tex_opt("res://graphics/background.png")
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.visible = false
	add_child(_background)

	# Раскладка боя/меню — фиксированного размера Layout.SCREEN_W x Layout.SCREEN_H, центрирована
	# по горизонтали в реальном экране (анкоры 0.5/0.5 + офсеты ±половина ширины). На обычном
	# экране (совпадающие пропорции) офсеты дают ровно (0,0)..(SCREEN_W,SCREEN_H) — как раньше.
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.anchor_left = 0.5
	_content.anchor_right = 0.5
	_content.anchor_top = 0.0
	_content.anchor_bottom = 0.0
	_content.offset_left = -Layout.SCREEN_W / 2.0
	_content.offset_right = Layout.SCREEN_W / 2.0
	_content.offset_top = 0.0
	_content.offset_bottom = Layout.SCREEN_H
	add_child(_content)

	# Арт-заставка меню в верхней области, где вне матча нет доски. Позади всего остального.
	_menu_art = TextureRect.new()
	_menu_art.texture = Icons.tex_opt("res://graphics/art.jpg")
	_menu_art.position = Vector2.ZERO
	_menu_art.size = Vector2(Layout.SCREEN_W, Layout.PANEL_TOP)
	_menu_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_menu_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_menu_art.visible = false
	_content.add_child(_menu_art)

	# Версия — маленькая надпись в правом верхнем углу главного меню (белым, поверх арта).
	# Ребёнок _menu_art: показывается/прячется вместе с ним, отдельно видимость вести не нужно.
	var version_lbl := Label.new()
	version_lbl.text = "v%d" % Consts.PROTOCOL_VERSION
	version_lbl.add_theme_font_size_override("font_size", 13)
	version_lbl.add_theme_color_override("font_color", Color.WHITE)
	version_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version_lbl.size = Vector2(64, 18)
	version_lbl.position = Vector2(Layout.SCREEN_W - 64 - 8, 8)
	_menu_art.add_child(version_lbl)

	# очки противника — сверху (вместо строки инфо)
	_opp_bar = ScoreBar.new()
	_content.add_child(_opp_bar)
	_opp_bar.position = Vector2(Layout.BOARD_X, Layout.SCORE_TOP_Y)
	_opp_bar.size = Vector2(Layout.BOARD_PX, Layout.SCORE_H)

	board_view = BoardView.new()
	board_view.position = Vector2(Layout.BOARD_X, Layout.BOARD_Y)
	_content.add_child(board_view)
	board_view.setup(Board.new())   # инициализация пустой доской; матч подменит на state.board

	# очки игрока — под доской, над панелью
	_my_bar = ScoreBar.new()
	_content.add_child(_my_bar)
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
	_content.add_child(_effect_panel)
	board_view.selected_effects_changed.connect(func(text): _effect_panel.text = text)

	panel_host = MarginContainer.new()
	panel_host.position = Vector2(Layout.BOARD_X, Layout.PANEL_TOP)
	panel_host.custom_minimum_size = Vector2(Layout.PANEL_W, Layout.PANEL_H)
	panel_host.size = panel_host.custom_minimum_size
	_content.add_child(panel_host)

	# кнопка настроек — в правом краю верхнего отступа, видна только в матче.
	# Добавляем последней, чтобы рисовалась поверх остального.
	var opt_size := 48   # крупная зона нажатия — палец на мобилке попадает уверенно
	_options_btn = TextureButton.new()
	_options_btn.texture_normal = Icons.tex_opt("res://graphics/options.png")
	_options_btn.ignore_texture_size = true
	_options_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_options_btn.custom_minimum_size = Vector2(opt_size, opt_size)
	_options_btn.size = Vector2(opt_size, opt_size)
	_options_btn.position = Vector2(
		Layout.SCREEN_W - opt_size - Layout.BOARD_X,
		(Layout.TOP_MARGIN - opt_size) / 2)
	_options_btn.pressed.connect(_on_options_pressed)
	_content.add_child(_options_btn)

	# доска и счёт скрыты вне матча — в меню/коллекции их нет, только в игре
	board_view.visible = false
	_opp_bar.visible = false
	_my_bar.visible = false
	_effect_panel.visible = false
	_options_btn.visible = false


func _connect_net() -> void:
	Net.connected_ok.connect(func(): _status("Соединение установлено. Поиск соперника…", true))
	Net.connect_failed.connect(func(): _status("Не удалось подключиться к серверу.", true))
	Net.server_gone.connect(func(): _status("Сервер недоступен.", true))
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
	_status("Версия игры не совпадает с сервером.\nСервер: v%d, у вас: v%d.\nОбновите страницу (Ctrl+Shift+R) или клиент." % [server_version, client_version], true)


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
	_options_btn.visible = state != null  # настройки — только во время боя
	if state == null:
		_opp_bar.visible = false
		_my_bar.visible = false
		return
	_opp_bar.visible = true
	_my_bar.visible = true
	var me := board_view.my_player
	_my_bar.set_score(state.score[me])
	_opp_bar.set_score(state.score[Consts.other_player(me)])


func _on_options_pressed() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Настройки"
	dlg.ok_button_text = "Закрыть"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.custom_minimum_size = Vector2(340, 0)

	# Отладка: разрешить выбирать невозможные цели (корректность цели не проверяется)
	var chk := CheckBox.new()
	chk.text = "Разрешить выбирать невозможные цели"
	chk.button_pressed = Settings.allow_impossible_targets
	chk.toggled.connect(func(on: bool): Settings.allow_impossible_targets = on)
	box.add_child(chk)

	# Сдаться — прервать текущий бой и вернуться в меню
	var surrender := Button.new()
	surrender.text = "Сдаться"
	surrender.custom_minimum_size = Vector2(0, 44)
	surrender.pressed.connect(func():
		dlg.queue_free()
		Net.disconnect_net()
		_show_menu())
	box.add_child(surrender)

	dlg.add_child(box)
	dlg.close_requested.connect(dlg.queue_free)
	dlg.confirmed.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


# show_cancel — показать кнопку «Отмена» под текстом (поиск соперника/ошибки до начала матча):
# обрывает соединение и возвращает в меню. Во время самого матча (ожидание хода соперника)
# кнопки нет — там для выхода уже есть «Сдаться» в настройках.
func _status(text: String, show_cancel: bool = false) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 22)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	if show_cancel:
		var btn := Button.new()
		btn.text = "Отмена"
		btn.custom_minimum_size = Vector2(160, 46)
		btn.pressed.connect(func():
			Net.disconnect_net()
			_show_menu())
		box.add_child(btn)
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
	b_ai.pressed.connect(_show_difficulty_dialog)
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


# Окно выбора сложности перед боем с ИИ: слайдер 1..24 + «Бой»/«Отмена».
func _show_difficulty_dialog() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Игра против ИИ"
	dlg.get_ok_button().visible = false   # свои кнопки «Бой»/«Отмена» ниже, вместо стандартного OK

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(360, 0)

	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.text = "Сложность: %d" % Difficulty.level
	box.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = Difficulty.MIN_LEVEL
	slider.max_value = Difficulty.MAX_LEVEL
	slider.step = 1
	slider.value = Difficulty.level
	slider.custom_minimum_size = Vector2(0, 28)
	slider.value_changed.connect(func(v: float): lbl.text = "Сложность: %d" % int(v))
	box.add_child(slider)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var b_cancel := Button.new()
	b_cancel.text = "Отмена"
	b_cancel.custom_minimum_size = Vector2(140, 46)
	b_cancel.pressed.connect(dlg.queue_free)
	row.add_child(b_cancel)

	var b_fight := Button.new()
	b_fight.text = "Бой"
	b_fight.custom_minimum_size = Vector2(140, 46)
	b_fight.pressed.connect(func():
		Difficulty.set_level(int(slider.value))
		dlg.queue_free()
		_start_local(true))
	row.add_child(b_fight)
	box.add_child(row)

	dlg.add_child(box)
	dlg.close_requested.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


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
	# Против ИИ бот всегда получает свой независимый случайный отряд — иначе он играл бы
	# зеркалом кита игрока, что не тот противник, каким должен быть бот. В hotseat двух людей
	# соперник (2-й игрок) получает случайный отряд только в «случайном бою», иначе — зеркало
	# (оба за одним устройством играют одним составом).
	var team_b := Loadout.random_team() if (vs_ai or Loadout.is_random_battle()) else team_a
	state.setup(team_a, team_b, randi() % Maps.count())   # случайная карта из ротации
	if vs_ai:
		Difficulty.apply(state, Consts.Player.B)   # модификаторы сложности достаются только боту
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
	_status("Подключение к %s…" % host, true)
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
	l.text = "Ничья!" if state.winner == Consts.DRAW else "Игрок %s победил!" % Consts.player_name(state.winner)
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
