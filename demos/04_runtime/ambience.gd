extends Node
## Sons de la démo, entièrement synthétisés (aucun fichier audio) :
## un vent doux qui va et vient, un « toc » de bois quand on pose, un souffle
## grave quand on retire. M : couper ou remettre le son.

@export_range(0.0, 1.0) var wind_volume := 0.35
@export_range(0.0, 1.0) var fx_volume := 0.5

const RATE := 22050.0

var _wind: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _fx: Array[AudioStreamPlayer] = []
var _tok: AudioStreamWAV
var _tok_soft: AudioStreamWAV
var _whoosh: AudioStreamWAV
var _muted := false
# État du bruit du vent.
var _b0 := 0.0
var _b1 := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 3
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.25
	_wind = AudioStreamPlayer.new()
	_wind.stream = gen
	_wind.volume_db = linear_to_db(wind_volume)
	add_child(_wind)
	_wind.play()
	_playback = _wind.get_stream_playback()
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.volume_db = linear_to_db(fx_volume)
		add_child(p)
		_fx.append(p)
	_tok = _make_tok(520.0, 0.09)
	_tok_soft = _make_tok(780.0, 0.06)
	_whoosh = _make_whoosh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_M:
		_muted = not _muted
		AudioServer.set_bus_mute(0, _muted)


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	for i in frames:
		_t += 1.0 / RATE
		# Bruit brun filtré, enveloppe lente : rafales douces toutes les quelques secondes.
		var white := _rng.randf_range(-1.0, 1.0)
		_b0 = _b0 * 0.995 + white * 0.03
		_b1 = _b1 * 0.9 + _b0 * 0.1
		var gust := 0.55 + 0.3 * sin(_t * 0.37) + 0.15 * sin(_t * 0.11 + 1.3)
		var s := _b1 * gust * 1.6
		_playback.push_frame(Vector2(s, s * 0.92))


## Pose : deux « toc » de bois, le second plus clair, comme une pièce qu'on emboîte.
func play_place() -> void:
	_play(_tok, 1.0)
	get_tree().create_timer(0.09).timeout.connect(func() -> void: _play(_tok_soft, 0.8))


func play_edit() -> void:
	_play(_tok_soft, 0.6)


func play_remove() -> void:
	_play(_whoosh, 0.9)


func _play(stream: AudioStreamWAV, volume: float) -> void:
	for p in _fx:
		if not p.playing:
			p.stream = stream
			p.volume_db = linear_to_db(fx_volume * volume)
			p.pitch_scale = _rng.randf_range(0.93, 1.07)
			p.play()
			return


## Petit bloc de bois frappé : sinus amorti avec une pointe de bruit à l'attaque.
func _make_tok(freq: float, decay: float) -> AudioStreamWAV:
	var n := int(RATE * 0.35)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := i / RATE
		var env := exp(-t / decay)
		var f := freq * (1.0 + 0.08 * exp(-t / 0.01))
		var s := sin(TAU * f * t) * 0.7 + sin(TAU * f * 2.71 * t) * 0.18 * exp(-t / (decay * 0.4))
		s += _rng.randf_range(-1, 1) * 0.25 * exp(-t / 0.004)
		data.encode_s16(i * 2, int(clampf(s * env * 0.6, -1.0, 1.0) * 32767.0))
	return _wav(data)


## Souffle de terre : bruit filtré qui monte puis s'éteint.
func _make_whoosh() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := i / RATE
		var env := sin(clampf(t / 0.7, 0.0, 1.0) * PI) * exp(-t * 2.0)
		lp = lp * 0.93 + _rng.randf_range(-1, 1) * 0.07
		var s := lp * 3.0 + sin(TAU * 90.0 * t) * 0.15
		data.encode_s16(i * 2, int(clampf(s * env * 0.7, -1.0, 1.0) * 32767.0))
	return _wav(data)


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(RATE)
	w.stereo = false
	w.data = data
	return w
