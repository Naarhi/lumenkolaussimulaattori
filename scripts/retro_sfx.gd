extends Node
## Old School RuneScapen henkiset 8-bittiset äänet, jotka syntetisoidaan koodissa.

enum { SCOOP, THROW, LEVEL_UP, ANNOUNCE, FOOTSTEP, ENGINE, FLAME, SALT, SCRAPE }

const MIX_RATE := 22050
const BUS := "Efektit"
const SETTINGS_PATH := "user://asetukset.cfg"

var _streams := {}
# Packed-taulukot välitetään arvona, joten syntetisaattori kirjoittaa tähän jäsenmuuttujaan.
var _buf := PackedFloat32Array()


func _ready() -> void:
	_setup_buses()
	for kind in [SCOOP, THROW, LEVEL_UP, ANNOUNCE, FOOTSTEP, ENGINE, FLAME, SALT, SCRAPE]:
		_streams[kind] = _make_stream(kind)


# --- Äänenvoimakkuudet -------------------------------------------------------------

func _setup_buses() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	for bus_name in [BUS, Music.BUS]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
		_apply_volume(bus_name, config.get_value("aanet", bus_name, 0.8))


## Äänenvoimakkuus 0..1 väylälle "Efektit" tai "Musiikki". Tallennetaan asetuksiin.
func set_volume(bus_name: String, linear: float) -> void:
	_apply_volume(bus_name, linear)
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("aanet", bus_name, linear)
	config.save(SETTINGS_PATH)


func get_volume(bus_name: String) -> float:
	return db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus_name)))


func _apply_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(index, linear <= 0.001)


# --- Toisto -------------------------------------------------------------------------

func play_at(kind: int, world_position: Vector3, parent: Node) -> void:
	var player := AudioStreamPlayer3D.new()
	player.bus = BUS
	player.stream = _streams[kind]
	player.unit_size = 6.0
	parent.add_child(player)
	player.global_position = world_position
	player.finished.connect(player.queue_free)
	player.play()


func play_2d(kind: int) -> void:
	var player := AudioStreamPlayer.new()
	player.bus = BUS
	player.stream = _streams[kind]
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _make_stream(kind: int) -> AudioStreamWAV:
	_buf = PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337 + kind
	match kind:
		SCOOP:
			_noise(rng, 0.0, 0.16, 0.25, 0.5)
			_square(0.0, 0.06, 180.0, 90.0, 0.25, 0.5)
		THROW:
			_square(0.0, 0.18, 520.0, 160.0, 0.2, 0.25)
			_noise(rng, 0.12, 0.22, 0.15, 0.45)
		LEVEL_UP:
			# Nouseva arpeggio ja loppusointu OSRS:n level up -fanfaarin henkeen.
			var notes := [523.25, 659.25, 783.99, 1046.5]
			for i in notes.size():
				_square(i * 0.12, 0.16, notes[i], notes[i], 0.22, 0.5)
			_square(0.48, 0.7, 1046.5, 1046.5, 0.18, 0.5)
			_square(0.48, 0.7, 783.99, 783.99, 0.14, 0.25)
			_square(0.48, 0.7, 523.25, 523.25, 0.12, 0.5)
		ANNOUNCE:
			_square(0.0, 0.15, 880.0, 880.0, 0.2, 0.5)
			_square(0.15, 0.3, 659.25, 659.25, 0.2, 0.5)
		FOOTSTEP:
			_noise(rng, 0.0, 0.07, 0.35, 0.25)
		ENGINE:
			# Lumilingon kaksitahtimoottorin pörinä
			for i in 6:
				_square(i * 0.05, 0.05, 95.0, 85.0, 0.16, 0.3)
			_noise(rng, 0.0, 0.3, 0.6, 0.12)
		FLAME:
			_noise(rng, 0.0, 0.3, 0.08, 0.6)
			_square(0.0, 0.3, 60.0, 50.0, 0.06, 0.5)
		SALT:
			for i in 5:
				_noise(rng, i * 0.04, 0.03, 0.9, 0.12)
		SCRAPE:
			_noise(rng, 0.0, 0.25, 0.5, 0.25)
			_square(0.0, 0.25, 140.0, 120.0, 0.05, 0.15)

	var data := PackedByteArray()
	data.resize(_buf.size() * 2)
	for i in _buf.size():
		data.encode_s16(i * 2, int(clampf(_buf[i], -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


## Neliöaalto, jonka taajuus liukuu start_hz -> end_hz.
func _square(start: float, length: float, start_hz: float, end_hz: float, volume: float, duty: float) -> void:
	var first := int(start * MIX_RATE)
	var count := int(length * MIX_RATE)
	_ensure(first + count)
	var phase := 0.0
	for i in count:
		var t := float(i) / count
		phase = fposmod(phase + lerpf(start_hz, end_hz, t) / MIX_RATE, 1.0)
		var wave := 1.0 if phase < duty else -1.0
		_buf[first + i] += wave * volume * _envelope(t)


## Alipäästösuodatettu kohina (lumen pöllähdys).
func _noise(rng: RandomNumberGenerator, start: float, length: float, smoothing: float, volume: float) -> void:
	var first := int(start * MIX_RATE)
	var count := int(length * MIX_RATE)
	_ensure(first + count)
	var filtered := 0.0
	for i in count:
		var t := float(i) / count
		filtered += (rng.randf_range(-1.0, 1.0) - filtered) * smoothing
		_buf[first + i] += filtered * volume * _envelope(t) * 2.0


func _envelope(t: float) -> float:
	return clampf(t / 0.02, 0.0, 1.0) * (1.0 - t)


func _ensure(length: int) -> void:
	if _buf.size() < length:
		var old := _buf.size()
		_buf.resize(length)
		for i in range(old, length):
			_buf[i] = 0.0
