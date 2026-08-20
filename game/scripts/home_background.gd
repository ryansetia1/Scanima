class_name HomeBackground
extends TextureRect

const HOME_BACKGROUND_DAY: Texture2D = preload(
	"res://assets/backgrounds/home_day_background.png"
)
const HOME_BACKGROUND_NIGHT: Texture2D = preload(
	"res://assets/backgrounds/home_background.png"
)
const HOME_BACKGROUND_SHADER: Shader = preload(
	"res://shaders/background_crossfade.gdshader"
)

var _background_material: ShaderMaterial
var _daylight_timer: Timer


func _ready() -> void:
	_background_material = ShaderMaterial.new()
	_background_material.shader = HOME_BACKGROUND_SHADER
	_background_material.set_shader_parameter("day_texture", HOME_BACKGROUND_DAY)
	material = _background_material
	texture = HOME_BACKGROUND_NIGHT
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
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _sync_daylight() -> void:
	if not visible:
		return
	_background_material.set_shader_parameter(
		"daylight_blend", LocalDaylight.daylight_blend()
	)
