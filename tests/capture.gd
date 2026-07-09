extends SceneTree

## Скриншот нового мобильного интерфейса. Запуск БЕЗ --headless.

var frames := 0
var scene: Node


func _initialize() -> void:
	scene = load("res://main.tscn").instantiate()
	get_root().add_child(scene)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	frames += 1
	if frames == 6:
		scene._start_local()
		scene.state.score[Consts.Player.A] = 4                 # очки противника (A) — сверху
		scene.state.score[Consts.Player.B] = 2                 # очки игрока (B) — под полем
		var dead = scene.state.get_unit(4)                     # B Фея — «убьём» ради могилы
		dead.alive = false
		dead.dead_timer = 3
		dead.death_cell = dead.cell
		# поставить капкан на доску (для проверки иконки капкана)
		scene.state.traps.append({"cell": Vector2i(3, 3), "owner_player": Consts.Player.B, "owner_id": 5, "expire_round": 5})
		scene._show_planning(Consts.Player.B)                  # перспектива B: свои синие, старт снизу
		scene.board_view.render(scene.state.snapshot())
		for ch in scene.panel_host.get_children():
			if ch is PlanningPanel:
				ch._on_cell_clicked(Vector2i(5, 0))            # выбрать B-Охотника → белая подсветка
				ch._arm(Consts.Action.ABILITY1)                # Капкан
				ch._on_cell_clicked(Vector2i(5, 2))            # цель → слот 1 = иконка капкана
				ch._pass_slot()                                # слот 2 = «нет действия» (cancel)
				ch.set_opponent_progress([true, true, false, false])  # соперник занял 2 слота (тёмные)
	if frames == 14:
		get_root().get_texture().get_image().save_png("res://tests/_capture.png")
		print("captured")
		quit(0)


func state_hunter_mana(scene: Node, m: int) -> void:
	scene.state.get_unit(0).mana = m
