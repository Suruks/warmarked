class_name CollectionPanel
extends VBoxContainer

## Экран «Коллекция»: собираем отряд из 3 троек по 3 скилла. Класс каждой тройки — любой
## (можно взять хоть три Охотника). Сверху — пул скиллов по классам, снизу — 9 слотов (3 тройки).
## Скиллы перетаскиваются из пула в слоты и обратно (drag&drop). Класс тройки определяется
## автоматически по первому положенному классовому скиллу; чужой класс в занятую тройку не кладётся.
## Один и тот же скилл можно давать разным тройкам. На диск не пишем — выбор применяется по «Сохранить».

signal closed

const N_TRIOS := 3
const SZ_SLOT := 50     # ячейка слота тройки (9 в ряд должны влезать в ширину)
const SZ_SOURCE := 95   # ячейка скилла в пуле (крупнее — по 5 в ряд)


# Ячейка скилла: и в пуле (source, перетаскиваемая), и в слоте тройки (slot).
class Cell:
	extends Control
	var host                 # CollectionPanel
	var mode: String = "source"   # "source" | "slot"
	var skill: int = -1
	var cls: int = -1
	var trio: int = -1
	var dimmed: bool = false
	var sz: float = 50.0
	var _font: Font
	var _dragging: bool = false

	func setup(p_host, p_mode: String, p_skill: int, p_cls: int, p_trio: int, p_sz: float) -> void:
		host = p_host
		mode = p_mode
		skill = p_skill
		cls = p_cls
		trio = p_trio
		sz = p_sz
		custom_minimum_size = Vector2(sz, sz)
		mouse_filter = Control.MOUSE_FILTER_STOP
		_font = ThemeDB.fallback_font
		mouse_entered.connect(func(): if skill >= 0: host.show_desc(skill))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and skill >= 0:
			host.show_desc(skill)   # тап показывает описание (мобилка)

	func _draw() -> void:
		if skill < 0:
			# пустой слот тройки
			draw_rect(Rect2(2, 2, sz - 4, sz - 4), Color(0.12, 0.13, 0.17, 0.7))
			draw_rect(Rect2(2, 2, sz - 4, sz - 4), Color(0.4, 0.42, 0.5), false, 1.5)
			return
		var a := 0.28 if dimmed else 1.0
		var tex := Icons.for_skill(skill)
		if tex != null:
			draw_texture_rect(tex, Rect2(0, 0, sz, sz), false, Color(1, 1, 1, a))
		else:
			draw_circle(Vector2(sz * 0.5, sz * 0.5), sz * 0.42, Color(0.32, 0.33, 0.38, a))
		var mana := HeroDefs.skill_def(skill).mana
		if mana > 0:
			var r := sz * 0.19
			var c := Vector2(sz - r - 2, sz - r - 2)
			var fs := int(sz * 0.28)
			draw_circle(c, r, Color(0.18, 0.42, 0.82, a))
			draw_string(_font, Vector2(c.x - r, c.y + fs * 0.35), str(mana), HORIZONTAL_ALIGNMENT_CENTER, r * 2, fs, Color(1, 1, 1, a))

	func _get_drag_data(_at: Vector2) -> Variant:
		if skill < 0:
			return null
		if mode == "source" and dimmed:
			return null   # уже разложен в тройку
		var prev := TextureRect.new()
		prev.texture = Icons.for_skill(skill)
		prev.custom_minimum_size = Vector2(sz, sz)
		prev.size = Vector2(sz, sz)
		set_drag_preview(prev)
		_dragging = true
		return {"skill": skill, "cls": cls, "from": mode, "trio": trio}

	# Конец перетаскивания: скилл из тройки, брошенный мимо (не принят ни слотом, ни областью
	# троек) — выкидывается из сборки. Так «избавиться» можно броском куда угодно.
	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END and _dragging:
			_dragging = false
			if mode == "slot" and is_instance_valid(host) and not get_viewport().gui_is_drag_successful():
				host.remove_from_trio(trio, skill)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		# Слот тройки поглощает любой перетаскиваемый скилл: сброс ВНУТРИ панели сборки
		# не выкидывает (валиден — кладём, невалиден — no-op). Ячейки пула дроп не принимают.
		return mode == "slot" and typeof(data) == TYPE_DICTIONARY and data.has("skill")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if mode == "slot" and host.can_place(trio, data):
			host.place_in_trio(trio, int(data.get("skill", -1)), int(data.get("cls", -1)))


# Контейнер троек: поглощает дроп в своих пределах (промежутки между слотами, шапки),
# чтобы сброс ВНУТРИ панели сборки не считался «за пределами» и не выкидывал скилл.
class TrioRow:
	extends HBoxContainer
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.has("skill")
	func _drop_data(_at: Vector2, _data: Variant) -> void:
		pass


var _trio_skills: Array = [[], [], []]
var _source_cells: Array = []          # все ячейки пула (для затемнения)
var _slot_cells: Array = [[], [], []]  # ячейки слотов по тройкам
var _trio_icon: Array = [null, null, null]
var _trio_label: Array = [null, null, null]
var _desc: RichTextLabel
var _err: Label
var _rolled_random := false   # отряд собран кнопкой «Рандом» и не правлен руками


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	# начальное состояние — из текущего отряда (произвольный состав, классы могут повторяться)
	var team := Loadout.get_team()
	for i in N_TRIOS:
		_trio_skills[i] = HeroDefs.sorted_by_mana((team[i].skills as Array))

	var title := Label.new()
	title.text = "Коллекция"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_build_source()

	# описание скилла по наведению/тапу
	_desc = RichTextLabel.new()
	_desc.bbcode_enabled = true
	_desc.fit_content = true
	_desc.scroll_active = false
	_desc.custom_minimum_size = Vector2(0, 78)
	_desc.add_theme_font_size_override("normal_font_size", 15)
	_desc.add_theme_font_size_override("bold_font_size", 16)
	add_child(_desc)

	_build_trios()

	_err = Label.new()
	_err.add_theme_color_override("font_color", Color(1, 0.5, 0.45))
	_err.add_theme_font_size_override("font_size", 15)
	_err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_err)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var back := Button.new()
	back.text = "Назад"
	back.custom_minimum_size = Vector2(0, 46)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func(): closed.emit())
	row.add_child(back)
	var rnd := Button.new()
	rnd.text = "Рандом"
	rnd.custom_minimum_size = Vector2(0, 46)
	rnd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rnd.pressed.connect(_on_random)
	row.add_child(rnd)
	var save := Button.new()
	save.text = "Сохранить"
	save.custom_minimum_size = Vector2(0, 46)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(_on_save)
	row.add_child(save)

	_refresh()


# ------------------------------------------------------------- пул по классам (перетаскиваемый)

func _build_source() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)

	for h in Loadout.HEROES:
		_add_source_section(col, Consts.hero_name(h), Icons.hero(h), HeroDefs.pool(h))
	_add_source_section(col, "Нейтральные", null, HeroDefs.neutrals())


func _add_source_section(col: VBoxContainer, title: String, icon_tex: Texture2D, skills: Array) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.add_child(icon)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 17)
	head.add_child(lbl)

	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	col.add_child(flow)
	for sk in HeroDefs.sorted_by_mana(skills):
		var cell := Cell.new()
		cell.setup(self, "source", sk, HeroDefs.hero_of_skill(sk), -1, SZ_SOURCE)
		flow.add_child(cell)
		_source_cells.append(cell)


# ------------------------------------------------------------- тройки слотов

func _build_trios() -> void:
	var row := TrioRow.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	for t in N_TRIOS:
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", 4)
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE   # дроп проходит сквозь к TrioRow (поглощение)
		row.add_child(group)
		# шапка: иконка героя + класс (авто по скиллам)
		var head := HBoxContainer.new()
		head.alignment = BoxContainer.ALIGNMENT_CENTER
		head.add_theme_constant_override("separation", 5)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_child(head)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(icon)
		_trio_icon[t] = icon
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(lbl)
		_trio_label[t] = lbl
		# 3 слота в ряд
		var slots := HBoxContainer.new()
		slots.add_theme_constant_override("separation", 4)
		slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_child(slots)
		_slot_cells[t] = []
		for i in Consts.SKILLS_PER_HERO:
			var cell := Cell.new()
			cell.setup(self, "slot", -1, -1, t, SZ_SLOT)
			slots.add_child(cell)
			_slot_cells[t].append(cell)


# ------------------------------------------------------------- логика drop (зовётся из Cell)

# Класс тройки = класс её классового скилла (нейтралы класс не задают); -1 если классовых нет.
func _trio_class_of(t: int) -> int:
	for sk in _trio_skills[t]:
		var h := HeroDefs.hero_of_skill(sk)
		if h >= 0:
			return h
	return -1


func can_place(trio: int, data: Dictionary) -> bool:
	var sk: int = int(data.get("skill", -1))
	if sk < 0:
		return false
	if sk in _trio_skills[trio]:
		return false
	if _trio_skills[trio].size() >= Consts.SKILLS_PER_HERO:
		return false
	if HeroDefs.is_neutral(sk):
		return true   # нейтрал — в любую тройку
	var cls := HeroDefs.hero_of_skill(sk)
	var tc := _trio_class_of(trio)
	if tc == -1:
		return true                # первый классовый скилл задаёт класс тройки (дубликаты классов разрешены)
	return tc == cls               # в одной тройке — только один класс


func place_in_trio(trio: int, skill: int, _cls: int) -> void:
	if not can_place(trio, {"skill": skill}):
		return
	_trio_skills[trio].append(skill)
	_trio_skills[trio] = HeroDefs.sorted_by_mana(_trio_skills[trio])   # слоты по возрастанию маны
	_rolled_random = false   # ручная правка отменяет «случайный бой»
	_err.text = ""
	_refresh()


func remove_from_trio(trio: int, skill: int) -> void:
	_trio_skills[trio].erase(skill)
	_rolled_random = false
	_refresh()


# «Рандом»: собрать отряд из трёх сбалансированных случайных китов (по одному каждого класса).
func _on_random() -> void:
	var team := Loadout.random_team()
	for t in N_TRIOS:
		_trio_skills[t] = HeroDefs.sorted_by_mana((team[t].skills as Array))
	_rolled_random = true
	_err.text = ""
	_refresh()


func show_desc(skill: int) -> void:
	var d := HeroDefs.skill_def(skill)
	var lines: Array = ["[b]%s[/b]" % d.name]
	if d.mana > 0:
		lines.append("Мана: %d" % d.mana)
	lines.append(d.desc)
	_desc.text = "\n".join(lines)


# ------------------------------------------------------------- обновление вида

func _refresh() -> void:
	for t in N_TRIOS:
		var tc := _trio_class_of(t)
		if tc >= 0:
			_trio_icon[t].texture = Icons.hero(tc)
			_trio_label[t].text = Consts.hero_name(tc)
		else:
			_trio_icon[t].texture = null
			_trio_label[t].text = "—"
		for i in Consts.SKILLS_PER_HERO:
			var cell: Cell = _slot_cells[t][i]
			if i < (_trio_skills[t] as Array).size():
				cell.skill = _trio_skills[t][i]
				cell.cls = HeroDefs.hero_of_skill(cell.skill)
			else:
				cell.skill = -1
				cell.cls = -1
			cell.queue_redraw()
	# Пул больше ничего не затемняет: любой скилл можно дать нескольким тройкам
	# (в т.ч. одинаковый класс — например, три Охотника со своими китами).
	for cell in _source_cells:
		if cell.dimmed:
			cell.dimmed = false
			cell.queue_redraw()


func _on_save() -> void:
	for t in N_TRIOS:
		if _trio_class_of(t) < 0 or (_trio_skills[t] as Array).size() != Consts.SKILLS_PER_HERO:
			_err.text = "В каждом отряде — 3 скилла и хотя бы один классовый"
			return
	var team: Array = []
	for t in N_TRIOS:
		team.append({"type": _trio_class_of(t), "skills": (_trio_skills[t] as Array).duplicate()})
	Loadout.set_team(team)
	Loadout.set_random_battle(_rolled_random)   # случайный отряд → сопернику тоже ролится свой
	closed.emit()
