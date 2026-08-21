class_name HomeBackground
extends TextureRect

const HOME_BACKGROUND_DAY: Texture2D = preload(
	"res://assets/backgrounds/home_day_background.png"
)
const HOME_BACKGROUND_NIGHT: Texture2D = preload(
	"res://assets/backgrounds/home_background.png"
)
const HOME_BACKGROUND_DAY_LANDSCAPE: Texture2D = preload(
	"res://assets/backgrounds/home_day_landscape_background.png"
)
const HOME_BACKGROUND_NIGHT_LANDSCAPE: Texture2D = preload(
	"res://assets/backgrounds/home_landscape_background.png"
)
const HOME_BACKGROUND_SHADER: Shader = preload(
	"res://shaders/background_crossfade.gdshader"
)

# Day dan night hasil generasi tidak menaruh pusat dais pada row yang sama.
# Stage tetap pada 68%; background yang di-art-direct ke focal point itu agar
# posisi Anima di layar tidak bergerak saat siang/malam berganti.
const PLATFORM_TARGET_PORTRAIT_RATIO := 0.68
const PLATFORM_TARGET_LANDSCAPE_RATIO := 0.69
const PLATFORM_CENTER_NIGHT_PORTRAIT_RATIO := 1062.0 / 1602.0
const PLATFORM_CENTER_DAY_PORTRAIT_RATIO := 1138.5 / 1602.0
const PLATFORM_PORTRAIT_ZOOM := 1.11

var _background_material: ShaderMaterial
var _daylight_timer: Timer


func _ready() -> void:
	_background_material = ShaderMaterial.new()
	_background_material.shader = HOME_BACKGROUND_SHADER
	material = _background_material
	_daylight_timer = Timer.new()
	_daylight_timer.name = "DaylightTimer"
	_daylight_timer.wait_time = 1.0
	_daylight_timer.autostart = true
	add_child(_daylight_timer)
	_daylight_timer.timeout.connect(_sync_daylight)
	visibility_changed.connect(_sync_daylight)
	get_viewport().size_changed.connect(_fit_viewport)
	_fit_viewport()
	_sync_daylight()


func _fit_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	var landscape := uses_landscape(viewport_size)
	var night := HOME_BACKGROUND_NIGHT_LANDSCAPE if landscape else HOME_BACKGROUND_NIGHT
	var day := HOME_BACKGROUND_DAY_LANDSCAPE if landscape else HOME_BACKGROUND_DAY
	texture = night
	_background_material.set_shader_parameter("day_texture", day)
	var fitted := floor_aligned_cover_rect(night.get_size(), viewport_size)
	if not landscape:
		fitted = portrait_platform_cover_rect(
			night.get_size(), viewport_size, LocalDaylight.daylight_blend()
		)
	position = fitted.position
	size = fitted.size


static func uses_landscape(viewport_size: Vector2) -> bool:
	return viewport_size.x > viewport_size.y


static func floor_aligned_cover_rect(texture_size: Vector2, viewport_size: Vector2) -> Rect2:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Rect2()
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Rect2()
	var cover_scale := maxf(
		viewport_size.x / texture_size.x,
		viewport_size.y / texture_size.y
	)
	var draw_size := texture_size * cover_scale
	return Rect2(
		Vector2((viewport_size.x - draw_size.x) * 0.5, viewport_size.y - draw_size.y),
		draw_size
	)


static func portrait_platform_cover_rect(
	texture_size: Vector2,
	viewport_size: Vector2,
	daylight_blend: float
) -> Rect2:
	var base := floor_aligned_cover_rect(texture_size, viewport_size)
	if base.size == Vector2.ZERO:
		return base
	var draw_size := base.size * PLATFORM_PORTRAIT_ZOOM
	var platform_center := lerpf(
		PLATFORM_CENTER_NIGHT_PORTRAIT_RATIO,
		PLATFORM_CENTER_DAY_PORTRAIT_RATIO,
		clampf(daylight_blend, 0.0, 1.0)
	)
	var target_y := base.position.y + base.size.y * PLATFORM_TARGET_PORTRAIT_RATIO
	return Rect2(
		Vector2((viewport_size.x - draw_size.x) * 0.5, target_y - draw_size.y * platform_center),
		draw_size
	)


func _sync_daylight() -> void:
	if not visible:
		return
	_background_material.set_shader_parameter(
		"daylight_blend", LocalDaylight.daylight_blend()
	)
	_fit_viewport()
