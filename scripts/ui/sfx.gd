class_name Sfx
extends RefCounted

## Звуковые эффекты. Файлы лежат в res://sounds/.
##
## Статический фасад, а НЕ автолоад: автолоад виден по имени только тем скриптам, что
## компилируются после его регистрации, а headless-тесты (--script, см. tests/ui_smoke.gd)
## компилируют UI раньше — там `Sfx` как автолоад просто не нашёлся бы. Глобальное имя класса
## (class_name) доступно везде одинаково, как у Icons.
##
## Голосов несколько, а не один: события раунда идут подряд и внахлёст (звук урона ложится
## поверх атаки), а одному AudioStreamPlayer каждый новый play() обрывал бы предыдущий звук на
## полуслове. Голоса переиспользуются: свободный, а если все заняты — самый старый (лучше
## оборвать давний звук, чем промолчать).
##
## Потоки грузятся лениво и кэшируются (как Icons.tex): сервер (main.gd там сразу уходит в
## Net.start_server) play() не зовёт — значит и mp3 не читает, и голосов не создаёт.

const DIR := "res://sounds/"
# Сколько звуков могут звучать одновременно. Эффекты длятся ~1с, а события раунда идут чаще
# (пауза между ними от 0.12с), поэтому 2-3 голоса регулярно оказывались бы заняты — берём с
# запасом, лишний AudioStreamPlayer ничего не стоит, а обрыв звука слышен.
const VOICES := 6

# Имена файлов — единственное место, где они записаны.
const ATTACK := "attack.mp3"
const MAGIC_ATTACK := "magical_attack.mp3"
const MOVE := "move.mp3"
const MISS := "miss.mp3"
const VICTORY := "victory.mp3"
const DEFEAT := "defeat.mp3"

static var _voices: Array[AudioStreamPlayer] = []
static var _cache := {}
static var _next := 0


## Проиграть звук (одна из констант выше); пустая строка — «звука нет», законный вызов (так
## вызывающему не нужен свой if вокруг каждого play). Отсутствующий файл — тоже не ошибка, а
## тишина: звук это украшение, из-за него игра падать не должна (как Icons.tex_opt с иконками).
static func play(file: String) -> void:
	if file.is_empty():
		return
	var stream := _stream(file)
	if stream == null:
		return
	var v := _pick_voice()
	if v == null:
		return   # дерева сцены нет (headless-инструмент) — играть некуда
	v.stream = stream
	v.play()


static func _stream(file: String) -> AudioStream:
	if not _cache.has(file):
		var path := DIR + file
		_cache[file] = load(path) if ResourceLoader.exists(path) else null
	return _cache[file]


# Свободный голос, иначе — следующий по кругу (самый давно занятый).
static func _pick_voice() -> AudioStreamPlayer:
	_ensure_voices()
	if _voices.is_empty():
		return null
	for v in _voices:
		if not v.playing:
			return v
	var v := _voices[_next]
	_next = (_next + 1) % _voices.size()
	return v


# Голоса живут в корне дерева, поэтому переживают смену панелей (звук не обрывается на полуслове,
# когда панель разрешения раунда сменится следующим экраном). Статика переживает и само дерево —
# после его закрытия узлы освобождены, поэтому проверяем и пересоздаём.
static func _ensure_voices() -> void:
	if not _voices.is_empty() and is_instance_valid(_voices[0]):
		return
	_voices.clear()
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return
	var root := (loop as SceneTree).root
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		root.add_child(p)
		_voices.append(p)
