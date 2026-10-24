extends Node3D
## Kyläläiset: koiranulkoiluttaja, potkukelkkailija ja hiihtäjä kulkevat omia reittejään.
## Pelkkää maisemaa: jokainen kone liikuttaa niitä itse kellon mukaan, verkossa ei lähetetä mitään.

const Village := preload("res://scripts/village.gd")
const Kelkkapuisto := preload("res://scripts/kelkkapuisto.gd")

## [nimi, nopeus m/s, reitti (x, z) -pisteinä, takki, lisävaruste]
var _walkers := []


func _ready() -> void:
	var road_n := Village.ROAD_Z - 0.9
	var road_s := Village.ROAD_Z + 0.9
	var park := Kelkkapuisto.AREA.grow(-4.0)
	_add("Seppo ja Musti", 1.3, [Vector2(-50, road_n), Vector2(50, road_n), Vector2(50, road_n - 0.3), Vector2(-50, road_n - 0.3)], Color(0.2, 0.45, 0.25), "koira")
	_add("Aino", 2.6, [Vector2(52, road_s), Vector2(-52, road_s), Vector2(-52, road_s + 0.3), Vector2(52, road_s + 0.3)], Color(0.75, 0.15, 0.3), "potkukelkka")
	_add("Hiihtäjä-Heikki", 3.4, [
		Vector2(park.position.x, park.end.y), Vector2(park.position.x, park.position.y),
		Vector2(park.end.x, park.position.y), Vector2(park.end.x, park.end.y),
	], Color(0.95, 0.75, 0.1), "sukset")


func _add(npc_name: String, speed: float, points: Array, jacket: Color, extra: String) -> void:
	var node := _make_person(npc_name, jacket, extra)
	add_child(node)
	var length := 0.0
	for i in points.size():
		length += points[i].distance_to(points[(i + 1) % points.size()])
	# Jokainen aloittaa eri kohdasta, jotta kaikki eivät ole samassa paikassa.
	_walkers.append({"node": node, "speed": speed, "points": points, "length": length, "offset": randf() * length})


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for w in _walkers:
		var d: float = fmod(w["offset"] + t * w["speed"], w["length"])
		var points: Array = w["points"]
		for i in points.size():
			var a: Vector2 = points[i]
			var b: Vector2 = points[(i + 1) % points.size()]
			var seg := a.distance_to(b)
			if d <= seg:
				var p := a.lerp(b, d / seg)
				var node: Node3D = w["node"]
				node.position = Vector3(p.x, Kelkkapuisto.height(p.x, p.y) + absf(sin(t * w["speed"] * 4.0)) * 0.05, p.y)
				node.rotation.y = atan2(-(b.x - a.x), -(b.y - a.y))
				break
			d -= seg


static func _make_person(npc_name: String, jacket: Color, extra: String) -> Node3D:
	var root := Node3D.new()
	root.name = npc_name
	_part(root, _capsule(0.26, 1.4), Vector3(0, 0.75, 0), jacket)
	_part(root, _sphere(0.15), Vector3(0, 1.55, -0.03), Color(0.93, 0.76, 0.62))
	_part(root, _sphere(0.16, 0.22), Vector3(0, 1.68, 0), Color(0.95, 0.95, 0.95) if extra == "sukset" else Color(0.15, 0.2, 0.5))
	match extra:
		"koira":
			# Musti kulkee hihnassa vähän edellä.
			_part(root, _box(Vector3(0.22, 0.25, 0.6)), Vector3(0.6, 0.35, -0.7), Color(0.12, 0.1, 0.08))
			_part(root, _box(Vector3(0.18, 0.18, 0.22)), Vector3(0.6, 0.52, -1.05), Color(0.12, 0.1, 0.08))
			for lx in [0.52, 0.68]:
				for lz in [-0.5, -0.9]:
					_part(root, _box(Vector3(0.06, 0.25, 0.06)), Vector3(lx, 0.12, lz), Color(0.12, 0.1, 0.08))
			var leash := _part(root, _box(Vector3(0.015, 0.015, 0.75)), Vector3(0.45, 0.8, -0.45), Color(0.8, 0.1, 0.1))
			leash.rotation = Vector3(0.6, -0.5, 0)
		"potkukelkka":
			_part(root, _box(Vector3(0.45, 0.06, 0.5)), Vector3(0, 0.5, -0.65), Color(0.6, 0.35, 0.15))
			for sx in [-0.22, 0.22]:
				_part(root, _box(Vector3(0.03, 0.03, 1.6)), Vector3(sx, 0.03, -0.3), Color(0.3, 0.3, 0.32))
				_part(root, _box(Vector3(0.03, 1.0, 0.03)), Vector3(sx, 0.55, 0.0), Color(0.3, 0.3, 0.32))
		"sukset":
			for sx in [-0.12, 0.12]:
				_part(root, _box(Vector3(0.08, 0.03, 1.8)), Vector3(sx, 0.02, -0.2), Color(0.85, 0.1, 0.1))
				var pole := _part(root, _box(Vector3(0.025, 1.2, 0.025)), Vector3(sx * 3.0, 0.6, 0.2), Color(0.2, 0.2, 0.2))
				pole.rotation.x = 0.35
	var label := Label3D.new()
	label.text = npc_name
	label.position.y = 2.05
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.pixel_size = 0.005
	label.outline_size = 8
	label.modulate = Color(0.85, 0.95, 0.85)
	root.add_child(label)
	return root


static func _part(root: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	mi.material_override = m
	mi.position = at
	root.add_child(mi)
	return mi


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	return c


static func _sphere(radius: float, height := -1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0 if height < 0.0 else height
	return s


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
