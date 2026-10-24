extends Node
## Lumipallosota: oikea hiiren nappi heittää lumipallon. Palvelin lennättää pallot ja päättää osumista,
## asiakkaat piirtävät saman lentoradan itse.

const Kelkkapuisto := preload("res://scripts/kelkkapuisto.gd")

const THROW_SPEED := 17.0
const GRAVITY := 9.8
const HIT_RADIUS := 0.55
const LIFETIME := 3.0
const COOLDOWN := 0.45

## Palvelin: {id: {"from", "pos", "vel", "age"}}. Asiakkaat: {id: {"node", "vel", "age"}}.
var _balls := {}
var _visuals := {}
var _next_id := 1
var _last_throw := {}
var _cooldown := 0.0
## Palvelin: viimeisin osuma [heittäjä, kohde] (autotesti).
var last_hit := []
## Autotestin maalitaulut (Node3D, nimenä tunniste) pelaajien lisäksi.
var test_targets := []


## Asiakas: heitä pallo katseen suuntaan.
func throw(camera: Camera3D) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = COOLDOWN
	var dir := -camera.global_transform.basis.z
	srv_throw.rpc_id(1, camera.global_position + dir * 0.5, dir)


@rpc("any_peer", "call_local", "reliable")
func srv_throw(origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var player = get_parent().players.get_node_or_null(str(sender))
	var now := Time.get_ticks_msec() / 1000.0
	if player == null or origin.distance_to(player.global_position) > 3.0 or now - _last_throw.get(sender, -10.0) < COOLDOWN * 0.8:
		return
	_last_throw[sender] = now
	var vel := dir.normalized() * THROW_SPEED + Vector3(0, 2.0, 0)
	var id := _next_id
	_next_id += 1
	_balls[id] = {"from": sender, "pos": origin, "vel": vel, "age": 0.0}
	_cl_ball.rpc(id, origin, vel)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_simulate(delta)
	for id in _visuals.keys():
		var v: Dictionary = _visuals[id]
		v["vel"].y -= GRAVITY * delta
		v["node"].position += v["vel"] * delta
		v["age"] += delta
		var at: Vector3 = v["node"].position
		if v["age"] > LIFETIME or at.y < Kelkkapuisto.height(at.x, at.z):
			_remove_visual(id)


func _simulate(delta: float) -> void:
	var main = get_parent()
	for id in _balls.keys():
		var b: Dictionary = _balls[id]
		b["vel"].y -= GRAVITY * delta
		b["pos"] += b["vel"] * delta
		b["age"] += delta
		var target := -1
		for player in main.players.get_children() + test_targets:
			var peer := int(String(player.name))
			if peer == b["from"]:
				continue
			# Pelaajan keskikohta: vartalo ulottuu jalkojen yläpuolelta pään korkeudelle.
			var p: Vector3 = player.global_position
			var closest := Vector3(p.x, clampf(b["pos"].y, p.y + 0.3, p.y + 1.7), p.z)
			if closest.distance_to(b["pos"]) < HIT_RADIUS:
				target = peer
				break
		if target >= 0:
			_balls.erase(id)
			_cl_pop.rpc(id, b["pos"])
			last_hit = [b["from"], target]
			var push: Vector3 = b["vel"] * Vector3(1, 0, 1)
			if target == multiplayer.get_unique_id() or target in multiplayer.get_peers():
				_cl_splat.rpc_id(target, push.normalized() * 0.35, main.display_name_for(b["from"])[0])
		elif b["age"] > LIFETIME or b["pos"].y < maxf(main.depth_at(b["pos"]) / 100.0, Kelkkapuisto.height(b["pos"].x, b["pos"].z)):
			_balls.erase(id)
			_cl_pop.rpc(id, b["pos"])


@rpc("authority", "call_local", "reliable")
func _cl_ball(id: int, origin: Vector3, vel: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.22
	sphere.radial_segments = 10
	sphere.rings = 6
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.97, 0.98, 1.0)
	mat.roughness = 0.9
	mi.material_override = mat
	get_parent().add_child(mi)
	mi.position = origin
	_visuals[id] = {"node": mi, "vel": vel, "age": 0.0}


@rpc("authority", "call_local", "reliable")
func _cl_pop(id: int, at: Vector3) -> void:
	_remove_visual(id)
	if DisplayServer.get_name() == "headless":
		return
	# Pieni lumipöllähdys osumakohtaan.
	var puff := CPUParticles3D.new()
	puff.one_shot = true
	puff.amount = 14
	puff.lifetime = 0.6
	puff.explosiveness = 1.0
	puff.direction = Vector3.UP
	puff.spread = 70.0
	puff.initial_velocity_min = 1.0
	puff.initial_velocity_max = 2.5
	puff.gravity = Vector3(0, -6, 0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.08
	puff.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	puff.material_override = mat
	get_parent().add_child(puff)
	puff.global_position = at
	puff.emitting = true
	get_tree().create_timer(1.0).timeout.connect(puff.queue_free)


@rpc("authority", "call_local", "reliable")
func _cl_splat(push: Vector3, thrower: String) -> void:
	var main = get_parent()
	if main.dedicated:
		return
	main.hud.splat()
	main.hud.chat("%s osui sinuun lumipallolla!" % thrower, Color(0.8, 0.9, 1.0))
	var me = main.local_player()
	if me and not me.riding:
		me.knockback(push * 9.0 + Vector3(0, 1.5, 0))


func _remove_visual(id: int) -> void:
	if _visuals.has(id):
		_visuals[id]["node"].queue_free()
		_visuals.erase(id)
