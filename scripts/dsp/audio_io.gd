class_name AudioIO
extends RefCounted
## Load/save mono float samples as WAV (16-bit PCM). Used by tests, offline
## analysis and the synth renderer.


## Returns {"samples": PackedFloat32Array (mono), "rate": float}, or {} on failure.
static func load_wav(path: String) -> Dictionary:
	var wav := AudioStreamWAV.load_from_file(path)
	if wav == null:
		return {}
	var data := wav.data
	var channels := 2 if wav.stereo else 1
	var out := PackedFloat32Array()
	match wav.format:
		AudioStreamWAV.FORMAT_16_BITS:
			var n := data.size() / (2 * channels)
			out.resize(n)
			for i in n:
				var s := 0.0
				for c in channels:
					s += data.decode_s16((i * channels + c) * 2) / 32768.0
				out[i] = s / channels
		AudioStreamWAV.FORMAT_8_BITS:
			var n := data.size() / channels
			out.resize(n)
			for i in n:
				var s := 0.0
				for c in channels:
					s += data.decode_s8(i * channels + c) / 128.0
				out[i] = s / channels
		_:
			push_error("Unsupported WAV format in %s (use 8/16-bit PCM)" % path)
			return {}
	return {"samples": out, "rate": float(wav.mix_rate)}


static func save_wav(path: String, samples: PackedFloat32Array, rate: int) -> Error:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = bytes
	return wav.save_to_wav(path)
