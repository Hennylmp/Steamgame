extends Node3D
## Minigame "Schmelzende Scholle" (jeder gegen jeden).
## Die Eisfläche schmilzt von außen nach innen, Platten blinken kurz vor dem Einbrechen.
## Mit der Leertaste rempelt man andere runter. Wer ins Wasser fällt, wird zum Geist
## und kann als Geist Eisplatten unter den Lebenden anknacksen.

signal finished(placements: Dictionary)

const Figure = preload("res://scripts/figure.gd")

const GRID := 9
const TILE := 1.6
const DURATION := 45.0
const SPEED := 5.0
const GHOST_SPEED := 6.5
const DASH_SPEED := 13.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 1.4
const KNOCKBACK := 14.0
## So lange ist man nach einem Rempler nicht steuerbar
const STUN_TIME := 0.4
## So viele Platten schmelzen nie, damit am Ende das Rempeln entscheidet
const MIN_TILES := 6
const RADIUS := 0.45
const WARN_TIME := 1.2
const GHOST_COOLDOWN := 3.0

enum TileState { SOLID, WARN, GONE }


class Tile:
	var node: MeshInstance3D
	var center := Vector2.ZERO
	var state := TileState.SOLID
	var timer := 0.0


class Racer:
	var id := 0
	var is_bot := true
	var figure: Node3D
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var facing := Vector2.DOWN
	var y := 0.0
	var alive := true
	var falling := false
	var dash_t := 0.0
	var dash_cd := 0.0
	var stun := 0.0
	var ghost_cd := GHOST_COOLDOWN
	var ai_t := 0.0
	var ai_target := Vector2.ZERO
	## Reaktionszeit der Bots, damit nicht alle gleich gut sind
	var react := 0.25


var tiles: Array[Tile] = []
var racers: Array[Racer] = []
## Spieler-ID -> Sekunde, in der der Spieler ausgeschieden ist
var eliminated_at := {}
var time_left := DURATION
var melt_timer := 2.5
var running := false
var want_dash := false
var hud: Label
var ice_mat := StandardMaterial3D.new()
var warn_mat := StandardMaterial3D.new()


func _ready() -> void:
	ice_mat.albedo_color = Color(0.78, 0.92, 1.0)
	ice_mat.roughness = 0.1
	warn_mat.albedo_color = Color(1.0, 0.45, 0.35)
	_build_arena()
	_spawn_players()
	_build_hud()
	hud.text = "Schmelzende Scholle\nBleib auf dem Eis und schubs die anderen ins Wasser!\nGleich geht's los ..."
	await get_tree().create_timer(2.5).timeout
	running = true


func _build_arena() -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	water.mesh = plane
	water.position.y = -3.0
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.05, 0.2, 0.4)
	water.material_override = water_mat
	add_child(water)

	var camera := Camera3D.new()
	camera.fov = 50
	add_child(camera)
	camera.position = Vector3(0, 15, 11)
	camera.look_at(Vector3(0, 0, 0.5))
	camera.make_current()

	var box := BoxMesh.new()
	box.size = Vector3(TILE - 0.08, 0.4, TILE - 0.08)
	for iz in GRID:
		for ix in GRID:
			var t := Tile.new()
			t.center = Vector2((ix - (GRID - 1) / 2.0) * TILE, (iz - (GRID - 1) / 2.0) * TILE)
			t.node = MeshInstance3D.new()
			t.node.mesh = box
			t.node.material_override = ice_mat
			t.node.position = Vector3(t.center.x, -0.2, t.center.y)
			add_child(t.node)
			tiles.append(t)


func _spawn_players() -> void:
	for p in Game.players:
		var r := Racer.new()
		r.id = p.id
		r.is_bot = p.is_bot
		var ang: float = TAU * p.id / Game.players.size()
		r.pos = Vector2(cos(ang), sin(ang)) * 3.6
		r.dash_cd = randf_range(0.5, 1.5)
		r.react = randf_range(0.15, 0.45)
		r.figure = Figure.new()
		r.figure.setup(p.color, p.name, not p.is_bot)
		add_child(r.figure)
		racers.append(r)
		_sync_figure(r)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	var settings := LabelSettings.new()
	settings.font_size = 24
	settings.outline_size = 8
	settings.outline_color = Color.BLACK
	hud.label_settings = settings
	hud.position = Vector2(24, 16)
	layer.add_child(hud)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		want_dash = true
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
		want_dash = true


func _physics_process(delta: float) -> void:
	if not running:
		return
	time_left -= delta
	_update_melting(delta)
	for r in racers:
		if r.alive:
			_update_racer(r, delta)
		else:
			_update_ghost(r, delta)
	want_dash = false
	_resolve_bumps()
	for r in racers:
		_sync_figure(r)
	var alive := racers.filter(func(r): return r.alive)
	hud.text = "Schmelzende Scholle   Noch %d s   %d auf dem Eis\n[WASD] laufen   [Leertaste] rempeln   Als Geist: [Leertaste] Eisplatte anknacksen" % [
		ceili(time_left), alive.size()]
	if alive.size() <= 1 or time_left <= 0.0:
		_finish()


# --- Eis ------------------------------------------------------------------

func _update_melting(delta: float) -> void:
	melt_timer -= delta
	if melt_timer <= 0.0:
		var progress := 1.0 - time_left / DURATION
		melt_timer = lerpf(2.2, 0.6, progress)
		_melt_outer(2 if progress < 0.5 else 3)
	for t in tiles:
		if t.state == TileState.WARN:
			t.timer -= delta
			t.node.material_override = warn_mat if fmod(t.timer, 0.3) < 0.15 else ice_mat
			if t.timer <= 0.0:
				_drop_tile(t)


## Schmilzt zufällige Platten aus dem äußeren Drittel der noch festen Fläche.
func _melt_outer(count: int) -> void:
	var solid := tiles.filter(func(t): return t.state == TileState.SOLID)
	count = mini(count, solid.size() - MIN_TILES)
	if count <= 0:
		return
	solid.sort_custom(func(a, b): return a.center.length() > b.center.length())
	var pool := solid.slice(0, maxi(count, int(solid.size() * 0.35)))
	pool.shuffle()
	for t in pool.slice(0, count):
		_warn(t, WARN_TIME)


func _warn(t: Tile, seconds: float) -> void:
	if t.state == TileState.SOLID:
		t.state = TileState.WARN
		t.timer = seconds


func _drop_tile(t: Tile) -> void:
	t.state = TileState.GONE
	t.node.material_override = ice_mat
	var tw := create_tween()
	tw.tween_property(t.node, "position:y", -6.0, 0.6).set_ease(Tween.EASE_IN)
	tw.tween_callback(t.node.hide)


func _tile_index(p: Vector2) -> int:
	var ix := roundi(p.x / TILE + (GRID - 1) / 2.0)
	var iz := roundi(p.y / TILE + (GRID - 1) / 2.0)
	if ix < 0 or ix >= GRID or iz < 0 or iz >= GRID:
		return -1
	return iz * GRID + ix


func _standing(p: Vector2) -> bool:
	var idx := _tile_index(p)
	return idx >= 0 and tiles[idx].state != TileState.GONE


# --- Spieler --------------------------------------------------------------

func _human_dir() -> Vector2:
	var d := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	var joy := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if joy.length() > 0.3:
		d = joy
	return d.limit_length(1.0)


func _update_racer(r: Racer, delta: float) -> void:
	if r.falling:
		r.y -= 8.0 * delta
		r.pos += r.vel * delta * 0.3
		if r.y < -4.0:
			_eliminate(r)
		return
	var dir := _bot_dir(r, delta) if r.is_bot else _human_dir()
	if dir.length() > 0.1:
		r.facing = dir.normalized()
	if not r.is_bot and want_dash and r.stun <= 0.0:
		_dash(r, r.facing)
	r.dash_cd -= delta
	if r.stun > 0.0:
		r.stun -= delta
		r.vel = r.vel.lerp(Vector2.ZERO, minf(1.0, 2.0 * delta))
	elif r.dash_t > 0.0:
		r.dash_t -= delta
	else:
		r.vel = r.vel.lerp(dir * SPEED, minf(1.0, 8.0 * delta))
	r.pos += r.vel * delta
	if not _standing(r.pos):
		r.falling = true


func _dash(r: Racer, dir: Vector2) -> void:
	if r.dash_cd > 0.0 or r.stun > 0.0 or r.falling or dir.length() < 0.01:
		return
	r.dash_t = DASH_TIME
	r.vel = dir.normalized() * DASH_SPEED
	r.dash_cd = DASH_COOLDOWN


func _bot_dir(r: Racer, delta: float) -> Vector2:
	r.ai_t -= delta
	if r.ai_t <= 0.0:
		r.ai_t = r.react
		r.ai_target = _best_tile_for(r)
		var victim := _nearest_opponent(r)
		if victim and victim.pos.distance_to(r.pos) < 1.8 and randf() < 0.45:
			_dash(r, victim.pos - r.pos)
	var to := r.ai_target - r.pos
	if to.length() < 0.25:
		return Vector2.ZERO
	return to.normalized() * clampf(to.length(), 0.3, 1.0)


## Bots wollen zur Mitte, aber nicht zu weit laufen und nie auf blinkende Platten.
func _best_tile_for(r: Racer) -> Vector2:
	var best := r.pos
	var best_score := INF
	# Bots verschätzen sich manchmal
	var careless := randf() < 0.1
	for t in tiles:
		if t.state != TileState.SOLID:
			continue
		var score := t.center.length() * 0.7 + t.center.distance_to(r.pos) * 0.5 + randf() * (6.0 if careless else 0.4)
		if score < best_score:
			best_score = score
			best = t.center
	return best


func _nearest_opponent(r: Racer) -> Racer:
	var best: Racer = null
	var best_dist := INF
	for o in racers:
		if o == r or not o.alive or o.falling:
			continue
		var dist := o.pos.distance_to(r.pos)
		if dist < best_dist:
			best_dist = dist
			best = o
	return best


func _resolve_bumps() -> void:
	var active := racers.filter(func(r): return r.alive and not r.falling)
	for i in active.size():
		for j in range(i + 1, active.size()):
			var a: Racer = active[i]
			var b: Racer = active[j]
			var d := b.pos - a.pos
			var dist := d.length()
			if dist >= RADIUS * 2.0 or dist < 0.001:
				continue
			var n := d / dist
			var overlap := RADIUS * 2.0 - dist
			a.pos -= n * overlap * 0.5
			b.pos += n * overlap * 0.5
			if a.dash_t > 0.0:
				b.vel = n * KNOCKBACK
				b.stun = STUN_TIME
				b.dash_t = 0.0
				a.dash_t = 0.0
				a.vel *= 0.2
			elif b.dash_t > 0.0:
				a.vel = -n * KNOCKBACK
				a.stun = STUN_TIME
				a.dash_t = 0.0
				b.dash_t = 0.0
				b.vel *= 0.2


func _eliminate(r: Racer) -> void:
	r.alive = false
	r.falling = false
	eliminated_at[r.id] = DURATION - time_left
	r.y = 1.6
	r.vel = Vector2.ZERO
	var half := TILE * GRID / 2.0
	r.pos = r.pos.clamp(Vector2(-half, -half), Vector2(half, half))
	r.figure.set_ghost()


## Geister schweben übers Eis und knacksen Platten an, damit sie schneller einbrechen.
func _update_ghost(r: Racer, delta: float) -> void:
	var dir := Vector2.ZERO
	var wants_crack := false
	if r.is_bot:
		r.ai_t -= delta
		if r.ai_t <= 0.0:
			r.ai_t = 0.8
			var alive := racers.filter(func(o): return o.alive and not o.falling)
			r.ai_target = alive.pick_random().pos if not alive.is_empty() else Vector2.ZERO
		var to := r.ai_target - r.pos
		if to.length() > 0.3:
			dir = to.normalized()
		wants_crack = to.length() < 0.6 and randf() < 0.05
	else:
		dir = _human_dir()
		wants_crack = want_dash
	var half := TILE * GRID / 2.0
	r.pos = (r.pos + dir * GHOST_SPEED * delta).clamp(Vector2(-half, -half), Vector2(half, half))
	r.ghost_cd -= delta
	if wants_crack and r.ghost_cd <= 0.0:
		var idx := _tile_index(r.pos)
		if idx >= 0 and tiles[idx].state == TileState.SOLID:
			_warn(tiles[idx], WARN_TIME * 1.4)
			r.ghost_cd = GHOST_COOLDOWN


func _sync_figure(r: Racer) -> void:
	r.figure.position = Vector3(r.pos.x, r.y, r.pos.y)
	if r.vel.length() > 0.5:
		r.figure.rotation.y = atan2(r.vel.x, r.vel.y)


# --- Ende -----------------------------------------------------------------

func _finish() -> void:
	running = false
	for r in racers:
		if r.alive and r.falling:
			_eliminate(r)
	var survivors := racers.filter(func(r): return r.alive)
	var placements := {}
	var names := []
	for r in survivors:
		placements[r.id] = 1
		names.append(Game.players[r.id].name)
	# Wer später rausfliegt, landet weiter vorn. Gleichzeitig Ausgeschiedene teilen sich den Platz.
	var out := eliminated_at.keys()
	out.sort_custom(func(a, b): return eliminated_at[a] > eliminated_at[b])
	var place := survivors.size() + 1
	for i in out.size():
		var id: int = out[i]
		if i > 0 and not is_equal_approx(eliminated_at[id], eliminated_at[out[i - 1]]):
			place = survivors.size() + 1 + i
		placements[id] = place
		if place == 1:
			names.append(Game.players[id].name)
	hud.text = "Geschafft! Gewinner: %s" % ", ".join(names)
	if Game.autotest:
		print("[Scholle] nach %.1f s, %d Überlebende, Gewinner: %s" % [DURATION - time_left, survivors.size(), ", ".join(names)])
	await get_tree().create_timer(2.0).timeout
	finished.emit(placements)
