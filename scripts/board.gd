extends Node3D
## Spielbrett: 24 Felder im Ring plus zwei Zocker-Abkürzungen (insgesamt 32 Felder).
## Alle Figuren laufen gleichzeitig. Danach wirken Feld-Effekte, Fallen und Rempler.

signal message(text: String)

const Figure = preload("res://scripts/figure.gd")

enum FieldType { BLUE, RED, ITEM, EVENT, GAMBLE }

const SPACING := 2.2
const STEP_TIME := 0.22
const FIELD_COLORS := {
	FieldType.BLUE: Color(0.25, 0.5, 0.95),
	FieldType.RED: Color(0.9, 0.25, 0.25),
	FieldType.ITEM: Color(0.3, 0.8, 0.4),
	FieldType.EVENT: Color(0.7, 0.4, 0.9),
	FieldType.GAMBLE: Color(1.0, 0.75, 0.1),
}
const FIELD_ICONS := {
	FieldType.BLUE: "+3",
	FieldType.RED: "-3",
	FieldType.ITEM: "Falle",
	FieldType.EVENT: "?",
	FieldType.GAMBLE: "$",
}
## Feldtypen im Ring, Feld 0 ist der Start.
const RING_PATTERN := "BBBBIBEBRBIBBEBRBIBBEBRB"
## Zocker-Wege: kurz, aber voller Glücksfelder.
const SHORTCUT_A_PATTERN := "GRGE"
const SHORTCUT_B_PATTERN := "GIGR"
const PATTERN_TYPES := {
	"B": FieldType.BLUE, "R": FieldType.RED, "I": FieldType.ITEM, "E": FieldType.EVENT, "G": FieldType.GAMBLE,
}

## Jedes Feld: {pos: Vector3, type: FieldType, next: Array[int]}
var fields: Array = []
var figures := {}
## Feld-ID -> Spieler-ID der Falle
var traps := {}
var trap_markers := {}
var shop_field := -1
var shop_node: Node3D
var ring_size := 0


func build() -> void:
	_build_table()
	_build_fields()
	for i in fields.size():
		_build_field_mesh(i)
	_build_shop()
	_move_shop()
	for p in Game.players:
		var f := Figure.new()
		f.setup(p.color, p.name, not p.is_bot)
		add_child(f)
		figures[p.id] = f
		f.position = _slot_pos(p)


func _build_table() -> void:
	var table := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(26, 0.5, 18)
	table.mesh = box
	table.position.y = -0.35
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.36, 0.22)
	mat.roughness = 0.8
	table.material_override = mat
	add_child(table)


func _grid_to_world(g: Vector2i) -> Vector3:
	return Vector3((g.x - 3.5) * SPACING, 0.0, (g.y - 2.5) * SPACING)


func _add_field(g: Vector2i, type: int) -> int:
	fields.append({"pos": _grid_to_world(g), "type": type, "next": []})
	return fields.size() - 1


func _build_fields() -> void:
	# Ring auf einem 8x6-Raster, im Uhrzeigersinn
	var ring: Array[Vector2i] = []
	for x in range(0, 8):
		ring.append(Vector2i(x, 0))
	for z in range(1, 6):
		ring.append(Vector2i(7, z))
	for x in range(6, -1, -1):
		ring.append(Vector2i(x, 5))
	for z in range(4, 0, -1):
		ring.append(Vector2i(0, z))
	ring_size = ring.size()
	for i in ring_size:
		_add_field(ring[i], PATTERN_TYPES[RING_PATTERN[i % RING_PATTERN.length()]])
	for i in ring_size:
		fields[i].next = [(i + 1) % ring_size]

	# Abkürzung A: von Feld 2 quer übers Brett zu Feld 17
	_add_shortcut(2, 17, [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4)], SHORTCUT_A_PATTERN)
	# Abkürzung B: von Feld 14 zurück zu Feld 5
	_add_shortcut(14, 5, [Vector2i(5, 4), Vector2i(5, 3), Vector2i(5, 2), Vector2i(5, 1)], SHORTCUT_B_PATTERN)


func _add_shortcut(from: int, to: int, cells: Array, pattern: String) -> void:
	var prev := from
	for i in cells.size():
		var id := _add_field(cells[i], PATTERN_TYPES[pattern[i]])
		fields[prev].next.append(id)
		prev = id
	fields[prev].next.append(to)


func _build_field_mesh(i: int) -> void:
	var f: Dictionary = fields[i]
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.8
	cyl.bottom_radius = 0.85
	cyl.height = 0.2
	disc.mesh = cyl
	disc.position = f.pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FIELD_COLORS[f.type]
	disc.material_override = mat
	add_child(disc)

	var icon := Label3D.new()
	icon.text = "Start" if i == 0 else FIELD_ICONS[f.type]
	icon.rotation_degrees.x = -90
	icon.position = f.pos + Vector3(0, 0.12, 0)
	icon.font_size = 64
	icon.pixel_size = 0.006
	icon.outline_size = 8
	add_child(icon)

	# Wegstücke zu den Nachbarfeldern
	for n in f.next:
		var a: Vector3 = f.pos
		var b: Vector3 = fields[n].pos
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.18, 0.06, a.distance_to(b) - 1.5)
		seg.mesh = box
		var seg_mat := StandardMaterial3D.new()
		seg_mat.albedo_color = Color(0.95, 0.9, 0.8) if fields[n].type != FieldType.GAMBLE else Color(1.0, 0.8, 0.2)
		seg.material_override = seg_mat
		add_child(seg)
		seg.position = (a + b) / 2.0
		seg.look_at(b + Vector3(0, 0.0001, 0), Vector3.UP)


func _build_shop() -> void:
	shop_node = Node3D.new()
	var crown := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.3
	cyl.height = 0.35
	crown.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.15)
	mat.metallic = 0.9
	mat.roughness = 0.25
	crown.material_override = mat
	crown.position.y = 1.6
	shop_node.add_child(crown)
	var tag := Label3D.new()
	tag.text = "Kronen-Shop\n%d Münzen" % Game.CROWN_PRICE
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 2.3
	tag.font_size = 40
	tag.pixel_size = 0.006
	tag.outline_size = 8
	tag.modulate = Color(1.0, 0.85, 0.3)
	shop_node.add_child(tag)
	add_child(shop_node)


## Der Shop wandert nach jedem Kauf auf ein freies Feld im Ring.
func _move_shop() -> void:
	var options := []
	for i in range(1, ring_size):
		if i == shop_field or fields[i].next.size() > 1:
			continue
		var occupied := false
		for p in Game.players:
			if p.field == i:
				occupied = true
		if not occupied:
			options.append(i)
	shop_field = options.pick_random()
	shop_node.position = fields[shop_field].pos


func _process(delta: float) -> void:
	if shop_node:
		shop_node.rotate_y(delta * 1.2)


func _slot_pos(p) -> Vector3:
	var same := []
	for q in Game.players:
		if q.field == p.field:
			same.append(q.id)
	var base: Vector3 = fields[p.field].pos + Vector3(0, 0.1, 0)
	if same.size() == 1:
		return base
	var ang := TAU * same.find(p.id) / same.size()
	return base + Vector3(cos(ang), 0, sin(ang)) * 0.55


func path_from(start: int, steps: int, branch: int) -> Array:
	var path := []
	var f := start
	for i in steps:
		var nexts: Array = fields[f].next
		f = nexts[mini(branch, nexts.size() - 1)]
		path.append(f)
	return path


## Schritte bis zum Shop, wenn man an Kreuzungen immer `branch` nimmt.
func distance_to_shop(start: int, branch: int) -> int:
	var path := path_from(start, 40, branch)
	var idx := path.find(shop_field)
	return idx + 1 if idx >= 0 else 999


func snap_figures() -> void:
	var tw := create_tween().set_parallel(true)
	for p in Game.players:
		tw.tween_property(figures[p.id], "position", _slot_pos(p), 0.3)
	await tw.finished


## Würfeln, alle gleichzeitig laufen lassen, Feld-Effekte auslösen.
## Gibt die Spieler zurück, die auf einem Glücksfeld gelandet sind.
func resolve_moves() -> Array:
	var paths := {}
	for p in Game.players:
		if p.place_trap and p.traps > 0 and not traps.has(p.field) and p.field != 0:
			_place_trap(p)
		var d: Dictionary = Game.DICE[p.dice]
		p.last_roll = randi_range(d.min, d.max)
		paths[p.id] = path_from(p.field, p.last_roll, p.branch)
		if not p.is_bot:
			message.emit("Du würfelst eine %d (%s)." % [p.last_roll, d.name])

	var longest := 0
	for id in paths:
		longest = maxi(longest, paths[id].size())
	for step in longest:
		for p in Game.players:
			var path: Array = paths[p.id]
			if step < path.size():
				p.field = path[step]
				if p.field == shop_field:
					_try_buy_crown(p)
		await snap_figures()

	var gamblers := []
	for p in Game.players:
		_land(p)
		if fields[p.field].type == FieldType.GAMBLE:
			gamblers.append(p)
	_resolve_bumps()
	await snap_figures()
	return gamblers


func _try_buy_crown(p) -> void:
	if p.coins < Game.CROWN_PRICE:
		return
	p.coins -= Game.CROWN_PRICE
	p.crowns += 1
	message.emit("%s kauft eine Krone! Der Shop wandert weiter." % p.name)
	_move_shop()


func _place_trap(p) -> void:
	p.traps -= 1
	traps[p.field] = p.id
	var marker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.1, 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = p.color
	marker.material_override = mat
	marker.position = fields[p.field].pos + Vector3(0.55, 0.15, -0.55)
	# Fallen sind verdeckt: Nur der Besitzer sieht sie.
	marker.visible = not p.is_bot or Game.autotest
	add_child(marker)
	trap_markers[p.field] = marker
	if not p.is_bot:
		message.emit("Du legst heimlich eine Falle.")


func _land(p) -> void:
	var f: Dictionary = fields[p.field]
	match f.type:
		FieldType.BLUE:
			p.coins += 3
		FieldType.RED:
			p.coins = maxi(0, p.coins - 3)
		FieldType.ITEM:
			p.traps += 1
			message.emit("%s findet eine Falle." % p.name)
		FieldType.EVENT:
			_event(p)

	if traps.has(p.field) and traps[p.field] != p.id:
		var owner = Game.players[traps[p.field]]
		var loss: int = p.coins / 2
		p.coins -= loss
		owner.coins += loss
		message.emit("%s tritt in die Falle von %s und verliert %d Münzen!" % [p.name, owner.name, loss])
		traps.erase(p.field)
		trap_markers[p.field].queue_free()
		trap_markers.erase(p.field)


func _event(p) -> void:
	match randi() % 3:
		0:
			var others := Game.players.filter(func(q): return q.id != p.id)
			var other = others.pick_random()
			var tmp: int = p.field
			p.field = other.field
			other.field = tmp
			message.emit("Wirbelwind! %s tauscht den Platz mit %s." % [p.name, other.name])
		1:
			p.coins += 6
			message.emit("Geldregen! %s bekommt 6 Münzen." % p.name)
		2:
			var loss := mini(4, p.coins)
			p.coins -= loss
			message.emit("Die Katze haut %s vom Feld: -%d Münzen." % [p.name, loss])


## Landen mehrere auf einem Feld, klaut der mit dem höchsten Wurf jedem 5 Münzen.
func _resolve_bumps() -> void:
	var by_field := {}
	for p in Game.players:
		if p.field == 0:
			continue
		by_field.get_or_add(p.field, []).append(p)
	for field in by_field:
		var group: Array = by_field[field]
		if group.size() < 2:
			continue
		group.sort_custom(func(a, b): return a.last_roll > b.last_roll)
		if group[0].last_roll == group[1].last_roll:
			continue
		var winner = group[0]
		var total := 0
		for i in range(1, group.size()):
			var take := mini(5, group[i].coins)
			group[i].coins -= take
			total += take
		winner.coins += total
		message.emit("%s rempelt %s weg und klaut %d Münzen." % [winner.name, ", ".join(group.slice(1).map(func(q): return q.name)), total])


## Glücksrad: Einsatz zahlen, dann entscheidet das Rad.
func gamble(p) -> void:
	p.coins -= Game.GAMBLE_STAKE
	var r := randf()
	if r < 0.35:
		p.coins += Game.GAMBLE_STAKE * 3
		message.emit("Glücksrad: JACKPOT! %s bekommt %d Münzen." % [p.name, Game.GAMBLE_STAKE * 3])
	elif r < 0.45:
		p.crowns += 1
		message.emit("Glücksrad: %s gewinnt eine KRONE!" % p.name)
	elif r < 0.8:
		message.emit("Glücksrad: Niete. %s ist den Einsatz los." % p.name)
	else:
		var loss: int = p.coins / 2
		p.coins -= loss
		p.field = 0
		message.emit("Glücksrad: ABSTURZ! %s verliert %d Münzen und muss zurück zum Start." % [p.name, loss + Game.GAMBLE_STAKE])
