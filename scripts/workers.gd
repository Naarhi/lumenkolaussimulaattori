extends Node
## Palkattavat työntekijät. Palvelin ohjaa duunareita: ne kävelevät tilattuun pihatiehen,
## lapioivat lunta ja kantavat sen lumikasaan. Työ kirjataan palkkaajalle, joka maksaa
## palkan minuutin välein. Jos rahat loppuvat, duunari lähtee kotiin.

const Village := preload("res://scripts/village.gd")
const SnowField := preload("res://scripts/snow_field.gd")

const WALK_SPEED := 2.4
const SCOOP_RADIUS := 0.6
const SCOOP_BITE_CM := 25
const SCOOP_TIME := 0.7
const DUMP_TIME := 0.5
const WAGE_INTERVAL := 60.0
const SYNC_INTERVAL := 0.15
const MAX_PER_PLAYER := 2
## Duunarit odottavat töitä työnvälityksen pihassa.
const IDLE_SPOT := Vector3(-3.0, 0.0, Village.ROAD_FAR + 2.0)

enum { WALK_TO_SNOW, SCOOP, WALK_TO_PILE, DUMP, IDLE }

## Palvelin: {id: {"item", "name", "employer", "pos", "yaw", "state", "target", "field", "carried", "timer", "wage_timer"}}
var _workers := {}
var _next_id := 1
var _sync_timer := 0.0
## Asiakkaat: {id: Node3D} ja tavoitesijainnit pehmeää liikettä varten.
var _nodes := {}
var _goal := {}


## Palvelin: palkkaa duunari. Palauttaa virheilmoituksen tai "".
func hire(employer: int, item: String) -> String:
	var count := 0
	for w in _workers.values():
		if w["employer"] == employer:
			if w["item"] == item:
				return "already"
			count += 1
	if count >= MAX_PER_PLAYER:
		return "Sinulla voi olla enintään %d duunaria." % MAX_PER_PLAYER
	var info: Dictionary = Village.ITEMS[item]
	var id := _next_id
	_next_id += 1
	_workers[id] = {
		"item": item, "name": info["worker"], "employer": employer, "pos": IDLE_SPOT + Vector3(randf_range(-2, 2), 0, randf_range(0, 1.5)),
		"yaw": 0.0, "state": IDLE, "target": Vector3.ZERO, "field": -1, "carried": 0, "timer": 0.0, "wage_timer": WAGE_INTERVAL,
	}
	_cl_spawn.rpc(id, info["worker"], get_parent().display_name_for(employer)[0], info["color"])
	get_parent().send_hired(employer)
	return ""


## Palvelin: irtisano palkkaajan duunari (item) tai kaikki duunarit (item = "").
func fire(employer: int, item := "") -> void:
	for id in _workers.keys():
		if _workers[id]["employer"] == employer and (item == "" or _workers[id]["item"] == item):
			_workers.erase(id)
			_cl_remove.rpc(id)
	get_parent().send_hired(employer)


func hired_by(employer: int) -> Array:
	var items := []
	for w in _workers.values():
		if w["employer"] == employer:
			items.append(w["item"])
	return items


func send_state(peer: int) -> void:
	var main = get_parent()
	for id in _workers:
		var w: Dictionary = _workers[id]
		_cl_spawn.rpc_id(peer, id, w["name"], main.display_name_for(w["employer"])[0], Village.ITEMS[w["item"]]["color"])


func _physics_process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and not _workers.is_empty():
		_simulate(delta)
	# Asiakkailla duunarit liukuvat kohti viimeisintä palvelimen sijaintia.
	for id in _nodes:
		if _goal.has(id):
			var node: Node3D = _nodes[id]
			var goal: Array = _goal[id]
			node.position = node.position.lerp(goal[0], minf(delta * 10.0, 1.0))
			node.rotation.y = lerp_angle(node.rotation.y, goal[1], minf(delta * 10.0, 1.0))
			node.get_node("Kuorma").visible = goal[2]


func _simulate(delta: float) -> void:
	var main = get_parent()
	var neighbours = main.neighbours
	for id in _workers.keys():
		var w: Dictionary = _workers[id]
		w["wage_timer"] -= delta
		if w["wage_timer"] <= 0.0:
			w["wage_timer"] += WAGE_INTERVAL
			var wage: int = Village.ITEMS[w["item"]]["wage"]
			if not main.charge(w["employer"], wage):
				main.announce("%s lähti kotiin, koska %s ei pystynyt maksamaan palkkaa." % [w["name"], main.display_name_for(w["employer"])[0]])
				_workers.erase(id)
				_cl_remove.rpc(id)
				continue
		var speed: float = WALK_SPEED * Village.ITEMS[w["item"]]["speed"]
		match w["state"]:
			IDLE:
				w["timer"] -= delta
				if w["timer"] <= 0.0:
					w["timer"] = 2.0
					_pick_job(w, neighbours)
			WALK_TO_SNOW, WALK_TO_PILE:
				var to: Vector3 = w["target"] - w["pos"]
				to.y = 0.0
				if to.length() < 0.5:
					w["state"] = SCOOP if w["state"] == WALK_TO_SNOW else DUMP
					w["timer"] = SCOOP_TIME if w["state"] == SCOOP else DUMP_TIME
				else:
					w["pos"] += to.normalized() * minf(speed * delta, to.length())
					w["yaw"] = atan2(-to.x, -to.z)
			SCOOP:
				w["timer"] -= delta
				if w["timer"] <= 0.0:
					var field = neighbours.fields[w["field"]]
					var capacity: int = Village.ITEMS[w["item"]]["capacity"]
					var removed: int = field.remove_snow(w["target"], SCOOP_RADIUS, capacity, SCOOP_BITE_CM)
					neighbours.credit(field, w["employer"], removed)
					w["carried"] = removed
					if removed > 0:
						var pile := Village.pile_center(w["field"])
						var offset := Vector2.from_angle(randf() * TAU) * randf_range(0.0, Village.PILE_RADIUS * 0.6)
						w["target"] = pile + Vector3(offset.x, 0, offset.y)
						w["state"] = WALK_TO_PILE
					else:
						w["state"] = IDLE
						w["timer"] = 0.0
			DUMP:
				w["timer"] -= delta
				if w["timer"] <= 0.0:
					neighbours.fields[w["field"]].add_snow(w["target"], 0.6, w["carried"])
					w["carried"] = 0
					w["state"] = IDLE
					w["timer"] = 0.0
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = SYNC_INTERVAL
		var data := PackedFloat32Array()
		for id in _workers:
			var w: Dictionary = _workers[id]
			data.append_array([id, w["pos"].x, w["pos"].z, w["yaw"], 1.0 if w["carried"] > 0 else 0.0])
		_cl_positions.rpc(data)


## Etsi lähin tilattu pihatie ja siltä lähin luminen kohta.
func _pick_job(w: Dictionary, neighbours) -> void:
	var best_dist := INF
	for i in neighbours.fields.size():
		if not neighbours.is_ordered(i):
			continue
		var field = neighbours.fields[i]
		var width := roundi(Village.NEIGHBOURS[i]["w"] / SnowField.CELL_SIZE)
		for z in range(1, field.cells_z, 3):
			for x in range(1, width, 3):
				if field.heights[z * field.cells_x + x] <= Village.CLEARED_CM:
					continue
				var spot: Vector3 = field.cell_center(x, z)
				var d: float = spot.distance_squared_to(w["pos"])
				if d < best_dist:
					best_dist = d
					w["target"] = spot
					w["field"] = i
	if best_dist < INF:
		w["state"] = WALK_TO_SNOW
	elif w["pos"].distance_to(IDLE_SPOT) > 3.0:
		w["target"] = IDLE_SPOT + Vector3(randf_range(-2, 2), 0, randf_range(0, 1.5))
		w["field"] = -1
		w["state"] = WALK_TO_PILE
		w["carried"] = 0


# --- Asiakkaat -------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _cl_spawn(id: int, worker_name: String, employer_name: String, color: Color) -> void:
	if DisplayServer.get_name() == "headless" or _nodes.has(id):
		return
	var node := _make_worker(color)
	var label: Label3D = node.get_node("Nimi")
	label.text = "%s\n(%s palkkalistoilla)" % [worker_name, employer_name]
	get_parent().add_child(node)
	node.position = IDLE_SPOT
	_nodes[id] = node


@rpc("authority", "call_local", "reliable")
func _cl_remove(id: int) -> void:
	_goal.erase(id)
	if _nodes.has(id):
		_nodes[id].queue_free()
		_nodes.erase(id)


@rpc("authority", "call_local", "unreliable_ordered")
func _cl_positions(data: PackedFloat32Array) -> void:
	for i in range(0, data.size(), 5):
		var id := int(data[i])
		_goal[id] = [Vector3(data[i + 1], 0.0, data[i + 2]), data[i + 3], data[i + 4] > 0.5]


## Duunari: haalari, pipo ja lapio.
static func _make_worker(color: Color) -> Node3D:
	var root := Node3D.new()
	var torso := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 1.45
	torso.mesh = capsule
	torso.material_override = _mat(color)
	torso.position.y = 0.75
	root.add_child(torso)
	var face := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	face.mesh = sphere
	face.material_override = _mat(Color(0.93, 0.76, 0.62))
	face.position = Vector3(0, 1.55, -0.04)
	root.add_child(face)
	var hat := MeshInstance3D.new()
	var hat_mesh := SphereMesh.new()
	hat_mesh.radius = 0.16
	hat_mesh.height = 0.2
	hat.mesh = hat_mesh
	hat.material_override = _mat(Color(0.9, 0.2, 0.15))
	hat.position.y = 1.68
	root.add_child(hat)
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	cyl.height = 1.2
	shaft.mesh = cyl
	shaft.material_override = _mat(Color(0.7, 0.55, 0.3))
	shaft.position = Vector3(0.3, 0.7, -0.35)
	shaft.rotation.x = -0.9
	root.add_child(shaft)
	var blade := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.38, 0.03, 0.34)
	blade.mesh = box
	blade.material_override = _mat(Color(0.15, 0.35, 0.8))
	blade.position = Vector3(0.3, 0.25, -0.8)
	root.add_child(blade)
	var load := MeshInstance3D.new()
	load.name = "Kuorma"
	var lump := SphereMesh.new()
	lump.radius = 0.16
	lump.height = 0.18
	load.mesh = lump
	load.material_override = _mat(Color(0.95, 0.97, 1.0))
	load.position = Vector3(0.3, 0.33, -0.8)
	load.visible = false
	root.add_child(load)
	var label := Label3D.new()
	label.name = "Nimi"
	label.position.y = 2.1
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.006
	label.outline_size = 8
	label.modulate = Color(0.75, 0.9, 1.0)
	root.add_child(label)
	return root


static func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	return m
