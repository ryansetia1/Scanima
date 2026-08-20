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


func _sync_daylight() -> void:
	if not visible:
		return
	_background_material.set_shader_parameter(
		"daylight_blend", LocalDaylight.daylight_blend()
	)
