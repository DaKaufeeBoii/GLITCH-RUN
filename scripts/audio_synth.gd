extends Node
## Procedural Audio Synthesizer for GLITCH//RUN.
## Generates 16-bit PCM retro-synth SFX at runtime using native AudioStreamWAV.
## Zero external audio asset dependencies.

const SAMPLE_RATE := 22050
const POOL_SIZE := 10

var sounds: Dictionary = {}
var player_pool: Array[AudioStreamPlayer] = []
var pool_index := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_player_pool()
	_synthesize_all_sounds()


func _init_player_pool() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		player_pool.append(p)


func play(sound_id: String, pitch_range: float = 0.0, volume_offset_db: float = 0.0) -> void:
	if not sounds.has(sound_id):
		return

	var p := player_pool[pool_index]
	pool_index = (pool_index + 1) % POOL_SIZE

	p.stream = sounds[sound_id]
	if pitch_range > 0.0:
		p.pitch_scale = randf_range(1.0 - pitch_range, 1.0 + pitch_range)
	else:
		p.pitch_scale = 1.0
	p.volume_db = volume_offset_db
	p.play()


func _create_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false

	var byte_count := samples.size() * 2
	var byte_data := PackedByteArray()
	byte_data.resize(byte_count)

	for i in range(samples.size()):
		var clamped := clampf(samples[i], -1.0, 1.0)
		var val_16 := int(round(clamped * 32760.0))
		if val_16 < -32768:
			val_16 = -32768
		elif val_16 > 32767:
			val_16 = 32767
		# Encode signed 16-bit little-endian
		var uval := val_16 if val_16 >= 0 else val_16 + 65536
		byte_data[i * 2] = uval & 0xFF
		byte_data[i * 2 + 1] = (uval >> 8) & 0xFF

	wav.data = byte_data
	return wav


func _synthesize_all_sounds() -> void:
	sounds["blaster"] = _synth_blaster()
	sounds["dash"] = _synth_dash()
	sounds["hit_impact"] = _synth_hit_impact()
	sounds["player_hurt"] = _synth_player_hurt()
	sounds["enemy_laser_charge"] = _synth_enemy_laser_charge()
	sounds["hazard_shock"] = _synth_hazard_shock()
	sounds["boss_alarm"] = _synth_boss_alarm()
	sounds["wave_clear"] = _synth_wave_clear()
	sounds["mutation_alert"] = _synth_mutation_alert()
	sounds["ui_hover"] = _synth_ui_hover()
	sounds["ui_click"] = _synth_ui_click()


func _synth_blaster() -> AudioStreamWAV:
	var duration := 0.11
	var num_samples := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(num_samples)

	var phase := 0.0
	for i in range(num_samples):
		var progress := float(i) / float(num_samples)
		# Exponential pitch dive from 880 down to 180 Hz
		var freq := lerpf(880.0, 180.0, pow(progress, 0.75))
		phase += freq * (1.0 / SAMPLE_RATE)
		# Square wave with duty cycle 0.5
		var wave := 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0
		# Fast decay envelope
		var env := 1.0 - progress
		samples[i] = wave * env * 0.42

	return _create_stream(samples)


func _synth_dash() -> AudioStreamWAV:
	var duration := 0.18
	var num_samples := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(num_samples)

	var last_noise := 0.0
	for i in range(num_samples):
		var progress := float(i) / float(num_samples)
		# Filtered white noise with smooth bell curve envelope
		var raw_noise := randf_range(-1.0, 1.0)
		last_noise = lerpf(last_noise, raw_noise, 0.45)
		var env := sin(progress * PI)
		samples[i] = last_noise * env * 0.45

	return _create_stream(samples)


func _synth_hit_impact() -> AudioStreamWAV:
	var duration := 0.08
	var num_samples := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(num_samples)

	var phase := 0.0
	for i in range(num_samples):
		var progress := float(i) / float(num_samples)
		var freq := lerpf(320.0, 60.0, progress)
		phase += freq * (1.0 / SAMPLE_RATE)
		var sq := 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0
		var noise := randf_range(-0.5, 0.5)
		var env := pow(1.0 - progress, 2.0)
		samples[i] = (sq * 0.6 + noise * 0.4) * env * 0.5

	return _create_stream(samples)


func _synth_player_hurt() -> AudioStreamWAV:
	var duration := 0.22
	var num_samples := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(num_samples)

	var phase := 0.0
	for i in range(num_samples):
		var progress := float(i) / float(num_samples)
		var freq := lerpf(180.0, 45.0, progress)
		phase += freq * (1.0 / SAMPLE_RATE)
		# Triangle / sine blend for heavy thud
		var tri := 2.0 * absf(2.0 * (fposmod(phase, 1.0) - 0.5)) - 1.0
		var noise := randf_range(-0.3, 0.3)
		var env := pow(1.0 - progress, 1.5)
		samples[i] = (tri * 0.75 + noise * 0.25) * env * 0.65

	return _create_stream(samples)


func _synth_enemy_laser_charge() -> AudioStreamWAV:
	var duration := 0.50
	var num_samples := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(num_samples)

	var phase := 0.0
	for i in range(num_samples):
		var progress := float(i) / float(num_samples)
		# Rising frequency with slight wobble
		var wobble := sin(progress * 40.0) * 15.0
		var freq := lerpf(180.0, 460.0, pow(progress, 1.4)) + wobble
		phase += freq * (1.0 / SAMPLE_RATE)
		# Sawtooth wave
		var saw := 2.0 * fposmod(phase, 1.0) - 1.0
		var env := progress * 0.8
		samples[i] = saw * env * 0.35

	return _create_stream(samples)


func _synth_hazard_shock() -> AudioStreamWAV:
	var duration := 0.14
	var num_samples := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(num_samples)

	var phase := 0.0
	for i in range(num_samples):
		var progress := float(i) / float(num_samples)
		phase += 60.0 * (1.0 / SAMPLE_RATE) # 60 Hz mains hum
		var hum := 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0
		var spark := randf_range(-0.9, 0.9) if (i % 7 == 0) else 0.0
		var env := 1.0 - progress
		samples[i] = (hum * 0.4 + spark * 0.6) * env * 0.45

	return _create_stream(samples)


func _synth_boss_alarm() -> AudioStreamWAV:
	var duration := 0.45
	var num_samples := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(num_samples)

	var phase := 0.0
	for i in range(num_samples):
		var progress := float(i) / float(num_samples)
		var freq := 440.0 if fposmod(progress * 6.0, 1.0) < 0.5 else 660.0
		phase += freq * (1.0 / SAMPLE_RATE)
		var sq := 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0
		var env := 1.0 - (progress * 0.3)
		samples[i] = sq * env * 0.35

	return _create_stream(samples)


func _synth_wave_clear() -> AudioStreamWAV:
	var duration := 0.44
	var num_samples := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(num_samples)

	# 4-note ascending major chord: C5 (523), E5 (659), G5 (784), C6 (1046)
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.50]
	var phase := 0.0

	for i in range(num_samples):
		var progress := float(i) / float(num_samples)
		var note_idx := clampi(int(progress * 4.0), 0, 3)
		var freq: float = notes[note_idx]
		phase += freq * (1.0 / SAMPLE_RATE)

		var note_sub_t := fposmod(progress * 4.0, 1.0)
		var sub_env := 1.0 - note_sub_t * 0.7
		var sq := 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0
		samples[i] = sq * sub_env * 0.35

	return _create_stream(samples)


func _synth_mutation_alert() -> AudioStreamWAV:
	var duration := 0.32
	var num_samples := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(num_samples)

	var phase := 0.0
	for i in range(num_samples):
		var progress := float(i) / float(num_samples)
		var freq := 520.0 + sin(progress * 30.0) * 320.0
		phase += freq * (1.0 / SAMPLE_RATE)
		var wave := 1.0 if fposmod(phase, 1.0) < 0.4 else -1.0
		var env := 1.0 - progress
		samples[i] = wave * env * 0.38

	return _create_stream(samples)


func _synth_ui_hover() -> AudioStreamWAV:
	var duration := 0.035
	var num_samples := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(num_samples)

	var phase := 0.0
	for i in range(num_samples):
		var progress := float(i) / float(num_samples)
		phase += 1180.0 * (1.0 / SAMPLE_RATE)
		var s := sin(phase * TAU)
		var env := 1.0 - progress
		samples[i] = s * env * 0.28

	return _create_stream(samples)


func _synth_ui_click() -> AudioStreamWAV:
	var duration := 0.05
	var num_samples := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(num_samples)

	var phase := 0.0
	for i in range(num_samples):
		var progress := float(i) / float(num_samples)
		var freq := lerpf(680.0, 220.0, progress)
		phase += freq * (1.0 / SAMPLE_RATE)
		var sq := 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0
		var env := 1.0 - progress
		samples[i] = sq * env * 0.38

	return _create_stream(samples)
