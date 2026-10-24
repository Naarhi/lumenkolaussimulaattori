extends Node
## Verkkoyhteys (ENet, UDP) ja komentoriviparametrit.
##
## Käynnistys komentoriviltä (parametrit "--"-erottimen jälkeen):
##   --server              dedikoitu palvelin (käytä myös --headless)
##   --host                isännöi peliä ja pelaa itse
##   --connect=osoite      liity palvelimelle (oletus himbe.jnarhi.fi)
##   --port=7777           portti
##   --autotest            testiajo: kolaa automaattisesti ja lopeta
##   --screenshot=polku    tallenna kuvakaappaus testiajon lopuksi

const DEFAULT_PORT := 7777
const DEFAULT_ADDRESS := "himbe.jnarhi.fi"
const MAX_PLAYERS := 8

var cli := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.substr(2).split("=", true, 1)
			cli[parts[0]] = parts[1] if parts.size() > 1 else "true"
	_setup_input()


func port() -> int:
	return int(cli.get("port", DEFAULT_PORT))


func host(listen_port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(listen_port, MAX_PLAYERS)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		print("[Net] Palvelin kuuntelee porttia %d" % listen_port)
	return err


func join(address: String, join_port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, join_port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		print("[Net] Yhdistetään %s:%d" % [address, join_port])
	return err


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _setup_input() -> void:
	_add_keys("eteen", [KEY_W, KEY_UP])
	_add_keys("taakse", [KEY_S, KEY_DOWN])
	_add_keys("vasen", [KEY_A, KEY_LEFT])
	_add_keys("oikea", [KEY_D, KEY_RIGHT])
	_add_keys("hyppy", [KEY_SPACE])
	_add_keys("juokse", [KEY_SHIFT])
	if not InputMap.has_action("kolaa"):
		InputMap.add_action("kolaa")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("kolaa", click)


func _add_keys(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
