extends RefCounted
## Suomalainen pihapiiri koodilla rakennettuna: hämärä talvitaivas, punainen talo, sauna,
## aita, postilaatikko, katulamppu, kuuset ja tie. Lisäksi satunnaistapahtumien ajoneuvot ja hirvi.

const SnowField := preload("res://scripts/snow_field.gd")

const SNOW_LEVEL := 0.30
const FALU_RED := Color(0.52, 0.11, 0.07)
const WHITE_TRIM := Color(0.92, 0.92, 0.88)
const ROAD_HALF_WIDTH := 1.6
const ROAD_OFFSET := 3.2

static var _materials := {}
static var _snow_material: StandardMaterial3D


## Rakentaa maiseman root-solmun alle. Palauttaa viittaukset (lumisade) pelilogiikalle.
static func build(root: Node3D, snow: Node3D) -> Dictionary:
	var field: Vector2 = snow.size()
	var hx := field.x * 0.5
	var hz := field.y * 0.5
	var road_z := hz + ROAD_OFFSET
	var world := Node3D.new()
	world.name = "Pihapiiri"
	root.add_child(world)

	_environment(world)
	_ground(world, hx, hz, road_z)
	_house(world, Vector3(0, 0, -hz - 5.5))
	_sauna(world, Vector3(-hx - 5.0, 0, -3.0))
	_fence(world, hx + 1.2, -hz, hz)
	_mailbox(world, Vector3(4.5, 0, road_z - ROAD_HALF_WIDTH - 0.5))
	_street_lamp(world, Vector3(-6.0, 0, road_z - ROAD_HALF_WIDTH - 0.6))
	_forest(world, hx, hz, road_z)
	var snowfall := _snowfall(world)
	return {"snowfall": snowfall, "world": world}


# --- Valaistus ja ympäristö ------------------------------------------------------

static func _environment(world: Node3D) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.1, 0.16, 0.34)
	sky_mat.sky_horizon_color = Color(0.86, 0.56, 0.42)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.2, 0.22, 0.28)
	sky_mat.ground_horizon_color = Color(0.7, 0.55, 0.5)
	sky_mat.sun_angle_max = 12.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.62, 0.66, 0.78)
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.6, 0.7)
	env.fog_density = 0.012
	env.fog_aerial_perspective = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.95

	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	# Matala iltapäivän aurinko lounaasta.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.78, 0.58)
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-14, -140, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_blur = 1.5
	world.add_child(sun)


static func _ground(world: Node3D, hx: float, hz: float, road_z: float) -> void:
	# Fyysinen maa y = 0. Lumi on vain kuvaa, pelaaja uppoaa siihen.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 1, 300)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	world.add_child(body)

	# Pihan sorapinta, joka paljastuu kun lumi kolataan pois.
	var gravel := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(hx * 2.0, hz * 2.0)
	gravel.mesh = plane
	var noise := FastNoiseLite.new()
	noise.frequency = 0.4
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.22, 0.2, 0.18))
	ramp.set_color(1, Color(0.5, 0.46, 0.42))
	tex.color_ramp = ramp
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = tex
	gm.roughness = 0.95
	gm.uv1_scale = Vector3(6, 6, 6)
	gravel.material_override = gm
	world.add_child(gravel)

	# Ympäröivä koskematon lumi samalla tasolla kuin pihan lähtölumi.
	var far := 120.0
	var road_near := road_z - ROAD_HALF_WIDTH
	var road_far := road_z + ROAD_HALF_WIDTH
	_snow_slab(world, Rect2(-far, -far, 2 * far, far - hz))                     # pohjoinen
	_snow_slab(world, Rect2(-far, -hz, far - hx, road_near + hz))               # länsi
	_snow_slab(world, Rect2(hx, -hz, far - hx, road_near + hz))                 # itä
	_snow_slab(world, Rect2(-hx, hz, 2 * hx, road_near - hz))                   # pihan ja tien väli
	_snow_slab(world, Rect2(-far, road_far, 2 * far, far - road_far))           # tien takana

	# Aurattu tie: tiivistynyt harmaa lumi ja aurausvallit.
	var road := _box(world, Vector3(2 * far, 0.06, 2 * ROAD_HALF_WIDTH), Vector3(0, 0.03, road_z), Color(0.55, 0.56, 0.6), 0.6)
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1.0, 1.0]:
		var bank := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.45
		capsule.height = 2 * far
		bank.mesh = capsule
		bank.material_override = snow_material()
		bank.rotation_degrees.z = 90
		bank.scale = Vector3(1, 1, 0.8)
		bank.position = Vector3(0, SNOW_LEVEL, road_z + side * (ROAD_HALF_WIDTH + 0.25))
		world.add_child(bank)
	# Pihatien liittymä tiehen (aurattu kaista ei ole, aura-auto tukkii sen).


static func _snow_slab(world: Node3D, rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(rect.size.x, SNOW_LEVEL, rect.size.y)
	mi.mesh = box
	var mat := snow_material()
	mi.material_override = mat
	mi.position = Vector3(rect.position.x + rect.size.x * 0.5, SNOW_LEVEL * 0.5, rect.position.y + rect.size.y * 0.5)
	world.add_child(mi)


static func snow_material() -> StandardMaterial3D:
	if _snow_material == null:
		_snow_material = SnowField.make_snow_material()
		_snow_material.uv1_triplanar = true
		_snow_material.uv1_scale = Vector3(0.6, 0.6, 0.6)
	return _snow_material


static func _snowfall(world: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 6000
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-25, -12, -25), Vector3(50, 14, 50))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(22, 0.5, 22)
	process.direction = Vector3(0.15, -1, 0.05)
	process.spread = 12.0
	process.gravity = Vector3(0, -0.4, 0)
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 1.4
	process.scale_min = 0.6
	process.scale_max = 1.4
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	p.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(1, 1, 1, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount_ratio = 0.35
	p.position = Vector3(0, 9, 0)
	world.add_child(p)
	return p


# --- Rakennukset ------------------------------------------------------------

static func _house(world: Node3D, at: Vector3) -> void:
	var house := Node3D.new()
	house.name = "Talo"
	house.position = at
	world.add_child(house)
	var w := 10.0
	var d := 7.0
	var h := 3.6
	_box(house, Vector3(w, h, d), Vector3(0, h * 0.5, 0), FALU_RED, 0.9, true)
	# Sokkeli
	_box(house, Vector3(w + 0.1, 0.5, d + 0.1), Vector3(0, 0.25, 0), Color(0.35, 0.35, 0.36), 0.95)
	# Valkoiset nurkkalaudat ja räystäslauta
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(house, Vector3(0.18, h, 0.18), Vector3(sx * w * 0.5, h * 0.5, sz * d * 0.5), WHITE_TRIM, 0.7)
	_box(house, Vector3(w + 0.2, 0.18, d + 0.2), Vector3(0, h - 0.05, 0), WHITE_TRIM, 0.7)
	# Harjakatto ja sen päällä paksu lumikerros
	_roof(house, Vector3(w + 1.0, 2.2, d + 1.4), Vector3(0, h + 1.1, 0), Color(0.18, 0.18, 0.2))
	var roof_snow := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(d + 1.6, 2.45, w + 1.1)
	roof_snow.mesh = prism
	roof_snow.material_override = snow_material()
	roof_snow.rotation_degrees.y = 90
	roof_snow.position = Vector3(0, h + 1.32, 0)
	house.add_child(roof_snow)
	# Ikkunat pihan puolella, lämmin valo sisältä
	for x in [-3.2, -1.0, 2.6]:
		_window(house, Vector3(x, 1.9, d * 0.5 + 0.03))
	# Ovi ja kuisti
	_box(house, Vector3(1.0, 2.1, 0.08), Vector3(1.0 - 0.1 + 0.0, 1.05 + 0.25, d * 0.5 + 0.04), Color(0.25, 0.32, 0.22), 0.6)
	_box(house, Vector3(2.4, 0.3, 1.4), Vector3(0.9, 0.15, d * 0.5 + 0.7), Color(0.45, 0.33, 0.22), 0.9)
	# Savupiippu
	_box(house, Vector3(0.6, 1.6, 0.6), Vector3(-2.5, h + 2.0, -0.8), Color(0.45, 0.2, 0.15), 0.95)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.72, 0.4)
	lamp.light_energy = 1.4
	lamp.omni_range = 6.0
	lamp.position = Vector3(0.9, 2.6, d * 0.5 + 0.6)
	house.add_child(lamp)


static func _window(parent: Node3D, at: Vector3) -> void:
	_box(parent, Vector3(1.2, 1.4, 0.06), at, WHITE_TRIM, 0.7)
	var glass := _box(parent, Vector3(1.0, 1.2, 0.08), at + Vector3(0, 0, 0.01), Color(1.0, 0.8, 0.45), 0.2)
	var mat: StandardMaterial3D = glass.material_override.duplicate()
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.35)
	mat.emission_energy_multiplier = 1.6
	glass.material_override = mat
	_box(parent, Vector3(0.06, 1.2, 0.1), at + Vector3(0, 0, 0.02), WHITE_TRIM, 0.7)
	_box(parent, Vector3(1.0, 0.06, 0.1), at + Vector3(0, 0, 0.02), WHITE_TRIM, 0.7)


static func _roof(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(size.z, size.y, size.x)
	mi.mesh = prism
	mi.material_override = _mat(color, 0.8)
	mi.rotation_degrees.y = 90
	mi.position = at
	parent.add_child(mi)


static func _sauna(world: Node3D, at: Vector3) -> void:
	var sauna := Node3D.new()
	sauna.name = "Sauna"
	sauna.position = at
	sauna.rotation_degrees.y = 90
	world.add_child(sauna)
	var log_color := Color(0.36, 0.24, 0.15)
	_box(sauna, Vector3(4.0, 2.4, 3.2), Vector3(0, 1.2, 0), log_color, 0.95, true)
	# Hirsien raidat
	for i in 7:
		_box(sauna, Vector3(4.1, 0.05, 3.3), Vector3(0, 0.3 + i * 0.32, 0), log_color.darkened(0.35), 1.0)
	_roof(sauna, Vector3(4.6, 1.3, 3.8), Vector3(0, 3.05, 0), Color(0.15, 0.15, 0.17))
	var roof_snow := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(4.0, 1.45, 4.7)
	roof_snow.mesh = prism
	roof_snow.material_override = snow_material()
	roof_snow.rotation_degrees.y = 90
	roof_snow.position = Vector3(0, 3.2, 0)
	sauna.add_child(roof_snow)
	_box(sauna, Vector3(0.8, 1.9, 0.08), Vector3(0.9, 0.95, 1.62), Color(0.28, 0.18, 0.1), 0.8)
	_window(sauna, Vector3(-1.0, 1.5, 1.62))
	_box(sauna, Vector3(0.45, 1.4, 0.45), Vector3(-1.2, 3.4, -0.6), Color(0.3, 0.3, 0.32), 0.9)
	# Savua piipusta: saunaa lämmitetään
	var smoke := CPUParticles3D.new()
	smoke.amount = 60
	smoke.lifetime = 5.0
	smoke.preprocess = 5.0
	smoke.direction = Vector3(0.3, 1, 0)
	smoke.spread = 15.0
	smoke.gravity = Vector3(0.25, 0.25, 0)
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 0.9
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 3.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.0))
	smoke.scale_amount_curve = curve
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.6, 0.6, 0.62, 0.5))
	gradient.set_color(1, Color(0.7, 0.7, 0.75, 0.0))
	smoke.color_ramp = gradient
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	smoke.mesh = quad
	smoke.position = Vector3(-1.2, 4.2, -0.6)
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sauna.add_child(smoke)


static func _fence(world: Node3D, x: float, z_start: float, z_end: float) -> void:
	var color := Color(0.5, 0.4, 0.3)
	var z := z_start
	while z <= z_end:
		_box(world, Vector3(0.1, 1.2, 0.1), Vector3(x, 0.6, z), color, 0.95)
		_box(world, Vector3(0.12, 0.08, 0.14), Vector3(x, 1.24, z), WHITE_TRIM, 0.9)
		z += 1.6
	for y in [0.55, 1.0]:
		_box(world, Vector3(0.05, 0.1, z_end - z_start), Vector3(x, y, (z_start + z_end) * 0.5), color.darkened(0.1), 0.95)


static func _mailbox(world: Node3D, at: Vector3) -> void:
	_box(world, Vector3(0.1, 1.1, 0.1), at + Vector3(0, 0.55, 0), Color(0.35, 0.3, 0.25), 0.9)
	_box(world, Vector3(0.35, 0.3, 0.5), at + Vector3(0, 1.25, 0), Color(0.12, 0.3, 0.6), 0.5)
	var lump := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.18
	lump.mesh = sphere
	lump.material_override = snow_material()
	lump.position = at + Vector3(0, 1.43, 0)
	world.add_child(lump)


static func _street_lamp(world: Node3D, at: Vector3) -> void:
	_box(world, Vector3(0.14, 5.0, 0.14), at + Vector3(0, 2.5, 0), Color(0.3, 0.3, 0.32), 0.5)
	_box(world, Vector3(0.1, 0.1, 1.2), at + Vector3(0, 4.95, 0.55), Color(0.3, 0.3, 0.32), 0.5)
	var head := _box(world, Vector3(0.35, 0.15, 0.5), at + Vector3(0, 4.85, 1.05), Color(1.0, 0.8, 0.5), 0.3)
	var mat: StandardMaterial3D = head.material_override.duplicate()
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.65, 0.3)
	mat.emission_energy_multiplier = 4.0
	head.material_override = mat
	var light := SpotLight3D.new()
	light.light_color = Color(1.0, 0.68, 0.35)
	light.light_energy = 6.0
	light.spot_range = 12.0
	light.spot_angle = 55.0
	light.shadow_enabled = true
	light.position = at + Vector3(0, 4.7, 1.05)
	light.rotation_degrees.x = -90
	world.add_child(light)


static func _forest(world: Node3D, hx: float, hz: float, road_z: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var placed := 0
	var tries := 0
	while placed < 140 and tries < 4000:
		tries += 1
		var p := Vector3(rng.randf_range(-70, 70), 0, rng.randf_range(-70, 60))
		# Ei pihalle, talon tai saunan päälle eikä tielle.
		if absf(p.x) < hx + 7.0 and p.z > -hz - 11.0 and p.z < road_z + 3.0:
			continue
		if absf(p.z - road_z) < ROAD_HALF_WIDTH + 1.5:
			continue
		_spruce(world, p, rng.randf_range(5.0, 13.0), rng.randf() * TAU)
		placed += 1


static func _spruce(world: Node3D, at: Vector3, height: float, yaw: float) -> void:
	var tree := Node3D.new()
	tree.position = at
	tree.rotation.y = yaw
	world.add_child(tree)
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.2
	cyl.height = height * 0.3
	trunk.mesh = cyl
	trunk.material_override = _mat(Color(0.3, 0.2, 0.13), 1.0)
	trunk.position.y = height * 0.15
	tree.add_child(trunk)
	var layers := 5
	for i in layers:
		var t := float(i) / layers
		var radius := lerpf(height * 0.28, height * 0.06, t)
		var layer_h := height * 0.32
		var y := height * 0.2 + t * height * 0.68 + layer_h * 0.5
		var cone := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = radius
		mesh.height = layer_h
		mesh.radial_segments = 9
		cone.mesh = mesh
		cone.material_override = _mat(Color(0.07, 0.2, 0.12), 0.95)
		cone.position.y = y
		tree.add_child(cone)
		# Lumikuorrute oksien päällä
		var cap := MeshInstance3D.new()
		var cap_mesh := CylinderMesh.new()
		cap_mesh.top_radius = 0.0
		cap_mesh.bottom_radius = radius * 0.8
		cap_mesh.height = layer_h * 0.45
		cap_mesh.radial_segments = 9
		cap.mesh = cap_mesh
		cap.material_override = snow_material()
		cap.position.y = y + layer_h * 0.3
		tree.add_child(cap)


# --- Satunnaistapahtumien hahmot ---------------------------------------------------

## Kunnan aura-auto. Kulkee +X-suuntaan.
static func make_plow_truck() -> Node3D:
	var truck := Node3D.new()
	truck.name = "AuraAuto"
	var orange := Color(0.88, 0.36, 0.02)
	_box(truck, Vector3(5.0, 1.6, 2.4), Vector3(-0.8, 1.6, 0), orange, 0.5)
	_box(truck, Vector3(1.8, 1.7, 2.4), Vector3(2.6, 2.0, 0), orange, 0.5)
	_box(truck, Vector3(0.1, 0.8, 2.0), Vector3(3.52, 2.4, 0), Color(0.15, 0.2, 0.25), 0.1)
	_box(truck, Vector3(7.0, 0.5, 2.3), Vector3(0.0, 0.8, 0), Color(0.15, 0.15, 0.15), 0.8)
	for x in [-2.6, -1.0, 2.6]:
		for z in [-1.15, 1.15]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.55
			cyl.bottom_radius = 0.55
			cyl.height = 0.4
			wheel.mesh = cyl
			wheel.material_override = _mat(Color(0.08, 0.08, 0.08), 0.9)
			wheel.rotation_degrees.x = 90
			wheel.position = Vector3(x, 0.55, z)
			truck.add_child(wheel)
	# Vino aurasiipi ja sen edessä pöllyävä lumi
	var blade := _box(truck, Vector3(0.15, 1.1, 3.6), Vector3(4.3, 0.6, 0), Color(0.9, 0.9, 0.2), 0.4)
	blade.rotation_degrees.y = 25
	var beacon := _box(truck, Vector3(0.3, 0.25, 0.3), Vector3(2.6, 3.0, 0), Color(1.0, 0.6, 0.1), 0.3)
	var mat: StandardMaterial3D = beacon.material_override.duplicate()
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.1)
	mat.emission_energy_multiplier = 6.0
	beacon.material_override = mat
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.1)
	light.light_energy = 1.2
	light.omni_range = 8.0
	light.position = Vector3(2.6, 4.2, 0)
	truck.add_child(light)
	var spray := _puff(200, 1.2, 0.14, Color(0.95, 0.97, 1.0, 0.9))
	spray.direction = Vector3(0.3, 1, 1)
	spray.spread = 25.0
	spray.initial_velocity_min = 3.0
	spray.initial_velocity_max = 6.0
	spray.position = Vector3(4.3, 0.8, 1.2)
	truck.add_child(spray)
	return truck


static func make_moose() -> Node3D:
	var moose := Node3D.new()
	moose.name = "Hirvi"
	var brown := Color(0.28, 0.18, 0.11)
	var body := _capsule(moose, 0.55, 2.4, Vector3(0, 1.75, 0), brown)
	body.rotation_degrees.x = 90
	for x in [-0.3, 0.3]:
		for z in [-0.75, 0.75]:
			var leg := _capsule(moose, 0.09, 1.4, Vector3(x, 0.7, z), brown.darkened(0.2))
			leg.name = "Leg"
	var neck := _capsule(moose, 0.22, 0.9, Vector3(0, 2.25, -1.15), brown)
	neck.rotation_degrees.x = -50
	var head := _capsule(moose, 0.2, 0.85, Vector3(0, 2.45, -1.6), brown.darkened(0.1))
	head.rotation_degrees.x = 80
	# Lapiosarvet
	for side in [-1.0, 1.0]:
		var antler := _box(moose, Vector3(0.7, 0.06, 0.4), Vector3(side * 0.45, 2.8, -1.45), Color(0.82, 0.76, 0.62), 0.8)
		antler.rotation_degrees.z = side * 20
		for i in 3:
			_box(antler, Vector3(0.05, 0.25, 0.05), Vector3(side * 0.3 - side * i * 0.18, 0.12, 0.15), Color(0.82, 0.76, 0.62), 0.8)
	_capsule(moose, 0.07, 0.3, Vector3(0, 2.0, -1.75), brown.darkened(0.3))
	return moose


## Naapurin Pertti moottorikelkalla. Keula -Z-suuntaan.
static func make_snowmobile() -> Node3D:
	var sled := Node3D.new()
	sled.name = "Moottorikelkka"
	var yellow := Color(0.95, 0.8, 0.05)
	_box(sled, Vector3(0.9, 0.5, 2.4), Vector3(0, 0.5, 0), yellow, 0.35)
	var nose := _box(sled, Vector3(0.85, 0.4, 0.8), Vector3(0, 0.55, -1.4), yellow, 0.35)
	nose.rotation_degrees.x = 25
	_box(sled, Vector3(0.7, 0.35, 0.05), Vector3(0, 1.0, -0.8), Color(0.6, 0.75, 0.9, 0.6), 0.05)
	_box(sled, Vector3(0.6, 0.15, 1.0), Vector3(0, 0.82, 0.4), Color(0.1, 0.1, 0.1), 0.8)
	for side in [-0.45, 0.45]:
		_box(sled, Vector3(0.12, 0.05, 1.2), Vector3(side, 0.05, -1.3), Color(0.15, 0.15, 0.15), 0.5)
	_box(sled, Vector3(0.7, 0.35, 1.6), Vector3(0, 0.18, 0.4), Color(0.12, 0.12, 0.12), 0.9)
	# Pertti: oranssi haalari ja pipo
	var pertti := Node3D.new()
	pertti.name = "Pertti"
	pertti.position = Vector3(0, 0.9, 0.3)
	sled.add_child(pertti)
	_capsule(pertti, 0.28, 1.0, Vector3(0, 0.45, 0), Color(0.95, 0.42, 0.05))
	var face := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	face.mesh = sphere
	face.material_override = _mat(Color(0.95, 0.72, 0.6), 0.7)
	face.position = Vector3(0, 1.1, 0)
	pertti.add_child(face)
	_box(pertti, Vector3(0.3, 0.14, 0.3), Vector3(0, 1.26, 0), Color(0.1, 0.25, 0.6), 0.9)
	# Pakokaasu ja lumipöly
	var exhaust := _puff(80, 1.0, 0.12, Color(0.92, 0.94, 1.0, 0.7))
	exhaust.direction = Vector3(0, 0.5, 1)
	exhaust.spread = 30.0
	exhaust.initial_velocity_min = 2.0
	exhaust.initial_velocity_max = 4.0
	exhaust.position = Vector3(0, 0.2, 1.3)
	sled.add_child(exhaust)
	return sled


# --- Apufunktiot --------------------------------------------------------------------

## Pehmeä, häipyvä lumipöly- tai savupartikkeli.
static func _puff(amount: int, lifetime: float, size: float, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color, 0.0))
	p.color_ramp = gradient
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	p.mesh = quad
	return p


static func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var key := "%s/%.2f" % [color.to_html(), roughness]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_materials[key] = m
	return _materials[key]


static func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color, roughness: float, solid := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = _mat(color, roughness)
	mi.position = at
	parent.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		body.add_child(shape)
		mi.add_child(body)
	return mi


static func _capsule(parent: Node3D, radius: float, height: float, at: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	mi.mesh = capsule
	mi.material_override = _mat(color, 0.9)
	mi.position = at
	parent.add_child(mi)
	return mi
