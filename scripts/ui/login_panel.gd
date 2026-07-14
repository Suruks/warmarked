class_name LoginPanel
extends VBoxContainer

## Форма входа/регистрации аккаунта. Показывается в panel_host на старте игры,
## пока сессия не подтверждена сервером (main.gd решает, когда). Кнопка «Отмена»
## опциональна (show_cancel) — до первого успешного входа в этом запуске возвращаться
## некуда, поэтому main.gd её не запрашивает; после — запрашивает, чтобы можно было
## прервать повторный вход (например, при выходе в онлайн после разрыва связи).

signal login_requested(login: String, password: String)
signal register_requested(login: String, password: String)
signal cancelled

var _login_edit: LineEdit
var _password_edit: LineEdit
var _error_lbl: Label
var _login_btn: Button
var _register_btn: Button


func _init(show_cancel: bool = false) -> void:
	add_theme_constant_override("separation", 14)
	alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "Вход в аккаунт"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_login_edit = LineEdit.new()
	_login_edit.placeholder_text = "Логин"
	_login_edit.custom_minimum_size = Vector2(260, 44)
	_login_edit.text_submitted.connect(func(_t): _password_edit.grab_focus())
	add_child(_login_edit)

	_password_edit = LineEdit.new()
	_password_edit.placeholder_text = "Пароль"
	_password_edit.secret = true
	_password_edit.custom_minimum_size = Vector2(260, 44)
	_password_edit.text_submitted.connect(func(_t): _submit_login())
	add_child(_password_edit)

	_error_lbl = Label.new()
	_error_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	_error_lbl.visible = false
	add_child(_error_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)

	_register_btn = Button.new()
	_register_btn.text = "Зарегистрироваться"
	_register_btn.custom_minimum_size = Vector2(170, 46)
	_register_btn.pressed.connect(_submit_register)
	row.add_child(_register_btn)

	_login_btn = Button.new()
	_login_btn.text = "Войти"
	_login_btn.custom_minimum_size = Vector2(120, 46)
	_login_btn.pressed.connect(_submit_login)
	row.add_child(_login_btn)

	if show_cancel:
		var cancel_btn := Button.new()
		cancel_btn.text = "Отмена"
		cancel_btn.custom_minimum_size = Vector2(0, 40)
		cancel_btn.pressed.connect(func(): cancelled.emit())
		add_child(cancel_btn)


func set_error(text: String) -> void:
	_error_lbl.text = text
	_error_lbl.visible = not text.is_empty()


func set_busy(busy: bool) -> void:
	_login_btn.disabled = busy
	_register_btn.disabled = busy


func _submit_login() -> void:
	login_requested.emit(_login_edit.text, _password_edit.text)


func _submit_register() -> void:
	register_requested.emit(_login_edit.text, _password_edit.text)
