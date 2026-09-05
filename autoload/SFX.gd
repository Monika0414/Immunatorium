extends Node
## Procedurally generated sound effects — no audio files, every stream is
## synthesized once and cached. Playback goes through a small round-robin
## pool of AudioStreamPlayer children so overlapping sounds (several hits in
## the same tick, across 3 lanes) don't cut each other off. Autoloaded as "SFX".

const POOL_SIZE: int = 8
const MIX_RATE: int = 22050

var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _cache: Dictionary = {}


func _ready() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play_place() -> void:
	_play(_cached("place", func(): return _sweep(260.0, 380.0, 0.07, "sine")), -4.0)


func play_hit() -> void:
	_play(_cached("hit", func(): return _sweep(700.0, 500.0, 0.045, "square")), -10.0)


func play_kill() -> void:
	_play(_cached("kill", func(): return _sweep(420.0, 120.0, 0.16, "sine")), -5.0)


func play_leak() -> void:
	_play(_cached("leak", func(): return _sweep(180.0, 120.0, 0.22, "square")), -3.0)


func play_invalid() -> void:
	_play(_cached("invalid", func(): return _sweep(150.0, 100.0, 0.09, "square")), -6.0)


func play_win() -> void:
	_play(_cached("win", func(): return _arpeggio([440.0, 554.0, 659.0, 880.0], 0.55, "sine")), 0.0)


func play_lose() -> void:
	_play(_cached("lose", func(): return _arpeggio([300.0, 220.0, 160.0], 0.6, "square")), -2.0)


func _play(stream: AudioStreamWAV, volume_db: float) -> void:
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.play()


func _cached(key: String, builder: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = builder.call()
	return _cache[key]


## A short frequency sweep (start -> end) with a linear fade-out so it never
## clicks at the end. "square" reads harsher/more alarming than "sine".
func _sweep(freq_start: float, freq_end: float, duration: float, wave: String) -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i in range(sample_count):
		var t: float = float(i) / sample_count
		var freq: float = lerp(freq_start, freq_end, t)
		phase += freq / MIX_RATE
		var envelope: float = 1.0 - t
		var raw: float = sign(sin(TAU * phase)) if wave == "square" else sin(TAU * phase)
		var sample: float = clampf(raw * 0.5 * envelope, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	return _build_wav(data)


## Plays each frequency in `freqs` as a short sequential note — a tiny
## melodic sting for win/lose, not a simultaneous chord.
func _arpeggio(freqs: Array, duration: float, wave: String) -> AudioStreamWAV:
	var note_duration: float = duration / freqs.size()
	var note_samples: int = int(MIX_RATE * note_duration)
	var data := PackedByteArray()
	data.resize(note_samples * freqs.size() * 2)
	var sample_i: int = 0
	for freq in freqs:
		for i in range(note_samples):
			var t: float = float(i) / note_samples
			var envelope: float = 1.0 - t
			var raw: float = sign(sin(TAU * freq * i / MIX_RATE)) if wave == "square" else sin(TAU * freq * i / MIX_RATE)
			var sample: float = clampf(raw * 0.5 * envelope, -1.0, 1.0)
			data.encode_s16(sample_i * 2, int(sample * 32767.0))
			sample_i += 1
	return _build_wav(data)


func _build_wav(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
