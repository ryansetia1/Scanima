class_name Sfx
extends RefCounted

## Gameplay one-shots. Call from the helper that already owns the visual
## (AnimaPresenter, IncubatorEffect, scan_flow Level Up) — never from a
## Button.pressed handler. UiJuice keeps chrome taps on a separate player.

const HOST_NAME := &"SfxHost"
const VOICES := 3
const VOLUME_DB := -10.0

## Kenney ships these peak-normalised, which hides a 10 dB spread in how loud
## they actually read: measured RMS runs from -21,6 dB on `sfx_strike` to
## -11,5 dB on `sfx_guard`. Untrimmed, the most frequent battle sound is the
## quietest thing on screen. Trims bring every cue to about -19 dB RMS; the ones
## sitting at 0 already peak near full scale and cannot be raised further.
const CUE_TRIM_DB := {
	"strike": 2.6,
	"surge": -1.8,
	"guard": -7.5,
	"item": -3.8,
	"feed": 0.0,
	"hit_super": -5.4,
	"hit_resist": 0.0,
	"portal": -1.4,
	"level_up": -4.1,
}

const CUE_STRIKE := &"strike"
const CUE_SURGE := &"surge"
const CUE_GUARD := &"guard"
const CUE_ITEM := &"item"
const CUE_FEED := &"feed"
const CUE_HIT_SUPER := &"hit_super"
const CUE_HIT_RESIST := &"hit_resist"
const CUE_PORTAL := &"portal"
const CUE_LEVEL_UP := &"level_up"

const _STREAM_PATHS := {
	"strike": "res://assets/audio/sfx/sfx_strike.ogg",
	"surge": "res://assets/audio/sfx/sfx_surge.ogg",
	"guard": "res://assets/audio/sfx/sfx_guard.ogg",
	"item": "res://assets/audio/sfx/sfx_item.ogg",
	"feed": "res://assets/audio/sfx/sfx_feed.ogg",
	"hit_super": "res://assets/audio/sfx/sfx_hit_super.ogg",
	"hit_resist": "res://assets/audio/sfx/sfx_hit_resist.ogg",
	"portal": "res://assets/audio/sfx/sfx_portal.ogg",
	"level_up": "res://assets/audio/sfx/sfx_level_up.ogg",
}

static var _streams: Dictionary = {}


static func play(cue: StringName) -> void:
	var stream := _stream_for(cue)
	if stream == null:
		return
	var player := _voice()
	if player == null:
		return
	player.stream = stream
	player.volume_db = VOLUME_DB + float(CUE_TRIM_DB.get(String(cue), 0.0))
	player.pitch_scale = randf_range(0.94, 1.06)
	if not player.is_inside_tree():
		return
	player.play()


static func play_effectiveness(multiplier: float) -> void:
	if multiplier > 1.0:
		play(CUE_HIT_SUPER)
	elif multiplier < 1.0:
		play(CUE_HIT_RESIST)


# ponytail: three voices on the tree root, no AudioManager. A fourth cue steals
# the first player; add a bus + settings when volume sliders exist.
static func _voice() -> AudioStreamPlayer:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var host := tree.root.get_node_or_null(NodePath(HOST_NAME))
	if host == null:
		host = Node.new()
		host.name = String(HOST_NAME)
		tree.root.add_child(host)
		for index in VOICES:
			var created := AudioStreamPlayer.new()
			created.name = "Voice%d" % index
			created.volume_db = VOLUME_DB
			host.add_child(created)
	for child in host.get_children():
		var player := child as AudioStreamPlayer
		if player != null and not player.playing:
			return player
	return host.get_child(0) as AudioStreamPlayer


static func _stream_for(cue: StringName) -> AudioStream:
	if _streams.has(cue):
		return _streams[cue] as AudioStream
	var path := String(_STREAM_PATHS.get(String(cue), ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream != null:
		_streams[cue] = stream
	return stream
