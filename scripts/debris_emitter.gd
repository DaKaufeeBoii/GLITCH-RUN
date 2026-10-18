extends RefCounted
## Procedural Geometric Particle Debris Emitter for GLITCH//RUN.
## Spawns dynamic geometric fragments on hostile defeat with zero external texture dependencies.

class_name DebrisEmitter


const MAX_ACTIVE_SHARDS := 64
static var active_shard_count := 0


static func spawn_shards(parent: Node2D, origin: Vector2, color: Color, shard_shape: String = "diamond", count: int = 8) -> void:
	if not is_instance_valid(parent):
		return

	var allowed_count: int = mini(count, maxi(0, MAX_ACTIVE_SHARDS - active_shard_count))
	if allowed_count <= 0:
		return

	for i in range(allowed_count):
		active_shard_count += 1
		var shard := Node2D.new()
		shard.global_position = origin
		shard.z_index = 5
		parent.add_child(shard)

		var angle := randf() * TAU
		var speed := randf_range(110.0, 250.0)
		var velocity := Vector2.from_angle(angle) * speed
		var spin := randf_range(-14.0, 14.0)
		var shard_color := color.lightened(randf_range(-0.15, 0.25))

		# Shard geometry polygon definition
		var poly := PackedVector2Array()
		match shard_shape:
			"diamond":
				poly = PackedVector2Array([Vector2(0, -6), Vector2(4, 0), Vector2(0, 6), Vector2(-4, 0)])
			"hexagon":
				poly = PackedVector2Array([Vector2(4, -2), Vector2(5, 2), Vector2(0, 5), Vector2(-5, 2), Vector2(-4, -2), Vector2(0, -5)])
			"chevron":
				poly = PackedVector2Array([Vector2(8, 0), Vector2(-5, -4), Vector2(-2, 0), Vector2(-5, 4)])
			_:
				poly = PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)])

		shard.draw.connect(func():
			shard.draw_colored_polygon(poly, shard_color)
			shard.draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[0]]), shard_color.lightened(0.4), 1.0)
		)

		var lifetime := randf_range(0.35, 0.55)
		var tween := shard.create_tween().set_parallel(true)
		tween.tween_property(shard, "position", shard.position + velocity * lifetime, lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(shard, "rotation", shard.rotation + spin * lifetime, lifetime)
		tween.tween_property(shard, "scale", Vector2.ZERO, lifetime).set_delay(lifetime * 0.4)
		tween.tween_property(shard, "modulate:a", 0.0, lifetime)
		tween.chain().tween_callback(func():
			active_shard_count = maxi(0, active_shard_count - 1)
			if is_instance_valid(shard):
				shard.queue_free()
		)
