extends Node
## Globaler Spielzustand (Autoload "Game"): Spieler, Runden und Regeln.

const PLAYER_COUNT := 10
const CROWN_PRICE := 40
const START_COINS := 10
const PLAN_SECONDS := 15.0
const GAMBLE_SECONDS := 6.0
const GAMBLE_STAKE := 10
const DICE := [
	{"name": "Standard", "min": 1, "max": 6},
	{"name": "Sicher", "min": 2, "max": 4},
	{"name": "Risiko", "min": 0, "max": 10},
]
## Münzen für Platz 1, 2, 3, 4 im Minigame, alle anderen bekommen 1.
const MINIGAME_REWARDS := [10, 7, 5, 3]
const COLORS := [
	Color("e63946"), Color("f4a261"), Color("e9c46a"), Color("2a9d8f"), Color("457b9d"),
	Color("9b5de5"), Color("f15bb5"), Color("00bbf9"), Color("8ac926"), Color("f1faee"),
]
const NAMES := ["Du", "Bolzen", "Feder", "Knopf", "Kurbel", "Murmel", "Zahnrad", "Spule", "Kreisel", "Dübel"]


class PlayerData:
	var id := 0
	var name := ""
	var color := Color.WHITE
	var is_bot := true
	var coins := 0
	var crowns := 0
	var field := 0
	var traps := 0
	## Planung für die aktuelle Runde
	var dice := 0
	var branch := 0
	var place_trap := false
	var last_roll := 0


var players: Array = []
var rounds := 12
var current_round := 1
## Mit "-- --autotest" spielen nur Bots, und das Spiel beendet sich am Ende selbst.
var autotest := false


func setup(args: PackedStringArray) -> void:
	autotest = "--autotest" in args
	for a in args:
		if a.begins_with("--rounds="):
			rounds = int(a.get_slice("=", 1))
	current_round = 1
	players.clear()
	for i in PLAYER_COUNT:
		var p := PlayerData.new()
		p.id = i
		p.name = NAMES[i]
		p.color = COLORS[i]
		p.is_bot = autotest or i > 0
		p.coins = START_COINS
		players.append(p)


func human() -> PlayerData:
	for p in players:
		if not p.is_bot:
			return p
	return null


func ranking() -> Array:
	var sorted := players.duplicate()
	sorted.sort_custom(func(a, b): return a.crowns > b.crowns or (a.crowns == b.crowns and a.coins > b.coins))
	return sorted


func reward_for_place(place: int) -> int:
	if place <= MINIGAME_REWARDS.size():
		return MINIGAME_REWARDS[place - 1]
	return 1
