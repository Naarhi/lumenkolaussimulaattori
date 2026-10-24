extends Node
## OSRS:n "random eventien" tapaiset hullut sattumukset. Palvelin arpoo, kaikki näkevät saman.

enum { AURA_AUTO, LUMIMYRSKY, HIRVI, PERTTI, KATTOLUMI, JALLU }

const Pihapiiri := preload("res://scripts/pihapiiri.gd")
const Village := preload("res://scripts/village.gd")

const EVENTS := [
	{"type": AURA_AUTO, "weight": 3.0, "text": "Kunnan aura-auto jyrisi ohi ja puski penkan pihatielle!"},
	{"type": LUMIMYRSKY, "weight": 2.0, "text": "Lumimyräkkä yllätti! Naapurien pihateille sataa lunta silmissä."},
	{"type": HIRVI, "weight": 1.0, "text": "Hirvi käveli pihalle eikä lähde ilman naavaa! Naavaa kasvaa kuusten alla. Älä mene lähelle tyhjin käsin."},
	{"type": PERTTI, "weight": 2.0, "text": "Naapurin Pertti kävi moottorikelkalla \"auttamassa\". Naapurien pihateillä on nyt lumikasoja."},
	{"type": KATTOLUMI, "weight": 2.0, "text": "Katolta romahti lumikuorma kolaajan niskaan!"},
	{"type": JALLU, "weight": 2.0, "text": "Pertti kurvasi pihaan ja jätti Jallu-colaa! Mene pullon luo ja paina E."},
]
const BOTTLES_PER_DELIVERY := 3
const BOTTLE_LIFETIME := 180.0
const DRINK_DISTANCE := 1.6
const BOOST_SECONDS := 20.0
const MIN_INTERVAL := 90.0
const MAX_INTERVAL := 240.0
## Hirvi potkaisee naavattoman kolaajan, joka tulee tätä lähemmäs, ja syö naavan tätä läheltä.
const MOOSE_KICK_DISTANCE := 2.6
const MOOSE_FEED_DISTANCE := 3.2
const MOOSE_KICK_DAMAGE := 25
const MOOSE_KICK_COOLDOWN_MS := 1500
const MOOSE_MAX_STAY := 600.0
const MOOSE_FEED_XP := 40

var _timer: Timer
# Pullot {id: sijainti}. Palvelin päättää, asiakkaat näyttävät.
var bottles := {}
var _bottle_nodes := {}
var _next_bottle := 1
## Hirvi: onko pihalla ja missä. Palvelin päättää, asiakkaat näyttävät.
var moose_active := false
var moose_pos := Vector3.ZERO
var _moose_node: Node3D
var _moose_left_at := 0.0
var _last_kick := {}
var _kick_check := 0.0
## Naavapuut [puu, poimintapaikka, korkeus], onko naavaa poimittavissa ja ketkä kantavat naavaa.
var naava_spots: Array = Pihapiiri.naava_spots()
## Aura-auto: ohitus alkoi (s, -1 = ei tiellä) ja ketkä se on jo heittänyt.
const TRUCK_START_X := -45.0
const TRUCK_END_X := 45.0
const TRUCK_TIME := 7.0
var _truck_started := -1.0
var _truck_hit := {}
var naava_ready := {}
var carrying_naava := {}


func start_server() -> void:
	for i in naava_spots.size():
		naava_ready[i] = true
	if _timer:
		_schedule()
		return
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	_schedule()


func _schedule() -> void:
	_timer.start(randf_range(MIN_INTERVAL, MAX_INTERVAL))


func _on_timer() -> void:
	var total := 0.0
	for e in EVENTS:
		total += e["weight"]
	var roll := randf() * total
	for e in EVENTS:
		roll -= e["weight"]
		if roll <= 0.0:
			trigger(e["type"])
			break
	_schedule()


## Palvelin: laukaise tapahtuma heti.
func trigger(type: int) -> void:
	if not multiplayer.is_server():
		return
	var main = get_parent()
	var snow = main.snow
	var size: Vector2 = snow.size()
	var point := Vector3.ZERO
	match type:
		AURA_AUTO:
			_truck_started = Time.get_ticks_msec() / 1000.0
			_truck_hit.clear()
			# Naapurien pihateiden suut tukkeutuvat (kotipiha on aurattu valmiiksi).
			for field in main.neighbours.fields:
				field.add_snow_line(field.cell_center(0, 3), field.cell_center(field.cells_x - 1, 3), 0.9, 35)
		LUMIMYRSKY:
			for field in main.neighbours.fields:
				field.add_snow_everywhere(8, field.STORM_MAX_DEPTH_CM)
		HIRVI:
			if moose_active:
				return
			point = snow.random_point()
			_cl_moose.rpc(true, point, randf() * TAU)
			_moose_left_at = Time.get_ticks_msec() / 1000.0 + MOOSE_MAX_STAY
		PERTTI:
			for i in 4:
				var field = main.neighbours.fields.pick_random()
				field.add_snow(field.random_point(), 0.8, 2500)
		KATTOLUMI:
			var victims: Array = main.players.get_children()
			if victims.is_empty():
				return
			point = victims[randi() % victims.size()].global_position
			main._add(point, 0.7, 3000)
		JALLU:
			for i in BOTTLES_PER_DELIVERY:
				var id := _next_bottle
				_next_bottle += 1
				var spot: Vector3 = snow.random_point()
				_cl_bottle.rpc(id, spot)
				get_tree().create_timer(BOTTLE_LIFETIME).timeout.connect(func(): if bottles.has(id): _cl_remove_bottle.rpc(id))
	for e in EVENTS:
		if e["type"] == type:
			main.announce(e["text"])
	_cl_visual.rpc(type, point, size.y)
	print("[Tapahtuma] %d" % type)


## Kaikilla: tapahtuman visuaalit (auto, hirvi, moottorikelkka).
@rpc("authority", "call_local", "reliable")
func _cl_visual(type: int, point: Vector3, field_depth: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var world: Node3D = get_parent()
	match type:
		AURA_AUTO:
			var truck := Pihapiiri.make_plow_truck()
			world.add_child(truck)
			var road_z := Village.ROAD_Z
			truck.position = Vector3(-45, 0, road_z)
			var tween := create_tween()
			tween.tween_property(truck, "position:x", 45.0, 7.0)
			tween.tween_callback(truck.queue_free)
		PERTTI, JALLU:
			var sled := Pihapiiri.make_snowmobile()
			world.add_child(sled)
			sled.position = Vector3(-14, 0.3, -2)
			sled.rotation.y = -PI * 0.5
			var tween := create_tween()
			tween.tween_property(sled, "position", Vector3(14, 0.3, 3), 4.0)
			tween.tween_callback(sled.queue_free)
		LUMIMYRSKY:
			var main = get_parent()
			if main.scenery.has("snowfall"):
				var particles: GPUParticles3D = main.scenery["snowfall"]
				particles.amount_ratio = 1.0
				get_tree().create_timer(30.0).timeout.connect(func(): particles.amount_ratio = 0.35)


# --- Hirvi ja naava -----------------------------------------------------------------

## Palvelin: pullot, hirvi ja naavat juuri liittyneelle.
func send_state(peer: int) -> void:
	send_bottles(peer)
	if moose_active:
		_cl_moose.rpc_id(peer, true, moose_pos, 0.0)
	for i in naava_ready:
		if not naava_ready[i]:
			_cl_naava.rpc_id(peer, i, false)
	for p in carrying_naava:
		_cl_carry_naava.rpc_id(peer, p, true)


@rpc("authority", "call_local", "reliable")
func _cl_moose(active: bool, pos: Vector3, yaw: float) -> void:
	moose_active = active
	if active:
		moose_pos = pos
	if DisplayServer.get_name() == "headless":
		return
	if active and _moose_node == null:
		_moose_node = Pihapiiri.make_moose()
		get_parent().add_child(_moose_node)
		_moose_node.position = pos
		_moose_node.rotation.y = yaw
	elif not active and _moose_node:
		# Hirvi lönkyttelee metsään ja katoaa.
		var leaving := _moose_node
		_moose_node = null
		var away := Vector3(leaving.position.x, 0, leaving.position.z).normalized()
		if away == Vector3.ZERO:
			away = Vector3.FORWARD
		leaving.rotation.y = atan2(away.x, away.z) + PI
		leaving.get_node("Collision").queue_free()
		var tween := create_tween()
		tween.tween_property(leaving, "position", leaving.position + away * 40.0, 12.0)
		tween.tween_callback(leaving.queue_free)


@rpc("authority", "call_local", "reliable")
func _cl_moose_kick(target: Vector3) -> void:
	if _moose_node == null:
		return
	# Hirvi kääntyy kohti ja nousee takajaloilleen.
	var dir := target - _moose_node.position
	_moose_node.rotation.y = atan2(dir.x, dir.z) + PI
	var tween := create_tween()
	tween.tween_property(_moose_node, "rotation:x", -0.35, 0.12)
	tween.tween_property(_moose_node, "rotation:x", 0.0, 0.3)


## Lähin poimittava naava, johon ylettyy, tai -1.
func naava_near(pos: Vector3) -> int:
	for i in naava_spots.size():
		var spot: Vector3 = naava_spots[i][1]
		if naava_ready.get(i, true) and Vector2(pos.x - spot.x, pos.z - spot.z).length() < Village.NAAVA_RANGE:
			return i
	return -1


func moose_near(pos: Vector3, distance: float) -> bool:
	return moose_active and Vector2(pos.x - moose_pos.x, pos.z - moose_pos.z).length() < distance


@rpc("any_peer", "call_local", "reliable")
func srv_pick_naava(index: int) -> void:
	if not multiplayer.is_server() or index < 0 or index >= naava_spots.size():
		return
	var sender := _sender()
	var player = get_parent().players.get_node_or_null(str(sender))
	var spot: Vector3 = naava_spots[index][1]
	if player == null or not naava_ready[index] or carrying_naava.has(sender) or Vector2(player.global_position.x - spot.x, player.global_position.z - spot.z).length() > Village.NAAVA_RANGE + 0.5:
		return
	naava_ready[index] = false
	_cl_naava.rpc(index, false)
	_cl_carry_naava.rpc(sender, true)
	get_tree().create_timer(Village.NAAVA_REGROW).timeout.connect(func():
		naava_ready[index] = true
		_cl_naava.rpc(index, true))


@rpc("authority", "call_local", "reliable")
func _cl_naava(index: int, available: bool) -> void:
	naava_ready[index] = available
	var main = get_parent()
	if main.scenery.has("naava") and index < main.scenery["naava"].size():
		main.scenery["naava"][index].visible = available


@rpc("authority", "call_local", "reliable")
func _cl_carry_naava(peer: int, carrying: bool) -> void:
	if carrying:
		carrying_naava[peer] = true
	else:
		carrying_naava.erase(peer)
	if peer == multiplayer.get_unique_id() and DisplayServer.get_name() != "headless":
		get_parent().hud.set_naava(carrying)
		if carrying:
			Sfx.play_2d(Sfx.SCOOP)


@rpc("any_peer", "call_local", "reliable")
func srv_feed_moose() -> void:
	if not multiplayer.is_server():
		return
	var sender := _sender()
	var main = get_parent()
	var player = main.players.get_node_or_null(str(sender))
	if player == null or not carrying_naava.has(sender) or not moose_near(player.global_position, MOOSE_FEED_DISTANCE + 0.5):
		return
	_cl_carry_naava.rpc(sender, false)
	_cl_moose.rpc(false, moose_pos, 0.0)
	main._add_xp(sender, MOOSE_FEED_XP)
	main.story.progress(sender, "fed_moose")
	main.announce("%s syötti hirvelle naavaa. Hirvi lönkytteli tyytyväisenä metsään." % main.display_name_for(sender)[0])


## Palvelin: naava putoaa, kun kantaja pyörtyy tai poistuu.
func drop_naava(peer: int) -> void:
	if carrying_naava.has(peer):
		_cl_carry_naava.rpc(peer, false)


func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if _truck_started >= 0.0:
		_check_truck()
	if not moose_active:
		return
	if Time.get_ticks_msec() / 1000.0 > _moose_left_at:
		_cl_moose.rpc(false, moose_pos, 0.0)
		get_parent().announce("Hirvi kyllästyi odottamaan naavaa ja lähti itse.")
		return
	_kick_check -= delta
	if _kick_check > 0.0:
		return
	_kick_check = 0.25
	var main = get_parent()
	var now := Time.get_ticks_msec()
	for player in main.players.get_children():
		var peer := int(String(player.name))
		if carrying_naava.has(peer) or not moose_near(player.global_position, MOOSE_KICK_DISTANCE):
			continue
		if now - int(_last_kick.get(peer, -100000)) < MOOSE_KICK_COOLDOWN_MS:
			continue
		_last_kick[peer] = now
		var push: Vector3 = player.global_position - moose_pos
		push.y = 0.0
		_cl_moose_kick.rpc(player.global_position)
		main.hurt(peer, MOOSE_KICK_DAMAGE, push.normalized() if push.length() > 0.01 else Vector3.BACK)


## Palvelin: tielle jäänyt kolaaja lentää aura-auton edestä kaaressa hankeen.
func _check_truck() -> void:
	var t := Time.get_ticks_msec() / 1000.0 - _truck_started
	if t > TRUCK_TIME:
		_truck_started = -1.0
		return
	var truck_x := lerpf(TRUCK_START_X, TRUCK_END_X, t / TRUCK_TIME)
	var main = get_parent()
	for player in main.players.get_children():
		var peer := int(String(player.name))
		var p: Vector3 = player.global_position
		if _truck_hit.has(peer) or p.y > 2.5 or absf(p.z - Village.ROAD_Z) > 1.9 or p.x < truck_x - 3.5 or p.x > truck_x + 4.8:
			continue
		_truck_hit[peer] = true
		# Auralevy viskaa eteen ja tien sivuun.
		var side := signf(p.z - Village.ROAD_Z + 0.01)
		var push := Vector3(randf_range(9.0, 14.0), randf_range(9.0, 12.0), side * randf_range(6.0, 9.0))
		main.ragdoll(peer, push)


func _sender() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return sender if sender != 0 else multiplayer.get_unique_id()


# --- Jallu-cola ---------------------------------------------------------------------

## Palvelin: lähetä pihalla olevat pullot juuri liittyneelle.
func send_bottles(peer: int) -> void:
	for id in bottles:
		_cl_bottle.rpc_id(peer, id, bottles[id])


@rpc("authority", "call_local", "reliable")
func _cl_bottle(id: int, spot: Vector3) -> void:
	bottles[id] = spot
	if DisplayServer.get_name() == "headless":
		return
	var bottle := Pihapiiri.make_jallu()
	get_parent().add_child(bottle)
	bottle.global_position = spot
	_bottle_nodes[id] = bottle


@rpc("authority", "call_local", "reliable")
func _cl_remove_bottle(id: int) -> void:
	bottles.erase(id)
	if _bottle_nodes.has(id):
		_bottle_nodes[id].queue_free()
		_bottle_nodes.erase(id)


## Lähin pullo, johon ylettyy, tai -1.
func bottle_near(pos: Vector3) -> int:
	var best := -1
	var best_dist := DRINK_DISTANCE
	for id in bottles:
		var d := Vector2(pos.x - bottles[id].x, pos.z - bottles[id].z).length()
		if d < best_dist:
			best = id
			best_dist = d
	return best


@rpc("any_peer", "call_local", "reliable")
func srv_drink(id: int) -> void:
	if not multiplayer.is_server() or not bottles.has(id):
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var main = get_parent()
	var player = main.players.get_node_or_null(str(sender))
	if player == null or Vector2(player.global_position.x - bottles[id].x, player.global_position.z - bottles[id].z).length() > DRINK_DISTANCE + 0.5:
		return
	_cl_remove_bottle.rpc(id)
	main.start_boost(sender, BOOST_SECONDS)
