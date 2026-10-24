extends Node3D
## Pelin runko: valikko, yhteydet, pelaajien luonti ja palvelimen pelilogiikka (lapio, XP).

const PlayerScript := preload("res://scripts/player.gd")
const Pihapiiri := preload("res://scripts/pihapiiri.gd")
const Skills := preload("res://scripts/skills.gd")
const Tools := preload("res://scripts/tools.gd")

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

# Omat skriptit tyypittämättöminä, jotta niiden funktioita voi kutsua suoraan.
@onready var snow = $SnowField
@onready var players: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $Spawner
@onready var events = $Events
@onready var hud = $HUD

var dedicated := false
var scenery := {}

# Palvelimen tila pelaajittain.
var _carried := {}
var _xp := {}
var _last_shovel := {}
var _footprint_timer := {}
var _names := {}
var _tool_timer := {}
var _xp_pending := {}
var _xp_flush := 0.0
var _last_chat := {}

# Testiajo
var _autotest_started := false


func _ready() -> void:
	snow.position = Vector3(-snow.size().x * 0.5, 0.0, -snow.size().y * 0.5)
	dedicated = Net.cli.has("server") or OS.has_feature("dedicated_server")
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


func _start_server(is_dedicated: bool) -> void:
	var err := Net.host(Net.port())
	if err != OK:
		hud.show_menu(self, "Palvelimen käynnistys epäonnistui (portti %d varattu?)" % Net.port())
		return
	snow.start_server()
	events.start_server()
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
	spawner.spawn(id)
	_cl_xp.rpc_id(id, 0, false)
	for peer in _names:
		_cl_name.rpc_id(id, peer, _names[peer])


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("[Peli] Pelaaja %d poistui" % id)
	if _names.has(id):
		_cl_announce.rpc("%s lähti pihalta." % _names[id])
		_names.erase(id)
	var player := players.get_node_or_null(str(id))
	if player:
		player.queue_free()
	_carried.erase(id)
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
	if now - int(_last_shovel.get(sender, -100000)) < SHOVEL_COOLDOWN_MS:
		return
	_last_shovel[sender] = now

	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var feet := player.global_position
	var carried: int = _carried.get(sender, 0)
	if carried == 0:
		var target := feet + forward * SHOVEL_REACH
		var removed: int = snow.remove_snow(target, SHOVEL_RADIUS, SHOVEL_CAPACITY, SHOVEL_BITE_CM)
		if removed > 0:
			_carried[sender] = removed
			_cl_carried.rpc(sender, removed)
			_cl_fx.rpc(target, true)
			print("[Peli] Pelaaja %d kauhoi %d" % [sender, removed])
	else:
		var target := feet + forward * THROW_DISTANCE
		snow.add_snow(target, SHOVEL_RADIUS * 1.6, carried)
		_carried[sender] = 0
		_cl_carried.rpc(sender, 0)
		_cl_fx.rpc(target, false)
		_add_xp(sender, maxi(1, carried / 20))
		print("[Peli] Pelaaja %d heitti %d" % [sender, carried])


func _add_xp(peer: int, amount: int) -> void:
	var old: int = _xp.get(peer, 0)
	var new_xp := old + amount
	_xp[peer] = new_xp
	var leveled := Skills.level_for_xp(new_xp) > Skills.level_for_xp(old)
	_cl_xp.rpc_id(peer, new_xp, leveled)


# --- Nimet ja chat ---------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func srv_set_name(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var clean := _clean_text(player_name, 16)
	if clean == "":
		clean = "Kolaaja%d" % (sender % 1000)
	var first := not _names.has(sender)
	_names[sender] = clean
	_cl_name.rpc(sender, clean)
	if first:
		_cl_announce.rpc("%s saapui pihalle!" % clean)


@rpc("authority", "call_local", "reliable")
func _cl_name(peer: int, player_name: String) -> void:
	_names[peer] = player_name
	var player = players.get_node_or_null(str(peer))
	if player:
		player.set_display_name(player_name)


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


func announce(text: String) -> void:
	_cl_announce.rpc(text)


func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		_server_footprints(delta)
		_server_tools(delta)
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
		if not child.tool_active or tool == Tools.LAPIO:
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
				var moved: int = snow.remove_snow(feet + forward * 0.75, 0.4, 100000, 10)
				if moved > 0:
					snow.add_snow(feet + forward * 1.45, 0.45, moved)
				xp = moved / 150.0
			Tools.LINKO:
				# Linko syö lumen edestä ja lennättää sen kuusi metriä oikealle eteen.
				var blown: int = snow.remove_snow(feet + forward * 0.8, 0.32, 100000, 12)
				if blown > 0:
					var throw_dir := (forward * 0.55 + right * 0.85).normalized()
					snow.add_snow(feet + throw_dir * 6.5, 1.0, blown)
				xp = blown / 60.0
			Tools.LIEKKI:
				var melted: int = snow.remove_snow(feet + forward * 1.6, 0.45, 100000, 3)
				melted += snow.remove_snow(feet + forward * 2.6, 0.6, 100000, 2)
				xp = melted / 90.0
			Tools.SUOLA:
				snow.salt_area(feet + forward * 1.2, 0.7, SALT_DURATION)
		_xp_pending[id] = _xp_pending.get(id, 0.0) + xp
	_xp_flush -= delta
	if _xp_flush <= 0.0:
		_xp_flush = 1.0
		for id in _xp_pending.keys():
			var whole := int(_xp_pending[id])
			if whole > 0:
				_xp_pending[id] -= whole
				_add_xp(id, whole)


## Liikkuvat pelaajat painavat lunta kasaan (jalanjäljet).
func _server_footprints(delta: float) -> void:
	for child in players.get_children():
		var player := child as Node3D
		var id := int(String(player.name))
		var last: Vector3 = player.get_meta("last_pos", player.global_position)
		var moved := Vector2(player.global_position.x - last.x, player.global_position.z - last.z).length()
		player.set_meta("last_pos", player.global_position)
		var timer: float = _footprint_timer.get(id, 0.0) - delta
		if moved > 0.01 and snow.depth_at(player.global_position) > FOOTPRINT_CM and timer <= 0.0:
			timer = 0.35
			snow.remove_snow(player.global_position, 0.14, 100000, FOOTPRINT_CM)
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
	var depth_before: float = snow.depth_at(me.global_position + Vector3(0, 0, -probe))
	if tool == Tools.LAPIO:
		for i in 6:
			me.request_shovel()
			await get_tree().create_timer(0.7).timeout
	else:
		me.select_tool(tool)
		me.force_active = true
		await get_tree().create_timer(4.0).timeout
	await get_tree().create_timer(1.0).timeout
	var depth_after: float = snow.depth_at(me.global_position + Vector3(0, 0, -probe))
	print("AUTOTEST %s: lumi ennen %.0f cm, jälkeen %.0f cm, XP %d" % [Tools.NAMES[tool], depth_before, depth_after, hud.xp])
	if Net.cli.has("screenshot"):
		me.rotation.y = deg_to_rad(float(Net.cli.get("yaw", "0")))
		me.head.rotation.x = -0.35
		if Net.cli.has("event") and multiplayer.is_server():
			events.trigger(int(Net.cli["event"]))
		await get_tree().create_timer(float(Net.cli.get("wait", "1.5"))).timeout
		var image := get_viewport().get_texture().get_image()
		image.save_png(Net.cli["screenshot"])
		print("AUTOTEST kuvakaappaus " + Net.cli["screenshot"])
	me.force_active = false
	var ok: bool = depth_after < depth_before and (hud.xp > 0 or tool == Tools.SUOLA)
	print("AUTOTEST " + ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
