extends SceneTree

## Kontrak care murni, tanpa scene dan tanpa jaringan:
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
##     --script res://tests/test_game_rules.gd

var _checks := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	print("1. normalisasi kebutuhan")
	var normalized := CareRules.normalized_care({"hunger": 120, "energy": -2, "hygiene": 50})
	_check_eq(normalized["hunger"], 100.0, "Hunger dijepit ke 100")
	_check_eq(normalized["energy"], 0.0, "Energy dijepit ke 0")
	_check_eq(normalized["hygiene"], 50.0, "Hygiene dipertahankan")
	_check_eq(normalized["bond"], 0.0, "Bond yang hilang memakai default")

	print("2. grace dan cap offline decay")
	var full := {"hunger": 100.0, "energy": 100.0, "hygiene": 100.0, "bond": 50.0}
	var after_8h := CareRules.apply_decay(full, 0.0, 8.0 * 3600.0)
	_check_eq(after_8h["hunger"], 100.0, "grace delapan jam harus utuh")
	var after_18h := CareRules.apply_decay(full, 0.0, 18.0 * 3600.0)
	_check_eq(after_18h["hunger"], 0.0, "18 jam berarti 10 jam decay efektif")
	_check(is_equal_approx(after_18h["energy"], 29.0), "Energy turun 71 setelah 10 jam")
	_check(is_equal_approx(after_18h["hygiene"], 58.0), "Hygiene turun 42 setelah 10 jam")
	var after_56h := CareRules.apply_decay(full, 0.0, 56.0 * 3600.0)
	var after_week := CareRules.apply_decay(full, 0.0, 168.0 * 3600.0)
	_check_eq(after_56h, after_week, "48 jam efektif harus menjadi cap")
	for need in CareRules.DEFAULT_CARE:
		_check(after_week[need] >= 0.0 and after_week[need] <= 100.0, "%s tetap 0–100" % need)

	print("3. Bond hanya turun saat Hunger dan Hygiene sama-sama nol")
	var hunger_only := CareRules.apply_decay(
		{"hunger": 0.0, "energy": 100.0, "hygiene": 100.0, "bond": 50.0},
		0.0,
		18.0 * 3600.0
	)
	_check_eq(hunger_only["bond"], 50.0, "Hunger nol sendiri tidak mengurangi Bond")
	var neglected := CareRules.apply_decay(
		{"hunger": 0.0, "energy": 100.0, "hygiene": 0.0, "bond": 50.0},
		0.0,
		18.0 * 3600.0
	)
	_check_eq(neglected["bond"], 30.0, "dua kebutuhan nol mengurangi Bond 2/jam efektif")

	print("4. tidur pulih linear dari nilai awal")
	var tired := {"hunger": 100.0, "energy": 0.0, "hygiene": 100.0, "bond": 0.0}
	var half_sleep := CareRules.apply_decay(tired, 0.0, 3.0 * 3600.0, 1.0, 0.0)
	# sleep_started_at=1 menghindari sentinel nol; selisihnya praktis tiga jam.
	_check(absf(half_sleep["energy"] - 50.0) < 0.1, "tidur tiga jam memulihkan setengah")
	var full_sleep := CareRules.apply_decay(tired, 0.0, 6.0 * 3600.0, 1.0, 0.0)
	_check(absf(full_sleep["energy"] - 100.0) < 0.1, "tidur enam jam mengisi penuh")

	print("5. care_score dan Dormant")
	_check_eq(CareRules.score_for_action("feed", {"hunger": 39}), 3, "Feed lapar memberi score")
	_check_eq(CareRules.score_for_action("feed", {"hunger": 40}), 0, "Feed Hunger 40 tidak memberi score")
	_check_eq(CareRules.score_for_action("clean", {"hygiene": 49}), 3, "Clean kotor memberi score")
	_check_eq(CareRules.score_for_action("clean", {"hygiene": 50}), 0, "Clean Hygiene 50 tidak memberi score")
	_check_eq(CareRules.score_for_action("play", {}, 4), 1, "Play kelima memberi score")
	_check_eq(CareRules.score_for_action("play", {}, 5), 0, "Play keenam tidak memberi score")
	_check(
		CareRules.enters_dormant({"hunger": 0, "hygiene": 0}, 48.0),
		"dua kebutuhan nol pada cap masuk Dormant"
	)
	_check(
		not CareRules.enters_dormant({"hunger": 0, "hygiene": 0}, 47.9),
		"sebelum cap belum Dormant"
	)
	_check(
		not CareRules.can_recover_from_dormant({"hunger": 70, "hygiene": 35}),
		"satu kebutuhan saja belum memulihkan Dormant"
	)
	_check(
		CareRules.can_recover_from_dormant({"hunger": 70, "hygiene": 70}),
		"dua kebutuhan di atas 50 memulihkan Dormant"
	)

	_finish()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s: dapat %s, mau %s" % [message, str(actual), str(expected)])


func _finish() -> void:
	if _failures.is_empty():
		print("test_game_rules: OK (%d check)" % _checks)
		quit(0)
		return
	printerr("test_game_rules: GAGAL %d dari %d check" % [_failures.size(), _checks])
	for failure in _failures:
		printerr("  - %s" % failure)
	quit(1)
