class_name CollectionPanel
extends VBoxContainer

## Экран «Коллекция»: для каждого героя выбираем SKILLS_PER_HERO скиллов из его пула.
## Порядок выбора = порядок слотов ABILITY1..3. Сохраняется в Loadout (и на диск).
##
## Герои, у которых пул ровно из SKILLS_PER_HERO скиллов, показываются как фиксированные:
## выбирать не из чего, но кит виден — это часть открытой информации в игре.

signal closed

const COL_ON := Color(1, 1, 1)
const COL_OFF := Color(0.42, 0.44, 0.5)

var _picked := {}          # hero_type -> Array выбранных скиллов (в порядке клика)
var _btns := {}            # hero_type -> {skill -> SkillButton}
var _counters := {}        # hero_type -> Label
var _desc: RichTextLabel
var _err: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	for h in Loadout.HEROES:
		_picked[h] = Loadout.get_skills(h)

	var title := Label.new()
	title.text = "Коллекция"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	scroll.add_child(col)
	for h in Loadout.HEROES:
		_build_hero(col, h)

	_desc = RichTextLabel.new()
	_desc.bbcode_enabled = true
	_desc.fit_content = true
	_desc.custom_minimum_size = Vector2(0, 84)
	_desc.add_theme_font_size_override("normal_font_size", 15)
	add_child(_desc)

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
	var save := Button.new()
	save.text = "Сохранить"
	save.custom_minimum_size = Vector2(0, 46)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(_on_save)
	row.add_child(save)


func _build_hero(col: VBoxContainer, hero_type: int) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)

	var icon := TextureRect.new()
	icon.texture = Icons.hero(hero_type)
	icon.custom_minimum_size = Vector2(34, 34)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)

	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 18)
	head.add_child(lbl)
	_counters[hero_type] = lbl

	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(flow)

	var pool := HeroDefs.pool(hero_type)
	var fixed: bool = pool.size() <= Consts.SKILLS_PER_HERO
	_btns[hero_type] = {}
	for skill in pool:
		var d := HeroDefs.skill_def(skill)
		var sb := SkillButton.new()
		sb.setup(Icons.for_skill(skill), d.mana, false)
		sb.hovered.connect(_on_hover.bind(skill))
		if not fixed:
			sb.pressed.connect(_on_toggle.bind(hero_type, skill))
		flow.add_child(sb)
		_btns[hero_type][skill] = sb
	_refresh(hero_type)


func _on_hover(skill: int) -> void:
	var d := HeroDefs.skill_def(skill)
	var lines: Array = ["[b]%s[/b]" % d.name]
	if d.mana > 0:
		lines.append("Мана: %d" % d.mana)
	lines.append(d.desc)
	_desc.text = "\n".join(lines)


func _on_toggle(hero_type: int, skill: int) -> void:
	_err.text = ""
	var cur: Array = _picked[hero_type]
	if skill in cur:
		cur.erase(skill)
	elif cur.size() >= Consts.SKILLS_PER_HERO:
		_err.text = "%s: уже выбрано %d — снимите один скилл" % [
			Consts.hero_name(hero_type), Consts.SKILLS_PER_HERO]
		return
	else:
		cur.append(skill)
	_refresh(hero_type)


func _refresh(hero_type: int) -> void:
	var cur: Array = _picked[hero_type]
	_counters[hero_type].text = "%s — %d/%d" % [
		Consts.hero_name(hero_type), cur.size(), Consts.SKILLS_PER_HERO]
	for skill in _btns[hero_type]:
		_btns[hero_type][skill].modulate = COL_ON if (skill in cur) else COL_OFF


func _on_save() -> void:
	for h in Loadout.HEROES:
		if (_picked[h] as Array).size() != Consts.SKILLS_PER_HERO:
			_err.text = "%s: нужно выбрать ровно %d скилла" % [
				Consts.hero_name(h), Consts.SKILLS_PER_HERO]
			return
	for h in Loadout.HEROES:
		Loadout.set_skills(h, _picked[h])
	Loadout.save_to_disk()
	closed.emit()
