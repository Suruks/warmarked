class_name Settings
extends RefCounted

## Пользовательские настройки. Живут за АККАУНТОМ, а не на диске: приходят при входе
## (main.gd/_on_auth_ok) и уезжают на сервер при закрытии окна настроек (Net.save_settings) —
## как отряд и прогресс сложности, они переживают переустановку и следуют за игроком на другое
## устройство. Источник истины — БД сервера, здесь — зеркало на сессию.
##
## Лежит в model/, хотя правит и UI, и звук: настройки санирует СЕРВЕР (PlayerDB.save_settings),
## а слою БД неоткуда знать про scripts/ui/.

const VOLUME_DEFAULT := 1.0

## Громкость игры, 0..1 (линейная). Применяется к мастер-шине — то есть ко всему звуку разом,
## а не к отдельным голосам Sfx: слайдер один, и «громкость» для игрока значит именно это.
static var volume := VOLUME_DEFAULT

## Отладка: разрешить выбирать невозможные цели. Когда включено — корректность цели
## не проверяется: можно таргетить стены для перемещения, недостижимые клетки и т.п.
## Работает локально; в онлайне сервер всё равно санитизирует приказы, поэтому «невозможный»
## приказ будет отклонён сервером (рассинхрона это не создаёт — обе стороны играют то, что
## одобрил сервер).
static var allow_impossible_targets := false


static func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	var bus := AudioServer.get_bus_index("Master")
	# Ровный ноль — это mute, а не «очень тихо»: linear_to_db(0) даёт -inf, и полагаться на то,
	# как шина обойдётся с бесконечностью, незачем — тишину можно попросить прямо.
	AudioServer.set_bus_mute(bus, is_zero_approx(volume))
	if not is_zero_approx(volume):
		AudioServer.set_bus_volume_db(bus, linear_to_db(volume))


# ------------------------------------------------------------------ сеть/БД

static func to_net() -> Dictionary:
	return {"vol": volume, "imp": allow_impossible_targets}


## Присланное клиентом или прочитанное из БД — внешние данные: битое поле не роняет и не
## включает втихую отладочный режим, а вырождается в дефолт. Возвращает ВСЕГДА полный словарь,
## поэтому досанировать поля вызывающему не нужно (как Loadout.canon_team_net с отрядом).
static func sanitize_net(data: Variant) -> Dictionary:
	var d: Dictionary = data if typeof(data) == TYPE_DICTIONARY else {}
	var raw_vol: Variant = d.get("vol")
	var vol := VOLUME_DEFAULT
	# JSON не различает int/float: 1 и 1.0 — одно и то же число, оба валидны.
	if typeof(raw_vol) == TYPE_FLOAT or typeof(raw_vol) == TYPE_INT:
		vol = clampf(float(raw_vol), 0.0, 1.0)
	var raw_imp: Variant = d.get("imp")
	return {"vol": vol, "imp": raw_imp if typeof(raw_imp) == TYPE_BOOL else false}


## Принять настройки от сервера (вход, в т.ч. с другого устройства): применить к сессии — со
## звуком включительно, иначе громкость молча осталась бы прежней до первого её изменения.
static func apply_net(data: Variant) -> void:
	var d := sanitize_net(data)
	set_volume(d["vol"])
	allow_impossible_targets = d["imp"]
