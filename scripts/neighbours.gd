extends Node
## Naapurit maksavat pihatiensä kolaamisesta. Palvelin pitää kirjaa siitä, kuka kolasi
## mitäkin pihatietä, ja jakaa palkkion tehdyn työn mukaan, kun pihatie on puhdas.
## Maksun jälkeen pihatielle tuiskuttaa hetken päästä uutta lunta ja naapuri tilaa uuden kolauksen.

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


func _ready() -> void:
	for i in Village.NEIGHBOURS.size():
		var n: Dictionary = Village.NEIGHBOURS[i]
		var field := SnowField.new()
		field.name = "Pihatie%d" % i
		field.setup(n["w"], n["d"], Village.NEIGHBOUR_START_CM)
		field.position = Village.neighbour_origin(i)
		add_child(field)
		fields.append(field)


func start_server() -> void:
	for i in fields.size():
		fields[i].start_server()
		_credit[i] = {}
		_ordered[i] = true


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
			if fields[i].fraction_cleared(Village.CLEARED_CM) >= Village.CLEARED_FRACTION:
				_pay(i)
		elif _clock >= _reorder_at[i]:
			_reorder(i)


func _pay(index: int) -> void:
	var main = get_parent()
	var n: Dictionary = Village.NEIGHBOURS[index]
	var pay: int = n["pay"]
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
		var share := maxi(1, roundi(pay * workers[peer] / total))
		main.add_money(peer, share)
		parts.append("%s %d €" % [main.display_name_for(peer)[0], share])
	main.announce("%s maksoi pihatien kolauksesta: %s" % [n["name"], ", ".join(parts)])


func _reorder(index: int) -> void:
	var n: Dictionary = Village.NEIGHBOURS[index]
	fields[index].refill(randi_range(REFILL_MIN_CM, REFILL_MAX_CM))
	_ordered[index] = true
	get_parent().announce("%s: \"Pihatielle tuiskutti taas. Maksan %d €, jos joku kolaa sen!\"" % [n["name"], n["pay"]])


## Autotesti: tyhjennä pihatie palvelimella kuin joku olisi kolannut loput.
func debug_clear(index: int) -> void:
	var field = fields[index]
	field.remove_snow(field.to_global(Vector3(field.size().x * 0.5, 0, field.size().y * 0.5)), 100.0, 100000000, 255)
