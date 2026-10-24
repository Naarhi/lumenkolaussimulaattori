extends Node
## Oma Old School RuneScapen henkinen taustamusiikki, joka syntetisoidaan koodissa.
## Kappale "Pihan valssi" (D-molli, 100 bpm, 16 tahtia) on sävelletty tätä peliä varten.
## Synteesi tehdään taustasäikeessä, jottei peli nyki käynnistyessä.

const MIX_RATE := 22050
const BPM := 100.0
const EIGHTH := 60.0 / BPM / 2.0
const BUS := "Musiikki"

# Melodia: [sävel, kesto kahdeksasosina]. "." on tauko.
const MELODY := [
	["D5", 4], ["F5", 2], ["A5", 2], ["G5", 3], ["F5", 1], ["E5", 2], ["D5", 2],
	["F5", 4], ["D5", 2], ["A#4", 2], ["C5", 3], ["D5", 1], ["C5", 2], ["A#4", 2],
	["E5", 4], ["G5", 2], ["E5", 2], ["C5", 3], ["D5", 1], ["E5", 2], ["G5", 2],
	["A5", 6], ["G5", 2], ["E5", 8],
	["D5", 4], ["F5", 2], ["A5", 2], ["D6", 3], ["C6", 1], ["A5", 2], ["F5", 2],
	["G5", 4], ["A#5", 2], ["G5", 2], ["D5", 3], ["E5", 1], ["F5", 2], ["G5", 2],
	["A5", 3], ["G5", 1], ["F5", 2], ["E5", 2], ["C#5", 4], ["E5", 2], ["A4", 2],
	["D5", 8], [".", 8],
]
# Sointu kahdeksi tahdiksi kerrallaan: pohjasävel ja soinnun sävelet.
const CHORDS := [
	["D3", ["D4", "F4", "A4"]],
	["A#2", ["A#3", "D4", "F4"]],
	["C3", ["C4", "E4", "G4"]],
	["A2", ["A3", "C4", "E4"]],
	["D3", ["D4", "F4", "A4"]],
	["G2", ["G3", "A#3", "D4"]],
	["A2", ["A3", "C#4", "E4"]],
	["D3", ["D4", "F4", "A4"]],
]

var _player: AudioStreamPlayer
var _thread: Thread
var _buf := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_player = AudioStreamPlayer.new()
	_player.bus = BUS
	_player.volume_db = -4.0
	add_child(_player)
	_thread = Thread.new()
	_thread.start(_compose)


func _compose() -> void:
	var bars := CHORDS.size() * 2
	var length := int(bars * 8 * EIGHTH * MIX_RATE)
	_buf.resize(length)
	_buf.fill(0.0)
	_rng.seed = 2026

	# Melodia: pehmeä pulssiaalto ja vibrato (OSRS:n "huilu").
	var t := 0.0
	for note in MELODY:
		var duration: float = note[1] * EIGHTH
		if note[0] != ".":
			_tone(t, duration * 0.95, _freq(note[0]), 0.16, 0.25, 5.0)
		t += duration

	for i in CHORDS.size():
		var start := i * 16 * EIGHTH
		var root := _freq(CHORDS[i][0])
		# Basso: pohjasävel, kvintti, oktaavi ja kvintti kahdeksasosina.
		for step in 16:
			var f: float = root * [1.0, 1.5, 2.0, 1.5][step % 4]
			_triangle(start + step * EIGHTH, EIGHTH * 0.9, f, 0.13)
		# Pehmeä sointumatto
		for tone in CHORDS[i][1]:
			_tone(start, 16 * EIGHTH, _freq(tone), 0.035, 0.5, 0.0)
		# Rummut: matala isku 1. ja 3. iskulla, kohinanapsu 2. ja 4. iskulla.
		for beat in 8:
			var bt := start + beat * 2 * EIGHTH
			if beat % 2 == 0:
				_kick(bt)
			else:
				_snare(bt)

	var data := PackedByteArray()
	data.resize(length * 2)
	for i in length:
		data.encode_s16(i * 2, int(clampf(_buf[i] * 0.9, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = length
	_start.call_deferred(stream)


func _start(stream: AudioStreamWAV) -> void:
	_thread.wait_to_finish()
	print("[Musiikki] Sävelletty %.1f s kappale" % (stream.data.size() / 2.0 / MIX_RATE))
	if Net.cli.has("music-wav"):
		stream.save_to_wav(Net.cli["music-wav"])
	_player.stream = stream
	_player.play()


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


static func _freq(note: String) -> float:
	var names := {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
	var octave := int(note.right(1))
	var semitone: int = names[note.left(note.length() - 1)]
	var midi := (octave + 1) * 12 + semitone
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


## Pulssiaalto, jossa on pehmeä verhokäyrä ja halutessa vibrato.
func _tone(start: float, length: float, hz: float, volume: float, duty: float, vibrato_hz: float) -> void:
	var first := int(start * MIX_RATE)
	var count := mini(int(length * MIX_RATE), _buf.size() - first)
	var phase := 0.0
	for i in count:
		var sec := float(i) / MIX_RATE
		var f := hz * (1.0 + 0.006 * sin(TAU * vibrato_hz * sec) * minf(sec * 3.0, 1.0))
		phase = fposmod(phase + f / MIX_RATE, 1.0)
		var wave := 1.0 if phase < duty else -1.0
		var env := minf(sec / 0.02, 1.0) * minf((count - i) / (0.06 * MIX_RATE), 1.0)
		_buf[first + i] += wave * volume * env


func _triangle(start: float, length: float, hz: float, volume: float) -> void:
	var first := int(start * MIX_RATE)
	var count := mini(int(length * MIX_RATE), _buf.size() - first)
	var phase := 0.0
	for i in count:
		phase = fposmod(phase + hz / MIX_RATE, 1.0)
		var wave := 4.0 * absf(phase - 0.5) - 1.0
		var env := minf(i / 200.0, 1.0) * (1.0 - float(i) / count * 0.6)
		_buf[first + i] += wave * volume * env


func _kick(start: float) -> void:
	var first := int(start * MIX_RATE)
	var count := mini(int(0.12 * MIX_RATE), _buf.size() - first)
	var phase := 0.0
	for i in count:
		var k := float(i) / count
		phase = fposmod(phase + lerpf(120.0, 45.0, k) / MIX_RATE, 1.0)
		_buf[first + i] += sin(phase * TAU) * 0.22 * (1.0 - k)


func _snare(start: float) -> void:
	var first := int(start * MIX_RATE)
	var count := mini(int(0.07 * MIX_RATE), _buf.size() - first)
	var filtered := 0.0
	for i in count:
		filtered += (_rng.randf_range(-1.0, 1.0) - filtered) * 0.5
		_buf[first + i] += filtered * 0.12 * (1.0 - float(i) / count)
