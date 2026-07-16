class_name DifficultyPanel
extends VBoxContainer

## Экран «Игра против ИИ» — на весь экран (фон background.png включает main.gd, как для
## «Коллекции»), а не диалогом поверх меню. Сверху — лидерборд личных рекордов, снизу —
## выбор уровня сложности и «Бой».
##
## Лидерборд приходит от сервера (Net.leaderboard_updated): один раз по запросу при открытии
## и дальше сам собой при каждом чужом рекорде, пока экран открыт — сервер шлёт таблицу всем
## подключённым (см. Net._finish_ai_match). Своя строка подсвечена.

signal closed
signal fight

const ROWS_VISIBLE := 8         # строк лидерборда без прокрутки (дальше — скроллом)
const ROW_H := 30
const GOLD := Color(1.0, 0.85, 0.3)      # своя строка и первое место
const DIM := Color(0.62, 0.66, 0.74)     # номер места, служебный текст

var _login := ""                # свой логин — подсветить свою строку в таблице
var _scroll: ScrollContainer
var _rows_box: VBoxContainer
var _status: Label
var _level_lbl: Label
var _slider: HSlider


# login — логин текущего игрока (для подсветки своей строки). Вызывать до добавления в дерево.
func setup(login: String) -> void:
	_login = login


func _ready() -> void:
	add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "Игра против ИИ"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_build_leaderboard()

	# Выбор сложности прижат к низу: между ним и лидербордом — растяжка, чтобы на высоком
	# экране пустота уходила в середину, а не оставляла кнопку «Бой» висеть посередине.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(spacer)

	_build_difficulty()
	_build_buttons()

	Net.leaderboard_updated.connect(_on_leaderboard)
	if not Net.request_leaderboard():
		_set_status("Лидерборд недоступен: нет связи с сервером")


# ------------------------------------------------------------- лидерборд

func _build_leaderboard() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	var head := Label.new()
	head.text = "Лидерборд"
	head.add_theme_font_size_override("font_size", 19)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)

	var sub := Label.new()
	sub.text = "лучший уровень сложности, на котором игрок победил ИИ"
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)

	# Карточка растёт по числу строк (см. _fit_rows), но не выше ROWS_VISIBLE: длинная таблица
	# прокручивается внутри, а не выдавливает выбор сложности за край экрана.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 0)
	_scroll.add_child(_rows_box)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	_set_status("Загрузка…")


func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.82)   # полупрозрачная подложка: фон читается, текст — тоже
	sb.border_color = Color(0.3, 0.33, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	return sb


func _on_leaderboard(rows: Array) -> void:
	for c in _rows_box.get_children():
		c.queue_free()
	_fit_rows(rows.size())
	if rows.is_empty():
		_set_status("Пока никто не побеждал ИИ — станьте первым")
		return
	_set_status("")
	for i in rows.size():
		_rows_box.add_child(_make_row(i + 1, String(rows[i]["login"]), int(rows[i]["level"])))


# Высота таблицы — ровно под её строки (до ROWS_VISIBLE), а не всегда под максимум: иначе
# короткий лидерборд оставлял бы внутри карточки пустой провал.
func _fit_rows(count: int) -> void:
	_scroll.custom_minimum_size = Vector2(0, mini(count, ROWS_VISIBLE) * ROW_H)


func _make_row(place: int, login: String, level: int) -> Control:
	var mine := login == _login
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_H)
	row.add_theme_constant_override("separation", 8)

	var n := Label.new()
	n.text = "%d." % place
	n.custom_minimum_size = Vector2(32, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.add_theme_font_size_override("font_size", 16)
	n.add_theme_color_override("font_color", GOLD if place == 1 else DIM)
	row.add_child(n)

	var name_lbl := Label.new()
	name_lbl.text = login
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	name_lbl.add_theme_font_size_override("font_size", 16)
	if mine:
		name_lbl.add_theme_color_override("font_color", GOLD)
	row.add_child(name_lbl)

	var lvl := Label.new()
	lvl.text = str(level)
	lvl.custom_minimum_size = Vector2(40, 0)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lvl.add_theme_font_size_override("font_size", 16)
	if mine:
		lvl.add_theme_color_override("font_color", GOLD)
	row.add_child(lvl)
	return row


func _set_status(text: String) -> void:
	_status.text = text
	_status.visible = not text.is_empty()


# ------------------------------------------------------------- выбор сложности

func _build_difficulty() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	_level_lbl = Label.new()
	_level_lbl.add_theme_font_size_override("font_size", 20)
	_level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_lbl.text = "Сложность: %d" % Difficulty.level
	col.add_child(_level_lbl)

	_slider = HSlider.new()
	_slider.min_value = Difficulty.MIN_LEVEL
	_slider.max_value = Difficulty.unlocked
	_slider.step = 1
	_slider.value = Difficulty.level
	_slider.custom_minimum_size = Vector2(0, 28)
	_slider.value_changed.connect(func(v: float): _level_lbl.text = "Сложность: %d" % int(v))
	col.add_child(_slider)

	var progress := Label.new()
	progress.add_theme_font_size_override("font_size", 14)
	progress.add_theme_color_override("font_color", DIM)
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress.text = ("Открыто %d из %d — победите на верхнем уровне, чтобы открыть ещё %d" %
		[Difficulty.unlocked, Difficulty.MAX_LEVEL, Difficulty.TIER]) if Difficulty.unlocked < Difficulty.MAX_LEVEL \
		else "Открыты все уровни сложности"
	col.add_child(progress)

	var record := Label.new()
	record.add_theme_font_size_override("font_size", 14)
	record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record.add_theme_color_override("font_color", GOLD if Difficulty.best > 0 else DIM)
	record.text = ("Ваш рекорд: %d" % Difficulty.best) if Difficulty.best > 0 \
		else "Побед над ИИ пока нет"
	col.add_child(record)


func _build_buttons() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	var back := Button.new()
	back.text = "Назад"
	back.custom_minimum_size = Vector2(0, 46)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func(): closed.emit())
	row.add_child(back)

	var go := Button.new()
	go.text = "Бой"
	go.custom_minimum_size = Vector2(0, 46)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(func():
		Difficulty.set_level(int(_slider.value))
		fight.emit())
	row.add_child(go)
