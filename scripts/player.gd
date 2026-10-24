extends CharacterBody3D
## Ensimmäisen persoonan pelaaja lumilapion kanssa.
## Liike lasketaan pelaajan omalla koneella ja synkronoidaan muille. Lumi ja lapio ovat palvelimen hallinnassa.

const WALK_SPEED := 4.5
const DEEP_SNOW_SPEED := 1.7
const DEEP_SNOW_CM := 60.0
const RUN_MULTIPLIER := 1.6
const BOOST_MULTIPLIER := 1.5
const JUMP_VELOCITY := 4.2
const MOUSE_SENSITIVITY := 0.0025
const Tools := preload("res://scripts/tools.gd")
const Village := preload("res://scripts/village.gd")
const Pihapiiri := preload("res://scripts/pihapiiri.gd")
const SLED_MAX_SPEED := 13.0
const SLED_REVERSE_SPEED := 3.0
const SLED_ACCEL := 7.0
const SLED_BRAKE := 12.0
const SLED_TURN := 1.9
const SLED_HEIGHT := 0.25
## Mäessä kelkka kiihtyy alamäkeen, ja ilmassa Shift + A/D pyörittää ja Shift + W/S tekee volttia.
const SLED_SLOPE_PULL := 0.7
const SLED_MAX_DOWNHILL := 22.0
const AIR_SPIN := 5.5
const AIR_FLIP := 6.0
## Näin pitkä ilmalento lasketaan stuntiksi.
const STUNT_MIN_AIR := 0.5
## Tanssit: näppäin, nimi ja kesto (0 = kunnes liikkuu).
enum { EI_TANSSIA = -1, HUMPPA, LETKAJENKKA, TUULETUS, KUMARRUS }
const EMOTES := [
	{"key": KEY_Z, "name": "Humppa", "time": 0.0},
	{"key": KEY_X, "name": "Letkajenkka", "time": 0.0},
	{"key": KEY_C, "name": "Tuuletus", "time": 3.0},
	{"key": KEY_V, "name": "Kumarrus", "time": 2.0},
]
const RAGDOLL_TIME := 3.5
const JACKET_COLORS := [
	Color(0.75, 0.12, 0.1), Color(0.1, 0.3, 0.7), Color(0.95, 0.55, 0.1),
	Color(0.15, 0.5, 0.25), Color(0.5, 0.2, 0.6), Color(0.85, 0.75, 0.2),
]

var peer_id := 1
## Valittu työkalu (Tools.LAPIO...) ja onko se käytössä. Pelaaja itse päättää, palvelin lukee synkronoidusta arvosta.
var tool := 0
var tool_active := false
## Testiajo pitää työkalua pohjassa ilman hiirtä.
var force_active := false
## Jallu-boostia jäljellä sekunteina (palvelin asettaa kaikille).
var boost_time := 0.0
## Ajaako pelaaja omalla moottorikelkallaan (synkronoidaan).
var riding := false
## Testiajo painaa kaasua ilman näppäimistöä.
var force_drive := false
## Käynnissä oleva tanssi (synkronoidaan) ja sen alkuhetki tällä koneella.
var emote := -1
var _emote_seen := -1
var _emote_clock := 0.0
## Aura-auton heittämänä lentäminen: jäljellä oleva aika ja pyörimisakseli.
var ragdoll_time := 0.0
var _spin_axis := Vector3.RIGHT
var _arms: Array[Node3D] = []
var head: Node3D
var camera: Camera3D
var shovel: Node3D
var shovel_snow: MeshInstance3D

var _body: Node3D
var _nametag: Label3D
var _tool_models: Array[Node3D] = []
var _tool_fx := {}
var _sound_timer := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _swing: Tween
var _sled: Node3D
## Kelkan nokan kallistus (mäki tai voltti). Synkronoidaan muille pelaajille.
var stunt_pitch := 0.0
var _air_time := 0.0
var _air_yaw := 0.0
var _air_pitch := 0.0
var _takeoff_pitch := 0.0
var _speed := 0.0
## Tönäisy (hirven potku), joka hiipuu nopeasti.
var _knock := Vector3.ZERO


func _init() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.76
	shape.shape = capsule
	shape.position.y = 0.88
	add_child(shape)

	head = Node3D.new()
	head.name = "Head"
	head.position.y = 1.6
	add_child(head)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 75.0
	camera.near = 0.05
	head.add_child(camera)

	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	_nametag = Label3D.new()
	_nametag.position.y = 2.15
	_nametag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nametag.font_size = 40
	_nametag.pixel_size = 0.004
	_nametag.outline_size = 10
	_nametag.modulate = Color(1.0, 0.9, 0.2)
	_nametag.no_depth_test = false
	_body.add_child(_nametag)

	_sled = Pihapiiri.make_snowmobile(false)
	_sled.position.y = SLED_HEIGHT
	_sled.visible = false
	add_child(_sled)

	shovel = _make_shovel()
	head.add_child(shovel)
	_build_tools()

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.root_path = NodePath("..")
	var config := SceneReplicationConfig.new()
	for path in [NodePath(".:position"), NodePath(".:rotation"), NodePath("Head:rotation"), NodePath(".:tool"), NodePath(".:tool_active"), NodePath(".:riding"), NodePath(".:emote"), NodePath(".:stunt_pitch")]:
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	add_child(sync)


func _ready() -> void:
	add_to_group("players")
	_build_body(JACKET_COLORS[absi(peer_id) % JACKET_COLORS.size()])
	var mine := is_multiplayer_authority()
	camera.current = mine
	_body.visible = not mine
	if mine:
		add_to_group("local_player")
	var shown: Array = _main().display_name_for(peer_id)
	set_display_name(shown[0], shown[1])


func _build_tools() -> void:
	var masi := Tools.make_masi()
	add_child(masi)
	var blower := Tools.make_blower()
	add_child(blower)
	var blower_fx := Tools.make_blower_fx()
	blower.get_node("FxAnchor").add_child(blower_fx)
	var flamer := Tools.make_flamethrower()
	head.add_child(flamer)
	var flame_fx := Tools.make_flame_fx()
	flamer.get_node("FxAnchor").add_child(flame_fx)
	var salt := Tools.make_salt_bucket()
	head.add_child(salt)
	var salt_fx := Tools.make_salt_fx()
	salt.get_node("FxAnchor").add_child(salt_fx)
	_tool_models = [shovel, masi, blower, flamer, salt]
	_tool_fx = {Tools.LINKO: blower_fx, Tools.LIEKKI: flame_fx, Tools.SUOLA: salt_fx}
	_show_tool()


func _show_tool() -> void:
	for i in _tool_models.size():
		_tool_models[i].visible = i == tool and not riding and emote < 0 and ragdoll_time <= 0.0


## Valitse työkalu. Ostamatonta ei voi valita; rullalla (step) hypätään seuraavaan omaan.
func select_tool(index: int, step := 0) -> void:
	var t := posmod(index, Tools.COUNT)
	if step != 0:
		for i in Tools.COUNT:
			if _main().has_tool(t):
				break
			t = posmod(t + step, Tools.COUNT)
	if not _main().has_tool(t):
		_main().hud.tool_locked(t)
		return
	tool = t
	_show_tool()
	_main().hud.set_tool(tool)


## Hyppää kelkan selkään tai pois.
func toggle_riding() -> void:
	if not riding and not "kelkka" in _main().owned:
		_main().hud.chat("Moottorikelkan saa koneliikkeestä tien itäpäästä.", Color(1.0, 0.75, 0.4))
		return
	riding = not riding
	_speed = 0.0
	stunt_pitch = 0.0
	_air_time = 0.0
	# Kelkalla kamera on selän takana, jotta hypyt ja voltit näkyvät.
	_set_third_person(riding or emote >= 0)
	if not riding:
		# Katse jää samaan suuntaan, kun noustaan kelkasta.
		rotation.y += head.rotation.y
		head.rotation.y = 0.0


func _process(delta: float) -> void:
	boost_time = maxf(boost_time - delta, 0.0)
	if is_multiplayer_authority():
		var hud = _main().hud
		hud.set_boost(boost_time)
		hud.set_hint(_interaction_hint())
	# Boostissa näkymä keinuu hieman.
	camera.rotation.z = sin(Time.get_ticks_msec() * 0.003) * 0.03 * minf(boost_time, 1.0)
	_sled.visible = riding
	_sled.rotation.x = stunt_pitch if riding else 0.0
	_animate_body(delta)
	var tool_shown := not riding and emote < 0 and ragdoll_time <= 0.0
	if _tool_models[tool].visible != tool_shown:
		_show_tool()
	for t in _tool_fx:
		_tool_fx[t].emitting = tool_active and tool == t
	var flamer := _tool_models[Tools.LIEKKI]
	(flamer.get_node("Pilot") as OmniLight3D).light_energy = 2.5 if tool_active and tool == Tools.LIEKKI else 0.0
	if tool_active and tool == Tools.LINKO:
		_tool_models[Tools.LINKO].get_node("Auger").rotate_x(delta * 20.0)
	_sound_timer -= delta
	if (tool_active or riding) and _sound_timer <= 0.0 and DisplayServer.get_name() != "headless":
		_sound_timer = Tools.SOUND_INTERVAL
		var sound := Sfx.SLED if riding else Tools.sound_for(tool)
		if sound >= 0:
			Sfx.play_at(sound, global_position + Vector3(0, 1, 0), self)


## Mitä E-näppäin tekisi juuri nyt: [tunniste, vihje].
func _interaction() -> Array:
	var events = _main().events
	var shop := Village.shop_near(global_position)
	var mine: bool = events.carrying_naava.has(peer_id)
	if shop >= 0:
		return ["kauppa", "E: %s" % Village.SHOPS[shop]["name"]]
	if mine and events.moose_near(global_position, events.MOOSE_FEED_DISTANCE):
		return ["hirvi", "E: syötä naavaa hirvelle"]
	if not mine and events.naava_near(global_position) >= 0:
		return ["naava", "E: kerää naavaa"]
	if events.bottle_near(global_position) >= 0:
		return ["jallu", "E: juo Jallu-colaa"]
	return ["", ""]


func _interaction_hint() -> String:
	return _interaction()[1]


## E-näppäin: kauppa, hirven ruokinta, naavan poiminta tai Jallu-cola. Palauttaa tehdyn toiminnon.
func interact() -> String:
	var events = _main().events
	var what: String = _interaction()[0]
	match what:
		"kauppa":
			_main().hud.open_shop(Village.shop_near(global_position))
		"hirvi":
			events.srv_feed_moose.rpc_id(1)
		"naava":
			events.srv_pick_naava.rpc_id(1, events.naava_near(global_position))
		"jallu":
			try_drink()
	return what


func knockback(push: Vector3) -> void:
	_knock = Vector3(push.x, 0.0, push.z)
	velocity.y = push.y


## Juo lähin Jallu-cola, jos sellainen on ulottuvilla.
func try_drink() -> bool:
	var id: int = _main().events.bottle_near(global_position)
	if id < 0:
		return false
	_main().events.srv_drink.rpc_id(1, id)
	return true


func set_display_name(player_name: String, level: int) -> void:
	_nametag.text = "%s (taso %d)" % [player_name, level] if player_name != "" else ""


func _typing() -> bool:
	return _main().hud.blocks_input()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or _typing():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if riding:
			# Kelkalla hiiri kääntää vain päätä, ohjaus on A/D-näppäimillä.
			head.rotation.y = clampf(head.rotation.y - event.relative.x * MOUSE_SENSITIVITY, -2.0, 2.0)
		else:
			rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.45, 1.45)
	elif event.is_action_pressed("kolaa"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif tool == Tools.LAPIO and not riding:
			request_shovel()
	elif event.is_action_pressed("heita") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_main().snowballs.throw(camera)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		interact()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		toggle_riding()
	elif event is InputEventKey and event.pressed and not event.echo and not riding:
		for i in EMOTES.size():
			if event.physical_keycode == EMOTES[i]["key"]:
				start_emote(-1 if emote == i else i)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode >= KEY_1 and event.physical_keycode < KEY_1 + Tools.COUNT:
		select_tool(event.physical_keycode - KEY_1)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var step := 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
		select_tool(tool + step, step)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	tool_active = force_active or tool != Tools.LAPIO and not riding and not _typing() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("kolaa")
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("hyppy") and not _typing() and not riding:
		velocity.y = JUMP_VELOCITY
	if ragdoll_time > 0.0:
		_fly(delta)
		return
	if riding:
		_drive(delta)
		return

	var input := Vector2.ZERO if _typing() else Input.get_vector("vasen", "oikea", "eteen", "taakse")
	# Liikkuminen tai työkalu keskeyttää tanssin.
	if emote >= 0 and (input != Vector2.ZERO or tool_active):
		start_emote(-1)
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var depth: float = _main().depth_at(global_position)
	var speed := lerpf(WALK_SPEED, DEEP_SNOW_SPEED, clampf(depth / DEEP_SNOW_CM, 0.0, 1.0))
	if Input.is_action_pressed("juokse") and not _typing():
		speed *= RUN_MULTIPLIER
	if boost_time > 0.0:
		speed *= BOOST_MULTIPLIER
	velocity.x = direction.x * speed + _knock.x
	velocity.z = direction.z * speed + _knock.z
	_knock = _knock.move_toward(Vector3.ZERO, 18.0 * delta)
	move_and_slide()

	camera.fov = 75.0
	# Syvässä lumessa silmät ovat hieman alempana.
	head.position.y = 1.6 - minf(depth, 60.0) / 100.0 * 0.4


## Aloita tai lopeta tanssi (-1). Vain oma pelaaja.
func start_emote(index: int) -> void:
	emote = index
	_set_third_person(emote >= 0 or riding)


## Aura-auto osui: pelaaja lentää ja pyörii hetken (kaikilla koneilla näkyy pyöriminen).
func start_ragdoll(push: Vector3) -> void:
	ragdoll_time = RAGDOLL_TIME
	_spin_axis = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()
	if is_multiplayer_authority():
		if riding:
			toggle_riding()
		emote = -1
		velocity = push
		_set_third_person(true)


func _fly(delta: float) -> void:
	velocity.y -= _gravity * delta
	if is_on_floor() and velocity.y <= 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
	move_and_slide()
	if ragdoll_time - delta <= 0.0:
		_set_third_person(false)


## Kolmannen persoonan kamera tanssiessa ja lentäessä, jotta oman hahmon näkee.
func _set_third_person(on: bool) -> void:
	if not is_multiplayer_authority():
		return
	camera.position = Vector3(0, 0.6, 3.6) if on else Vector3.ZERO
	camera.rotation.x = -0.2 if on else 0.0
	_body.visible = on
	# Omaa nimeä ei näytetä omassa kamerassa.
	_nametag.visible = false
	_show_tool()


func _animate_body(delta: float) -> void:
	if emote != _emote_seen:
		_emote_seen = emote
		_emote_clock = 0.0
		if emote >= 0 and DisplayServer.get_name() != "headless":
			Sfx.play_at(Sfx.DANCE, global_position + Vector3(0, 1, 0), self)
	_emote_clock += delta
	var t := _emote_clock
	var pos := Vector3(0, 0.5 if riding else 0.0, 0)
	var rot := Vector3.ZERO
	var arm_l := Vector3.ZERO
	var arm_r := Vector3.ZERO
	if ragdoll_time > 0.0:
		ragdoll_time = maxf(ragdoll_time - delta, 0.0)
		# Lennossa pyöritään, maassa maataan kyljellään.
		var spin := 14.0 * minf(ragdoll_time, 1.0)
		_body.rotate(_spin_axis, spin * delta)
		_body.position = Vector3(0, 0.5, 0)
		for arm in _arms:
			arm.rotation.z = sin(Time.get_ticks_msec() * 0.02 + arm.position.x * 10.0) * 2.0
		if ragdoll_time <= 0.0:
			_body.rotation = Vector3.ZERO
		return
	match emote:
		HUMPPA:
			pos.y = absf(sin(t * 6.5)) * 0.12
			rot.y = sin(t * 3.25) * 0.5
			arm_l.x = sin(t * 6.5) * 1.1
			arm_r.x = -sin(t * 6.5) * 1.1
		LETKAJENKKA:
			pos.y = maxf(sin(t * 8.0), 0.0) * 0.25
			rot.z = sin(t * 4.0) * 0.2
			arm_l.z = -1.3
			arm_r.z = 1.3
		TUULETUS:
			pos.y = absf(sin(t * 5.0)) * 0.3
			arm_l.z = -2.7 + sin(t * 12.0) * 0.3
			arm_r.z = 2.7 - sin(t * 12.0) * 0.3
		KUMARRUS:
			pos = Vector3(0, 0, -0.25 * minf(t * 3.0, 1.0))
			rot.x = -0.6 * minf(t * 3.0, 1.0)
			arm_l.x = 0.4
			arm_r.x = 0.4
	if emote >= 0 and EMOTES[emote]["time"] > 0.0 and t > EMOTES[emote]["time"] and is_multiplayer_authority():
		start_emote(-1)
	if riding:
		rot.x += stunt_pitch
	_body.position = pos
	_body.rotation = rot
	if _arms.size() == 2:
		_arms[0].rotation = arm_l
		_arms[1].rotation = arm_r


## Moottorikelkka: W/S kaasu ja jarru, A/D ohjaus. Syvä lumi ei hidasta kelkkaa.
func _drive(delta: float) -> void:
	var throttle := 1.0 if force_drive else (0.0 if _typing() else Input.get_axis("taakse", "eteen"))
	var steer := 0.0 if _typing() else Input.get_axis("oikea", "vasen")
	if throttle > 0.0:
		_speed = move_toward(_speed, SLED_MAX_SPEED * (BOOST_MULTIPLIER if boost_time > 0.0 else 1.0), SLED_ACCEL * delta)
	elif throttle < 0.0:
		_speed = move_toward(_speed, -SLED_REVERSE_SPEED, SLED_BRAKE * delta)
	else:
		_speed = move_toward(_speed, 0.0, 3.0 * delta)
	if not is_on_floor():
		_air(delta, throttle, steer)
		return
	var grip := clampf(absf(_speed) / 4.0, 0.0, 1.0) * signf(_speed if _speed != 0.0 else 1.0)
	rotate_y(steer * SLED_TURN * grip * delta)
	var forward := -transform.basis.z
	# Kuljetaan maan pintaa pitkin, jotta hyppyrin nokalta lähdetään ilmaan.
	var normal := get_floor_normal()
	var along := (forward - normal * forward.dot(normal)).normalized()
	_speed = clampf(_speed - along.y * _gravity * SLED_SLOPE_PULL * delta, -SLED_REVERSE_SPEED * 2.0, SLED_MAX_DOWNHILL)
	if _air_time > 0.0:
		_land()
	velocity = along * _speed
	stunt_pitch = lerp_angle(stunt_pitch, asin(clampf(along.y, -1.0, 1.0)), minf(delta * 12.0, 1.0))
	move_and_slide()
	if is_on_wall():
		_speed *= 0.5
	head.position.y = 1.6 + SLED_HEIGHT * 0.4
	camera.fov = 75.0 + absf(_speed) * 0.8


## Ilmassa vauhti säilyy. Shift pohjassa A/D pyörittää kelkkaa ja W/S tekee volttia.
func _air(delta: float, throttle: float, steer: float) -> void:
	if _air_time == 0.0:
		_takeoff_pitch = stunt_pitch
		_air_yaw = 0.0
		_air_pitch = 0.0
	_air_time += delta
	# Temput vain Shift pohjassa, ettei hyppyristä kaasu pohjassa lähtevä pyöri vahingossa.
	var trick := not _typing() and Input.is_action_pressed("juokse")
	var spin := steer * (AIR_SPIN if trick else SLED_TURN * 0.5) * delta
	rotate_y(spin)
	_air_yaw += spin
	if trick:
		_air_pitch -= throttle * AIR_FLIP * delta
	stunt_pitch = _takeoff_pitch + _air_pitch
	move_and_slide()
	head.position.y = 1.6 + SLED_HEIGHT * 0.4


## Alastulo: laske temput ja kerro palvelimelle. Huono asento kaataa kelkan.
func _land() -> void:
	var yaw_off := absf(wrapf(_air_yaw, -PI, PI))
	var pitch_off := absf(wrapf(_air_pitch, -PI, PI))
	var spins := roundi(absf(_air_yaw) / TAU)
	var flips := roundi(absf(_air_pitch) / TAU)
	var crashed := pitch_off > 0.9 or yaw_off > 1.1
	if _air_time >= STUNT_MIN_AIR or crashed:
		_main().srv_stunt.rpc_id(1, _air_time, spins, flips, crashed)
	if not crashed:
		# Laskeudutaan sinne päin, mihin nokka osoittaa.
		_speed = maxf(_speed * cos(minf(yaw_off, PI * 0.5)), 0.0)
	_air_time = 0.0
	_air_yaw = 0.0
	_air_pitch = 0.0


## Pyydä palvelinta kauhomaan tai heittämään. Animaatio näytetään heti.
func request_shovel() -> void:
	if _swing:
		_swing.kill()
	_swing = create_tween()
	_swing.tween_property(shovel, "rotation:x", -0.5, 0.1)
	_swing.tween_property(shovel, "rotation:x", 0.0, 0.25)
	_main().srv_shovel.rpc_id(1, rotation.y)


func set_carrying(carrying: bool) -> void:
	shovel_snow.visible = carrying


func _main():
	return get_tree().current_scene


func _make_shovel() -> Node3D:
	# Juuri on kädessä (kuvan oikea alakulma), joten heilautus kiertää kahvan ympäri.
	var root := Node3D.new()
	root.name = "Shovel"
	root.position = Vector3(0.34, -0.44, -0.4)
	var blade_center := Vector3(-0.26, -0.32, -0.96)
	var blade_back := Vector3(-0.23, -0.29, -0.78)
	var axis := blade_back
	var shaft := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.018
	cylinder.bottom_radius = 0.02
	cylinder.height = axis.length() + 0.12
	shaft.mesh = cylinder
	shaft.material_override = _mat(Color(0.75, 0.6, 0.35))
	shaft.basis = Basis(Quaternion(Vector3.UP, -axis.normalized()))
	shaft.position = axis * 0.5 - axis.normalized() * 0.06
	root.add_child(shaft)
	var grip := MeshInstance3D.new()
	var grip_mesh := CylinderMesh.new()
	grip_mesh.top_radius = 0.022
	grip_mesh.bottom_radius = 0.022
	grip_mesh.height = 0.14
	grip.mesh = grip_mesh
	grip.material_override = _mat(Color(0.12, 0.12, 0.12))
	grip.position = -axis.normalized() * 0.12
	grip.rotation.z = PI * 0.5
	root.add_child(grip)
	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.42, 0.03, 0.38)
	blade.mesh = blade_mesh
	blade.material_override = _mat(Color(0.1, 0.35, 0.8))
	blade.position = blade_center
	blade.rotation = Vector3(-0.12, atan2(-axis.x, -axis.z), 0)
	root.add_child(blade)
	# Terän takareuna ja sivulaidat
	var back := MeshInstance3D.new()
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(0.42, 0.09, 0.02)
	back.mesh = back_mesh
	back.material_override = blade.material_override
	back.position = Vector3(0, 0.045, 0.18)
	blade.add_child(back)
	for side in [-1.0, 1.0]:
		var rim := MeshInstance3D.new()
		var rim_mesh := BoxMesh.new()
		rim_mesh.size = Vector3(0.02, 0.07, 0.38)
		rim.mesh = rim_mesh
		rim.material_override = blade.material_override
		rim.position = Vector3(side * 0.2, 0.035, 0)
		blade.add_child(rim)
	shovel_snow = MeshInstance3D.new()
	var lump := SphereMesh.new()
	lump.radius = 0.17
	lump.height = 0.18
	shovel_snow.mesh = lump
	shovel_snow.material_override = _mat(Color(0.95, 0.97, 1.0))
	shovel_snow.position = Vector3(0, 0.07, 0)
	shovel_snow.visible = false
	blade.add_child(shovel_snow)
	return root


func _build_body(jacket: Color) -> void:
	var torso := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.5
	torso.mesh = capsule
	torso.material_override = _mat(jacket)
	torso.position.y = 0.8
	_body.add_child(torso)
	# Kädet olkapäistä, jotta tanssit näkyvät.
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.34, 1.3, 0)
		_body.add_child(shoulder)
		var arm := MeshInstance3D.new()
		var arm_mesh := CapsuleMesh.new()
		arm_mesh.radius = 0.08
		arm_mesh.height = 0.62
		arm.mesh = arm_mesh
		arm.material_override = torso.material_override
		arm.position.y = -0.28
		shoulder.add_child(arm)
		var mitten := MeshInstance3D.new()
		var mitten_mesh := SphereMesh.new()
		mitten_mesh.radius = 0.08
		mitten_mesh.height = 0.16
		mitten.mesh = mitten_mesh
		mitten.material_override = _mat(Color(0.15, 0.15, 0.18))
		mitten.position.y = -0.6
		shoulder.add_child(mitten)
		_arms.append(shoulder)
	var face := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	face.mesh = sphere
	face.material_override = _mat(Color(0.95, 0.78, 0.65))
	face.position = Vector3(0, 1.6, -0.05)
	_body.add_child(face)
	var hat := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.17
	cone.height = 0.25
	hat.mesh = cone
	hat.material_override = _mat(Color(0.9, 0.9, 0.95))
	hat.position.y = 1.78
	_body.add_child(hat)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m
