extends CharacterBody3D
## Ensimmäisen persoonan pelaaja lumilapion kanssa.
## Liike lasketaan pelaajan omalla koneella ja synkronoidaan muille. Lumi ja lapio ovat palvelimen hallinnassa.

const WALK_SPEED := 4.5
const DEEP_SNOW_SPEED := 1.7
const DEEP_SNOW_CM := 60.0
const RUN_MULTIPLIER := 1.6
const JUMP_VELOCITY := 4.2
const MOUSE_SENSITIVITY := 0.0025
const Tools := preload("res://scripts/tools.gd")
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

	shovel = _make_shovel()
	head.add_child(shovel)
	_build_tools()

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.root_path = NodePath("..")
	var config := SceneReplicationConfig.new()
	for path in [NodePath(".:position"), NodePath(".:rotation"), NodePath("Head:rotation"), NodePath(".:tool"), NodePath(".:tool_active")]:
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
		_tool_models[i].visible = i == tool


func select_tool(index: int) -> void:
	tool = posmod(index, Tools.COUNT)
	_show_tool()
	_main().hud.set_tool(tool)


func _process(delta: float) -> void:
	if not _tool_models[tool].visible:
		_show_tool()
	for t in _tool_fx:
		_tool_fx[t].emitting = tool_active and tool == t
	var flamer := _tool_models[Tools.LIEKKI]
	(flamer.get_node("Pilot") as OmniLight3D).light_energy = 2.5 if tool_active and tool == Tools.LIEKKI else 0.0
	if tool_active and tool == Tools.LINKO:
		_tool_models[Tools.LINKO].get_node("Auger").rotate_x(delta * 20.0)
	_sound_timer -= delta
	if tool_active and _sound_timer <= 0.0 and DisplayServer.get_name() != "headless":
		_sound_timer = Tools.SOUND_INTERVAL
		var sound := Tools.sound_for(tool)
		if sound >= 0:
			Sfx.play_at(sound, global_position + Vector3(0, 1, 0), self)


func set_display_name(player_name: String, level: int) -> void:
	_nametag.text = "%s (taso %d)" % [player_name, level] if player_name != "" else ""


func _typing() -> bool:
	return _main().hud.blocks_input()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or _typing():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.45, 1.45)
	elif event.is_action_pressed("kolaa"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif tool == Tools.LAPIO:
			request_shovel()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode >= KEY_1 and event.physical_keycode < KEY_1 + Tools.COUNT:
		select_tool(event.physical_keycode - KEY_1)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		select_tool(tool + (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1))


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	tool_active = force_active or tool != Tools.LAPIO and not _typing() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("kolaa")
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("hyppy") and not _typing():
		velocity.y = JUMP_VELOCITY

	var input := Vector2.ZERO if _typing() else Input.get_vector("vasen", "oikea", "eteen", "taakse")
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var depth: float = _main().snow.depth_at(global_position)
	var speed := lerpf(WALK_SPEED, DEEP_SNOW_SPEED, clampf(depth / DEEP_SNOW_CM, 0.0, 1.0))
	if Input.is_action_pressed("juokse") and not _typing():
		speed *= RUN_MULTIPLIER
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()

	# Syvässä lumessa silmät ovat hieman alempana.
	head.position.y = 1.6 - minf(depth, 60.0) / 100.0 * 0.4


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
