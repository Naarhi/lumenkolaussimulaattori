extends RefCounted
## Kolaustyökalut: tunnisteet, nimet, käyttöparametrit ja mallit.
## Lapio on painallustyökalu (kauho / heitä). Muut toimivat, kun hiiren nappia pidetään pohjassa.

enum { LAPIO, MASI, LINKO, LIEKKI, SUOLA }

const NAMES := ["Lapio", "MASI-lumikola", "Lumilinko", "Liekinheitin", "Suola"]
const COUNT := 5

## Työkalut, joiden malli kulkee maata pitkin (pelaajan juuren lapsi, ei käänny katseen mukana ylös/alas).
const GROUND_TOOLS := [MASI, LINKO]

## Palvelimen käyttötahti sekunteina.
const INTERVAL := {MASI: 0.12, LINKO: 0.1, LIEKKI: 0.1, SUOLA: 0.25}
## Kuinka usein toistuva käyttöääni soitetaan.
const SOUND_INTERVAL := 0.28


static func sound_for(tool: int) -> int:
	match tool:
		MASI:
			return Sfx.SCRAPE
		LINKO:
			return Sfx.ENGINE
		LIEKKI:
			return Sfx.FLAME
		SUOLA:
			return Sfx.SALT
	return -1


# --- Mallit -----------------------------------------------------------------------
# Pään lapsina olevat mallit ovat pään koordinaatistossa (silmät origossa, katse -Z).
# Maatyökalut ovat pelaajan juuren koordinaatistossa (jalat origossa).

## Suomalainen MASI-lumikola: leveä kaareva terä ja U-mallinen putkikahva.
static func make_masi() -> Node3D:
	var root := Node3D.new()
	root.name = "Masi"
	var blade_color := Color(0.08, 0.1, 0.14)
	var steel := Color(0.75, 0.77, 0.8)
	var blade_z := -1.05
	# Kaareva terä kolmesta osasta
	_box(root, Vector3(0.8, 0.42, 0.03), Vector3(0, 0.25, blade_z - 0.05), blade_color, 0.5).rotation.x = deg_to_rad(-12)
	_box(root, Vector3(0.8, 0.03, 0.4), Vector3(0, 0.03, blade_z + 0.12), blade_color, 0.5)
	_box(root, Vector3(0.8, 0.03, 0.04), Vector3(0, 0.02, blade_z - 0.1), steel, 0.25)
	for side in [-1.0, 1.0]:
		_box(root, Vector3(0.03, 0.42, 0.42), Vector3(side * 0.4, 0.22, blade_z + 0.08), blade_color, 0.5)
		# Kahvan putket terästä käsiin
		var start := Vector3(side * 0.3, 0.35, blade_z + 0.2)
		var end := Vector3(side * 0.22, 1.0, -0.25)
		_tube(root, start, end, 0.016, steel)
	_tube(root, Vector3(-0.24, 1.0, -0.25), Vector3(0.24, 1.0, -0.25), 0.022, Color(0.1, 0.1, 0.1))
	var label := Label3D.new()
	label.text = "MASI"
	label.font_size = 48
	label.pixel_size = 0.004
	label.modulate = Color(0.95, 0.75, 0.1)
	label.outline_size = 0
	label.position = Vector3(0, 0.28, blade_z - 0.075)
	label.rotation.x = deg_to_rad(-12)
	label.rotation.y = PI
	root.add_child(label)
	return root


## Työnnettävä lumilinko: punainen runko, kita edessä, poistotorvi oikealle.
static func make_blower() -> Node3D:
	var root := Node3D.new()
	root.name = "Linko"
	var red := Color(0.75, 0.08, 0.05)
	var dark := Color(0.12, 0.12, 0.13)
	_box(root, Vector3(0.62, 0.38, 0.32), Vector3(0, 0.22, -1.05), red, 0.4)
	_box(root, Vector3(0.58, 0.32, 0.04), Vector3(0, 0.2, -1.22), dark, 0.6)
	var auger := _tube(root, Vector3(-0.27, 0.14, -1.16), Vector3(0.27, 0.14, -1.16), 0.1, Color(0.85, 0.85, 0.8))
	auger.name = "Auger"
	_box(root, Vector3(0.36, 0.3, 0.36), Vector3(0, 0.45, -0.78), dark, 0.5)
	_box(root, Vector3(0.3, 0.12, 0.3), Vector3(0, 0.66, -0.78), red, 0.4)
	for side in [-1.0, 1.0]:
		var wheel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.13
		cyl.bottom_radius = 0.13
		cyl.height = 0.08
		wheel.mesh = cyl
		wheel.material_override = _mat(dark, 0.9)
		wheel.rotation.z = PI * 0.5
		wheel.position = Vector3(side * 0.3, 0.13, -0.72)
		root.add_child(wheel)
		_tube(root, Vector3(side * 0.22, 0.5, -0.7), Vector3(side * 0.22, 1.0, -0.3), 0.016, dark)
	_tube(root, Vector3(-0.24, 1.0, -0.3), Vector3(0.24, 1.0, -0.3), 0.022, dark)
	# Poistotorvi
	var chute := _tube(root, Vector3(0.12, 0.4, -1.0), Vector3(0.32, 0.85, -1.1), 0.07, red)
	chute.name = "Chute"
	var fx_anchor := Node3D.new()
	fx_anchor.name = "FxAnchor"
	fx_anchor.position = Vector3(0.34, 0.9, -1.1)
	root.add_child(fx_anchor)
	return root


## Liekinheitin lanteella: tankki ja suutin.
static func make_flamethrower() -> Node3D:
	var root := Node3D.new()
	root.name = "Liekinheitin"
	root.position = Vector3(0.3, -0.42, -0.45)
	var olive := Color(0.3, 0.33, 0.18)
	var metal := Color(0.35, 0.35, 0.37)
	_tube(root, Vector3(0, 0, 0.1), Vector3(-0.05, 0.03, -0.55), 0.035, metal)
	_tube(root, Vector3(0.0, -0.05, 0.0), Vector3(0.0, -0.05, -0.3), 0.07, olive)
	_tube(root, Vector3(0, -0.02, -0.1), Vector3(0, -0.2, -0.1), 0.02, Color(0.1, 0.1, 0.1))
	var tip := _tube(root, Vector3(-0.05, 0.03, -0.55), Vector3(-0.055, 0.035, -0.62), 0.045, Color(0.15, 0.15, 0.15))
	tip.name = "Tip"
	var fx_anchor := Node3D.new()
	fx_anchor.name = "FxAnchor"
	fx_anchor.position = Vector3(-0.055, 0.035, -0.65)
	root.add_child(fx_anchor)
	var pilot := OmniLight3D.new()
	pilot.name = "Pilot"
	pilot.light_color = Color(1.0, 0.55, 0.15)
	pilot.light_energy = 0.0
	pilot.omni_range = 6.0
	pilot.position = Vector3(-0.05, 0.1, -1.0)
	root.add_child(pilot)
	return root


## Suolasanko vasemmassa kädessä.
static func make_salt_bucket() -> Node3D:
	var root := Node3D.new()
	root.name = "Suola"
	root.position = Vector3(-0.45, -0.46, -0.62)
	var bucket := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.13
	cyl.bottom_radius = 0.1
	cyl.height = 0.22
	bucket.mesh = cyl
	bucket.material_override = _mat(Color(0.85, 0.15, 0.1), 0.5)
	root.add_child(bucket)
	var salt := MeshInstance3D.new()
	var top := CylinderMesh.new()
	top.top_radius = 0.12
	top.bottom_radius = 0.12
	top.height = 0.02
	salt.mesh = top
	salt.material_override = _mat(Color(0.95, 0.95, 0.92), 0.9)
	salt.position.y = 0.09
	root.add_child(salt)
	var label := Label3D.new()
	label.text = "SUOLA"
	label.font_size = 28
	label.pixel_size = 0.003
	label.outline_size = 0
	label.position = Vector3(0, 0, 0.125)
	root.add_child(label)
	var fx_anchor := Node3D.new()
	fx_anchor.name = "FxAnchor"
	fx_anchor.position = Vector3(0, 0.12, -0.05)
	root.add_child(fx_anchor)
	return root


# --- Tehosteet ----------------------------------------------------------------------

static func make_flame_fx() -> CPUParticles3D:
	var p := _particles(220, 0.55, 0.12)
	p.direction = Vector3(0, 0.05, -1)
	p.spread = 9.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 8.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 4.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.5))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	g.add_point(0.3, Color(1.0, 0.5, 0.1, 0.9))
	g.set_color(g.get_point_count() - 1, Color(0.3, 0.3, 0.3, 0.0))
	p.color_ramp = g
	(p.mesh.material as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	(p.mesh.material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return p


static func make_blower_fx() -> CPUParticles3D:
	var p := _particles(260, 1.4, 0.1)
	p.direction = Vector3(0.8, 0.9, -0.4)
	p.spread = 12.0
	p.gravity = Vector3(0, -6.0, 0)
	p.initial_velocity_min = 5.5
	p.initial_velocity_max = 7.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	var g := Gradient.new()
	g.set_color(0, Color(0.97, 0.98, 1.0, 1.0))
	g.set_color(1, Color(0.97, 0.98, 1.0, 0.0))
	p.color_ramp = g
	return p


static func make_salt_fx() -> CPUParticles3D:
	var p := _particles(60, 0.7, 0.025)
	p.direction = Vector3(0, 0.6, -1)
	p.spread = 30.0
	p.gravity = Vector3(0, -9.0, 0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.5
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(0.9, 0.9, 0.9, 0.8))
	p.color_ramp = g
	return p


static func _particles(amount: int, lifetime: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.mesh = quad
	return p


# --- Apufunktiot --------------------------------------------------------------------

static var _materials := {}


static func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var key := "%s/%.2f" % [color.to_html(), roughness]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		_materials[key] = m
	return _materials[key]


static func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color, roughness: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = _mat(color, roughness)
	mi.position = at
	parent.add_child(mi)
	return mi


## Putki kahden pisteen välille.
static func _tube(parent: Node3D, start: Vector3, end: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var axis := end - start
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = axis.length()
	cyl.radial_segments = 12
	mi.mesh = cyl
	mi.material_override = _mat(color, 0.5)
	mi.basis = Basis(Quaternion(Vector3.UP, axis.normalized()))
	mi.position = (start + end) * 0.5
	parent.add_child(mi)
	return mi
