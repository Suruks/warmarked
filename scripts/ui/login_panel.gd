class_name LoginPanel
extends VBoxContainer

## Форма входа/регистрации аккаунта. Показывается в panel_host на старте игры,
## пока сессия не подтверждена сервером (main.gd решает, когда). Кнопка «Отмена»
## опциональна (show_cancel) — до первого успешного входа в этом запуске возвращаться
## некуда, поэтому main.gd её не запрашивает; после — запрашивает, чтобы можно было
## прервать повторный вход (например, при выходе в онлайн после разрыва связи).
##
## На вебе (особенно с телефона) поля Godot-а не вызывают экранную клавиатуру:
## экспериментальная виртуальная клавиатура Godot 4 на мобильных браузерах не работает
## (canvas теряет фокус, клавиатура перекрывает поле, Enter не отправляет форму —
## godotengine/godot#108355). Поэтому на вебе форму рисуем НАСТОЯЩИМИ HTML <input>
## поверх canvas: по ним нативно поднимается клавиатура, работают автозаполнение и
## менеджеры паролей. На десктопе/в нативных сборках остаётся обычная Godot-форма.

signal login_requested(login: String, password: String)
signal register_requested(login: String, password: String)
signal cancelled

# --- Godot-форма (десктоп/натив) ---
var _login_edit: LineEdit
var _password_edit: LineEdit
var _error_lbl: Label
var _login_btn: Button
var _register_btn: Button

# --- HTML-форма (веб) ---
var _js                     # синглтон JavaScriptBridge (только на вебе; иначе null)
var _login_cb               # JavaScriptObject-обёртки Callable — держим ссылки, иначе GC
var _register_cb
var _cancel_cb


func _init(show_cancel: bool = false) -> void:
	# JavaScriptBridge доступен только в веб-сборке. Обращаемся через Engine.get_singleton,
	# чтобы на десктопе скрипт не падал на неизвестном идентификаторе при загрузке.
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		_js = Engine.get_singleton("JavaScriptBridge")
		_build_html_form(show_cancel)
	else:
		_build_godot_form(show_cancel)


func _build_godot_form(show_cancel: bool) -> void:
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


func _build_html_form(show_cancel: bool) -> void:
	# Колбэки из JS в GDScript: create_callback возвращает JS-функцию, которая при вызове
	# передаёт в Callable ОДИН аргумент — Array из переданных в JS аргументов.
	_login_cb = _js.create_callback(_html_login)
	_register_cb = _js.create_callback(_html_register)
	_cancel_cb = _js.create_callback(_html_cancel)
	var win = _js.get_interface("window")
	win.godotLoginSubmit = _login_cb
	win.godotRegisterSubmit = _register_cb
	win.godotLoginCancel = _cancel_cb

	var cancel_js := ""
	if show_cancel:
		cancel_js = (
			"var cancelB=document.createElement('button');"
			+ "cancelB.textContent='Отмена';"
			+ "cancelB.style.cssText='padding:10px;font-size:15px;border-radius:8px;border:none;cursor:pointer;color:#ddd;background:transparent;';"
			+ "cancelB.onclick=function(){if(window.godotLoginCancel)window.godotLoginCancel();};"
			+ "card.appendChild(cancelB);"
		)

	# Прозрачный оверлей на весь экран (арт Godot просвечивает сзади) с центральной
	# полупрозрачной карточкой. pointer-events:none на контейнере пропускает тапы мимо
	# карточки в canvas; на самой карточке — auto, чтобы поля/кнопки ловили тапы.
	_js.eval(_HTML_FORM_JS.replace("/*__CANCEL__*/", cancel_js), true)


const _HTML_FORM_JS := """(function(){
	var old=document.getElementById('godot-login-overlay'); if(old)old.remove();
	var overlay=document.createElement('div'); overlay.id='godot-login-overlay';
	overlay.style.cssText='position:fixed;inset:0;z-index:100;display:flex;align-items:center;justify-content:center;pointer-events:none;font-family:sans-serif;';
	var card=document.createElement('div');
	card.style.cssText='pointer-events:auto;width:min(88vw,360px);box-sizing:border-box;padding:22px;border-radius:14px;background:rgba(15,15,20,0.72);box-shadow:0 8px 40px rgba(0,0,0,0.55);display:flex;flex-direction:column;gap:14px;color:#fff;';
	var title=document.createElement('div'); title.textContent='Вход в аккаунт';
	title.style.cssText='font-size:22px;text-align:center;font-weight:600;';
	var mkInput=function(ph,type){var i=document.createElement('input'); i.type=type; i.placeholder=ph; i.autocapitalize='off'; i.autocorrect='off'; i.spellcheck=false; i.style.cssText='width:100%;box-sizing:border-box;padding:12px 14px;font-size:17px;border-radius:8px;border:1px solid #555;background:#1e1e28;color:#fff;outline:none;'; return i;};
	var loginI=mkInput('Логин','text'); loginI.autocomplete='username';
	var passI=mkInput('Пароль','password'); passI.autocomplete='current-password';
	var err=document.createElement('div'); err.id='godot-login-error';
	err.style.cssText='display:none;color:#e64d4d;text-align:center;font-size:14px;';
	var mkBtn=function(txt,primary){var b=document.createElement('button'); b.textContent=txt; b.style.cssText='flex:1;padding:12px;font-size:16px;border-radius:8px;border:none;cursor:pointer;color:#fff;background:'+(primary?'#3a6ea5':'#444')+';'; return b;};
	var regB=mkBtn('Зарегистрироваться',false);
	var loginB=mkBtn('Войти',true);
	var row=document.createElement('div'); row.style.cssText='display:flex;gap:10px;';
	row.appendChild(regB); row.appendChild(loginB);
	loginB.onclick=function(){if(window.godotLoginSubmit)window.godotLoginSubmit(loginI.value,passI.value);};
	regB.onclick=function(){if(window.godotRegisterSubmit)window.godotRegisterSubmit(loginI.value,passI.value);};
	loginI.addEventListener('keydown',function(e){if(e.key==='Enter'){e.preventDefault();passI.focus();}});
	passI.addEventListener('keydown',function(e){if(e.key==='Enter'){e.preventDefault();if(window.godotLoginSubmit)window.godotLoginSubmit(loginI.value,passI.value);}});
	window.godotLoginSetError=function(m){err.textContent=m||''; err.style.display=(m&&m.length)?'block':'none';};
	window.godotLoginSetBusy=function(b){loginB.disabled=b; regB.disabled=b; loginB.style.opacity=b?'0.6':'1'; regB.style.opacity=b?'0.6':'1';};
	card.appendChild(title); card.appendChild(loginI); card.appendChild(passI); card.appendChild(err); card.appendChild(row);
	/*__CANCEL__*/
	overlay.appendChild(card); document.body.appendChild(overlay);
})();"""


func set_error(text: String) -> void:
	if _js != null:
		_js.eval("if(window.godotLoginSetError)window.godotLoginSetError(%s)" % JSON.stringify(text), true)
		return
	_error_lbl.text = text
	_error_lbl.visible = not text.is_empty()


func set_busy(busy: bool) -> void:
	if _js != null:
		_js.eval("if(window.godotLoginSetBusy)window.godotLoginSetBusy(%s)" % ("true" if busy else "false"), true)
		return
	_login_btn.disabled = busy
	_register_btn.disabled = busy


func _notification(what: int) -> void:
	# Убираем HTML-оверлей и глобальные хуки, когда панель удаляется (main.gd пересоздаёт
	# её при ошибке входа и очищает panel_host при успехе) — иначе форма зависла бы на экране.
	if what == NOTIFICATION_PREDELETE and _js != null:
		_js.eval(
			"var o=document.getElementById('godot-login-overlay'); if(o)o.remove();"
			+ "delete window.godotLoginSubmit; delete window.godotRegisterSubmit;"
			+ "delete window.godotLoginCancel; delete window.godotLoginSetError;"
			+ "delete window.godotLoginSetBusy;",
			true)


func _html_login(args: Array) -> void:
	login_requested.emit(String(args[0]), String(args[1]))


func _html_register(args: Array) -> void:
	register_requested.emit(String(args[0]), String(args[1]))


func _html_cancel(_args: Array) -> void:
	cancelled.emit()


func _submit_login() -> void:
	login_requested.emit(_login_edit.text, _password_edit.text)


func _submit_register() -> void:
	register_requested.emit(_login_edit.text, _password_edit.text)
