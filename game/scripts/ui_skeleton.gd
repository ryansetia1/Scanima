class_name UiSkeleton
extends VBoxContainer

const SURFACE_THEME := &"StatValuePanel"
const PULSE_SIDE_SEC := 0.62
const RESOLVE_SEC := 0.18
const PULSE_LOW := Color(0.82, 0.9, 1.0, 0.42)
const PULSE_HIGH := Color(0.72, 0.94, 1.12, 0.9)
const THUMBNAIL_SURFACE_COLOR := Color(0.075, 0.115, 0.225, 0.92)
const THUMBNAIL_BORDER_COLOR := Color(0.278, 0.902, 1.0, 0.54)
const META_RESOLVE_TWEEN := &"_scanima_skeleton_resolve"
const THUMBNAIL_PULSE_FRAME_COUNT := 8
const THUMBNAIL_RESOLVE_FRAME_COUNT := 6

static var _thumbnail_pulse_cache: Dictionary = {}

var _pulse: Tween
var _resolve: Tween
var _resolve_target: CanvasItem
var _resolve_revision := 0


func _ready() -> void:
	_ignore_input(self)


static func art_placeholder(size: Vector2, node_name: String = "SkeletonPlaceholder") -> PanelContainer:
	var placeholder := PanelContainer.new()
	placeholder.name = node_name
	placeholder.custom_minimum_size = size
	placeholder.theme_type_variation = SURFACE_THEME
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placeholder.focus_mode = Control.FOCUS_NONE
	return placeholder


static func thumbnail_loading_texture(size: int) -> AnimatedTexture:
	var animated := AnimatedTexture.new()
	thumbnail_restart_loading(animated, size)
	return animated


static func thumbnail_restart_loading(animated: AnimatedTexture, size: int) -> void:
	if animated == null:
		return
	animated.pause = true
	_clear_thumbnail_frames(animated)
	var pulse_frames := _thumbnail_pulse_frames(size)
	animated.frames = pulse_frames.size()
	for frame_index in pulse_frames.size():
		animated.set_frame_texture(frame_index, pulse_frames[frame_index] as Texture2D)
		animated.set_frame_duration(
			frame_index, PULSE_SIDE_SEC * 2.0 / float(pulse_frames.size())
		)
	animated.one_shot = false
	animated.current_frame = 0
	animated.pause = false


static func thumbnail_begin_resolve(
	animated: AnimatedTexture, final_texture: Texture2D
) -> void:
	if animated == null or final_texture == null:
		return
	var start_texture := animated.get_frame_texture(animated.current_frame)
	if start_texture == null:
		start_texture = _thumbnail_pulse_frames(final_texture.get_width())[0] as Texture2D
	var resolve_frames: Array[Texture2D] = []
	for frame_index in THUMBNAIL_RESOLVE_FRAME_COUNT:
		var progress := float(frame_index) / float(THUMBNAIL_RESOLVE_FRAME_COUNT - 1)
		if frame_index == 0:
			resolve_frames.append(start_texture)
		elif frame_index == THUMBNAIL_RESOLVE_FRAME_COUNT - 1:
			resolve_frames.append(final_texture)
		else:
			resolve_frames.append(_thumbnail_blend_texture(
				start_texture,
				final_texture,
				1.0 - progress * progress,
				1.0 - pow(1.0 - progress, 2.0)
			))
	animated.pause = true
	_clear_thumbnail_frames(animated)
	animated.frames = THUMBNAIL_RESOLVE_FRAME_COUNT
	for frame_index in THUMBNAIL_RESOLVE_FRAME_COUNT:
		animated.set_frame_texture(frame_index, resolve_frames[frame_index])
		animated.set_frame_duration(
			frame_index, RESOLVE_SEC / float(THUMBNAIL_RESOLVE_FRAME_COUNT)
		)
	animated.one_shot = true
	animated.current_frame = 0
	animated.pause = false


static func thumbnail_settle(
	animated: AnimatedTexture, final_texture: Texture2D
) -> void:
	if animated == null or final_texture == null:
		return
	animated.pause = true
	_clear_thumbnail_frames(animated)
	animated.frames = 1
	animated.set_frame_texture(0, final_texture)
	animated.set_frame_duration(0, RESOLVE_SEC)
	animated.one_shot = true
	animated.current_frame = 0


static func thumbnail_fail(animated: AnimatedTexture) -> void:
	if animated == null:
		return
	var frame := animated.get_frame_texture(animated.current_frame)
	var size := frame.get_width() if frame != null else 128
	var fallback := _thumbnail_pulse_frames(size)[0] as Texture2D
	animated.pause = true
	_clear_thumbnail_frames(animated)
	animated.frames = 1
	animated.set_frame_texture(0, fallback)
	animated.set_frame_duration(0, PULSE_SIDE_SEC)
	animated.one_shot = true
	animated.current_frame = 0


static func _thumbnail_pulse_frames(size: int) -> Array:
	var safe_size := maxi(size, 1)
	if _thumbnail_pulse_cache.has(safe_size):
		return _thumbnail_pulse_cache[safe_size] as Array
	var frames: Array[Texture2D] = []
	for frame_index in THUMBNAIL_PULSE_FRAME_COUNT:
		var progress := float(frame_index) / float(THUMBNAIL_PULSE_FRAME_COUNT)
		var strength := (1.0 - cos(progress * TAU)) * 0.5
		frames.append(_thumbnail_surface_texture(
			safe_size, PULSE_LOW.lerp(PULSE_HIGH, strength)
		))
	_thumbnail_pulse_cache[safe_size] = frames
	return frames


static func _thumbnail_surface_texture(size: int, modulation: Color) -> ImageTexture:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var center := Vector2(size, size) * 0.5
	var half_extent := float(size) * 0.5 - 0.5
	var radius := float(size) * 12.0 / 112.0
	var border_top := float(size) - maxf(2.0, float(size) * 2.0 / 112.0)
	for y in size:
		for x in size:
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			var offset := (point - center).abs() - Vector2.ONE * (half_extent - radius)
			var outside := Vector2(maxf(offset.x, 0.0), maxf(offset.y, 0.0)).length()
			var inside := minf(maxf(offset.x, offset.y), 0.0)
			var coverage := clampf(0.5 - (outside + inside - radius), 0.0, 1.0)
			if coverage <= 0.0:
				continue
			var pixel := (
				THUMBNAIL_BORDER_COLOR if point.y >= border_top else THUMBNAIL_SURFACE_COLOR
			) * modulation
			pixel.a *= coverage
			image.set_pixel(x, y, pixel)
	return ImageTexture.create_from_image(image)


static func _thumbnail_blend_texture(
	from_texture: Texture2D,
	to_texture: Texture2D,
	from_alpha: float,
	to_alpha: float
) -> ImageTexture:
	var size := Vector2i(from_texture.get_width(), from_texture.get_height())
	var from_image := from_texture.get_image()
	var to_image := to_texture.get_image()
	if to_image.get_size() != size:
		to_image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var blended := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	blended.fill(Color.TRANSPARENT)
	for y in size.y:
		for x in size.x:
			var under := from_image.get_pixel(x, y)
			var over := to_image.get_pixel(x, y)
			under.a *= from_alpha
			over.a *= to_alpha
			blended.set_pixel(x, y, under.blend(over))
	return ImageTexture.create_from_image(blended)


static func _clear_thumbnail_frames(animated: AnimatedTexture) -> void:
	for frame_index in animated.frames:
		animated.set_frame_texture(frame_index, null)


func set_loading(loading: bool) -> void:
	_stop_resolve(true)
	visible = loading
	if not loading:
		_stop_pulse()
		modulate = Color.WHITE
		return
	_ignore_input(self)
	_start_pulse()


func resolve_to(content: CanvasItem) -> void:
	if not is_instance_valid(content):
		set_loading(false)
		return
	_stop_resolve(true)
	_stop_pulse()
	_ignore_input(self)
	_resolve_revision += 1
	var revision := _resolve_revision
	_resolve_target = content
	content.visible = true
	content.modulate = Color(content.modulate.r, content.modulate.g, content.modulate.b, 0.0)
	_resolve = create_tween().set_parallel(true)
	set_meta(META_RESOLVE_TWEEN, _resolve)
	_resolve.tween_property(self, "modulate:a", 0.0, RESOLVE_SEC) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_resolve.tween_property(content, "modulate:a", 1.0, RESOLVE_SEC) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_resolve.finished.connect(func() -> void: _finish_resolve(revision))


func _finish_resolve(revision: int) -> void:
	if revision != _resolve_revision:
		return
	var target := _resolve_target
	_resolve = null
	_resolve_target = null
	remove_meta(META_RESOLVE_TWEEN)
	modulate = Color.WHITE
	visible = false
	if is_instance_valid(target):
		target.modulate = Color.WHITE


func _start_pulse() -> void:
	_stop_pulse()
	modulate = PULSE_LOW
	_pulse = create_tween().set_loops()
	_pulse.tween_property(self, "modulate", PULSE_HIGH, PULSE_SIDE_SEC) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(self, "modulate", PULSE_LOW, PULSE_SIDE_SEC) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _stop_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null


func _stop_resolve(reset_target: bool) -> void:
	_resolve_revision += 1
	if _resolve != null and _resolve.is_valid():
		_resolve.kill()
	_resolve = null
	remove_meta(META_RESOLVE_TWEEN)
	if reset_target and is_instance_valid(_resolve_target):
		_resolve_target.modulate = Color.WHITE
	_resolve_target = null


func _ignore_input(node: Node) -> void:
	if node is Control:
		var control := node as Control
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_ignore_input(child)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		_stop_pulse()
		_stop_resolve(true)
		modulate = Color.WHITE
