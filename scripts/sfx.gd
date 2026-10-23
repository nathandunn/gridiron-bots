class_name Sfx
extends Node
## Robot football sounds, made from scratch when the game starts (no sound files): metal
## crunches for tackles, clanks, the throw's whoosh, the ball bouncing, the whistle and the crowd.

const RATE := 22050
var on := true
var _streams := {}
var _pool: Array = []
var _next := 0


func _ready() -> void:
	for i in 10:
		var pl := AudioStreamPlayer.new()
		add_child(pl)
		_pool.append(pl)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_streams["crunch"] = _crunch(rng, 0.38, 0.8)
	_streams["big_crunch"] = _crunch(rng, 0.6, 1.0)
	_streams["clank"] = _clank(rng, 0.28, [1250.0, 1980.0, 3150.0])
	_streams["clink"] = _clank(rng, 0.18, [2100.0, 3300.0, 4700.0])
	_streams["whoosh"] = _whoosh(rng, 0.32)
	_streams["thump"] = _thump(rng, 0.14, 130.0)
	_streams["bounce"] = _thump(rng, 0.1, 320.0)
	_streams["whistle"] = _whistle(0.55)
	_streams["roar"] = _roar(rng, 2.6)
	_streams["servo"] = _servo(0.22)


func play(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not on or not _streams.has(name):
		return
	var pl: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	pl.stream = _streams[name]
	pl.volume_db = vol_db
	pl.pitch_scale = pitch * randf_range(0.92, 1.08)
	pl.play()


## A moment from the play, as a sound.
func on_action(kind: String) -> void:
	match kind:
		"tackle", "dive_tackle":
			play("crunch", -3.0)
		"big_hit", "sack":
			play("big_crunch", 0.0)
			play("clank", -8.0, 0.8)
		"fumble":
			play("big_crunch", -1.0)
			play("bounce", -4.0)
		"miss", "dive_miss":
			play("clank", -5.0)
		"stiff_arm", "pancake":
			play("crunch", -6.0, 1.2)
		"juke":
			play("servo", -9.0)
		"throw":
			play("whoosh", -6.0)
		"catch", "int", "handoff":
			play("thump", -4.0)
		"drop", "pbu", "incomplete":
			play("clink", -6.0)
			play("bounce", -5.0)


func _wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


## Metal on metal: a low thump, ringing plates and a crackle of grinding.
func _crunch(rng: RandomNumberGenerator, secs: float, weight: float) -> AudioStreamWAV:
	var n := int(secs * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var modes := [[410.0, 9.0], [730.0, 12.0], [1170.0, 16.0], [1890.0, 22.0], [2650.0, 30.0]]
	var ph := []
	for m in modes:
		ph.append(rng.randf() * TAU)
	var lp := 0.0
	var crackle := 0.0
	for i in n:
		var t := float(i) / RATE
		var thump := sin(TAU * (75.0 - 40.0 * t / secs) * t) * exp(-t * 14.0) * weight
		var ring := 0.0
		for j in modes.size():
			ring += sin(TAU * float(modes[j][0]) * t + float(ph[j])) * exp(-t * float(modes[j][1]))
		ring *= 0.16
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.35
		if rng.randf() < 0.02 * exp(-t * 6.0):
			crackle = rng.randf_range(-1.0, 1.0)
		crackle *= 0.9
		var grind := (lp * exp(-t * 18.0) * 0.9 + crackle * 0.5) * weight
		buf[i] = (thump * 0.9 + ring + grind) * 0.75
	return _wav(buf)


func _clank(rng: RandomNumberGenerator, secs: float, freqs: Array) -> AudioStreamWAV:
	var n := int(secs * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for j in freqs.size():
			v += sin(TAU * float(freqs[j]) * t + j) * exp(-t * (14.0 + j * 6.0))
		v += rng.randf_range(-1, 1) * exp(-t * 90.0) * 0.6
		buf[i] = v * 0.3
	return _wav(buf)


func _whoosh(rng: RandomNumberGenerator, secs: float) -> AudioStreamWAV:
	var n := int(secs * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var u := float(i) / n
		var cut := 0.04 + 0.25 * sin(u * PI)
		lp += (rng.randf_range(-1, 1) - lp) * cut
		buf[i] = lp * sin(u * PI) * 1.4
	return _wav(buf)


func _thump(rng: RandomNumberGenerator, secs: float, f: float) -> AudioStreamWAV:
	var n := int(secs * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		buf[i] = (sin(TAU * f * t) * exp(-t * 30.0) + rng.randf_range(-1, 1) * exp(-t * 200.0) * 0.4) * 0.8
	return _wav(buf)


func _whistle(secs: float) -> AudioStreamWAV:
	var n := int(secs * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / 0.03, 1.0) * minf((secs - t) / 0.08, 1.0)
		var trill := 0.65 + 0.35 * sin(TAU * 38.0 * t)
		buf[i] = sin(TAU * (2350.0 + 60.0 * sin(TAU * 38.0 * t)) * t) * env * trill * 0.35
	return _wav(buf)


func _roar(rng: RandomNumberGenerator, secs: float) -> AudioStreamWAV:
	var n := int(secs * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var a := 0.0
	var b := 0.0
	for i in n:
		var u := float(i) / n
		var x := rng.randf_range(-1, 1)
		a += (x - a) * 0.12
		b += (a - b) * 0.3
		var env := minf(u / 0.15, 1.0) * (1.0 - u) * (1.0 - u)
		buf[i] = b * env * 1.6
	return _wav(buf)


func _servo(secs: float) -> AudioStreamWAV:
	var n := int(secs * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in n:
		var u := float(i) / n
		ph += (300.0 + 700.0 * u) / RATE
		buf[i] = (fmod(ph, 1.0) * 2.0 - 1.0) * sin(u * PI) * 0.25
	return _wav(buf)
