class_name MusicDirector
extends Node

## Crossfading background music for the shell.
##
## The shell hands over one callable that names the cue the current screen
## wants, and this node polls it. Twenty-one call sites already open or close a
## battle session, so a push from each of them would go silent the first time a
## new branch forgets one.
# ponytail: poll 0,25 detik, bukan signal per transisi. Plafon: cue terdengar
# telat maksimal seperempat detik dan tidak pernah tepat frame; upgrade ke
# signal kalau nanti ada stinger yang harus jatuh persis di satu event.

const BUS := &"Music"
const FADE_SEC := 0.9
const POLL_SEC := 0.25
const SILENT_DB := -60.0

# Vorbis, not MP3. Every MP3 carries an encoder delay the decoder replays as
# silence on each loop, and these three also arrived with up to 1,25 s of dead
# air baked into the tail.
const TRACKS := {
	&"lobby": "res://assets/audio/music/lobby_lantern_save_point.ogg",
	&"battle": "res://assets/audio/music/battle_chromatic_arena_run.ogg",
	&"boss": "res://assets/audio/music/boss_forge_of_victory.ogg",
}

var cue_source: Callable

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _cue: StringName = &""
var _enabled := true
var _positions: Dictionary = {}
var _streams: Dictionary = {}
# One tween per player. A single shared tween loses the pending stop() of the
# outgoing track whenever a second cue change kills it mid-fade, and that track
# then keeps playing under the new one at whatever volume it froze at.
var _fades: Array[Tween] = [null, null]


func _ready() -> void:
	for _i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = BUS
		player.volume_db = SILENT_DB
		add_child(player)
		_players.append(player)
	var timer := Timer.new()
	timer.wait_time = POLL_SEC
	timer.timeout.connect(_poll)
	add_child(timer)
	timer.start()


func set_enabled(enabled: bool) -> void:
	if enabled == _enabled:
		return
	_remember_position()
	_enabled = enabled
	_apply()


func play(cue: StringName) -> void:
	if cue == _cue:
		return
	_remember_position()
	_cue = cue
	_apply()


func current_cue() -> StringName:
	return _cue


func is_sounding() -> bool:
	return _players.any(func(player: AudioStreamPlayer) -> bool: return player.playing)


func playback_position() -> float:
	if _players.is_empty():
		return 0.0
	return _players[_active].get_playback_position()


func _poll() -> void:
	if cue_source.is_valid():
		play(cue_source.call())


func _apply() -> void:
	if _players.is_empty():
		return
	if _players[_active].playing:
		_fade_to(_active, SILENT_DB, true)
	if not _enabled:
		return
	var stream := _stream(_cue)
	if stream == null:
		return
	_active = 1 - _active
	var incoming: AudioStreamPlayer = _players[_active]
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play(float(_positions.get(_cue, 0.0)))
	_fade_to(_active, 0.0, false)


func _fade_to(index: int, target_db: float, stop_after: bool) -> void:
	if is_instance_valid(_fades[index]):
		_fades[index].kill()
	var player: AudioStreamPlayer = _players[index]
	var tween := create_tween()
	_fades[index] = tween
	tween.tween_property(player, "volume_db", target_db, FADE_SEC)
	if stop_after:
		tween.tween_callback(player.stop)


func _remember_position() -> void:
	# The lobby track runs seven minutes. Restarting it after every battle would
	# leave the player hearing only its opening minute, forever.
	if _cue.is_empty() or _players.is_empty():
		return
	var player: AudioStreamPlayer = _players[_active]
	if player.playing:
		_positions[_cue] = player.get_playback_position()


func _stream(cue: StringName) -> AudioStream:
	if _streams.has(cue):
		return _streams[cue]
	if not TRACKS.has(cue):
		return null
	var stream: AudioStream = load(str(TRACKS[cue])) as AudioStream
	if stream != null:
		# Looping is set here rather than in the .import files so the three
		# assets keep default import settings and cannot drift apart.
		stream.set(&"loop", true)
	_streams[cue] = stream
	return stream
