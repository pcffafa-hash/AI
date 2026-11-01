extends RefCounted
## Erzeugt Sounds prozedural (kein Audio-Asset nötig).

static func make(dur: float, f0: float, f1: float, noise: float, decay: float, vol := 0.8, loop := false) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f := lerpf(f0, f1, t)
		ph += TAU * f / float(rate)
		var tone := sin(ph)
		var nz := randf() * 2.0 - 1.0
		lp += (nz - lp) * 0.35
		var s := (tone * (1.0 - noise) + lp * noise) * exp(-t * decay) * vol
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w
