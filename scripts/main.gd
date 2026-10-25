extends Node3D
## Spielablauf pro Runde: Planung (alle gleichzeitig) -> Bewegung -> Glücksrad -> Minigame.

const Board = preload("res://scripts/board.gd")
const IceFloe = preload("res://scripts/minigames/ice_floe.gd")

var board
var camera: Camera3D
var hud_layer: CanvasLayer
var round_label: Label
var prompt_label: Label
var log_label: Label
var scoreboard: RichTextLabel
var center_label: Label
var log_lines: Array[String] = []

## Planungsphase
var planning := false
var plan_time := 0.0
var human_ready := false

## Glücksrad-Abfrage für den menschlichen Spieler
var gamble_asking := false
var gamble_answer := false
var gamble_time := 0.0


func _ready() -> void:
	randomize()
	Game.setup(OS.get_cmdline_user_args())
	_build_world()
	_build_hud()
	board = Board.new()
	add_child(board)
	board.message.connect(log_msg)
	board.build()
	_run_game()


func _run_game() -> void:
	log_msg("Willkommen bei Rumble Table! Sammle die meisten Kronen.")
	while Game.current_round <= Game.rounds:
		_update_scoreboard()
		await _planning_phase()
		round_label.text = "Runde %d / %d: Alle laufen los!" % [Game.current_round, Game.rounds]
		var gamblers: Array = await board.resolve_moves()
		for p in gamblers:
			await _gamble_phase(p)
		await board.snap_figures()
		_update_scoreboard()
		await _wait(1.0)
		await _play_minigame()
		Game.current_round += 1
	_show_final()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# --- Planung --------------------------------------------------------------

func _planning_phase() -> void:
	round_label.text = "Runde %d / %d: Plane deinen Zug" % [Game.current_round, Game.rounds]
	for p in Game.players:
		p.place_trap = false
		if p.is_bot:
			_bot_plan(p)
	human_ready = Game.human() == null
	plan_time = Game.PLAN_SECONDS
	planning = true
	while planning:
		await get_tree().process_frame
	prompt_label.text = ""


func _bot_plan(p) -> void:
	p.dice = [0, 0, 0, 1, 2].pick_random()
	if p.coins >= Game.CROWN_PRICE:
		# Mit genug Münzen nimmt der Bot den kürzesten Weg zum Shop.
		p.branch = 0 if board.distance_to_shop(p.field, 0) <= board.distance_to_shop(p.field, 1) else 1
	else:
		p.branch = randi() % 2
	p.place_trap = p.traps > 0 and randf() < 0.6


func _update_plan_prompt() -> void:
	var h = Game.human()
	if h == null:
		return
	var dice_parts := []
	for i in Game.DICE.size():
		var d: Dictionary = Game.DICE[i]
		var s := "[%d] %s %d-%d" % [i + 1, d.name, d.min, d.max]
		dice_parts.append(">> %s <<" % s if i == h.dice else s)
	var main_way := ">> [Q] Hauptweg <<" if h.branch == 0 else "[Q] Hauptweg"
	var gamble_way := ">> [E] Zocker-Abkürzung <<" if h.branch == 1 else "[E] Zocker-Abkürzung"
	var trap := "keine Fallen"
	if h.traps > 0:
		trap = "[T] Falle legen: %s (%d übrig)" % ["JA" if h.place_trap else "nein", h.traps]
	prompt_label.text = "Würfel:   %s\nAn Kreuzungen:   %s   %s\n%s        [Enter] Fertig        Noch %d s" % [
		"    ".join(dice_parts), main_way, gamble_way, trap, ceili(plan_time)]


# --- Glücksrad ------------------------------------------------------------

func _gamble_phase(p) -> void:
	if p.coins < Game.GAMBLE_STAKE:
		if not p.is_bot:
			log_msg("Glücksrad: Du hast keine %d Münzen zum Setzen." % Game.GAMBLE_STAKE)
		return
	var play := false
	if p.is_bot:
		# Wer hinten liegt, zockt lieber.
		var behind: bool = Game.ranking().find(p) >= 5
		play = randf() < (0.8 if behind else 0.5)
	else:
		round_label.text = "Glücksrad!"
		gamble_asking = true
		gamble_answer = false
		gamble_time = Game.GAMBLE_SECONDS
		while gamble_asking:
			await get_tree().process_frame
		prompt_label.text = ""
		play = gamble_answer
	if play:
		board.gamble(p)
		_update_scoreboard()
		await _wait(0.6)


func _process(delta: float) -> void:
	if planning:
		plan_time -= delta
		_update_plan_prompt()
		if plan_time <= 0.0 or human_ready:
			planning = false
	elif gamble_asking:
		gamble_time -= delta
		prompt_label.text = "Glücksrad!  %d Münzen setzen?\n35%%: dreifach zurück   10%%: eine Krone   35%%: Niete   20%%: Absturz (halbe Münzen weg, zurück zum Start)\n[J] Zocken!     [N] Lieber nicht        Noch %d s" % [
			Game.GAMBLE_STAKE, ceili(gamble_time)]
		if gamble_time <= 0.0:
			gamble_asking = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var h = Game.human()
	if h == null:
		return
	if planning:
		match event.keycode:
			KEY_1, KEY_KP_1:
				h.dice = 0
			KEY_2, KEY_KP_2:
				h.dice = 1
			KEY_3, KEY_KP_3:
				h.dice = 2
			KEY_Q:
				h.branch = 0
			KEY_E:
				h.branch = 1
			KEY_T:
				h.place_trap = h.traps > 0 and not h.place_trap
			KEY_ENTER, KEY_KP_ENTER:
				human_ready = true
	elif gamble_asking:
		match event.keycode:
			KEY_J, KEY_Y:
				gamble_answer = true
				gamble_asking = false
			KEY_N:
				gamble_asking = false


# --- Minigame -------------------------------------------------------------

func _play_minigame() -> void:
	board.visible = false
	hud_layer.visible = false
	var mg = IceFloe.new()
	add_child(mg)
	var placements: Dictionary = await mg.finished
	mg.queue_free()
	board.visible = true
	hud_layer.visible = true
	camera.make_current()
	var winners := []
	for p in Game.players:
		var place: int = placements[p.id]
		p.coins += Game.reward_for_place(place)
		if place == 1:
			winners.append(p.name)
	log_msg("Minigame gewonnen von %s (+%d Münzen)." % [", ".join(winners), Game.reward_for_place(1)])
	_update_scoreboard()


# --- Ende -----------------------------------------------------------------

func _show_final() -> void:
	round_label.text = "Spiel vorbei!"
	var ranking := Game.ranking()
	var text := "%s gewinnt Rumble Table!\n\n" % ranking[0].name
	for i in ranking.size():
		var p = ranking[i]
		text += "%d. %s   Kronen %d   Münzen %d\n" % [i + 1, p.name, p.crowns, p.coins]
	center_label.text = text
	if Game.autotest:
		print(text)
		get_tree().quit()


# --- Welt und Anzeige -----------------------------------------------------

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.1, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.92, 0.85)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = 50
	add_child(camera)
	camera.position = Vector3(0, 17, 12)
	camera.look_at(Vector3(0, 0, 0.8))
	camera.current = true


func _make_label(pos: Vector2, font_size: int) -> Label:
	var label := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = font_size
	settings.outline_size = 8
	settings.outline_color = Color.BLACK
	label.label_settings = settings
	label.position = pos
	hud_layer.add_child(label)
	return label


func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	round_label = _make_label(Vector2(24, 16), 30)
	log_label = _make_label(Vector2(24, 70), 18)
	prompt_label = _make_label(Vector2(24, 770), 22)
	center_label = _make_label(Vector2(500, 220), 34)

	scoreboard = RichTextLabel.new()
	scoreboard.bbcode_enabled = true
	scoreboard.position = Vector2(1240, 16)
	scoreboard.size = Vector2(350, 420)
	scoreboard.add_theme_font_size_override("normal_font_size", 19)
	scoreboard.add_theme_font_size_override("bold_font_size", 22)
	scoreboard.add_theme_constant_override("outline_size", 6)
	scoreboard.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_layer.add_child(scoreboard)


func _update_scoreboard() -> void:
	var text := "[b]Rangliste[/b]\n"
	var ranking := Game.ranking()
	for i in ranking.size():
		var p = ranking[i]
		text += "%d. [color=#%s]%s[/color]   Kronen %d   Münzen %d\n" % [i + 1, p.color.to_html(false), p.name, p.crowns, p.coins]
	scoreboard.text = text


func log_msg(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 8:
		log_lines.remove_at(0)
	log_label.text = "\n".join(log_lines)
	if Game.autotest:
		print(text)
