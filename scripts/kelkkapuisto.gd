extends RefCounted
## Kelkkapuisto kotitalon pohjoispuolella: lumisia mäkiä ja hyppyreitä moottorikelkkastuntteihin.
## Maasto on korkeuskenttä (1 m ruudut), jonka päälle tehdään sama lumipinta kuin muualle.

const Pihapiiri := preload("res://scripts/pihapiiri.gd")

## Puiston alue maailmassa (x, z, leveys, syvyys). Reunoilla maasto laskee tasamaalle.
const AREA := Rect2(-45.0, -92.0, 90.0, 58.0)
const EDGE := 6.0
## Mäet: [x, z, korkeus, säde].
const HILLS := [
	[-26.0, -76.0, 8.0, 10.0],
	[22.0, -82.0, 11.0, 11.0],
	[0.0, -88.0, 5.0, 7.0],
]
## Hyppyrit: [x, z, pituus, leveys, korkeus, suunta asteina]. Nousevat suuntaan -Z käännettynä suunnan verran.
## Hyppyrit ovat puiston etelälaidalla, ja alastulot tasaisella ennen mäkiä.
const RAMPS := [
	[0.0, -38.0, 5.0, 3.2, 1.5, 0.0],
	[-14.0, -40.0, 6.0, 3.2, 2.2, 15.0],
	[14.0, -40.0, 6.0, 3.2, 2.2, -15.0],
	[30.0, -38.0, 7.5, 4.0, 3.2, 0.0],
	[-34.0, -40.0, 4.0, 3.0, 1.2, -30.0],
]
## Puuton kelkkaura tieltä kotipihan itäpuolitse puistoon.
const TRAIL := Rect2(11.0, -34.0, 7.0, 46.0)
const SIGN_POS := Vector3(-6.0, 0.0, -35.0)


## Maaston korkeus (ilman hyppyreitä) maailman pisteessä.
static func height(x: float, z: float) -> float:
	if not AREA.has_point(Vector2(x, z)):
		return 0.0
	var h := 0.0
	for hill in HILLS:
		var d2: float = (x - hill[0]) * (x - hill[0]) + (z - hill[1]) * (z - hill[1])
		h += hill[2] * exp(-d2 / (hill[3] * hill[3]))
	var edge := minf(minf(x - AREA.position.x, AREA.end.x - x), minf(z - AREA.position.y, AREA.end.y - z))
	return h * smoothstep(0.0, EDGE, edge)


static func contains(pos: Vector3) -> bool:
	return AREA.grow(2.0).has_point(Vector2(pos.x, pos.z))


static func build(world: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Kelkkapuisto"
	world.add_child(root)
	_terrain(root)
	for r in RAMPS:
		_ramp(root, Vector3(r[0], 0.0, r[1]), r[2], r[3], r[4], r[5])
	_sign(root)


static func _terrain(root: Node3D) -> void:
	var nx := int(AREA.size.x) + 1
	var nz := int(AREA.size.y) + 1
	var data := PackedFloat32Array()
	data.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			data[iz * nx + ix] = height(AREA.position.x + ix, AREA.position.y + iz)
	var shape := HeightMapShape3D.new()
	shape.map_width = nx
	shape.map_depth = nz
	shape.map_data = data
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	# Korkeuskenttä on keskitetty origoonsa.
	body.position = Vector3(AREA.get_center().x, 0.0, AREA.get_center().y)
	root.add_child(body)

	# Lumipinta on SNOW_LEVEL maaston yläpuolella kuten muualla, ja hieman tasaisen lumen yläpuolella.
	var lift := Pihapiiri.SNOW_LEVEL + 0.02
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz:
		for ix in nx:
			var x := AREA.position.x + ix
			var z := AREA.position.y + iz
			var h := data[iz * nx + ix]
			var n := Vector3(height(x - 0.5, z) - height(x + 0.5, z), 1.0, height(x, z - 0.5) - height(x, z + 0.5)).normalized()
			st.set_normal(n)
			st.set_uv(Vector2(x, z) * 0.25)
			st.add_vertex(Vector3(x, h + lift, z))
	for iz in nz - 1:
		for ix in nx - 1:
			var a := iz * nx + ix
			var b := a + 1
			var c := a + nx
			var d := c + 1
			# Myötäpäivään ylhäältä katsottuna (Godotin etupuoli).
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	var mi := MeshInstance3D.new()
	mi.name = "Maasto"
	mi.mesh = st.commit()
	mi.material_override = Pihapiiri.snow_material()
	root.add_child(mi)


## Kiilan muotoinen hyppyri. at on hyppyrin alkupää (maan tasossa).
static func _ramp(root: Node3D, at: Vector3, length: float, width: float, rise: float, yaw_deg: float) -> void:
	var hw := width * 0.5
	var pts := PackedVector3Array([
		Vector3(-hw, 0, 0), Vector3(hw, 0, 0),
		Vector3(-hw, 0, -length), Vector3(hw, 0, -length),
		Vector3(-hw, rise, -length), Vector3(hw, rise, -length),
	])
	var body := StaticBody3D.new()
	body.name = "Hyppyri"
	body.position = at + Vector3(0, height(at.x, at.z), 0)
	body.rotation_degrees.y = yaw_deg
	var col := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	col.shape = shape
	body.add_child(col)
	root.add_child(body)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Ramppipinta, takaseinä ja kyljet.
	var faces := [
		[pts[0], pts[4], pts[1]], [pts[1], pts[4], pts[5]],
		[pts[2], pts[3], pts[4]], [pts[3], pts[5], pts[4]],
		[pts[0], pts[2], pts[4]], [pts[1], pts[5], pts[3]],
	]
	for f in faces:
		for p in f:
			st.add_vertex(p)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := Pihapiiri.snow_material().duplicate()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.93, 0.96, 1.0)
	mi.material_override = mat
	body.add_child(mi)
	# Oranssit reunakepit, jotta hyppyrin näkee kaukaa.
	for sx in [-hw - 0.2, hw + 0.2]:
		Pihapiiri._box(body, Vector3(0.06, rise + 1.0, 0.06), Vector3(sx, (rise + 1.0) * 0.5, -length), Color(1.0, 0.45, 0.05), 0.6)


static func _sign(root: Node3D) -> void:
	for px in [-1.4, 1.4]:
		Pihapiiri._box(root, Vector3(0.12, 2.6, 0.12), SIGN_POS + Vector3(px, 1.3, 0), Color(0.4, 0.28, 0.16), 0.9)
	Pihapiiri._box(root, Vector3(3.4, 1.2, 0.1), SIGN_POS + Vector3(0, 2.2, 0), Color(0.12, 0.3, 0.6), 0.6)
	var label := Label3D.new()
	label.text = "KELKKAPUISTO\nhyppyrit ja mäet"
	label.font_size = 64
	label.pixel_size = 0.006
	label.outline_size = 10
	label.position = SIGN_POS + Vector3(0, 2.2, 0.07)
	root.add_child(label)
