extends Node3D
## Pelin runko: valikko, yhteydet, pelaajien luonti ja palvelimen pelilogiikka (lapio, XP).

const PlayerScript := preload("res://scripts/player.gd")
const Pihapiiri := preload("res://scripts/pihapiiri.gd")
const Skills := preload("res://scripts/skills.gd")
const Tools := preload("res://scripts/tools.gd")
const Village := preload("res://scripts/village.gd")
const NeighboursScript := preload("res://scripts/neighbours.gd")

const SHOVEL_REACH := 1.1
const SHOVEL_RADIUS := 0.25
const SHOVEL_CAPACITY := 400
const SHOVEL_BITE_CM := 15
const THROW_DISTANCE := 2.6
const SHOVEL_COOLDOWN_MS := 450
const FOOTPRINT_CM := 3
const SALT_DURATION := 600.0
const CHAT_MAX_LENGTH := 120
const CHAT_COOLDOWN_MS := 600
## Suolaa kuluu näin monta kiloa jokaisella sirottelulla (Tools.INTERVAL).
const SALT_PER_USE := 0.25
## Moottorikelkka painaa lunta kasaan, mutta ei tätä matalammaksi.
const SLED_PACK_CM := 10
const MAX_HEALTH := 100
const HEALTH_REGEN := 5
const SPAWN_POINT := Vector3(0, 0.05, 4.0)

# Omat skriptit tyypittämättöminä, jotta niiden funktioita voi kutsua suoraan.
@onready var snow = $SnowField
@onready var players: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $Spawner
@onready var events = $Events
@onready var hud = $HUD

var dedicated := false
var scenery := {}
var neighbours
## Kaikki lumikentät: kotipiha ja naapurien pihatiet.
var fields: Array = []
## Oman pelaajan rahat, ostetut tavarat ja suolakilot (palvelin lähettää).
var money := 0
var owned: Array = []
var salt := 0.0

# Palvelimen tila pelaajittain.
var _carried := {}
var _xp := {}
# Palvelin: tallennetut kolaajat nimen mukaan (pienillä kirjaimilla): {"xp", "money", "owned", "salt"}.
var _saved := {}
var _save_dirty := false
var _save_timer := 0.0
var _levels := {}
# Palvelin: Jallu-boostin päättymishetki pelaajittain (ms).
var _boost_until := {}
var _last_shovel := {}
var _footprint_timer := {}
var _names := {}
var _tool_timer := {}
var _xp_pending := {}
var _xp_flush := 0.0
var _last_chat := {}
var _money := {}
var _owned := {}
var _salt := {}
var _profile_dirty := {}
## Palvelin: kolaajien kunto (0-100). Hirven potku vie kuntoa, ja se palautuu hiljalleen.
var _health := {}
var _regen_timer := 0.0

# Testiajo
var _autotest_started := false


func _ready() -> void:
	# Kotipiha ulottuu talon edestä tien reunaan asti, jotta aura-auton penkka on suoraan tien vieressä.
	snow.setup(19.2, 9.6 + Village.ROAD_Z - Village.ROAD_HALF_WIDTH)
	snow.position = Vector3(-snow.size().x * 0.5, 0.0, -9.6)
	dedicated = Net.cli.has("server") or OS.has_feature("dedicated_server")
	neighbours = NeighboursScript.new()
	neighbours.name = "Naapurit"
	add_child(neighbours)
	fields = [snow] + neighbours.fields
	if not dedicated:
		scenery = Pihapiiri.build(self, snow)

	spawner.spawn_function = _spawn_player
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if dedicated:
		_start_server(true)
	elif Net.cli.has("host"):
		_start_server(false)
	elif Net.cli.has("connect"):
		var address: String = Net.cli["connect"]
		_join(Net.DEFAULT_ADDRESS if address == "true" else address)
	else:
		hud.show_menu(self)


# --- Valikon toiminnot -------------------------------------------------------

func start_singleplayer() -> void:
	_start_server(false)


func start_host() -> void:
	_start_server(false)


func join_game(address: String) -> void:
	_join(address)


## Esc-valikon "Poistu päävalikkoon": katkaise yhteys tai lopeta oma palvelin.
func leave_game() -> void:
	if multiplayer.is_server():
		for peer in _names:
			_store_profile(peer)
		_write_saves()
	Net.leave()
	for p in players.get_children():
		p.queue_free()
	for dict in [_carried, _names, _levels, _xp, _money, _owned, _salt]:
		dict.clear()
	hud.show_menu(self)


func _start_server(is_dedicated: bool) -> void:
	var err := Net.host(Net.port())
	if err != OK:
		hud.show_menu(self, "Palvelimen käynnistys epäonnistui (portti %d varattu?)" % Net.port())
		return
	snow.start_server()
	neighbours.start_server()
	events.start_server()
	_load_saves()
	if not is_dedicated:
		spawner.spawn(1)
		_enter_game()
		srv_set_name(hud.player_name())


func _join(address: String) -> void:
	var host := address
	var join_port := Net.port()
	if ":" in address:
		host = address.get_slice(":", 0)
		join_port = int(address.get_slice(":", 1))
	if Net.join(host, join_port) != OK:
		hud.show_menu(self, "Yhdistäminen epäonnistui.")
		return
	hud.show_status("Yhdistetään palvelimelle %s..." % address)


func _enter_game() -> void:
	hud.hide_menu()
	hud.show_game()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Yhteystapahtumat ------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("[Peli] Pelaaja %d liittyi" % id)
	snow.send_full_state(id)
	neighbours.send_full_state(id)
	events.send_state(id)
	spawner.spawn(id)
	for peer in _names:
		_cl_name.rpc_id(id, peer, _names[peer], Skills.level_for_xp(_xp.get(peer, 0)))


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("[Peli] Pelaaja %d poistui" % id)
	_store_profile(id)
	_write_saves()
	events.drop_naava(id)
	if _names.has(id):
		_cl_announce.rpc("%s lähti pihalta." % _names[id])
		_names.erase(id)
	var player := players.get_node_or_null(str(id))
	if player:
		player.queue_free()
	for dict in [_carried, _xp, _money, _owned, _salt, _profile_dirty, _health]:
		dict.erase(id)
	_xp_pending.erase(id)
	_tool_timer.erase(id)


func _on_connected() -> void:
	print("[Peli] Yhdistetty palvelimelle, oma id %d" % multiplayer.get_unique_id())
	_enter_game()
	srv_set_name.rpc_id(1, hud.player_name())


func _on_connection_failed() -> void:
	Net.leave()
	hud.show_menu(self, "Palvelimeen ei saatu yhteyttä.")
	if Net.cli.has("autotest"):
		print("AUTOTEST FAIL: yhteys epäonnistui")
		get_tree().quit(1)


func _on_server_disconnected() -> void:
	Net.leave()
	for p in players.get_children():
		p.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_menu(self, "Yhteys palvelimeen katkesi.")


func _spawn_player(id: int) -> Node:
	var player := PlayerScript.new()
	player.name = str(id)
	player.peer_id = id
	player.position = Vector3(float(absi(id) % 5) - 2.0, 0.05, 4.0)
	player.set_multiplayer_authority(id)
	return player


func local_player():
	return players.get_node_or_null(str(multiplayer.get_unique_id()))


# --- Pelilogiikka palvelimella -----------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func srv_shovel(yaw: float) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var player := players.get_node_or_null(str(sender)) as Node3D
	if player == null:
		return
	var now := Time.get_ticks_msec()
	var cooldown := SHOVEL_COOLDOWN_MS / 2 if now < int(_boost_until.get(sender, 0)) else SHOVEL_COOLDOWN_MS
	if now - int(_last_shovel.get(sender, -100000)) < cooldown:
		return
	_last_shovel[sender] = now

	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var feet := player.global_position
	var carried: int = _carried.get(sender, 0)
	if carried == 0:
		var target := feet + forward * SHOVEL_REACH
		var removed := _remove(sender, target, SHOVEL_RADIUS, SHOVEL_CAPACITY, SHOVEL_BITE_CM)
		if removed > 0:
			_carried[sender] = removed
			_cl_carried.rpc(sender, removed)
			_cl_fx.rpc(target, true)
			print("[Peli] Pelaaja %d kauhoi %d" % [sender, removed])
	else:
		var target := feet + forward * THROW_DISTANCE
		_add(target, SHOVEL_RADIUS * 1.6, carried)
		_carried[sender] = 0
		_cl_carried.rpc(sender, 0)
		_cl_fx.rpc(target, false)
		_add_xp(sender, maxi(1, carried / 20))
		print("[Peli] Pelaaja %d heitti %d" % [sender, carried])


func _add_xp(peer: int, amount: int) -> void:
	var old: int = _xp.get(peer, 0)
	var new_xp := old + amount
	_xp[peer] = new_xp
	_store_profile(peer)
	var leveled := Skills.level_for_xp(new_xp) > Skills.level_for_xp(old)
	_cl_xp.rpc_id(peer, new_xp, leveled)
	if leveled and _names.has(peer):
		_cl_name.rpc(peer, _names[peer], Skills.level_for_xp(new_xp))


# --- Lumikentät -------------------------------------------------------------------

## Lumikenttä, jonka alueella piste on, tai null (tie, metsä, kaupat).
func field_at(pos: Vector3):
	for field in fields:
		if field.contains(pos):
			return field
	return null


func depth_at(pos: Vector3) -> float:
	var field = field_at(pos)
	return field.depth_at(pos) if field else 0.0


## Palvelin: poista lunta siltä kentältä, jolla piste on. Naapurin pihatiellä työ kirjataan pelaajalle.
func _remove(peer: int, pos: Vector3, radius: float, max_amount: int, max_per_cell: int) -> int:
	var field = field_at(pos)
	if field == null:
		return 0
	var removed: int = field.remove_snow(pos, radius, max_amount, max_per_cell)
	if peer != 0:
		neighbours.credit(field, peer, removed)
	return removed


## Palvelin: kasaa lunta. Pihojen ulkopuolelle heitetty lumi katoaa hankeen.
func _add(pos: Vector3, radius: float, amount: int) -> void:
	var field = field_at(pos)
	if field:
		field.add_snow(pos, radius, amount)


# --- Rahat, tavarat ja tallennus ------------------------------------------------------

func _save_path() -> String:
	return Net.cli.get("save", "user://kolaajat.json")


func _load_saves() -> void:
	var file := FileAccess.open(_save_path(), FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		for key in data:
			# Vanhoissa tallennuksissa oli pelkkä XP-luku.
			var entry = data[key]
			_saved[str(key)] = entry if entry is Dictionary else {"xp": int(entry)}
	print("[Peli] Ladattu %d kolaajan tiedot tiedostosta %s" % [_saved.size(), ProjectSettings.globalize_path(_save_path())])


func _store_profile(peer: int) -> void:
	if _names.has(peer) and _xp.has(peer):
		_saved[String(_names[peer]).to_lower()] = {
			"xp": _xp[peer], "money": _money.get(peer, 0), "owned": _owned.get(peer, []), "salt": snappedf(_salt.get(peer, 0.0), 0.01),
		}
		_save_dirty = true


func _write_saves() -> void:
	if not _save_dirty:
		return
	_save_dirty = false
	var file := FileAccess.open(_save_path(), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_saved, "\t"))
	else:
		push_warning("Kolaajien tallennus epäonnistui: %s" % _save_path())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		for peer in _names:
			_store_profile(peer)
		_write_saves()


## Palvelin: anna pelaajalle rahaa (naapurin palkkio).
func add_money(peer: int, amount: int) -> void:
	_money[peer] = _money.get(peer, 0) + amount
	_store_profile(peer)
	_send_profile(peer)
	_cl_cash.rpc_id(peer, amount)


func _send_profile(peer: int) -> void:
	_profile_dirty.erase(peer)
	_cl_profile.rpc_id(peer, _money.get(peer, 0), _owned.get(peer, []), _salt.get(peer, 0.0))


@rpc("authority", "call_local", "reliable")
func _cl_profile(new_money: int, new_owned: Array, new_salt: float) -> void:
	money = new_money
	owned = new_owned
	salt = new_salt
	hud.set_inventory(money, owned, salt)
	var me = local_player()
	if me and not has_tool(me.tool):
		me.select_tool(Tools.LAPIO)


@rpc("authority", "call_local", "reliable")
func _cl_cash(amount: int) -> void:
	if not dedicated:
		Sfx.play_2d(Sfx.COINS)
		hud.chat("Sait %d €." % amount, Color(0.5, 1.0, 0.4))


## Asiakas: onko oma pelaaja ostanut työkalun (lapio on aina, suolaa pitää olla säkissä).
func has_tool(tool: int) -> bool:
	if tool == Tools.SUOLA:
		return salt > 0.0
	var item := Village.item_for_tool(tool)
	return item == "" or item in owned


## Palvelin: saako pelaaja käyttää työkalua.
func _may_use(peer: int, tool: int) -> bool:
	if tool == Tools.SUOLA:
		return _salt.get(peer, 0.0) > 0.0
	var item := Village.item_for_tool(tool)
	return item == "" or item in _owned.get(peer, [])


func buy(item: String) -> void:
	srv_buy.rpc_id(1, item)


@rpc("any_peer", "call_local", "reliable")
func srv_buy(item: String) -> void:
	if not multiplayer.is_server() or not Village.ITEMS.has(item):
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var player = players.get_node_or_null(str(sender))
	var info: Dictionary = Village.ITEMS[item]
	if player == null or Village.shop_near(player.global_position) != info["shop"] or not _names.has(sender):
		return
	var list: Array = _owned.get(sender, [])
	var consumable := info.has("salt")
	if not consumable and item in list:
		return
	var price: int = info["price"]
	if _money.get(sender, 0) < price:
		_cl_announce.rpc_id(sender, "Rahat eivät riitä: %s maksaa %d €." % [info["name"], price])
		return
	_money[sender] -= price
	if consumable:
		_salt[sender] = _salt.get(sender, 0.0) + info["salt"]
	else:
		list.append(item)
		_owned[sender] = list
	_store_profile(sender)
	_send_profile(sender)
	_cl_bought.rpc_id(sender, item)
	print("[Kauppa] %s osti: %s" % [_names[sender], info["name"]])
	if not consumable:
		_cl_announce.rpc("%s osti uuden vehkeen: %s!" % [_names[sender], info["name"]])


@rpc("authority", "call_local", "reliable")
func _cl_bought(item: String) -> void:
	if dedicated:
		return
	Sfx.play_2d(Sfx.COINS)
	var info: Dictionary = Village.ITEMS[item]
	hud.chat("Ostit: %s (%d €)." % [info["name"], info["price"]], Color(0.5, 1.0, 0.4))
	var me = local_player()
	if me and info.has("tool"):
		me.select_tool(info["tool"])


# --- Nimet ja chat ---------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func srv_set_name(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if _names.has(sender):
		return
	var clean := _clean_text(player_name, 16)
	if clean == "":
		clean = "Kolaaja%d" % (sender % 1000)
	# Sama nimi ei voi olla kahdella paikalla olevalla pelaajalla (XP jaettaisiin).
	var taken := false
	for peer in _names:
		if String(_names[peer]).to_lower() == clean.to_lower():
			taken = true
	if taken:
		clean = "%s%d" % [clean.left(13), randi_range(10, 99)]
	_names[sender] = clean
	var saved: Dictionary = _saved.get(clean.to_lower(), {})
	var xp := int(saved.get("xp", 0))
	_xp[sender] = xp
	_money[sender] = int(saved.get("money", 0))
	_owned[sender] = Array(saved.get("owned", [])).filter(func(i): return Village.ITEMS.has(i))
	_salt[sender] = float(saved.get("salt", 0.0))
	# Testiajo (vain palvelimen komentorivillä): kaikki tavarat heti.
	if Net.cli.has("give"):
		_owned[sender] = Village.ITEM_ORDER.filter(func(i): return i != "suola")
		_salt[sender] = 50.0
	_cl_xp.rpc_id(sender, xp, false)
	_send_profile(sender)
	var level := Skills.level_for_xp(xp)
	_cl_name.rpc(sender, clean, level)
	if xp > 0:
		_cl_announce.rpc("%s (Kolaus-taso %d) palasi pihalle!" % [clean, level])
	else:
		_cl_announce.rpc("%s saapui pihalle!" % clean)


@rpc("authority", "call_local", "reliable")
func _cl_name(peer: int, player_name: String, level: int) -> void:
	_names[peer] = player_name
	_levels[peer] = level
	var player = players.get_node_or_null(str(peer))
	if player:
		player.set_display_name(player_name, level)


## Nimikyltin teksti pelaajalle, jos nimi on jo tiedossa (pelaaja voi syntyä vasta nimen jälkeen).
func display_name_for(peer: int) -> Array:
	return [_names.get(peer, ""), _levels.get(peer, 1)]


func send_chat(text: String) -> void:
	srv_chat.rpc_id(1, text)


@rpc("any_peer", "call_local", "reliable")
func srv_chat(text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var now := Time.get_ticks_msec()
	if now - int(_last_chat.get(sender, -100000)) < CHAT_COOLDOWN_MS:
		return
	_last_chat[sender] = now
	var clean := _clean_text(text, CHAT_MAX_LENGTH)
	if clean != "":
		_cl_chat.rpc(_names.get(sender, "Kolaaja"), clean)


@rpc("authority", "call_local", "reliable")
func _cl_chat(from_name: String, text: String) -> void:
	print("[Chat] %s: %s" % [from_name, text])
	if not dedicated:
		hud.chat("%s: %s" % [from_name, text], Color(0.55, 0.8, 1.0))


## Poistaa rivinvaihdot ja ohjausmerkit ja lyhentää tekstin.
static func _clean_text(text: String, max_length: int) -> String:
	var out := ""
	for c in text:
		if c.unicode_at(0) >= 32:
			out += c
	return out.strip_edges().left(max_length)


## Palvelin: vahinko ja tönäisy (hirven potku). Kunnon loppuessa kolaaja pyörtyy ja herää kotipihalta.
func hurt(peer: int, damage: int, push: Vector3) -> void:
	var health: int = _health.get(peer, MAX_HEALTH) - damage
	var fainted := health <= 0
	var player_name: String = _names.get(peer, "Joku")
	if fainted:
		health = MAX_HEALTH
		events.drop_naava(peer)
		_cl_announce.rpc("Hirvi potkaisi kolaajan %s hankeen. %s pyörtyi ja heräsi kotipihalta." % [player_name, player_name])
	else:
		_cl_announce.rpc("Hirvi potkaisi kolaajaa %s! Hae naavaa ennen kuin menet lähelle." % player_name)
	_health[peer] = health
	_cl_health.rpc_id(peer, health, push, fainted)


@rpc("authority", "call_local", "reliable")
func _cl_health(health: int, push: Vector3, fainted: bool) -> void:
	hud.set_health(health, push != Vector3.ZERO)
	var me = local_player()
	if me == null:
		return
	if fainted:
		if me.riding:
			me.toggle_riding()
		me.global_position = SPAWN_POINT
		me.velocity = Vector3.ZERO
	elif push != Vector3.ZERO:
		me.knockback(push * 9.0 + Vector3(0, 4.0, 0))
	if push != Vector3.ZERO and not dedicated:
		Sfx.play_2d(Sfx.OOF)


## Palvelin: Jallu-cola nopeuttaa juojan liikettä ja lapiota.
func start_boost(peer: int, seconds: float) -> void:
	_boost_until[peer] = Time.get_ticks_msec() + int(seconds * 1000.0)
	_cl_boost.rpc(peer, seconds)
	_cl_announce.rpc("%s joi Jallu-colaa! Lapio heiluu nyt tuplavauhtia." % _names.get(peer, "Joku"))


@rpc("authority", "call_local", "reliable")
func _cl_boost(peer: int, seconds: float) -> void:
	var player = players.get_node_or_null(str(peer))
	if player:
		player.boost_time = seconds
	if not dedicated and player:
		Sfx.play_at(Sfx.DRINK, player.global_position + Vector3(0, 1.5, 0), self)
		get_tree().create_timer(0.8).timeout.connect(func(): if is_instance_valid(player): Sfx.play_at(Sfx.BURP, player.global_position + Vector3(0, 1.5, 0), self))


func announce(text: String) -> void:
	_cl_announce.rpc(text)


func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		_server_footprints(delta)
		_server_tools(delta)
		_save_timer -= delta
		if _save_timer <= 0.0:
			_save_timer = 10.0
			_write_saves()
		_regen_timer -= delta
		if _regen_timer <= 0.0:
			_regen_timer = 3.0
			for peer in _health.keys():
				if _health[peer] < MAX_HEALTH:
					_health[peer] = mini(_health[peer] + HEALTH_REGEN, MAX_HEALTH)
					_cl_health.rpc_id(peer, _health[peer], Vector3.ZERO, false)
	if not Net.cli.has("autotest") or _autotest_started:
		return
	if local_player():
		_autotest_started = true
		_run_autotest()


## Pohjassa pidettävät työkalut: kola, linko, liekinheitin ja suola.
func _server_tools(delta: float) -> void:
	for child in players.get_children():
		var id := int(String(child.name))
		var tool: int = child.tool
		if not child.tool_active or tool == Tools.LAPIO or child.riding or not _may_use(id, tool):
			_tool_timer[id] = 0.0
			continue
		var timer: float = _tool_timer.get(id, 0.0) - delta
		if timer > 0.0:
			_tool_timer[id] = timer
			continue
		_tool_timer[id] = timer + Tools.INTERVAL[tool]
		var yaw: float = child.rotation.y
		var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var feet: Vector3 = child.global_position
		var xp := 0.0
		match tool:
			Tools.MASI:
				# Kola työntää lunta edellään. Pihan reunan yli työnnetty lumi katoaa.
				var moved := _remove(id, feet + forward * 0.75, 0.4, 100000, 10)
				if moved > 0:
					_add(feet + forward * 1.45, 0.45, moved)
				xp = moved / 150.0
			Tools.LINKO:
				# Linko syö lumen edestä ja lennättää sen kuusi metriä oikealle eteen.
				var blown := _remove(id, feet + forward * 0.8, 0.32, 100000, 12)
				if blown > 0:
					var throw_dir := (forward * 0.55 + right * 0.85).normalized()
					_add(feet + throw_dir * 6.5, 1.0, blown)
				xp = blown / 60.0
			Tools.LIEKKI:
				var melted := _remove(id, feet + forward * 1.6, 0.45, 100000, 3)
				melted += _remove(id, feet + forward * 2.6, 0.6, 100000, 2)
				xp = melted / 90.0
			Tools.SUOLA:
				var spot := feet + forward * 1.2
				var field = field_at(spot)
				if field:
					var cells: int = field.salt_area(spot, 0.7, SALT_DURATION)
					neighbours.credit(field, id, cells * 3.0)
				_salt[id] = maxf(_salt.get(id, 0.0) - SALT_PER_USE, 0.0)
				_profile_dirty[id] = true
		_xp_pending[id] = _xp_pending.get(id, 0.0) + xp
	_xp_flush -= delta
	if _xp_flush <= 0.0:
		_xp_flush = 1.0
		for id in _xp_pending.keys():
			var whole := int(_xp_pending[id])
			if whole > 0:
				_xp_pending[id] -= whole
				_add_xp(id, whole)
		for id in _profile_dirty.keys():
			_store_profile(id)
			_send_profile(id)


## Liikkuvat pelaajat painavat lunta kasaan (jalanjäljet).
func _server_footprints(delta: float) -> void:
	for child in players.get_children():
		var player := child as Node3D
		var id := int(String(player.name))
		var last: Vector3 = player.get_meta("last_pos", player.global_position)
		var moved := Vector2(player.global_position.x - last.x, player.global_position.z - last.z).length()
		player.set_meta("last_pos", player.global_position)
		var timer: float = _footprint_timer.get(id, 0.0) - delta
		var depth := depth_at(player.global_position)
		if player.riding:
			# Kelkan telamatto painaa leveän uran, mutta ei kolaa pihaa puhtaaksi.
			if moved > 0.01 and depth > SLED_PACK_CM and timer <= 0.0:
				timer = 0.1
				_remove(0, player.global_position, 0.45, 100000, mini(4, int(depth) - SLED_PACK_CM))
		elif moved > 0.01 and depth > FOOTPRINT_CM and timer <= 0.0:
			timer = 0.35
			_remove(0, player.global_position, 0.14, 100000, FOOTPRINT_CM)
		_footprint_timer[id] = timer


# --- Asiakkaalle lähetettävät -------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _cl_carried(peer: int, amount: int) -> void:
	var player = players.get_node_or_null(str(peer))
	if player:
		player.set_carrying(amount > 0)
	if peer == multiplayer.get_unique_id():
		hud.set_carrying(amount)


@rpc("authority", "call_local", "unreliable")
func _cl_fx(world_position: Vector3, scoop: bool) -> void:
	if not dedicated:
		Sfx.play_at(Sfx.SCOOP if scoop else Sfx.THROW, world_position, self)


@rpc("authority", "call_local", "reliable")
func _cl_xp(xp: int, leveled: bool) -> void:
	hud.set_xp(xp)
	if leveled:
		var level := Skills.level_for_xp(xp)
		Sfx.play_2d(Sfx.LEVEL_UP)
		hud.chat("Onneksi olkoon, nousit Kolaus-tasolle %d!" % level, Color(1.0, 0.9, 0.2))
		hud.level_up_popup(level)


@rpc("authority", "call_local", "reliable")
func _cl_announce(text: String) -> void:
	print("[Ilmoitus] " + text)
	if not dedicated:
		Sfx.play_2d(Sfx.ANNOUNCE)
		hud.chat(text, Color(0.4, 1.0, 1.0))


func _process(_delta: float) -> void:
	# Lumisade seuraa omaa kameraa.
	var me = local_player()
	if me and scenery.has("snowfall"):
		scenery["snowfall"].global_position = me.global_position + Vector3(0, 9, 0)


# --- Testiajo ------------------------------------------------------------

func _run_autotest() -> void:
	print("AUTOTEST alkaa, pelaaja %d" % multiplayer.get_unique_id())
	send_chat("Moi testistä!")
	await get_tree().create_timer(1.0).timeout
	var me = local_player()
	var tool := int(Net.cli.get("tool", "0"))
	# Mittauspiste työkalun vaikutusalueelta (katse -Z-suuntaan).
	var probe := {Tools.LAPIO: SHOVEL_REACH, Tools.MASI: 0.75, Tools.LINKO: 0.8, Tools.LIEKKI: 1.6, Tools.SUOLA: 1.2}[tool] as float
	var depth_before := depth_at(me.global_position + Vector3(0, 0, -probe))
	if tool == Tools.LAPIO:
		for i in 6:
			me.request_shovel()
			await get_tree().create_timer(0.7).timeout
	else:
		me.select_tool(tool)
		me.force_active = true
		await get_tree().create_timer(4.0).timeout
	await get_tree().create_timer(1.0).timeout
	var depth_after := depth_at(me.global_position + Vector3(0, 0, -probe))
	var jallu_ok := true
	if Net.cli.has("jallu") and multiplayer.is_server():
		events.trigger(events.JALLU)
		await get_tree().create_timer(0.3).timeout
		var spot: Vector3 = events.bottles.values()[0]
		me.global_position = spot + Vector3(0.3, 0.05, 0)
		await get_tree().create_timer(0.3).timeout
		var drank: bool = me.try_drink()
		await get_tree().create_timer(0.5).timeout
		jallu_ok = drank and me.boost_time > 0.0 and events.bottles.size() == events.BOTTLES_PER_DELIVERY - 1
		print("AUTOTEST Jallu-cola: joi %s, boostia %.1f s, pulloja jäljellä %d" % [drank, me.boost_time, events.bottles.size()])
	print("AUTOTEST %s: lumi ennen %.0f cm, jälkeen %.0f cm, XP %d" % [Tools.NAMES[tool], depth_before, depth_after, hud.xp])
	var economy_ok := true
	if Net.cli.has("economy") and multiplayer.is_server():
		economy_ok = await _autotest_economy(me)
	var moose_ok := true
	if Net.cli.has("hirvi") and multiplayer.is_server():
		moose_ok = await _autotest_moose(me)
	var sled_ok := true
	if Net.cli.has("kelkka"):
		sled_ok = await _autotest_sled(me)
	if Net.cli.has("screenshot"):
		me.rotation.y = deg_to_rad(float(Net.cli.get("yaw", "0")))
		me.head.rotation.x = -0.35
		if Net.cli.has("jallu") and not events.bottles.is_empty():
			me.global_position = events.bottles.values()[0] + Vector3(0, 0.05, 1.3)
			me.head.rotation.x = -0.6
		if Net.cli.has("pos"):
			var xz: PackedStringArray = Net.cli["pos"].split(",")
			me.global_position = Vector3(float(xz[0]), 0.05, float(xz[1]))
			me.head.rotation.x = deg_to_rad(float(Net.cli.get("pitch", "-8")))
		if Net.cli.has("ride") and not me.riding:
			me.toggle_riding()
		if Net.cli.has("pause"):
			hud._open_pause()
		if Net.cli.has("event") and multiplayer.is_server():
			events.trigger(int(Net.cli["event"]))
			if events.moose_active:
				# Katsotaan hirveä sivulta.
				await get_tree().create_timer(0.2).timeout
				me.global_position = events.moose_pos + Vector3(4.5, 0.05, -1.0)
				me.rotation.y = deg_to_rad(80)
				me.head.rotation.x = -0.1
		await get_tree().create_timer(float(Net.cli.get("wait", "1.5"))).timeout
		var image := get_viewport().get_texture().get_image()
		image.save_png(Net.cli["screenshot"])
		print("AUTOTEST kuvakaappaus " + Net.cli["screenshot"])
	me.force_active = false
	var ok: bool = jallu_ok and economy_ok and sled_ok and moose_ok and depth_after < depth_before and (hud.xp > 0 or tool == Tools.SUOLA)
	print("AUTOTEST " + ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


## Kolaa naapurin pihatie, ota palkkio ja osta sillä MASI rautakaupasta.
func _autotest_economy(me) -> bool:
	var start_money := money
	me.select_tool(Tools.MASI)
	var locked: bool = me.tool == Tools.LAPIO
	var index := 2
	var field = neighbours.fields[index]
	me.global_position = field.to_global(Vector3(field.size().x * 0.5, 0.05, 3.0))
	me.rotation.y = 0.0
	await get_tree().create_timer(0.3).timeout
	for i in 4:
		me.request_shovel()
		await get_tree().create_timer(0.7).timeout
	neighbours.debug_clear(index)
	await get_tree().create_timer(NeighboursScript.CHECK_INTERVAL + 0.5).timeout
	var paid := money - start_money
	me.global_position = Village.counter_position(Village.RAUTAKAUPPA) + Vector3(0, 0.05, 0)
	await get_tree().create_timer(0.3).timeout
	buy("masi")
	await get_tree().create_timer(0.5).timeout
	var price: int = Village.ITEMS["masi"]["price"]
	var bought: bool = "masi" in owned and money == start_money + paid - price
	me.select_tool(Tools.MASI)
	print("AUTOTEST Talous: lukossa %s, palkkio %d €, MASI ostettu %s, rahaa %d €, työkalu %s" % [locked, paid, bought, money, Tools.NAMES[me.tool]])
	return locked and paid == Village.NEIGHBOURS[index]["pay"] and bought and me.tool == Tools.MASI


## Aja moottorikelkalla tielle päin.
func _autotest_sled(me) -> bool:
	me.rotation.y = PI
	var start: Vector3 = me.global_position
	me.toggle_riding()
	me.force_drive = true
	await get_tree().create_timer(2.5).timeout
	me.force_drive = false
	var dist := Vector2(me.global_position.x - start.x, me.global_position.z - start.z).length()
	var rode: bool = me.riding
	print("AUTOTEST Moottorikelkka: kyydissä %s, ajettu %.1f m" % [rode, dist])
	if not Net.cli.has("ride"):
		me.toggle_riding()
	return rode and dist > 8.0


## Hirvi potkaisee tyhjin käsin tulevaa, mutta lähtee, kun sille tuo naavaa.
func _autotest_moose(me) -> bool:
	events.trigger(events.HIRVI)
	await get_tree().create_timer(0.3).timeout
	me.global_position = events.moose_pos + Vector3(1.6, 0.05, 0)
	await get_tree().create_timer(1.0).timeout
	var kicked: bool = hud.health < MAX_HEALTH
	var spot: Vector3 = events.naava_spots[0][1]
	me.global_position = spot + Vector3(0, 0.05, 0)
	await get_tree().create_timer(0.3).timeout
	var picked: bool = me.interact() == "naava"
	await get_tree().create_timer(0.3).timeout
	var carrying: bool = events.carrying_naava.has(multiplayer.get_unique_id())
	me.global_position = events.moose_pos + Vector3(2.0, 0.05, 0.8)
	await get_tree().create_timer(0.3).timeout
	var fed: bool = me.interact() == "hirvi"
	await get_tree().create_timer(0.5).timeout
	print("AUTOTEST Hirvi: potkaisi %s (kunto %d), naava poimittu %s, syötetty %s, hirvi pihalla %s" % [kicked, hud.health, picked and carrying, fed, events.moose_active])
	return kicked and picked and carrying and fed and not events.moose_active
