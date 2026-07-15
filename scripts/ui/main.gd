extends Control

## Оркестратор: меню → локальный hotseat ИЛИ онлайн (через автолоад Net).
## Заголовки запуска:
##   сервер:      godot --headless --path . -- server
##   автотест-кл: godot --headless --path . -- autoclient <host>

enum Phase { MENU, HANDOFF, PLAN, RESOLVE, VICTORY }

const DEFAULT_HOST := "wss://warmarked.duckdns.org"

var state: MatchState
var resolver := Resolver.new()

const OPT_SIZE := 72    # кнопка настроек — крупная зона нажатия, палец на мобилке попадает уверенно (x1.5)
const OPT_TOP_PAD := 10 # отступ кнопки от самого верха экрана (не от TOP_MARGIN — кнопка крупнее его)

var board_view: BoardView
var _opp_bar: ScoreBar   # очки противника — сверху
var _my_bar: ScoreBar    # очки игрока — под доской
var panel_host: MarginContainer
var _menu_art: TextureRect   # арт в пустой верхней области меню (вне матча)
var _art_tex: Texture2D     # исходная текстура арта
var _art_atlas: AtlasTexture   # обрезка сверху под текущую ширину/высоту области арта (см. _apply_layout)
var _background: TextureRect   # фон в матче и коллекции (позади всего, на весь реальный экран)
var _effect_panel: RichTextLabel   # эффекты выделенного юнита — между очками и скиллами
var _options_btn: TextureButton    # кнопка настроек — справа в верхнем отступе экрана боя
var _version_lbl: Label     # версия — правый верхний угол меню
# Область раскладки боя/меню. Ширина/высота — из Layout (пересчитаны под реальный экран
# в _process), центрирована по горизонтали. Все элементы боя/меню — её дети: позиции
# берутся из Layout.* и переприменяются в _apply_layout при каждом пересчёте. Фон (_background)
# вне неё, на весь реальный экран.
var _content: Control
var _last_layout_size := Vector2(-1, -1)   # под какой размер вьюпорта посчитана текущая раскладка (см. _process)

# локальный режим
var _vs_ai := false          # PvE hotseat: игрок B — бот (AI.plan), человек играет за A
var round_order: Array = []
var plan_index: int = 0
var orders := {Consts.Player.A: [], Consts.Player.B: []}
var round_start_events: Array = []
var _just_unlocked_difficulty := false   # победа на верхнем открытом уровне только что открыла ещё TIER

# онлайн-режим
var online := false
var my_index := -1
var _auto := false
var _planning_pp: PlanningPanel = null

# аутентификация — обязательна при старте, см. _begin_auth()/_on_connected_ok()
var _menu_shown_once := false   # меню открывалось хотя бы раз в этом запуске
var _authed_connection := false   # текущий сокет ещё жив и авторизован
var _pending_host := ""           # куда повторить попытку подключения
var _current_login := ""


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
		_begin_auth(_arg_value(args, ["autoclient", "--autoclient"], "127.0.0.1"))
	else:
		# Вход обязателен: без аккаунта недоступно вообще ничего, включая хотсит и игру с ИИ —
		# меню строится только после успешного auth_ok (см. _on_auth_ok).
		_begin_auth(DEFAULT_HOST)


# Значение аргумента, идущего сразу за одним из ключей (для «-- autoclient <host>»).
func _arg_value(args: Array, keys: Array, fallback: String) -> String:
	for i in args.size():
		if args[i] in keys and i + 1 < args.size():
			return args[i + 1]
	return fallback


# На портретном экране (выше, чем шире — телефон/планшет вертикально) растягиваем канвас без
# чёрных полос по бокам: EXPAND сам расширяет сверх базовых 540x1200 ту ось (обычно высоту),
# которой не хватает, чтобы покрыть экран целиком. На ландшафте (ПК и вообще где угодно шире,
# чем выше) полосы по бокам ожидаемы и неизбежны — но область самой игры держим фиксированной
# пропорции 1:2 (а не 540:1200 ≈ 0.45:1, как в портрете), а не просто «оставляем как есть»:
# content_scale_size — это ЕДИНСТВЕННЫЙ параметр, влияющий на пропорцию при KEEP, база проекта
# (540x1200) тут ни при чём, поэтому меняем её только для книжной/альбомной ветки.
func _adapt_stretch_for_orientation() -> void:
	var sz := DisplayServer.window_get_size()
	var portrait := sz.y > sz.x
	var win := get_window()
	if portrait:
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		win.content_scale_size = Vector2i(540, 1200)
	else:
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		win.content_scale_size = Vector2i(600, 1200)   # 1:2


# Раскладку не привязываем к сигналам resize/размера: момент, когда смена content_scale_aspect
# фактически долетает до Viewport.size — недокументированная деталь движка, и сигналы вроде
# Viewport.size_changed после ПРОГРАММНОЙ смены аспекта могут не сработать (было замечено —
# раскладка так и оставалась посчитана под старый размер после смены аспекта). Вместо этого
# раз в кадр сверяем реальный размер вьюпорта с тем, под который посчитана текущая раскладка
# (_last_layout_size), и пересчитываем при малейшем расхождении — дешёвая проверка (Vector2 ==),
# а взамен раскладка гарантированно сходится к актуальному размеру максимум за один кадр.
func _process(_delta: float) -> void:
	if _content == null:
		return   # раскладка ещё не построена (первый кадр до _build_layout)
	var avail := get_viewport().get_visible_rect().size
	if avail != _last_layout_size:
		_last_layout_size = avail
		Layout.recompute(avail.x, avail.y)
		_apply_layout()


func _build_layout() -> void:
	# Фон матча и коллекции — на весь РЕАЛЬНЫЙ экран (не только раскладку), позади всего
	# остального (первым в дереве, вне _content) — иначе по бокам от раскладки было бы пусто.
	# Высота ЯВНО берётся из Layout.SCREEN_H (не из anchor-растяжения по родителю и не из
	# отдельного опроса вьюпорта) — это ТО ЖЕ САМОЕ число, которым _apply_layout уже надёжно
	# (через опрос в _process, см. его комментарий) выставляет высоту _content, так что фон
	# гарантированно совпадает по нижнему краю с раскладкой боя/меню, а не может от неё отстать.
	_background = TextureRect.new()
	_background.texture = Icons.tex_opt("res://graphics/background.png")
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.visible = false
	add_child(_background)

	# Раскладка боя/меню — размер Layout.SCREEN_W x Layout.SCREEN_H (растёт вместе с клеткой
	# доски под реальный экран, см. Layout.recompute), центрирована по горизонтали в реальном
	# экране (анкоры 0.5/0.5 + офсеты ±половина ширины пересчитываются в _apply_layout).
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.anchor_left = 0.5
	_content.anchor_right = 0.5
	_content.anchor_top = 0.0
	_content.anchor_bottom = 0.0
	add_child(_content)

	# Арт-заставка меню — на ВСЮ область меню (SCREEN_W x SCREEN_H), позади всего остального,
	# а не только в верхней полосе: иначе ниже неё просвечивал отдельный фон (background.png,
	# тёмные геометрические абстракции) — чужеродный на фоне сцены с охотником и драконом.
	# STRETCH_KEEP_ASPECT_COVERED обрезает картинку по высоте, отдавая предпочтение НИЖНЕЙ части
	# (ботинки охотника видны целиком, а весь запас неба/леса НАД драконом обрезается) — картинка
	# выглядит «подвинутой вверх», упираясь прямо в статус-бар. AtlasTexture с ручным region_rect
	# вместо этого обрезает СНИЗУ, если контейнер шире картинки (запас неба остаётся, дракон и
	# охотник целиком видны, теряется только трава у самых ботинок), либо обрезает бока, если
	# контейнер уже картинки (полная высота видна) — см. _apply_layout()/_update_art_region().
	_art_tex = Icons.tex_opt("res://graphics/art.jpg")
	_art_atlas = AtlasTexture.new()
	_art_atlas.atlas = _art_tex
	_menu_art = TextureRect.new()
	_menu_art.texture = _art_atlas
	_menu_art.position = Vector2.ZERO
	_menu_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_menu_art.stretch_mode = TextureRect.STRETCH_SCALE
	_menu_art.visible = false
	_content.add_child(_menu_art)

	# Версия — маленькая надпись в правом верхнем углу главного меню (белым, поверх арта).
	# Ребёнок _menu_art: показывается/прячется вместе с ним, отдельно видимость вести не нужно.
	_version_lbl = Label.new()
	_version_lbl.text = "v%d" % Consts.PROTOCOL_VERSION
	_version_lbl.add_theme_font_size_override("font_size", 13)
	_version_lbl.add_theme_color_override("font_color", Color.WHITE)
	_version_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_version_lbl.size = Vector2(64, 18)
	_menu_art.add_child(_version_lbl)

	# очки противника — сверху (вместо строки инфо)
	_opp_bar = ScoreBar.new()
	_content.add_child(_opp_bar)

	board_view = BoardView.new()
	_content.add_child(board_view)
	board_view.setup(Board.new())   # инициализация пустой доской; матч подменит на state.board

	# очки игрока — под доской, над панелью
	_my_bar = ScoreBar.new()
	_content.add_child(_my_bar)

	# полоса эффектов выделенного юнита — между очками и скиллами
	_effect_panel = RichTextLabel.new()
	_effect_panel.bbcode_enabled = true
	_effect_panel.scroll_active = false
	_effect_panel.clip_contents = true
	_effect_panel.add_theme_font_size_override("normal_font_size", 15)
	_effect_panel.add_theme_font_size_override("bold_font_size", 16)
	_content.add_child(_effect_panel)
	board_view.selected_effects_changed.connect(func(text): _effect_panel.text = text)

	panel_host = MarginContainer.new()
	_content.add_child(panel_host)

	# кнопка настроек — в правом краю верхнего отступа, видна только в матче.
	# Добавляем последней, чтобы рисовалась поверх остального.
	_options_btn = TextureButton.new()
	_options_btn.texture_normal = Icons.tex_opt("res://graphics/options.png")
	_options_btn.ignore_texture_size = true
	_options_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_options_btn.custom_minimum_size = Vector2(OPT_SIZE, OPT_SIZE)
	_options_btn.pressed.connect(_on_options_pressed)
	_content.add_child(_options_btn)

	# доска и счёт скрыты вне матча — в меню/коллекции их нет, только в игре
	board_view.visible = false
	_opp_bar.visible = false
	_my_bar.visible = false
	_effect_panel.visible = false
	_options_btn.visible = false

	var avail := get_viewport().get_visible_rect().size
	_last_layout_size = avail
	Layout.recompute(avail.x, avail.y)
	_apply_layout()


# Раскладывает все элементы боя/меню по текущим Layout.*-значениям — вызывается один раз при
# построении и заново при каждом пересчёте (resize/поворот), когда клетка доски (и всё, что от
# неё зависит) могла измениться. Сама доска и панель «Готово» растягиваются вместе с Layout.PANEL_W —
# см. board_view.set_cell_size и planning_panel.gd (перечитывает Layout.PANEL_W/PANEL_H заново).
func _apply_layout() -> void:
	_content.offset_left = -Layout.SCREEN_W / 2.0
	_content.offset_right = Layout.SCREEN_W / 2.0
	_content.offset_top = 0.0
	_content.offset_bottom = Layout.SCREEN_H

	_update_background()

	_menu_art.size = Vector2(Layout.SCREEN_W, Layout.SCREEN_H)
	_update_art_region()
	_version_lbl.position = Vector2(Layout.SCREEN_W - 64 - 8, 8)

	_opp_bar.position = Vector2(Layout.BOARD_X, Layout.SCORE_TOP_Y)
	_opp_bar.size = Vector2(Layout.BOARD_PX, Layout.SCORE_H)

	board_view.position = Vector2(Layout.BOARD_X, Layout.BOARD_Y)
	board_view.set_cell_size(Layout.cell_size)

	_my_bar.position = Vector2(Layout.BOARD_X, Layout.SCORE_BOTTOM_Y)
	_my_bar.size = Vector2(Layout.BOARD_PX, Layout.SCORE_H)

	_effect_panel.position = Vector2(Layout.BOARD_X + 6, Layout.EFFECT_Y)
	_effect_panel.size = Vector2(Layout.PANEL_W - 12, Layout.EFFECT_H)

	panel_host.position = Vector2(Layout.BOARD_X, Layout.PANEL_TOP)
	panel_host.custom_minimum_size = Vector2(Layout.PANEL_W, Layout.PANEL_H)
	panel_host.size = panel_host.custom_minimum_size

	# Кнопка крупнее TOP_MARGIN — свисает поверх верха полосы очков соперника (та рисуется
	# первой, кнопка последней). Не страшно: очки в полосе центрированы по горизонтали и
	# ничем не перекрываются, а сам TOP_MARGIN остаётся маленьким — под клетку доски больше места.
	_options_btn.position = Vector2(
		Layout.SCREEN_W - OPT_SIZE - Layout.BOARD_X,
		OPT_TOP_PAD)


# Область арта (SCREEN_W x SCREEN_H, вся область меню) — если она шире картинки, обрезаем
# лишнее СНИЗУ (запас неба + дракон + охотник целиком остаются); если уже картинки — обрезаем
# бока симметрично, высота остаётся полной. Вместо стандартной обрезки TextureRect по центру.
func _update_art_region() -> void:
	var tex_w := float(_art_tex.get_width())
	var tex_h := float(_art_tex.get_height())
	var container_ar := Layout.SCREEN_W / Layout.SCREEN_H
	var tex_ar := tex_w / tex_h
	if container_ar >= tex_ar:
		var region_h := minf(tex_w / container_ar, tex_h)
		_art_atlas.region = Rect2(0, 0, tex_w, region_h)
	else:
		var region_w := tex_h * container_ar
		_art_atlas.region = Rect2((tex_w - region_w) / 2.0, 0, region_w, tex_h)


# Фон покрывает ВЕСЬ реальный видимый экран без пустот (режим «cover», как в CSS): масштаб —
# по БОЛЬШЕЙ из осей (max по ширине/высоте), пропорции сохраняются, лишнее по одной из осей
# выходит за кромку и обрезается, центрируем. Размер экрана берём из _last_layout_size — это
# фактический размер вьюпорта, под который _process уже посчитал текущую раскладку (тот же
# надёжный ежекадровый опрос), а НЕ Layout.SCREEN_H (там maxf с мин. высотой панели, из-за
# чего фон мог уезжать низом за кромку).
func _update_background() -> void:
	var tex := _background.texture
	if tex == null:
		return
	var screen := _last_layout_size
	var scale := maxf(screen.x / float(tex.get_width()), screen.y / float(tex.get_height()))
	var size := Vector2(tex.get_width() * scale, tex.get_height() * scale)
	_background.size = size
	_background.position = (screen - size) / 2.0


func _connect_net() -> void:
	Net.connected_ok.connect(_on_connected_ok)
	Net.connect_failed.connect(func(): _on_connect_trouble("Не удалось подключиться к серверу."))
	Net.server_gone.connect(func(): _on_connect_trouble("Сервер недоступен."))
	Net.auth_ok.connect(_on_auth_ok)
	Net.auth_failed.connect(_on_auth_failed)
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
	_on_connect_trouble("Версия игры не совпадает с сервером.\nСервер: v%d, у вас: v%d.\nОбновите страницу (Ctrl+Shift+R) или клиент." % [server_version, client_version])


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

	# Сдаться — прервать текущий бой и вернуться в меню. Рвём сокет только для онлайн-матча:
	# в хотсите/против ИИ сеть не участвует, а сокет — это ещё и постоянная сессия входа,
	# закрывать её здесь незачем.
	var surrender := Button.new()
	surrender.text = "Сдаться"
	surrender.custom_minimum_size = Vector2(0, 44)
	surrender.pressed.connect(func():
		dlg.queue_free()
		if online:
			Net.disconnect_net()
			_authed_connection = false
		_show_menu())
	box.add_child(surrender)

	dlg.add_child(box)
	dlg.close_requested.connect(dlg.queue_free)
	dlg.confirmed.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _status_box(text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 22)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return box


# show_cancel — показать кнопку «Отмена» под текстом (поиск соперника/ошибки до начала матча):
# обрывает соединение и возвращает в уже открытое меню. Во время самого матча (ожидание хода
# соперника) кнопки нет — там для выхода уже есть «Сдаться» в настройках. Доступна только когда
# меню уже открывалось хотя бы раз — до первого входа возвращаться некуда (см. _status_retry).
func _status(text: String, show_cancel: bool = false) -> void:
	var box := _status_box(text)
	if show_cancel:
		var btn := Button.new()
		btn.text = "Отмена"
		btn.custom_minimum_size = Vector2(160, 46)
		btn.pressed.connect(func():
			Net.disconnect_net()
			_authed_connection = false
			_show_menu())
		box.add_child(btn)
	_set_panel(box)


# Экран без «Отмены»: до первого успешного входа в аккаунт возвращаться некуда, поэтому вместо
# отмены — повтор попытки подключения/входа на тот же хост.
func _status_retry(text: String) -> void:
	var box := _status_box(text)
	var btn := Button.new()
	btn.text = "Повторить попытку"
	btn.custom_minimum_size = Vector2(220, 46)
	btn.pressed.connect(func(): _begin_auth(_pending_host))
	box.add_child(btn)
	_set_panel(box)


func _on_connect_trouble(text: String) -> void:
	_authed_connection = false
	if not _menu_shown_once:
		_status_retry(text)   # ещё нет меню — только это и есть текущий экран
	elif online:
		_status(text, true)   # мешает онлайн-подключению/поиску/матчу — показываем
	# иначе (меню, хотсит, ИИ, коллекция) сокет умер фоном — сокет умер, экран не трогаем;
	# следующий клик «Онлайн» увидит _authed_connection == false и переподключится сам


# ============================================================ меню

func _show_menu() -> void:
	state = null
	_update_score_bars()
	_background.visible = true   # фон на весь экран — без него ниже арта пусто на растянутых экранах
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
	b_online.pressed.connect(func():
		online = true
		_menu_art.visible = false
		if _authed_connection:
			_status("Поиск соперника…", true)
			Net.join_queue()
		else:
			_begin_auth(DEFAULT_HOST))   # разрыв связи со старта — тихо переподключаемся по токену
	box.add_child(b_online)

	var b_coll := Button.new()
	b_coll.text = "Коллекция"
	b_coll.custom_minimum_size = Vector2(0, 52)
	b_coll.add_theme_font_size_override("font_size", 20)
	b_coll.pressed.connect(_show_collection)
	box.add_child(b_coll)

	var acc_row := HBoxContainer.new()
	acc_row.alignment = BoxContainer.ALIGNMENT_CENTER
	acc_row.add_theme_constant_override("separation", 8)
	var acc_lbl := Label.new()
	acc_lbl.text = "Аккаунт: %s" % _current_login
	acc_lbl.add_theme_font_size_override("font_size", 14)
	acc_row.add_child(acc_lbl)
	var b_logout := Button.new()
	b_logout.text = "Выйти"
	b_logout.custom_minimum_size = Vector2(70, 32)
	b_logout.pressed.connect(func():
		Account.clear_session()
		Net.disconnect_net()
		_authed_connection = false
		_menu_shown_once = false   # снова обязателен вход, прежде чем меню откроется опять
		_begin_auth(DEFAULT_HOST))
	acc_row.add_child(b_logout)
	box.add_child(acc_row)

	_set_panel(box)


# Окно выбора сложности перед боем с ИИ: слайдер MIN_LEVEL..unlocked + «Бой»/«Отмена».
# Максимум растёт блоками по Difficulty.TIER — победа на старшем открытом уровне открывает
# следующий блок (см. _on_local_resolution_done/_check_difficulty_unlock), вплоть до MAX_LEVEL.
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
	slider.max_value = Difficulty.unlocked
	slider.step = 1
	slider.value = Difficulty.level
	slider.custom_minimum_size = Vector2(0, 28)
	slider.value_changed.connect(func(v: float): lbl.text = "Сложность: %d" % int(v))
	box.add_child(slider)

	var progress := Label.new()
	progress.add_theme_font_size_override("font_size", 14)
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.text = ("Открыто %d из %d — победите на верхнем уровне, чтобы открыть ещё %d" %
		[Difficulty.unlocked, Difficulty.MAX_LEVEL, Difficulty.TIER]) if Difficulty.unlocked < Difficulty.MAX_LEVEL \
		else "Открыты все уровни сложности"
	box.add_child(progress)

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
	cp.team_saved.connect(func(): Net.save_loadout(Loadout.team_net()))
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
		_check_difficulty_unlock()
		_show_victory()
	else:
		_local_new_round()


# Человек всегда играет за A против бота (см. _local_begin_plan) — победа A на текущем
# Difficulty.level, если это был верхний открытый уровень, открывает следующий блок и
# сохраняет прогресс на сервере (переживает переустановку/смену устройства, как и отряд).
func _check_difficulty_unlock() -> void:
	if not (_vs_ai and state.winner == Consts.Player.A):
		return
	_just_unlocked_difficulty = Difficulty.record_win(Difficulty.level)
	if _just_unlocked_difficulty:
		Net.save_difficulty_unlocked(Difficulty.unlocked)


# ============================================================ аутентификация

# Общая точка входа и для старта игры (обязательный вход до меню), и для повторного выхода
# в онлайн после разрыва связи — оба раза нужно (пере)подключиться и аутентифицироваться.
func _begin_auth(host: String) -> void:
	_menu_art.visible = false
	if host == "":
		host = DEFAULT_HOST
	_pending_host = host
	_status("Подключение к %s…" % host)
	Net.start_client(host)


func _on_connected_ok() -> void:
	if _auto:
		var auto_login := "auto_%d_%d" % [int(Time.get_unix_time_from_system()), randi()]
		Net.register(auto_login, "autoclient-pass")
		return
	var sess := Account.load_session()
	if not sess.is_empty():
		_status("Вход…")
		Net.resume_session(sess["token"])
	else:
		_show_login_panel("", _menu_shown_once)


func _show_login_panel(error_text: String = "", show_cancel: bool = false) -> void:
	_menu_art.visible = false
	var lp := LoginPanel.new(show_cancel)
	if not error_text.is_empty():
		lp.set_error(error_text)
	lp.login_requested.connect(func(l: String, p: String):
		_status("Вход…")
		Net.login(l, p))
	lp.register_requested.connect(func(l: String, p: String):
		_status("Регистрация…")
		Net.register(l, p))
	if show_cancel:
		lp.cancelled.connect(func():
			Net.disconnect_net()
			_authed_connection = false
			_show_menu())
	_set_panel(lp)


func _on_auth_ok(login: String, token: String, _rating: int, loadout: Array, difficulty_unlocked: int) -> void:
	Account.save_session(login, token)
	Loadout.set_team(Loadout.sanitize_team_net(loadout))   # сервер уже прислал сохранённый (или дефолтный) отряд
	Difficulty.set_unlocked(difficulty_unlocked)
	_current_login = login
	_authed_connection = true
	if _auto:
		Net.join_queue()
		return
	if not _menu_shown_once:
		_menu_shown_once = true
		_show_menu()
	else:
		# Повторный вход был затребован кнопкой «Онлайн» после разрыва связи — сразу в очередь.
		online = true
		_status("Поиск соперника…", true)
		Net.join_queue()


func _on_auth_failed(reason: String) -> void:
	_authed_connection = false
	if _auto:
		push_error("[autoclient] авторизация не удалась: %s" % reason)
		get_tree().quit(1)
		return
	var silent_resume := reason == "invalid_session"
	if silent_resume:
		Account.clear_session()   # токен протух/отозван — тихо просим войти заново
	_show_login_panel("" if silent_resume else _auth_error_text(reason), _menu_shown_once)


func _auth_error_text(reason: String) -> String:
	match reason:
		"login_taken":
			return "Такой логин уже занят."
		"wrong_password":
			return "Неверный пароль."
		"not_found":
			return "Такого логина нет. Зарегистрируйтесь."
		"empty_fields":
			return "Заполните логин и пароль."
		_:
			return "Не удалось войти. Попробуйте ещё раз."


# ============================================================ онлайн

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
	if _just_unlocked_difficulty:
		_just_unlocked_difficulty = false
		var u := Label.new()
		u.text = "Открыт новый уровень сложности: до %d!" % Difficulty.unlocked
		u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		u.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		box.add_child(u)
	var btn := Button.new()
	btn.text = "В меню"
	btn.custom_minimum_size = Vector2(0, 46)
	btn.pressed.connect(func():
		if online:
			Net.disconnect_net()
			_authed_connection = false
		_show_menu())
	box.add_child(btn)
	_set_panel(box)
