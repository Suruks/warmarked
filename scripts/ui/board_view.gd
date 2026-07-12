class_name BoardView
extends Control

## Рисует поле примитивами + иконки героев. Клетки/точки/подсветки/капканы — в _draw,
## юниты — тоже в _draw, но с анимируемыми смещениями (vis) и вспышками (tint).
## Логика везде в РЕАЛЬНЫХ координатах; вид можно повернуть на 180° (flip), чтобы игрок
## видел свой старт снизу — карта точечно-симметрична, поэтому поворот честен.
## Клик по клетке → сигнал cell_clicked (уже в реальных координатах).

signal cell_clicked(cell: Vector2i)
signal selected_effects_changed(text: String)   # эффекты выделенного юнита -> панель под очками

const CELL := 76
const PAD := 6

const MOVE_DUR := 0.36
const LUNGE_DUR := 0.32
const FLASH_UP := 0.20
const FLASH_DOWN := 0.60
const FLOAT_DUR := 1.60          # время жизни всплывающей цифры урона/лечения
const FLOAT_HOLD := 0.55         # доля жизни, которую цифра висит непрозрачной, прежде чем гаснуть

# Насколько далеко токен подаётся к цели (в долях клетки)
const LUNGE_MELEE := 0.32        # ближняя атака — заметный удар
const LUNGE_RANGED := 0.16       # дальняя — лёгкая отдача в сторону выстрела

const COL_DMG := Color(1.0, 0.36, 0.36)
const COL_HEAL := Color(0.38, 1.0, 0.52)

var board: Board
var snap: Dictionary = {}
var highlights: Array[Vector2i] = []
var flip := false          # true → вид повёрнут на 180° (перспектива игрока B)

var vis := {}    # id -> Vector2 (пиксельный центр токена, анимируется; уже в экранных коорд.)
var tint := {}   # id -> Color (цвет-вспышка поверх иконки, alpha=сила)
var floaters: Array = []   # [{uid:int, pos:Vector2, text:String, color:Color, p:float}] — всплывающие цифры
var _floater_uid := 0

var _font: Font
var markers: Array = []
var ghosts: Array = []

const COL_BG := Color("1c2029")
const COL_CELL := Color("2b313d")
const COL_OBSTACLE := Color("11141a")
const COL_GRID := Color("3a4150")
const COL_CP := Color("caa63c")
const COL_A := Color("4a90d9")
const COL_B := Color("d95c5c")
const COL_HL := Color(0.95, 0.85, 0.2, 0.28)


func _ready() -> void:
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(CELL * Consts.BOARD_W, CELL * Consts.BOARD_H)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(p_board: Board) -> void:
	board = p_board
	queue_redraw()


var my_player := Consts.Player.A   # чью перспективу показываем: свои — синие, враг — красный


# Задать перспективу игрока: свой старт снизу (флип для B) + свой цвет синий.
func set_view(player: int) -> void:
	var nf := (player == Consts.Player.B)
	if player == my_player and nf == flip:
		return
	my_player = player
	flip = nf
	if not snap.is_empty():
		_reset_visuals()
	queue_redraw()


func _owner_color(owner: int) -> Color:
	return COL_A if owner == my_player else COL_B   # COL_A — синий, COL_B — красный


# Полная перерисовка (смена фазы/раунда): гасим и незавершённые всплывающие цифры.
func render(p_snap: Dictionary) -> void:
	snap = p_snap
	floaters.clear()
	_reset_visuals()
	_emit_selected_effects()
	queue_redraw()


# Синхронизация после одного события плейбека: цифры продолжают жить своей анимацией.
func reconcile(p_snap: Dictionary) -> void:
	snap = p_snap
	_reset_visuals()
	_emit_selected_effects()
	queue_redraw()


func _reset_visuals() -> void:
	vis.clear()
	tint.clear()
	for u in snap.get("units", []):
		vis[u.id] = _scell(u.cell)
		tint[u.id] = Color(1, 1, 1, 0)


func set_highlights(cells: Array[Vector2i], _sel: Vector2i = Vector2i(-1, -1)) -> void:
	highlights = cells
	queue_redraw()


func clear_highlights() -> void:
	highlights = []
	queue_redraw()


func set_ghosts(g: Array) -> void:
	ghosts = g
	queue_redraw()


func set_markers(m: Array) -> void:
	markers = m
	queue_redraw()


var selected_unit_id := -1
func set_selected_unit(id: int) -> void:
	selected_unit_id = id
	_emit_selected_effects()
	queue_redraw()


func cell_of(id: int) -> Vector2i:
	for u in snap.get("units", []):
		if u.id == id:
			return u.cell
	return Vector2i(-1, -1)


# ------------------------------------------------------------- геометрия (флип)

func _flip_cell(c: Vector2i) -> Vector2i:
	if flip:
		return Vector2i(Consts.BOARD_W - 1 - c.x, Consts.BOARD_H - 1 - c.y)
	return c


func _center(c: Vector2i) -> Vector2:   # центр ЭКРАННОЙ клетки
	return Vector2(c.x * CELL + CELL * 0.5, c.y * CELL + CELL * 0.5)


func _scell(real: Vector2i) -> Vector2:  # пиксельный центр РЕАЛЬНОЙ клетки с учётом флипа
	return _center(_flip_cell(real))


func _cell_rect(real: Vector2i) -> Rect2:
	var c := _flip_cell(real)
	return Rect2(c.x * CELL + PAD, c.y * CELL + PAD, CELL - PAD * 2, CELL - PAD * 2)


# ------------------------------------------------------------- анимации (возвращают Tween)

func anim_move(id: int, to_cell: Vector2i) -> Tween:
	var from: Vector2 = vis.get(id, _scell(to_cell))
	var tw := create_tween()
	tw.tween_method(Callable(self, "_set_vis").bind(id), from, _scell(to_cell), MOVE_DUR)
	return tw


# Толчок в сторону цели и обратно. reach — глубина в долях клетки (ближняя/дальняя).
func anim_lunge(id: int, toward_cell: Vector2i, reach: float = LUNGE_MELEE) -> Tween:
	var start: Vector2 = vis.get(id, Vector2.ZERO)
	var dir := (_scell(toward_cell) - start)
	if dir.length() > 0.001:
		dir = dir.normalized()
	var peak := start + dir * CELL * reach
	var tw := create_tween()
	tw.tween_method(Callable(self, "_set_vis").bind(id), start, peak, LUNGE_DUR * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(Callable(self, "_set_vis").bind(id), peak, start, LUNGE_DUR * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return tw


func anim_flash(id: int, base: Color) -> Tween:
	var tw := create_tween()
	tw.tween_method(Callable(self, "_set_flash").bind(id, base), 0.0, 0.65, FLASH_UP)
	tw.tween_method(Callable(self, "_set_flash").bind(id, base), 0.65, 0.0, FLASH_DOWN).set_trans(Tween.TRANS_SINE)
	return tw


# Всплывающая цифра над юнитом: «-4» красным, «+3» зелёным. Не блокирует плейбек —
# живёт своей анимацией и снимает себя сама.
func anim_floater(id: int, text: String, col: Color) -> Tween:
	_floater_uid += 1
	var pos: Vector2 = vis.get(id, _scell(cell_of(id)))
	# цифры живут дольше одного события: если по этому же месту уже висит цифра
	# (капкан + засада за один вход), поднимаем новую выше, чтобы не наложились
	var stack := 0
	for other in floaters:
		if other.pos.distance_to(pos) < CELL * 0.9:
			stack += 1
	var f := {"uid": _floater_uid, "pos": pos - Vector2(0, stack * 24), "text": text, "color": col, "p": 0.0}
	floaters.append(f)
	var tw := create_tween()
	tw.tween_method(Callable(self, "_set_float").bind(f), 0.0, 1.0, FLOAT_DUR).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(Callable(self, "_drop_float").bind(f.uid))
	return tw


func anim_damage_number(id: int, amount: int) -> void:
	if amount > 0:
		anim_floater(id, "-%d" % amount, COL_DMG)


func anim_heal_number(id: int, amount: int) -> void:
	if amount > 0:
		anim_floater(id, "+%d" % amount, COL_HEAL)


func _set_vis(p: Vector2, id: int) -> void:
	vis[id] = p
	queue_redraw()


func _set_flash(a: float, id: int, base: Color) -> void:
	tint[id] = Color(base.r, base.g, base.b, a)
	queue_redraw()


func _set_float(p: float, f: Dictionary) -> void:
	f.p = p
	queue_redraw()


# Снимаем именно свой флоатер: два одинаковых по содержимому не должны стирать друг друга.
func _drop_float(uid: int) -> void:
	for i in floaters.size():
		if floaters[i].uid == uid:
			floaters.remove_at(i)
			break
	queue_redraw()


# ------------------------------------------------------------- ввод

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var screen := Vector2i(int(event.position.x) / CELL, int(event.position.y) / CELL)
		var c := _flip_cell(screen)   # экран → реальные (флип — сам себе обратный)
		if board != null and board.in_bounds(c):
			cell_clicked.emit(c)


# ------------------------------------------------------------- отрисовка

func _draw() -> void:
	if board == null:
		return
	if _font == null:
		_font = ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), COL_BG)
	# грид: идём по экранным клеткам, содержимое берём из реальной клетки
	for sy in Consts.BOARD_H:
		for sx in Consts.BOARD_W:
			var real := _flip_cell(Vector2i(sx, sy))
			var rect := Rect2(sx * CELL, sy * CELL, CELL, CELL)
			draw_rect(rect, COL_OBSTACLE if board.is_obstacle(real) else COL_CELL)
			draw_rect(rect, COL_GRID, false, 1.0)
	for cp in board.control_points:
		var ctr := _scell(cp)
		var r := CELL * 0.5 - 4
		draw_polyline(PackedVector2Array([
			ctr + Vector2(0, -r), ctr + Vector2(r, 0),
			ctr + Vector2(0, r), ctr + Vector2(-r, 0), ctr + Vector2(0, -r),
		]), COL_CP, 2.0)
	for h in highlights:
		draw_rect(_cell_rect(h), COL_HL)
	for t in snap.get("traps", []):
		_draw_hazard(t.cell, Icons.for_skill(Consts.Skill.TRAP), t.owner)
	for a in snap.get("ambushes", []):
		_draw_hazard(a.cell, Icons.for_skill(Consts.Skill.AMBUSH), a.owner)
	for g in ghosts:
		_draw_ghost(g)
	for u in snap.get("units", []):
		if u.alive:
			_draw_unit(u)
		else:
			_draw_grave(u)
	_draw_markers()
	_draw_floaters()   # цифры урона/лечения — поверх юнитов и маркеров


# Цифра всплывает над токеном, висит непрозрачной FLOAT_HOLD своей жизни, затем гаснет.
func _draw_floaters() -> void:
	for f in floaters:
		var p: float = f.p
		var ctr: Vector2 = f.pos + Vector2(0, -CELL * 0.34 - p * CELL * 0.50)
		var col: Color = f.color
		col.a = 1.0 if p <= FLOAT_HOLD else clampf(1.0 - (p - FLOAT_HOLD) / (1.0 - FLOAT_HOLD), 0.0, 1.0)
		var left := Vector2(ctr.x - CELL * 0.5, ctr.y)
		# тёмная подложка-обводка, чтобы цифра читалась на любом фоне
		draw_string(_font, left + Vector2(1, 1), f.text, HORIZONTAL_ALIGNMENT_CENTER, CELL, 24,
			Color(0, 0, 0, col.a * 0.75))
		draw_string(_font, left, f.text, HORIZONTAL_ALIGNMENT_CENTER, CELL, 24, col)


func _draw_hazard(cell: Vector2i, tex: Texture2D, owner: int) -> void:
	var ctr := _scell(cell)
	var col := _owner_color(owner)
	var s := CELL * 0.6
	if tex != null:
		draw_texture_rect(tex, Rect2(ctr - Vector2(s, s) * 0.5, Vector2(s, s)), false)
	draw_arc(ctr, s * 0.5 + 2, 0, TAU, 24, Color(col.r, col.g, col.b, 0.75), 2.0)


func _draw_ghost(g: Dictionary) -> void:
	var ctr := _scell(g.cell)
	_draw_icon(ctr, g.type, 0.45)
	var owner_col := _owner_color(g.owner)
	owner_col.a = 0.45
	draw_arc(ctr, CELL * 0.44, 0, TAU, 32, owner_col, 2.5)


func _draw_grave(u: Dictionary) -> void:
	var ctr := _scell(u.cell)
	var owner_col := _owner_color(u.owner)
	var tex := Icons.grave()
	var s := CELL * 0.72
	if tex != null:
		draw_texture_rect(tex, Rect2(ctr - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(1, 1, 1, 0.9))
	else:
		draw_string(_font, ctr + Vector2(-16, 6), "RIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.7, 0.7, 0.75))
	draw_arc(ctr, CELL * 0.40, 0, TAU, 28, Color(owner_col.r, owner_col.g, owner_col.b, 0.6), 2.0)
	# счётчик раундов до воскрешения
	var t: int = u.get("dead_timer", 0)
	if t > 0:
		draw_string(_font, Vector2(ctr.x - 26, ctr.y + CELL * 0.30), "респ %d" % t,
			HORIZONTAL_ALIGNMENT_CENTER, 52, 14, Color(0.85, 0.85, 0.9))


func _draw_unit(u: Dictionary) -> void:
	var ctr: Vector2 = vis.get(u.id, _scell(u.cell))
	var owner_col := _owner_color(u.owner)
	_draw_icon(ctr, u.type, 1.0)
	var fl: Color = tint.get(u.id, Color(1, 1, 1, 0))
	if fl.a > 0.001:
		draw_circle(ctr, CELL * 0.42, fl)
	draw_arc(ctr, CELL * 0.44, 0, TAU, 32, owner_col, 3.0)
	if u.id == selected_unit_id:
		draw_arc(ctr, CELL * 0.54, 0, TAU, 40, Color.WHITE, 4.0)   # выбранный герой — белым
	if u.get("shield", false):
		draw_arc(ctr, CELL * 0.50, 0, TAU, 32, Color(0.5, 0.9, 1.0), 2.5)
	# HP слева-сверху, мана справа-сверху — на полупрозрачной тёмной подложке
	_draw_stat(ctr, u.hp, true)
	_draw_stat(ctr, u.mana, false)
	_draw_debuffs(u, ctr)


# Число статистики в верхнем углу клетки на полупрозрачной тёмной подложке (left=true — левый/HP).
func _draw_stat(ctr: Vector2, value: int, left: bool) -> void:
	var w := 26.0
	var h := 20.0
	var x: float = (ctr.x - CELL * 0.5 + 3) if left else (ctr.x + CELL * 0.5 - 3 - w)
	var y := ctr.y - CELL * 0.5 + 2
	# HP (слева) — светло-красная, мана (справа) — светло-синяя
	var col := Color(1.0, 0.55, 0.55) if left else Color(0.55, 0.78, 1.0)
	draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0.55))
	draw_string(_font, Vector2(x, y + 16), str(value), HORIZONTAL_ALIGNMENT_CENTER, w, 18, col)


# Иконки активных эффектов рядком под героем. Рисуются только те, у кого есть арт
# (детали читаются в панели под очками — см. selected_effects_changed).
func _draw_debuffs(u: Dictionary, ctr: Vector2) -> void:
	var texes: Array = []
	for e in _active_effects(u):
		var tex := Icons.effect(e.file)
		if tex != null:
			texes.append(tex)
	if texes.is_empty():
		return
	var isz := 20.0
	var gap := 2.0
	var total := texes.size() * isz + (texes.size() - 1) * gap
	var x := ctr.x - total * 0.5
	var y := ctr.y + CELL * 0.5 - isz - 2
	for tex in texes:
		draw_rect(Rect2(x - 1, y - 1, isz + 2, isz + 2), Color(0, 0, 0, 0.6))
		draw_texture_rect(tex, Rect2(x, y, isz, isz), false)
		x += isz + gap


# Метаданные активных эффектов юнита: файл иконки, название, длительность, описание.
func _active_effects(u: Dictionary) -> Array:
	var out: Array = []
	if u.get("shield", false):
		out.append({"file": "effect_shield.png", "name": "Щит",
			"dur": "этот раунд", "desc": "Поглощает следующий эффект по юниту"})
	if u.get("reflex", false):
		out.append({"file": "effect_reflex.png", "name": "Рефлексы",
			"dur": "этот раунд", "desc": "Уходит из-под удара соседа и получает ману"})
	if u.get("hardened", false):
		out.append({"file": "effect_harden.png", "name": "Затвердение",
			"dur": "этот раунд", "desc": "Входящий урон меньше на %d" % Consts.HARDENING_REDUCTION})
	if u.get("shards", false):
		out.append({"file": "effect_shards.png", "name": "Осколки",
			"dur": "этот раунд", "desc": "Атаковавший враг получает %d в ответ" % Consts.SHARDS_DMG})
	if u.get("immobilized", false):
		out.append({"file": "effect_immobilized.png", "name": "Обездвижен",
			"dur": "до конца раунда", "desc": "Не может ходить и применять скиллы-перемещения"})
	if u.get("hunted", false):
		out.append({"file": "effect_hunt.png", "name": "Охота началась",
			"dur": "этот раунд", "desc": "Урон Охотника по цели ×%d" % Consts.HUNT_MULT})
	if u.get("disoriented", false):
		out.append({"file": "effect_disorient.png", "name": "Дезориентация",
			"dur": "этот раунд", "desc": "Следующий направленный скилл сработает в обратную сторону"})
	var bt: int = u.get("bleed", 0)
	if bt > 0:
		out.append({"file": "effect_blood_path.png", "name": "Кровавый след",
			"dur": _plural_turns(bt), "desc": "Каждое перемещение наносит %d урона" % Consts.BLEED_DMG})
	var na: int = u.get("no_attack", 0)
	if na > 0:
		out.append({"file": "effect_shackles.png", "name": "Оковы",
			"dur": _plural_turns(na), "desc": "Не может использовать базовую атаку"})
	var sl: int = u.get("slow", 0)
	if sl > 0:
		out.append({"file": "effect_slow.png", "name": "Замедление",
			"dur": _plural_turns(sl), "desc": "-%d к дальности хода" % Consts.SLOW_MOVE_PENALTY})
	return out


# Эффекты выделенного юнита -> текст для панели под очками (bbcode). Пусто, если нет.
func _emit_selected_effects() -> void:
	var text := ""
	if selected_unit_id >= 0:
		for u in snap.get("units", []):
			if u.id == selected_unit_id:
				text = _effects_text(u)
				break
	selected_effects_changed.emit(text)


func _effects_text(u: Dictionary) -> String:
	var effs := _active_effects(u)
	if effs.is_empty():
		return ""
	var lines: Array = []
	for e in effs:
		var icon := ""
		var path: String = Icons.DIR + e.file
		if ResourceLoader.exists(path):
			icon = "[img=20]%s[/img] " % path   # иконка эффекта перед строкой
		lines.append("%s[b]%s[/b]  [color=#8a93a3](%s)[/color]  %s" % [icon, e.name, e.dur, e.desc])
	return "\n".join(lines)


func _plural_turns(n: int) -> String:
	var m10 := n % 10
	var m100 := n % 100
	if m10 == 1 and m100 != 11:
		return "%d ход" % n
	if m10 >= 2 and m10 <= 4 and (m100 < 10 or m100 >= 20):
		return "%d хода" % n
	return "%d ходов" % n


func _draw_icon(ctr: Vector2, hero_type: int, alpha: float) -> void:
	var tex: Texture2D = Icons.hero(hero_type)
	var s := CELL * 0.88
	if tex != null:
		draw_texture_rect(tex, Rect2(ctr - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(1, 1, 1, alpha))
	else:
		draw_circle(ctr, CELL * 0.34, Color(0.5, 0.5, 0.5, alpha))


# Мелкие иконки нацеленных скиллов в клетках (напоминание на время планирования)
func _draw_markers() -> void:
	var by_cell := {}
	for m in markers:
		var key: Vector2i = m.cell
		if not by_cell.has(key):
			by_cell[key] = []
		by_cell[key].append(m)
	var sz := 26
	for cell_key in by_cell:
		var scr: Vector2i = _flip_cell(cell_key)
		var list: Array = by_cell[cell_key]
		var base_x: int = scr.x * CELL + 3
		var base_y: int = scr.y * CELL + CELL - sz - 3
		for i in list.size():
			var m: Dictionary = list[i]
			var tex: Texture2D = Icons.action(m.hero_type, m.action, m.get("skills", []))
			var col := _owner_color(m.get("owner", Consts.Player.A))
			var x: int = base_x + (i % 2) * (sz + 2)
			var y: int = base_y - int(i / 2) * (sz + 2)
			var r := Rect2(x, y, sz, sz)
			draw_rect(Rect2(x - 1, y - 1, sz + 2, sz + 2), Color(0, 0, 0, 0.6))
			if tex != null:
				draw_texture_rect(tex, r, false)
			draw_rect(r, col, false, 1.5)
