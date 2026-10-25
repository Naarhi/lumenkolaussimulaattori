extends Node3D
## Pihan lumi korkeusruudukkona (10 cm solut, syvyys senttimetreinä).
## Palvelin päättää lumesta ja lähettää muuttuneet 16 x 16 solun palat pelaajille.
## Ruudukko alkaa solmun sijainnista ja jatkuu +X- ja +Z-suuntiin.

const CELL_SIZE := 0.1
const CHUNK := 16
const MAX_DEPTH_CM := 250
const INITIAL_DEPTH_CM := 30
const SNOWFALL_CM_PER_MINUTE := 0.3
## Hiljainen lumisade ei kasvata lunta tätä syvemmäksi (muuten pitkään pyörivä palvelin hautaa pihan).
const SNOWFALL_MAX_DEPTH_CM := 40
## Lumimyräkkäkään ei nosta tasaista hankea tätä korkeammaksi.
const STORM_MAX_DEPTH_CM := 60
const MAX_MESH_REBUILDS_PER_FRAME := 24
## Suola sulattaa näin monta cm lunta joka SALT_MELT_INTERVAL sekunti ja estää uuden lumen kertymisen.
const SALT_MELT_CM := 1
const SALT_MELT_INTERVAL := 0.4

## Ruudukon koko soluina (16:n monikerta). Aseta ennen kuin solmu lisätään puuhun.
var cells_x := 192
var cells_z := 192
var chunks_x := 12
var chunks_z := 12
var initial_depth := INITIAL_DEPTH_CM
## Sataako tälle kentälle lunta (kotipiha pysyy puhtaana).
var snowfall := true
## Palvelin: sulatettu lumi (liekinheitin ja suola), jotta naapuri tietää, minne lumet menivät.
var melted_total := 0
## Palvelin: suola sulatti pelaajan suolaamista soluista amount cm x solua lunta.
signal salt_melted(peer: int, amount: int)
var heights := PackedByteArray()
var material: StandardMaterial3D

var _is_server := false
var _dirty := {}
var _mesh_queue := {}
var _meshes: Array[MeshInstance3D] = []
var _snowfall_acc := 0.0
# Palvelin: suolatut solut {indeksi: vanhenemishetki} ja oma kello sekunteina.
var _salted := {}
## Palvelin: kuka suolasi solun ({solu: pelaaja}). Sulanut lumi lasketaan suolaajan työksi.
var _salt_owner := {}
var _clock := 0.0
var _melt_acc := 0.0
var _render := true


## Pihan koko metreinä (pyöristetään palan monikertaan).
@warning_ignore("integer_division")
func setup(width: float, depth: float, start_depth := INITIAL_DEPTH_CM) -> void:
	cells_x = maxi(1, roundi(width / CELL_SIZE / CHUNK)) * CHUNK
	cells_z = maxi(1, roundi(depth / CELL_SIZE / CHUNK)) * CHUNK
	chunks_x = cells_x / CHUNK
	chunks_z = cells_z / CHUNK
	initial_depth = start_depth
	# Kohtaukseen valmiiksi lisätty kenttä rakennetaan uudelleen uuteen kokoon.
	if is_node_ready():
		for mi in _meshes:
			mi.queue_free()
		_meshes.clear()
		_ready()


func _ready() -> void:
	heights.resize(cells_x * cells_z)
	heights.fill(0)
	_render = DisplayServer.get_name() != "headless"
	if not _render:
		return
	if material == null:
		material = make_snow_material()
	for i in chunks_x * chunks_z:
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
	heights.fill(initial_depth)
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
		if snowfall:
			add_snow_everywhere(whole, SNOWFALL_MAX_DEPTH_CM)
	melt_salted(delta)
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


## Suolaa ympyrän alueen duration sekunniksi. peer on suolaaja, jolle sulanut lumi kirjataan.
func salt_area(world_pos: Vector3, radius: float, duration: float, peer := 0) -> int:
	var count := 0
	for cell in _cells_in_radius(world_pos, radius):
		var index := cell.y * cells_x + cell.x
		_salted[index] = _clock + duration
		_salt_owner[index] = peer
		count += 1
	return count


func is_salted(x: int, z: int) -> bool:
	return _salted.get(z * cells_x + x, -1.0) > _clock


## Palvelin: suola sulattaa lunta. Kutsutaan joka fysiikkaruudulla.
func melt_salted(delta: float) -> void:
	_clock += delta
	_melt_acc += delta
	if _melt_acc < SALT_MELT_INTERVAL:
		return
	_melt_acc = 0.0
	var by_peer := {}
	for index in _salted.keys():
		if _salted[index] <= _clock:
			_salted.erase(index)
			_salt_owner.erase(index)
			continue
		var x: int = index % cells_x
		@warning_ignore("integer_division")
		var z: int = index / cells_x
		if heights[index] > 0:
			var melted := -_change(x, z, -SALT_MELT_CM)
			melted_total += melted
			var peer: int = _salt_owner.get(index, 0)
			by_peer[peer] = by_peer.get(peer, 0) + melted
	for peer in by_peer:
		if peer != 0:
			salt_melted.emit(peer, by_peer[peer])


## Sataa lunta koko pihalle, mutta vain soluihin, joissa lunta on alle max_depth_cm.
func add_snow_everywhere(depth_cm: int, max_depth_cm: int) -> void:
	for z in cells_z:
		for x in cells_x:
			var room := max_depth_cm - _cell(x, z)
			if room > 0 and not is_salted(x, z):
				_change(x, z, mini(depth_cm, room))


## Lunta janan suuntaiselle kaistalle (esim. aura-auton penkka).
## Lisää lunta janalle. max_cm rajaa, kuinka korkeaksi kasa saa kasvaa (toistuvat aurauskerrat).
func add_snow_line(start: Vector3, end: Vector3, width: float, depth_cm: int, max_cm := MAX_DEPTH_CM) -> void:
	var a := Vector2(to_local(start).x, to_local(start).z)
	var b := Vector2(to_local(end).x, to_local(end).z)
	for z in cells_z:
		for x in cells_x:
			var p := Vector2((x + 0.5) * CELL_SIZE, (z + 0.5) * CELL_SIZE)
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) <= width * 0.5:
				_change(x, z, clampi(max_cm - heights[z * cells_x + x], 0, depth_cm))


# --- Kyselyt -----------------------------------------------------------------

func depth_at(world_pos: Vector3) -> float:
	var local := to_local(world_pos)
	return _cell(floori(local.x / CELL_SIZE), floori(local.z / CELL_SIZE))


func cell_center(x: int, z: int) -> Vector3:
	return to_global(Vector3((x + 0.5) * CELL_SIZE, 0.0, (z + 0.5) * CELL_SIZE))


func random_point() -> Vector3:
	return to_global(Vector3(randf() * cells_x * CELL_SIZE, 0.0, randf() * cells_z * CELL_SIZE))


## Onko piste tämän pihan alueella (vaakatasossa).
func contains(world_pos: Vector3) -> bool:
	var local := to_local(world_pos)
	return local.x >= 0.0 and local.z >= 0.0 and local.x < cells_x * CELL_SIZE and local.z < cells_z * CELL_SIZE


## Kuinka suuri osa soluista on enintään max_cm syvyisiä (0..1).
func fraction_cleared(max_cm: int) -> float:
	var clear := 0
	for h in heights:
		if h <= max_cm:
			clear += 1
	return float(clear) / maxf(heights.size(), 1)


## Lunta solujen x0..x1, z0..z1 (mukaan lukien) alueella.
func sum_rect(x0: int, x1: int, z0: int, z1: int) -> int:
	var total := 0
	for z in range(maxi(z0, 0), mini(z1, cells_z - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, cells_x - 1) + 1):
			total += heights[z * cells_x + x]
	return total


## Kuinka suuri osa alueen soluista on enintään max_cm syvyisiä.
func fraction_cleared_rect(x0: int, x1: int, z0: int, z1: int, max_cm: int) -> float:
	var clear := 0
	var count := 0
	for z in range(maxi(z0, 0), mini(z1, cells_z - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, cells_x - 1) + 1):
			count += 1
			if heights[z * cells_x + x] <= max_cm:
				clear += 1
	return float(clear) / maxf(count, 1)


## Lunta ympyrän alueella (lumikasa).
func sum_circle(world_pos: Vector3, radius: float) -> int:
	var total := 0
	for cell in _cells_in_radius(world_pos, radius):
		total += heights[cell.y * cells_x + cell.x]
	return total


## Tasoittaa ympyrän alueen annettuun syvyyteen (kasa ajettu pois).
func flatten_circle(world_pos: Vector3, radius: float, depth_cm: int) -> void:
	for cell in _cells_in_radius(world_pos, radius):
		_change(cell.x, cell.y, depth_cm - heights[cell.y * cells_x + cell.x])


## Täyttää koko pihan vähintään depth_cm syvyiseksi (uusi tilaus naapurilta).
func refill(depth_cm: int) -> void:
	add_snow_everywhere(depth_cm, depth_cm)


func size() -> Vector2:
	return Vector2(cells_x * CELL_SIZE, cells_z * CELL_SIZE)


func total_snow() -> int:
	var sum := 0
	for h in heights:
		sum += h
	return sum


# --- Sisäiset --------------------------------------------------------------

func _cell(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= cells_x or z >= cells_z:
		return 0
	return heights[z * cells_x + x]


@warning_ignore("integer_division")
func _change(x: int, z: int, delta: int) -> int:
	if x < 0 or z < 0 or x >= cells_x or z >= cells_z or delta == 0:
		return 0
	var i := z * cells_x + x
	var old := heights[i]
	var value := clampi(old + delta, 0, MAX_DEPTH_CM)
	if value != old:
		heights[i] = value
		_dirty[(z / CHUNK) * chunks_x + x / CHUNK] = true
	return value - old


func _cells_in_radius(world_pos: Vector3, radius: float) -> Array[Vector2i]:
	var local := to_local(world_pos)
	var result: Array[Vector2i] = []
	var min_x := maxi(0, floori((local.x - radius) / CELL_SIZE))
	var max_x := mini(cells_x - 1, floori((local.x + radius) / CELL_SIZE))
	var min_z := maxi(0, floori((local.z - radius) / CELL_SIZE))
	var max_z := mini(cells_z - 1, floori((local.z + radius) / CELL_SIZE))
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
	var cx := index % chunks_x
	var cz := index / chunks_x
	var data := PackedByteArray()
	for row in CHUNK:
		var start := (cz * CHUNK + row) * cells_x + cx * CHUNK
		data.append_array(heights.slice(start, start + CHUNK))
	return data


@warning_ignore("integer_division")
func _write_chunk(index: int, data: PackedByteArray) -> void:
	if data.size() != CHUNK * CHUNK:
		return
	var cx := index % chunks_x
	var cz := index / chunks_x
	for row in CHUNK:
		var start := (cz * CHUNK + row) * cells_x + cx * CHUNK
		for col in CHUNK:
			heights[start + col] = data[row * CHUNK + col]


## Palojen reunaverteksit lukevat naapurisoluja, joten päivitetään myös naapurit.
@warning_ignore("integer_division")
func _queue_mesh(index: int) -> void:
	if not _render:
		return
	var cx := index % chunks_x
	var cz := index / chunks_x
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nx := cx + dx
			var nz := cz + dz
			if nx >= 0 and nz >= 0 and nx < chunks_x and nz < chunks_z:
				_mesh_queue[nz * chunks_x + nx] = true


func _queue_all_meshes() -> void:
	if not _render:
		return
	for i in chunks_x * chunks_z:
		_mesh_queue[i] = true


@warning_ignore("integer_division")
func _build_mesh(index: int) -> void:
	var cx := index % chunks_x
	var cz := index / chunks_x
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
