class_name ResolutionView
extends VBoxContainer

## Автопроигрывание событий раунда с анимацией: доска анимирует ход/атаку/урон, лог
## дописывает строку в такт. В конце — «Завершить раунд».

signal finished

const STEP_PAUSE := 0.22   # пауза после каждого события, чтобы глаз успевал за доской

var board_view: BoardView
var events: Array = []

var _log: RichTextLabel
var _btn: Button
var _title: Label
var _playing := false


func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _log != null:
		return
	add_theme_constant_override("separation", 8)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.text = "Разрешение раунда"
	add_child(_title)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 17)
	_log.custom_minimum_size = Vector2(360, 250)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_log)

	_btn = Button.new()
	_btn.custom_minimum_size = Vector2(0, 48)
	_btn.add_theme_font_size_override("font_size", 20)
	_btn.pressed.connect(_on_button)
	add_child(_btn)


func begin(p_events: Array, p_board_view: BoardView) -> void:
	_ensure_built()
	events = p_events
	board_view = p_board_view
	_log.clear()
	board_view.clear_highlights()
	if events.is_empty():
		_log.append_text("[i]Оба игрока спасовали — ничего не произошло.[/i]\n")
		_btn.text = "Завершить раунд"
		return
	_btn.text = "Проигрывание…"
	_btn.disabled = true
	_play()


func _play() -> void:
	_playing = true
	for e in events:
		_log.append_text(_format(e) + "\n")
		await _animate(e)
		board_view.reconcile(e.snapshot)
		await _delay(STEP_PAUSE)   # передышка между действиями — иначе за раундом не уследить
	_playing = false
	_btn.text = "Завершить раунд"
	_btn.disabled = false


func _on_button() -> void:
	if not _playing and _btn.text == "Завершить раунд":
		emit_signal("finished")


func _animate(e: Dictionary) -> void:
	match e.type:
		Consts.EventType.MOVE, Consts.EventType.KNOCKBACK:
			if e.has("actor") and e.has("to_cell"):
				await board_view.anim_move(e.actor, e.to_cell).finished
			else:
				await _delay(0.16)
		Consts.EventType.ATTACK, Consts.EventType.ABILITY:
			# толчок в сторону цели и обратно — и для ближней, и для дальней (у дальней слабее,
			# как отдача, плюс белая вспышка стрелка параллельно)
			if e.has("actor"):
				var tc: Vector2i = e.get("target_cell", Vector2i(-1, -1))
				if tc.x >= 0:
					var melee := _is_melee(e.actor, tc)
					if not melee:
						board_view.anim_flash(e.actor, Color(1, 1, 1))
					var reach := BoardView.LUNGE_MELEE if melee else BoardView.LUNGE_RANGED
					await board_view.anim_lunge(e.actor, tc, reach).finished
				else:
					await _delay(0.24)   # способность без цели (Вспышка, Засада)
			else:
				await _delay(0.2)
		Consts.EventType.DAMAGE, Consts.EventType.COLLISION:
			if e.has("victim"):
				board_view.anim_damage_number(e.victim, e.get("amount", 0))
				await board_view.anim_flash(e.victim, Color(1, 0.25, 0.25)).finished  # красная вспышка цели
			else:
				await _delay(0.2)
		Consts.EventType.HEAL:
			if e.has("victim"):
				board_view.anim_heal_number(e.victim, e.get("amount", 0))
				await board_view.anim_flash(e.victim, Color(0.3, 1.0, 0.45)).finished
			else:
				await _delay(0.2)
		Consts.EventType.DEATH:
			await _delay(0.4)
		Consts.EventType.INFO:
			pass   # заголовки слотов: паузу даст STEP_PAUSE, своя задержка не нужна
		_:
			await _delay(0.12)


func _is_melee(actor_id: int, target_cell: Vector2i) -> bool:
	var c := board_view.cell_of(actor_id)
	if c.x < 0:
		return false
	return max(absi(c.x - target_cell.x), absi(c.y - target_cell.y)) <= 1


func _delay(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _format(e: Dictionary) -> String:
	var t: int = e.type
	var col := "b6c0cf"
	match t:
		Consts.EventType.INFO: col = "8892a3"
		Consts.EventType.DAMAGE, Consts.EventType.COLLISION: col = "e08a8a"
		Consts.EventType.HEAL: col = "8ad39a"
		Consts.EventType.DEATH: col = "ff6b6b"
		Consts.EventType.KILL, Consts.EventType.SCORE: col = "ffd24a"
		Consts.EventType.TRAP_TRIGGER, Consts.EventType.AMBUSH_TRIGGER: col = "e0a54a"
		Consts.EventType.FIZZLE: col = "6a7180"
		Consts.EventType.SHIELD_ABSORB, Consts.EventType.SHIELD_ARMED: col = "7fd0ff"
	return "[color=#%s]%s[/color]" % [col, e.text]
