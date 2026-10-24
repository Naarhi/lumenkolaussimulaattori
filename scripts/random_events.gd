extends Node
## OSRS:n "random eventien" tapaiset hullut sattumukset. Palvelin arpoo, kaikki näkevät saman.

enum { AURA_AUTO, LUMIMYRSKY, HIRVI, PERTTI, KATTOLUMI }

const Pihapiiri := preload("res://scripts/pihapiiri.gd")

const EVENTS := [
	{"type": AURA_AUTO, "weight": 3.0, "text": "Kunnan aura-auto jyrisi ohi ja puski penkan pihatielle!"},
	{"type": LUMIMYRSKY, "weight": 2.0, "text": "Lumimyräkkä yllätti! Pihalle sataa lunta silmissä."},
	{"type": HIRVI, "weight": 1.0, "text": "Hirvi käveli pihalle eikä aio lähteä mihinkään."},
	{"type": PERTTI, "weight": 2.0, "text": "Naapurin Pertti tuli moottorikelkalla \"auttamaan\". Pihalla on nyt lumikasoja."},
	{"type": KATTOLUMI, "weight": 2.0, "text": "Katolta romahti lumikuorma kolaajan niskaan!"},
]
const MIN_INTERVAL := 90.0
const MAX_INTERVAL := 240.0

var _timer: Timer


func start_server() -> void:
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
			var row: int = snow.CELLS_Z - 4
			snow.add_snow_line(snow.cell_center(0, row), snow.cell_center(snow.CELLS_X - 1, row), 0.9, 45)
		LUMIMYRSKY:
			snow.add_snow_everywhere(8)
		HIRVI:
			point = snow.random_point()
		PERTTI:
			for i in 4:
				snow.add_snow(snow.random_point(), 0.8, 2500)
		KATTOLUMI:
			var victims: Array = main.players.get_children()
			if victims.is_empty():
				return
			point = victims[randi() % victims.size()].global_position
			snow.add_snow(point, 0.7, 3000)
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
			var road_z := field_depth * 0.5 + 3.2
			truck.position = Vector3(-45, 0, road_z)
			var tween := create_tween()
			tween.tween_property(truck, "position:x", 45.0, 7.0)
			tween.tween_callback(truck.queue_free)
		HIRVI:
			var moose := Pihapiiri.make_moose()
			world.add_child(moose)
			moose.position = point
			moose.rotation.y = randf() * TAU
			get_tree().create_timer(60.0).timeout.connect(moose.queue_free)
		PERTTI:
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
