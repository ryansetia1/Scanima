class_name UiMotion
extends RefCounted

## One switch shared by chrome, ambience, and character presentation.
## Nilainya dipersist oleh GameState dan diubah dari menu Seeker.
static var reduced_motion := false


static func set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled
