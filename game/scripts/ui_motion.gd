class_name UiMotion
extends RefCounted

## One switch shared by chrome, ambience, and character presentation.
## ponytail: no settings screen yet; wire this flag to the future accessibility
## preference without changing individual components.
static var reduced_motion := false


static func set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled
