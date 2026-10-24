extends Node3D
## Vuorokausi: talvipäivä hämärtyy yöksi ja aamu valkenee taas. Yöllä taivaalla loimuavat revontulet.
## Palvelin kertoo liittyjälle vuorokauden vaiheen, ja jokainen kone kuluttaa aikaa itse.

## Koko vuorokausi kestää näin monta sekuntia.
const CYCLE := 960.0
## Vaihe 0 on iltapäivä (aloituskuva), 0.5 keskiyö.
const CLOCK_AT_ZERO := 13.0

const DAY_TOP := Color(0.1, 0.16, 0.34)
const DAY_HORIZON := Color(0.86, 0.56, 0.42)
const NIGHT_TOP := Color(0.01, 0.015, 0.05)
const NIGHT_HORIZON := Color(0.05, 0.07, 0.16)
const DAY_FOG := Color(0.62, 0.6, 0.7)
const NIGHT_FOG := Color(0.06, 0.07, 0.14)

var phase := 0.0
var _env: Environment
var _sun: DirectionalLight3D
var _sky: ProceduralSkyMaterial
var _aurora: Array[MeshInstance3D] = []
var _shown_minute := -1


func setup(env: Environment, sun: DirectionalLight3D) -> void:
	_env = env
	_sun = sun
	_sky = env.sky.sky_material
	_build_aurora()
	_apply()


## Päivän valoisuus 0 (yö) … 1 (päivä).
static func daylight(p: float) -> float:
	return smoothstep(-0.25, 0.6, cos(p * TAU))


## Kellonaika tunteina (0–24).
static func clock(p: float) -> float:
	return fposmod(CLOCK_AT_ZERO + p * 24.0, 24.0)


func _process(delta: float) -> void:
	phase = fposmod(phase + delta / CYCLE, 1.0)
	_apply()
	var minutes := int(clock(phase) * 60.0)
	if minutes / 10 != _shown_minute:
		_shown_minute = minutes / 10
		get_parent().hud.set_clock("Klo %02d:%02d" % [minutes / 60, (minutes % 60) / 10 * 10])


func _apply() -> void:
	if _env == null:
		return
	var d := daylight(phase)
	_sky.sky_top_color = NIGHT_TOP.lerp(DAY_TOP, d)
	_sky.sky_horizon_color = NIGHT_HORIZON.lerp(DAY_HORIZON, d)
	_sky.ground_horizon_color = NIGHT_HORIZON.lerp(Color(0.7, 0.55, 0.5), d)
	_env.ambient_light_energy = lerpf(0.35, 1.0, d)
	_env.fog_light_color = NIGHT_FOG.lerp(DAY_FOG, d)
	_sun.light_energy = lerpf(0.0, 1.3, d)
	# Yöllä kuu valaisee sinertävästi korkeammalta.
	_sun.light_color = Color(0.55, 0.65, 1.0).lerp(Color(1.0, 0.78, 0.58), d)
	_sun.light_energy = maxf(_sun.light_energy, 0.18)
	var night := clampf((0.3 - d) / 0.3, 0.0, 1.0)
	var t := Time.get_ticks_msec() / 1000.0
	for i in _aurora.size():
		var mat: StandardMaterial3D = _aurora[i].material_override
		var wave := 0.6 + 0.4 * sin(t * 0.4 + i * 1.7)
		mat.albedo_color.a = night * wave * 0.55
		_aurora[i].visible = night > 0.0


## Revontulet: muutama kaareva, hehkuva verho korkealla pohjoisessa.
func _build_aurora() -> void:
	var colors := [Color(0.3, 1.0, 0.55), Color(0.35, 0.9, 0.8), Color(0.6, 0.4, 1.0)]
	for i in 3:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		var segments := 40
		for k in segments + 1:
			var u := float(k) / segments
			var x := lerpf(-160.0, 160.0, u)
			var z := -150.0 - i * 25.0 + sin(u * TAU * 1.5 + i) * 22.0
			var y := 62.0 + i * 8.0 + sin(u * TAU * 2.0 + i * 0.7) * 6.0
			st.set_color(Color(1, 1, 1, 0.0))
			st.add_vertex(Vector3(x, y, z))
			st.set_color(Color(1, 1, 1, 1.0))
			st.add_vertex(Vector3(x, y + 30.0 + sin(u * 9.0 + i) * 8.0, z - 4.0))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = colors[i]
		mat.disable_fog = true
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_aurora.append(mi)
