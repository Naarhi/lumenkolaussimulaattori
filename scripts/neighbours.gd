extends Node
## Naapurit maksavat pihatiensä kolaamisesta. Palvelin pitää kirjaa siitä, kuka kolasi
## mitäkin pihatietä, ja jakaa palkkion tehdyn työn mukaan, kun pihatie on puhdas.
## Maksun jälkeen pihatielle tuiskuttaa hetken päästä uutta lunta ja naapuri tilaa uuden kolauksen.
## Lumet pitää kasata pihatien vieressä olevaan lumikasaan. Minne sattuu heitellyistä lumista naapuri maksaa vähemmän.

const SnowField := preload("res://scripts/snow_field.gd")
const Village := preload("res://scripts/village.gd")

const CHECK_INTERVAL := 2.0
const REORDER_MIN := 150.0
const REORDER_MAX := 300.0
const REFILL_MIN_CM := 15
const REFILL_MAX_CM := 28

## Pihateiden lumikentät samassa järjestyksessä kuin Village.NEIGHBOURS.
var fields: Array = []
## Palvelin: {naapuri: {pelaaja: tehty työ}}, tilauksen tila ja uuden tilauksen hetki.
var _credit := {}
var _ordered := {}
var _reorder_at := {}
var _clock := 0.0
var _check := 0.0
## Tilauksen alussa: pihatien lumi, kasan lumi ja sulatettu lumi.
var _start_drive := {}
var _start_pile := {}
var _start_melted := {}


func _ready() -> void:
	for i in Village.NEIGHBOURS.size():
		var n: Dictionary = Village.NEIGHBOURS[i]
		var field := SnowField.new()
		field.name = "Pihatie%d" % i
		field.setup(Village.neighbour_field_width(i), n["d"], Village.NEIGHBOUR_START_CM)
		field.position = Village.neighbour_origin(i)
		add_child(field)
		fields.append(field)


func start_server() -> void:
	for i in fields.size():
		fields[i].start_server()
		_credit[i] = {}
		_ordered[i] = true
		_snapshot(i)


func send_full_state(peer: int) -> void:
	for field in fields:
		field.send_full_state(peer)


## Palvelin: kirjaa pelaajan työn, jos kenttä on naapurin pihatie.
func credit(field, peer: int, amount: float) -> void:
	var index := fields.find(field)
	if index < 0 or amount <= 0.0 or not _ordered.get(index, false):
		return
	_credit[index][peer] = _credit[index].get(peer, 0.0) + amount


func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or _credit.is_empty():
		return
	_clock += delta
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_INTERVAL
	for i in fields.size():
		if _ordered[i]:
			if drive_cleared(i) >= Village.CLEARED_FRACTION:
				_pay(i)
		elif _clock >= _reorder_at[i]:
			_reorder(i)


## Pihatien solut (ilman lumikasan kaistaa): [x0, x1, z0, z1].
func _drive_rect(index: int) -> Array:
	var n: Dictionary = Village.NEIGHBOURS[index]
	return [0, roundi(n["w"] / SnowField.CELL_SIZE) - 1, 0, fields[index].cells_z - 1]


func drive_cleared(index: int) -> float:
	var r := _drive_rect(index)
	return fields[index].fraction_cleared_rect(r[0], r[1], r[2], r[3], Village.CLEARED_CM)


func _drive_snow(index: int) -> int:
	var r := _drive_rect(index)
	return fields[index].sum_rect(r[0], r[1], r[2], r[3])


func _pile_snow(index: int) -> int:
	return fields[index].sum_circle(Village.pile_center(index), Village.PILE_RADIUS)


func _snapshot(index: int) -> void:
	_start_drive[index] = _drive_snow(index)
	_start_pile[index] = _pile_snow(index)
	_start_melted[index] = fields[index].melted_total


## Kuinka suuri osa pihatieltä poistetusta lumesta päätyi kasaan tai sulatettiin (0..1).
func pile_share(index: int) -> float:
	var removed: int = _start_drive[index] - _drive_snow(index)
	if removed <= 0:
		return 1.0
	var kept: int = _pile_snow(index) - _start_pile[index] + fields[index].melted_total - _start_melted[index]
	return clampf(float(kept) / removed / 0.85, 0.0, 1.0)


func _pay(index: int) -> void:
	var main = get_parent()
	var n: Dictionary = Village.NEIGHBOURS[index]
	var share := pile_share(index)
	var pay := roundi(n["pay"] * lerpf(Village.MIN_PAY_SHARE, 1.0, share))
	_ordered[index] = false
	_reorder_at[index] = _clock + randf_range(REORDER_MIN, REORDER_MAX)
	# Vain paikalla olevat kolaajat saavat osansa. Pienin osuus on 1 €.
	var workers := {}
	var total := 0.0
	for peer in _credit[index]:
		if main.players.get_node_or_null(str(peer)):
			workers[peer] = _credit[index][peer]
			total += _credit[index][peer]
	_credit[index] = {}
	if total <= 0.0:
		main.announce("%s katsoi ikkunasta: pihatie on puhdas, vaikka kukaan ei kolannut. Ei makseta." % n["name"])
		return
	var parts := []
	for peer in workers:
		var part := maxi(1, roundi(pay * workers[peer] / total))
		main.add_money(peer, part)
		parts.append("%s %d €" % [main.display_name_for(peer)[0], part])
	var verdict := "Lumet on kasattu siististi kasaan!" if share > 0.9 else ("Osa lumista on heitelty minne sattuu." if share > 0.5 else "Lumet on viskottu pitkin pihaa ja tietä, maksan vain osan.")
	main.announce("%s: \"%s\" Maksoi %d € / %d €: %s" % [n["name"], verdict, pay, n["pay"], ", ".join(parts)])


func _reorder(index: int) -> void:
	var n: Dictionary = Village.NEIGHBOURS[index]
	# Kunnan kuorma-auto on hakenut vanhan kasan pois.
	var depth := randi_range(REFILL_MIN_CM, REFILL_MAX_CM)
	fields[index].flatten_circle(Village.pile_center(index), Village.PILE_RADIUS, depth)
	fields[index].refill(depth)
	_ordered[index] = true
	_snapshot(index)
	get_parent().announce("%s: \"Pihatielle tuiskutti taas. Maksan %d €, jos joku kolaa sen ja kasaa lumet lumikasaan!\"" % [n["name"], n["pay"]])


## Autotesti: kolaa pihatie palvelimella loppuun ja kasaa lumet kasaan.
func debug_clear(index: int) -> void:
	var field = fields[index]
	var n: Dictionary = Village.NEIGHBOURS[index]
	var removed := 0
	for z in field.cells_z:
		for x in roundi(n["w"] / SnowField.CELL_SIZE):
			removed += field.remove_snow(field.cell_center(x, z), 0.01, 255, 255)
	field.add_snow(Village.pile_center(index), Village.PILE_RADIUS, removed)
