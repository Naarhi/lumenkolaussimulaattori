extends Node3D
## Pihan lumi korkeusruudukkona (10 cm solut, syvyys senttimetreinä).
## Palvelin päättää lumesta ja lähettää muuttuneet 16 x 16 solun palat pelaajille.
## Ruudukko alkaa solmun sijainnista ja jatkuu +X- ja +Z-suuntiin.

const CELLS_X := 192
const CELLS_Z := 192
const CELL_SIZE := 0.1
const CHUNK := 16
const CHUNKS_X := CELLS_X / CHUNK
const CHUNKS_Z := CELLS_Z / CHUNK
const MAX_DEPTH_CM := 250
const INITIAL_DEPTH_CM := 30
const SNOWFALL_CM_PER_MINUTE := 0.3
## Hiljainen lumisade ei kasvata lunta tätä syvemmäksi (muuten pitkään pyörivä palvelin hautaa pihan).
const SNOWFALL_MAX_DEPTH_CM := 40
## Lumimyräkkäkään ei nosta tasaista hankea tätä korkeammaksi.
const STORM_MAX_DEPTH_CM := 60
const MAX_MESH_REBUILDS_PER_FRAME := 24

var heights := PackedByteArray()
var material: StandardMaterial3D

var _is_server := false
var _dirty := {}
var _mesh_queue := {}
var _meshes: Array[MeshInstance3D] = []
var _snowfall_acc := 0.0
var _render := true


func _ready() -> void:
	heights.resize(CELLS_X * CELLS_Z)
	heights.fill(0)
	_render = DisplayServer.get_name() != "headless"
	if not _render:
		return
	material = make_snow_material()
	for i in CHUNKS_X * CHUNKS_Z:
		var mi := MeshInstance3D.new()
		mi.material_override = material
		add_child(mi)
		_meshes.append(mi)


static func make_snow_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	var bumps := NoiseTexture2D.new()
	bumps.noise = noise
	bumps.seamless = true
	bumps.as_normal_map = true
	bumps.bump_strength = 6.0
	bumps.width = 256
	bumps.height = 256

	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.95, 1.0)
	m.roughness = 0.75
	m.metallic_specular = 0.4
	m.normal_enabled = true
	m.normal_texture = bumps
	m.normal_scale = 0.35
	m.uv1_scale = Vector3(1.5, 1.5, 1.5)
	m.subsurf_scatter_enabled = true
	m.subsurf_scatter_strength = 0.15
	return m


## Palvelin: täytä piha lähtölumella.
func start_server() -> void:
	_is_server = true
	heights.fill(INITIAL_DEPTH_CM)
	_queue_all_meshes()


## Palvelin: lähetä koko lumitilanne juuri liittyneelle pelaajalle.
func send_full_state(peer_id: int) -> void:
	_rx_full.rpc_id(peer_id, heights)


@rpc("authority", "call_remote", "reliable")
func _rx_full(data: PackedByteArray) -> void:
	if data.size() == heights.size():
		heights = data
		_queue_all_meshes()


@rpc("authority", "call_remote", "reliable")
func _rx_chunk(index: int, data: PackedByteArray) -> void:
	_write_chunk(index, data)
	_queue_mesh(index)


func _physics_process(delta: float) -> void:
	if not _is_server:
		return
	_snowfall_acc += SNOWFALL_CM_PER_MINUTE * delta / 60.0
	if _snowfall_acc >= 1.0:
		var whole := int(_snowfall_acc)
		_snowfall_acc -= whole
		add_snow_everywhere(whole, SNOWFALL_MAX_DEPTH_CM)
	_flush_dirty()


func _process(_delta: float) -> void:
	var budget := MAX_MESH_REBUILDS_PER_FRAME
	for index in _mesh_queue.keys():
		if budget <= 0:
			break
		_mesh_queue.erase(index)
		_build_mesh(index)
		budget -= 1


# --- Lumen muokkaus (vain palvelimella) ------------------------------------

## Poistaa lunta ympyrän alueelta, enintään max_per_cell cm solusta. Palauttaa poistetun määrän (cm x solu).
func remove_snow(world_pos: Vector3, radius: float, max_amount: int, max_per_cell: int) -> int:
	var removed := 0
	for cell in _cells_in_radius(world_pos, radius):
		var want := mini(max_per_cell, max_amount - removed)
		if want <= 0:
			break
		removed -= _change(cell.x, cell.y, -want)
	return removed


## Kasaa lunta ympyrän alueelle, eniten keskelle. Ruudukon ulkopuolelle heitetty lumi katoaa.
func add_snow(world_pos: Vector3, radius: float, amount: int) -> void:
	var local := to_local(world_pos)
	var cells := _cells_in_radius(world_pos, radius)
	var weights := PackedFloat32Array()
	var total := 0.0
	for cell in cells:
		var center := Vector2((cell.x + 0.5) * CELL_SIZE, (cell.y + 0.5) * CELL_SIZE)
		var w := 1.1 - center.distance_to(Vector2(local.x, local.z)) / radius
		weights.append(w)
		total += w
	for i in cells.size():
		_change(cells[i].x, cells[i].y, roundi(amount * weights[i] / total))


## Sataa lunta koko pihalle, mutta vain soluihin, joissa lunta on alle max_depth_cm.
func add_snow_everywhere(depth_cm: int, max_depth_cm: int) -> void:
	for z in CELLS_Z:
		for x in CELLS_X:
			var room := max_depth_cm - _cell(x, z)
			if room > 0:
				_change(x, z, mini(depth_cm, room))


## Lunta janan suuntaiselle kaistalle (esim. aura-auton penkka).
func add_snow_line(start: Vector3, end: Vector3, width: float, depth_cm: int) -> void:
	var a := Vector2(to_local(start).x, to_local(start).z)
	var b := Vector2(to_local(end).x, to_local(end).z)
	for z in CELLS_Z:
		for x in CELLS_X:
			var p := Vector2((x + 0.5) * CELL_SIZE, (z + 0.5) * CELL_SIZE)
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) <= width * 0.5:
				_change(x, z, depth_cm)


# --- Kyselyt -----------------------------------------------------------------

func depth_at(world_pos: Vector3) -> float:
	var local := to_local(world_pos)
	return _cell(floori(local.x / CELL_SIZE), floori(local.z / CELL_SIZE))


func cell_center(x: int, z: int) -> Vector3:
	return to_global(Vector3((x + 0.5) * CELL_SIZE, 0.0, (z + 0.5) * CELL_SIZE))


func random_point() -> Vector3:
	return to_global(Vector3(randf() * CELLS_X * CELL_SIZE, 0.0, randf() * CELLS_Z * CELL_SIZE))


func size() -> Vector2:
	return Vector2(CELLS_X * CELL_SIZE, CELLS_Z * CELL_SIZE)


func total_snow() -> int:
	var sum := 0
	for h in heights:
		sum += h
	return sum


# --- Sisäiset --------------------------------------------------------------

func _cell(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= CELLS_X or z >= CELLS_Z:
		return 0
	return heights[z * CELLS_X + x]


@warning_ignore("integer_division")
func _change(x: int, z: int, delta: int) -> int:
	if x < 0 or z < 0 or x >= CELLS_X or z >= CELLS_Z or delta == 0:
		return 0
	var i := z * CELLS_X + x
	var old := heights[i]
	var value := clampi(old + delta, 0, MAX_DEPTH_CM)
	if value != old:
		heights[i] = value
		_dirty[(z / CHUNK) * CHUNKS_X + x / CHUNK] = true
	return value - old


func _cells_in_radius(world_pos: Vector3, radius: float) -> Array[Vector2i]:
	var local := to_local(world_pos)
	var result: Array[Vector2i] = []
	var min_x := maxi(0, floori((local.x - radius) / CELL_SIZE))
	var max_x := mini(CELLS_X - 1, floori((local.x + radius) / CELL_SIZE))
	var min_z := maxi(0, floori((local.z - radius) / CELL_SIZE))
	var max_z := mini(CELLS_Z - 1, floori((local.z + radius) / CELL_SIZE))
	for z in range(min_z, max_z + 1):
		for x in range(min_x, max_x + 1):
			var center := Vector2((x + 0.5) * CELL_SIZE, (z + 0.5) * CELL_SIZE)
			if center.distance_to(Vector2(local.x, local.z)) <= radius:
				result.append(Vector2i(x, z))
	return result


func _flush_dirty() -> void:
	if _dirty.is_empty():
		return
	var online := multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0
	for index in _dirty.keys():
		if online:
			_rx_chunk.rpc(index, _read_chunk(index))
		_queue_mesh(index)
	_dirty.clear()


@warning_ignore("integer_division")
func _read_chunk(index: int) -> PackedByteArray:
	var cx := index % CHUNKS_X
	var cz := index / CHUNKS_X
	var data := PackedByteArray()
	for row in CHUNK:
		var start := (cz * CHUNK + row) * CELLS_X + cx * CHUNK
		data.append_array(heights.slice(start, start + CHUNK))
	return data


@warning_ignore("integer_division")
func _write_chunk(index: int, data: PackedByteArray) -> void:
	if data.size() != CHUNK * CHUNK:
		return
	var cx := index % CHUNKS_X
	var cz := index / CHUNKS_X
	for row in CHUNK:
		var start := (cz * CHUNK + row) * CELLS_X + cx * CHUNK
		for col in CHUNK:
			heights[start + col] = data[row * CHUNK + col]


## Palojen reunaverteksit lukevat naapurisoluja, joten päivitetään myös naapurit.
@warning_ignore("integer_division")
func _queue_mesh(index: int) -> void:
	if not _render:
		return
	var cx := index % CHUNKS_X
	var cz := index / CHUNKS_X
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nx := cx + dx
			var nz := cz + dz
			if nx >= 0 and nz >= 0 and nx < CHUNKS_X and nz < CHUNKS_Z:
				_mesh_queue[nz * CHUNKS_X + nx] = true


func _queue_all_meshes() -> void:
	if not _render:
		return
	for i in CHUNKS_X * CHUNKS_Z:
		_mesh_queue[i] = true


@warning_ignore("integer_division")
func _build_mesh(index: int) -> void:
	var cx := index % CHUNKS_X
	var cz := index / CHUNKS_X
	var n := CHUNK + 1

	# Verteksien korkeudet yhden ylimääräisen reunan kanssa normaaleja varten.
	var side := n + 2
	var hv := PackedFloat32Array()
	hv.resize(side * side)
	for j in side:
		for i in side:
			var vx := cx * CHUNK + i - 1
			var vz := cz * CHUNK + j - 1
			var avg := (_cell(vx - 1, vz - 1) + _cell(vx, vz - 1) + _cell(vx - 1, vz) + _cell(vx, vz)) * 0.25
			# Paljas maa painetaan hieman maan alle, ettei lumi välky maan kanssa.
			hv[j * side + i] = avg / 100.0 if avg > 0.5 else -0.02

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	for j in n:
		for i in n:
			var vx := cx * CHUNK + i
			var vz := cz * CHUNK + j
			var h := hv[(j + 1) * side + i + 1]
			verts.append(Vector3(vx * CELL_SIZE, h, vz * CELL_SIZE))
			var dx := hv[(j + 1) * side + i + 2] - hv[(j + 1) * side + i]
			var dz := hv[(j + 2) * side + i + 1] - hv[j * side + i + 1]
			normals.append(Vector3(-dx, 2.0 * CELL_SIZE, -dz).normalized())
			tangents.append_array([1.0, 0.0, 0.0, 1.0])
			uvs.append(Vector2(vx * CELL_SIZE, vz * CELL_SIZE))

	# Godot piirtää myötäpäivään kiertävät kolmiot etupuolina.
	var indices := PackedInt32Array()
	for j in CHUNK:
		for i in CHUNK:
			var a := j * n + i
			indices.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[index].mesh = mesh
